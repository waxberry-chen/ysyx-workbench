# 1 - 可变延迟 Memory Request/Response：从零延迟访存到真实事务

> 适用工程状态：C6 单周期 NPC 已完成，准备进入 B1。  
> 对应讲义：[B1：总线](../../lectures/ysyx/ysyx2306-b-stage.md#3-b1总线)。  
> 本文范围：先建立简单、明确、可验证的 memory request/response 接口；**暂不实现 AXI4-Lite 五通道**。

## 1. 这一增量到底在解决什么问题？

C 阶段的 NPC 假设取指和 load 可以立即得到结果：RTL 给出地址，DPI-C 在同一次组合求值中读取 C++ `pmem`，数据马上回到 RTL。这个模型适合尽快验证 ISA，但它隐含了一个现实中通常不成立的条件：

> memory 永远零延迟、永远能够接收请求，而且永远不会报告错误。

真实 SRAM、总线、Cache 和外设都可能要求 CPU 等待：

- SRAM 常在发出地址后的下一个或若干周期返回数据；
- AXI slave 可以通过 `ready` 施加 backpressure；
- Cache miss 可能等待几十个周期；
- UART 等 MMIO device 可能暂时不能接受写入；
- 多个 master 共享 memory 时，请求还要等待仲裁；
- 非法地址需要返回 error，而不是静默得到 0。

因此，本增量的目标不是“让 RAM 慢一点”，而是建立一种新的控制关系：

```text
CPU 发出一次请求
  -> 对方明确接受请求
  -> CPU 记住正在等待什么
  -> 若干周期后收到且接受一次响应
  -> 对应指令才允许写回、更新 PC 和 commit
```

完成后，NPC 虽然仍是单发射顺序核，但不再是“每个周期必定执行一条指令”的单周期核，而是能够因取指或数据访存停顿的 **multi-cycle/stallable core**。这是之后 AXI、流水线和 Cache 的共同基础。

## 2. 当前工程为什么不能直接增加一拍延迟？

### 2.1 当前取指和 load 是组合 DPI-C 读取

[ysyx_i_ram.sv](../../../npc/vsrc/core/ysyx_i_ram.sv) 中，`addr` 变化或 Verilator 重新求值时就可能调用：

```systemverilog
always @(*) begin
  inst_r = 32'h00000013;
  if (re) pmem_read(1'b1, addr, 32'h4, inst_r);
end
```

[ysyx_d_ram.sv](../../../npc/vsrc/core/ysyx_d_ram.sv) 的 load 也采用相同方式，而 store 在上升沿直接调用 `pmem_write()`。这些模块实际是 **simulation memory proxy**，不是 RAM，更不是 Cache。

组合 DPI-C 访问的问题包括：

- `always @(*)` 可能因一次 `eval()` 内多轮组合收敛而执行多次；
- MMIO callback 具有副作用，多次读取不一定等价于一次读取；
- 没有信号表示请求何时被接受、响应属于哪个地址；
- 无法施加 backpressure；
- DPI-C 位于处理器 RTL 内部，未来接入可综合 SoC 时边界不清晰；
- 复位或无效组合值也可能意外触发访存。

### 2.2 当前 CPU 每个有效沿都 commit

[ysyx_core.sv](../../../npc/vsrc/core/ysyx_core.sv) 当前直接定义：

```systemverilog
assign commit_wb = 1'b1;
```

PC、GPR、CSR 和 store 都默认当前指令会在下一个上升沿完成。若只把 `rd` 延迟一拍：

```text
e_k:     CPU 发出 load A，同时 PC 前进
e_(k+1): memory 才返回 A，但组合地址已变成下一条指令的地址 B
```

此时至少会出现：

- 返回数据与指令/地址错位；
- load 尚未完成，PC 和 GPR 却已经前进；
- 同一个 store 可能在等待期间重复执行；
- ITrace 和 DiffTest 把未完成的指令误认为已提交；
- MMIO skip 属性与真正提交的指令失配。

所以需要一起引入：**事务握手、状态保存、等待状态、写使能门控和真实 commit 条件**。

## 3. 必要理论：一次 memory transaction 是什么？

一次最小事务分为两个独立阶段：

```text
Request channel                      Response channel
req_valid + req_ready                rsp_valid + rsp_ready
addr/write/size/wdata                rdata/error
        |                                    |
        +---- request accepted               +---- response consumed
```

### 3.1 `valid/ready` 的含义

对任意通道，只在某个上升沿同时满足以下条件时发生一次 transfer：

```systemverilog
fire = valid && ready;
```

- `valid`：source 声明 payload 当前有效；
- `ready`：destination 声明当前能够接收；
- `valid && ready`：双方在该上升沿完成一次交付；
- 只有 `valid` 或只有 `ready` 都不算交付。

request source 是 CPU，response source 是 memory：

```text
CPU                          Memory
 |--- req_valid/payload ----->|
 |<-- req_ready --------------|
 |                             |
 |<-- rsp_valid/payload -------|
 |--- rsp_ready -------------->|
```

### 3.2 Source 必须持有请求

若 `req_valid=1` 而 `req_ready=0`，CPU 不能撤回请求，也不能改变地址、写数据、size 或读写类型：

```text
req_valid && !req_ready
  => next cycle: req_valid remains 1 and request payload remains stable
```

否则 memory 在真正接受请求时可能看到另一个地址。

同理，memory 在 `rsp_valid=1 && !rsp_ready` 时必须保持 response payload 稳定。

### 3.3 `valid` 不能等待 `ready`

request master 不应使用以下策略：

```text
if (req_ready) req_valid = 1;
```

如果 slave 也等待 `req_valid` 才拉高 `req_ready`，双方会永久等待。正确策略是：CPU 有请求时独立拉高 `req_valid`，保持到握手；slave 可以提前或稍后给出 `req_ready`。

这是避免 deadlock 的基本依赖方向。组合路径如何限制、`ready` 是否允许依赖 `valid`，还要服从具体总线规范；进入 AXI 阶段必须重新核对 AMBA 文档。

### 3.4 接受请求不等于完成请求

`req_fire` 只说明 memory 接管了请求，不代表数据已经返回：

```text
e_1: req_fire，memory 接受 load A
e_2 ... e_6: memory processing
e_7: rsp_fire，CPU 接收 A 的数据
```

CPU 必须在 `e_1` 到 `e_7` 之间记住自己有一个 outstanding transaction。第一版只允许最多一个 outstanding request，因而不需要 transaction ID，也不存在乱序响应：

```text
accepted_requests - consumed_responses ∈ {0, 1}
```

这比完整 AXI 简单很多，但已经建立了正确 mental model。

### 3.5 Store 也应该有 response

store 没有读数据，但仍应等待 completion response：

- memory 可能拒绝或延迟写入；
- 非法地址需要返回 error；
- MMIO device 可能施加 backpressure；
- CPU 需要知道 store 在什么时候完成并允许 commit。

因此 response 至少包含：

```text
rsp_valid, rsp_ready, rsp_err, rsp_rdata
```

store 忽略 `rsp_rdata`，但不能忽略 response 本身。

## 4. 第一版接口应该长什么样？

### 4.1 先做自定义接口，不直接做 AXI

第一版的目标是学会 latency、backpressure 和 outstanding state。推荐为 IFU 与 LSU 分别定义一个简单接口：

```systemverilog
// request: core -> memory
output logic        req_valid;
input  logic        req_ready;
output logic [31:0] req_addr;
output logic        req_write;
output logic [31:0] req_wdata;
output logic [1:0]  req_size;   // 0/1/2 -> 1/2/4 bytes

// response: memory -> core
input  logic        rsp_valid;
output logic        rsp_ready;
input  logic [31:0] rsp_rdata;
input  logic        rsp_err;
```

instruction port 可以删除 `req_write/req_wdata`，但 request/response 语义保持一致。

当前增量应尽量保持 [ysyx_d_ram_ctrl.sv](../../../npc/vsrc/core/ysyx_d_ram_ctrl.sv) 的数据约定：请求仍携带 byte address 和 1/2/4-byte size，返回值中的有效 byte/halfword 位于低位，再由 LSU 做符号/零扩展。等简单总线稳定后，再单独改成 AXI 的 aligned data lane 和 `WSTRB` 语义，避免同时调试 latency 与 byte-lane 转换。

### 4.2 接口契约必须先写清楚

第一版建议明确以下约束：

| 项目 | 第一版约定 |
|---|---|
| outstanding 数量 | 每个 port 最多 1 个 |
| response 顺序 | 与 request 顺序一致 |
| request 接受条件 | `req_valid && req_ready` 的上升沿 |
| response 接受条件 | `rsp_valid && rsp_ready` 的上升沿 |
| 最小 response latency | request 接受后的下一个周期 |
| payload 保持 | source 在 `valid && !ready` 时保持稳定 |
| store completion | 收到无错误 response 后才能 commit |
| error | 先传递 `rsp_err`；当前可结束仿真，后续转换成 access fault |
| reset | 清除 valid/outstanding/commit，不产生 memory transaction |

规定 response 最早在下一周期出现，可以简化第一版状态机。以后若接口允许 zero-cycle response，要显式验证 request 和 response 同周期握手的情况，不能靠偶然组合路径工作。

### 4.3 建议的工程边界

长期更清晰的结构是：

```text
                  synthesizable boundary
            +-------------------------------+
            | ysyx_core                     |
            |  IFU/LSU request-response     |
            +-------------------------------+
                       |
             simulation or SoC adapter
                       |
       +---------------+----------------+
       |                                |
 C++ pmem/MMIO model              future AXI/ysyxSoC
```

推荐让 `ysyx_core` 只暴露硬件接口，不在 core 内调用 DPI-C。NPC 仿真可以新增 wrapper 或由 C++ harness 直接驱动 memory response；未来 ysyxSoC 则把同一 core 接到 AXI adapter。

这种边界使处理器 RTL 不依赖 Verilator/NEMU，也使 memory model 可以独立替换。

## 5. CPU 为什么需要状态机？

### 5.1 推荐的最小控制状态

当前核没有 instruction register：`inst` 直接来自组合读取。可变延迟后必须锁存已经取回的指令及其 PC，例如 `inst_q/inst_pc_q`。

一种易于调试的第一版状态机是：

```text
RESET
  |
  v
IF_REQ --req_fire--> IF_WAIT --rsp_fire--> EXEC
  ^                                             |
  |                  ordinary/branch/CSR/trap   |
  +---------------------- commit ---------------+
                                                |
                             load/store          v
                              D_REQ --req_fire--> D_WAIT
                                                   |
                                        rsp_fire + commit
                                                   |
                                                   +--> IF_REQ
```

状态职责可定义为：

| 状态 | 主要行为 | 允许 commit？ |
|---|---|---:|
| `IF_REQ` | 保持取指地址与 `i_req_valid`，等待 request 接受 | 否 |
| `IF_WAIT` | PC 保持，等待 instruction response | 否 |
| `EXEC` | 译码 `inst_q`，执行非访存指令或准备 data request | 非访存指令可以 |
| `D_REQ` | 保持 load/store request payload | 否 |
| `D_WAIT` | 等待 data response | response 成功时可以 |

也可以把 `D_REQ` 合并到 `EXEC`，或增加独立 `COMMIT` 状态。第一版应优先选择容易画状态图、容易写 assertion、容易看波形的方案，而不是减少一个周期。

### 5.2 等待期间必须冻结什么？

等待 instruction 或 data response 时：

- `pc_cur` 不得前进；
- `inst_q/inst_pc_q` 不得被其他请求覆盖；
- GPR/CSR write enable 必须为 0；
- branch/trap redirect 不得重复发生；
- store request 不能重复被接受；
- `commit_valid` 必须为 0；
- request 已接受后，不能再次发送同一 request。

因此，现有 IDU 给出的 `rf_we/csr_we/dm_we_raw` 只能被视为 **decoded intent**，不能再直接连接寄存器或 memory side effect。实际使能必须与当前状态及 completion event 相与：

```text
rf_we_commit  = decoded_rf_we  && instruction_is_completing
csr_we_commit = decoded_csr_we && instruction_is_completing
store_issue   = state == D_REQ && d_req_valid && d_req_ready
```

### 5.3 PC 只在指令完成时更新

非访存指令在 `EXEC` 完成时更新 PC；load/store 在 response 成功时更新 PC。等待状态只保持当前 PC。

不要将 `pc_next` 简单写成“等待时选择 `pc_cur`”后就结束设计。还必须保证同一等待周期内 GPR、CSR、store 和 commit 全部被抑制，否则 PC 虽然没动，指令副作用仍会重复发生。

## 6. Commit 与 DiffTest 必须怎样变化？

### 6.1 从“每周期提交”变为“完成事件提交”

当前 `commit_wb=1`。改造后它应表示：

> 当前 `commit_pc/commit_inst` 对应的指令将在这个有效上升沿完成全部架构效果。

使用已有时序记号：

```text
e_k^-: commit_valid=1，I_n 将完成
e_k:   PC/GPR/CSR/store architectural effect 生效
e_k^+: harness 采集 S_(n+1)，让 REF 执行 I_n 并比较
```

详见 [同步电路时序描述约定](../../misc/synchronous-timing-description.md)。

不同指令的提交条件为：

| 指令类型 | commit 条件 |
|---|---|
| ALU/branch/jump | `EXEC` 中结果将在当前沿写入 |
| CSR/`ecall`/`mret` | CSR 和 PC redirect 将在当前沿更新 |
| load | data response 被 CPU 接受，load data 在同一沿写回 GPR |
| store | write completion response 被 CPU 接受且无错误 |
| fetch/wait bubble | 永不 commit |

### 6.2 Commit metadata 不能来自正在变化的组合线

至少应稳定提供：

```text
commit_valid
commit_pc
commit_inst
commit_is_mmio
```

它们应来自 `inst_pc_q/inst_q` 以及已保存的 data request metadata，而不是直接读取当前 fetch address 或组合 `alu_res`。等待 load/store 的多个周期内，commit metadata 必须仍对应原指令。

### 6.3 Harness 不应按 cycle 推进 REF

[sim.cpp](../../../npc/csrc/sim.cpp) 当前主循环已经只在 `will_commit` 时递增 `g_nr_guest_inst`、减少 `n` 并执行 `difftest_step()`。因此总体结构可以保留：

```text
loop by RTL cycle
  sample whether this edge will commit
  drive one RTL cycle
  if committed:
    capture post-commit DUT state
    REF executes exactly one instruction
    compare DUT and REF
```

但必须同步检查：

- `test_break()` 只在 `commit_valid` 时识别 `ebreak`；
- ITrace 只打印提交指令；
- `cpu_exec(n)` 在若干等待周期后仍只计算 `n` 次 commit；
- `commit_is_mmio` 与完成的 load/store 对齐；
- memory error 中止后不再执行 DiffTest；
- timeout/watchdog 统计 RTL cycle，而不是 guest instruction。

NEMU REF、AM 程序和 `difftest_exec(1)` 的 ISA 语义不需要为了 memory latency 改变。REF 可以“一步执行完”，DUT 可以等待任意周期；双方只在 commit 后比较 architectural state。

## 7. Simulation memory model 应该放在哪里？

### 7.1 保留 `paddr_*` 作为存储和 MMIO backend

[paddr.cpp](../../../npc/csrc/memory/paddr.cpp) 中的 `paddr_read/paddr_write`、`pmem` 和 MMIO map 仍有用。需要改变的是“何时调用它们”：

```text
旧：RTL 组合求值 -> DPI-C 立即 paddr_read

新：request handshake
      -> simulation slave 保存 request 和 delay
      -> delay 到期，只执行一次 paddr_read/write
      -> response channel 返回结果/error
```

不要通过 `sleep()` 阻塞 host，也不要让 `pmem_read()` 在每个等待周期反复执行。

### 7.2 推荐 C++ slave 的最小状态

每个 memory port 可以维护：

```cpp
struct PendingRequest {
  bool valid;
  bool write;
  uint32_t addr;
  uint32_t wdata;
  uint8_t size;
  unsigned cycles_left;
};
```

概念行为为：

```text
if no pending request:
  may assert req_ready
  on req_fire:
    capture payload once
    choose fixed/random delay

if pending and delay expires:
  perform paddr_read/write once
  assert rsp_valid with stable data/error

if rsp_fire:
  clear response and pending request
```

随机延迟必须使用可记录 seed 的伪随机生成器。失败日志至少打印 seed、port、request sequence number、地址、读写类型和 delay，以便完全复现。

### 7.3 Store 和 MMIO 副作用只能发生一次

推荐在 transaction completion 时执行一次 `paddr_write/mmio_write`，随后返回 response。无论 `rsp_ready` 延迟多少周期，都不能再次调用 write callback。

MMIO read 也可能有“read-to-clear”等副作用，因此只能在规定的 completion 点调用一次。当前 UART/RTC 比较简单，不代表重复调用 DPI-C 是安全的。

### 7.4 Error 应成为 response 的一部分

当前 MMIO map 越界会设置 `sim_state`。新接口仍可暂时让 error 结束仿真，但 slave 应先形成明确的 `rsp_err`，使接口未来可以映射到：

- AXI `RRESP/BRESP`；
- instruction/load/store access fault；
- 可定位的 bus error trace。

这比在 CPU 内按地址高位提前拦截更容易接入新设备。

## 8. 推荐的增量实现顺序

不要一次删除 I-RAM/D-RAM、加入 AXI、随机延迟和流水线。每一步都应保持可运行和可回退。

### Step 0：冻结 C6 baseline

- 保存当前 commit/DiffTest 时序说明；
- CPU tests 35/35；
- `hello`、RTC、yield-os 和 C6 trap workload 通过；
- 保存当前指令数、RTL cycle 数和 lint 结果；
- 建立独立 milestone commit。

### Step 1：写接口规格和状态图

先产出文档，不写 AXI：

- instruction/data port signal table；
- request/response handshake definition；
- maximum outstanding 数量；
- response 最小延迟；
- reset/error/unaligned/MMIO 行为；
- CPU 状态图和每个状态的 register enable；
- commit 条件表。

规格若不能回答“谁在什么边沿接收了什么”，RTL 也很难写对。

### Step 2：只改 instruction fetch

- 增加 `inst_q/inst_pc_q`；
- 用 `IF_REQ/IF_WAIT/EXEC` 驱动 instruction port；
- memory 先固定为一周期响应；
- 非访存指令仍在 `EXEC` commit；
- 检查 PC 在 fetch wait 期间稳定；
- 先运行只包含 ALU/branch 的小测试，再运行全部 CPU tests。

此时 data port 暂时保留旧实现，便于隔离 fetch 问题。

### Step 3：改 load

- 在 `EXEC` 保存 address、size、destination register 和 unsigned/sign 信息；
- 进入 `D_REQ/D_WAIT`；
- response 到达时完成 extension、GPR writeback 和 commit；
- 等待期间 PC/GPR/commit 保持；
- 用 `load-store` 类 directed test 和 CPU tests 验证。

### Step 4：改 store 与 MMIO

- store request 只允许握手一次；
- completion response 后再 commit；
- 同一 MMIO callback 不得重复执行；
- `commit_is_mmio` 使用保存的地址/指令 metadata；
- 验证 UART 字符不重复、RTC 读取与 DiffTest skip 对齐；
- 验证非法地址得到明确 error/BAD TRAP。

### Step 5：加入可配置固定延迟

至少验证：

```text
instruction latency = 1, 5, 10, 20 cycles
data latency        = 1, 5, 10, 20 cycles
```

分别改变 instruction/data latency，避免两个端口同时变化时难以归因。记录每个配置的 cycle、instruction 和 CPI。

### Step 6：加入随机 backpressure 和 response latency

- 独立随机化 `req_ready` 和 response delay；
- seed 必须可指定和打印；
- 增加 cycle watchdog；
- 多 seed 运行 CPU tests；
- 再运行 `hello`、RTC 和较长 workload；
- 出错时保存 bus trace 和短窗口 FST，而不是全程波形。

### Step 7：稳定后再映射到 AXI4-Lite

此时 CPU 已经理解 request、wait、response 和 commit；AXI adapter 的主要任务才变成通道拆分、payload 保存和协议映射，而不是同时修复 CPU 零延迟假设。

## 9. 建议的源码职责变化

| 位置 | 当前职责 | 本增量后的建议职责 |
|---|---|---|
| `ysyx_core.sv` | 组合取指、每周期 commit | memory ports、FSM、instruction/request metadata、真实 commit |
| `ysyx_i_ram.sv` | 组合 DPI-C fetch | 从 core 移除；或改成 simulation-only response adapter |
| `ysyx_d_ram.sv` | 组合 DPI-C load、沿上 store | 从 core 移除；或改成 simulation-only transaction slave |
| `ysyx_d_ram_ctrl.sv` | size、load extension | 保留 LSU 数据格式职责，逐步与 transaction control 分离 |
| `sim.cpp` | drive clock、commit 后 DiffTest | 另行推进 memory slave、记录 cycle/transaction、保持 commit-driven DiffTest |
| `paddr.cpp` | PMEM/MMIO 直接 DPI backend | 保留 storage/map，实现被 transaction slave 每个请求调用一次 |
| `common.h/config.h` | 全局配置和 DPI prototype | 增加 latency/seed/trace 配置，避免散落 magic number |
| `Makefile/filelist.f` | `ysyx_core` 为仿真 top | 若增加 wrapper，区分 simulation top 与 synthesizable core |

`paddr.h` 中已经出现无参数 `pmem_read()/pmem_write()` 和源码中的 `#ifdef AXI` 占位，但它们不是已完成的 bus model。不要仅打开宏；应先定义并实现上述 transaction contract。

## 10. 如何画和读波形？

### 10.1 固定延迟取指

假设下表每列都表示对应上升沿到来前的 `e_k^-`，request 在 `e_1` 被接受，response 在 `e_4` 被接受：

```text
observation    e_1^-   e_2^-   e_3^-   e_4^-   e_5^-   e_5^+
state          IF_REQ  IF_WAIT IF_WAIT IF_WAIT EXEC     IF_REQ
i_req_valid       1       0       0       0       0         1
i_req_ready       1       x       x       x       x         ?
i_rsp_valid       0       0       0       1       0         0
i_rsp_ready       1       1       1       1       1         1
pc_cur            P       P       P       P       P      P_next
commit_valid      0       0       0       0       1         0
```

读图时说：

- `e_1` 发生 instruction request handshake；
- `e_1` 到 `e_4` 期间 PC 保持为 `P`；
- `e_4` 接收 instruction response 并锁存 `inst_q`；
- 组合执行后，指令在 `e_5` commit，PC 更新为 `P_next`。

不要只说“取指用了三个周期”，因为它没有声明从哪个 handshake 到哪个 handshake。

### 10.2 Load response 与 commit 同沿

在 `D_WAIT` 中，可以定义：

```text
d_rsp_valid && d_rsp_ready
  -> load data 在该沿写入 rd
  -> PC 在该沿更新
  -> commit_valid 在该沿有效
```

这样 response consumption 和 architectural commit 是同一个上升沿上的事件。harness 在该沿之后读取 GPR/PC，并与 REF 执行一条 load 后的状态比较。

### 10.3 波形至少观察这些信号

```text
clk, rstn, state
pc_cur, inst_q, inst_pc_q
i_req_valid/ready/addr
i_rsp_valid/ready/data/error
d_req_valid/ready/write/addr/size/wdata
d_rsp_valid/ready/data/error
rf_we_commit, csr_we_commit
commit_valid, commit_pc, commit_inst, commit_is_mmio
```

若波形不能同时回答“哪个请求被接受、哪个响应被消费、哪条指令提交”，调试信息仍然不够。

## 11. Assertion 与验证计划

### 11.1 最小接口 assertion

request 被 backpressure 时必须保持：

```systemverilog
assert property (@(posedge clk) disable iff (!rstn)
  req_valid && !req_ready
  |=> req_valid && $stable({req_addr, req_write, req_wdata, req_size}));
```

response 被 backpressure 时必须保持：

```systemverilog
assert property (@(posedge clk) disable iff (!rstn)
  rsp_valid && !rsp_ready
  |=> rsp_valid && $stable({rsp_rdata, rsp_err}));
```

还应检查：

- 没有 outstanding request 时不得产生 response；
- outstanding count 永远不超过 1；
- reset 期间不产生 request/response/commit；
- wait 状态下 PC、GPR/CSR write enable 和 commit 保持；
- 每个 accepted request 最终最多得到一个 response；
- 每个 store transaction 最多执行一次 memory/MMIO side effect；
- 每个 guest instruction 最多 commit 一次。

“最终一定得到 response”属于 liveness property，需要合理环境假设或 bounded timeout；仅靠简单 safety assertion 不能证明 memory 永不永久阻塞。

### 11.2 Regression matrix

| 测试 | 1-cycle | 5-cycle | 20-cycle | random multi-seed | 重点 |
|---|---:|---:|---:|---:|---|
| ALU/branch directed | 必做 | 必做 | 建议 | 必做 | fetch wait、PC/commit |
| load/store directed | 必做 | 必做 | 必做 | 必做 | metadata、single side effect |
| 35 CPU tests | 必做 | 必做 | 建议 | 必做 | ISA regression + DiffTest |
| `hello` | 必做 | 必做 | 建议 | 必做 | UART store 不重复 |
| RTC test | 必做 | 必做 | 建议 | 必做 | MMIO load 与 skip 对齐 |
| yield/trap test | 必做 | 建议 | 可选 | 建议 | CSR/redirect 在 wait 后保持正确 |
| RT-Thread smoke | 最终 | 最终 | 可选 | 最终 | 长运行 deadlock smoke test |
| invalid address | 必做 | 必做 | 可选 | 必做 | error path |

RT-Thread 在这里仍只是长 workload：它能暴露偶发 deadlock 或重复 transaction，但不替代接口 assertion、directed test 和随机验证。

### 11.3 性能记录

至少记录：

```text
guest instructions
RTL cycles
CPI = cycles / committed_instructions
I-request count / average response latency
D-read/D-write count / average response latency
stall cycles by reason
random seed
```

不要用 Verilator 在 host 上运行了多少秒代替硬件性能。host simulation time 反映模拟器效率，不等于芯片执行时间。

## 12. 常见错误和 Debug mental model

### 错误 1：只把 `rdata` 延迟一拍

根因：没有保存请求，也没有冻结 PC/写回。返回数据自然会与新地址错位。

### 错误 2：`req_valid` 只脉冲一个周期

若该周期 `req_ready=0`，请求从未被接受。`valid` 必须保持到 handshake。

### 错误 3：请求接受后仍保持 `req_valid`

若 slave 继续 `ready=1`，相同请求会在每个上升沿重复接受。master 必须在 `req_fire` 后进入 wait 状态。

### 错误 4：等待期间仅冻结 PC

GPR、CSR、trap redirect 或 store 仍可能重复执行。所有 architectural side effect 必须由 completion/commit 统一门控。

### 错误 5：memory 每个等待周期都调用一次 DPI-C

普通 RAM 可能只是重复读取，但 UART、FIFO、read-to-clear register 会产生真实错误。backend 每个 transaction 只能调用一次。

### 错误 6：store 在 request 和 response 两处各写一次

必须选择唯一 side-effect point，并用计数器/assertion 验证 accepted store 与实际写次数一致。

### 错误 7：仍然使用 live `inst/alu_res` 做 commit metadata

等待期间 fetch/data 组合线可能变化。必须使用与 outstanding instruction/request 一起保存的 metadata。

### 错误 8：DiffTest 每个 RTL cycle 都执行 REF

DUT 等待 20 周期时 REF 会多执行 19 条指令。REF 只能由真实 commit 驱动。

### 错误 9：随机测试不可复现

只调用随机数却不打印 seed，偶发失败就无法重放。seed 是失败证据的一部分。

### 错误 10：第一步同时实现 AXI、Cache 和流水线

三个机制都会引入 stall、状态保存和 response alignment。出现错误时难以判断责任边界。先完成本文的单 outstanding 简单接口，再逐层替换。

## 13. 与后续 AXI、流水线和 Cache 的关系

### 13.1 到 AXI4-Lite

简单事务将被拆成 AXI 通道：

```text
simple read request  -> AR channel
simple read response -> R channel
simple write request -> AW + W channels
write completion     -> B channel
```

AXI 的 AW 与 W 相互独立，slave/adapter 必须分别保存它们；这比本文的一体化 write request 更复杂。但 CPU 已经学会等待 request/response，复杂度被限制在 adapter 内。

### 13.2 到流水线

当前全核等待会变成 pipeline backpressure：

- IF response 控制 frontend valid；
- load/store wait 阻塞相关后端级；
- stall 向前传播；
- commit 仍只在最老且完成的有效指令上产生；
- flush 必须取消尚未产生不可逆副作用的错误路径请求。

### 13.3 到 Cache

Cache 位于 CPU 与下游 memory 之间：

- hit 可以快速产生 response；
- miss 保存原请求并发起 refill；
- refill 完成后再响应 CPU；
- MMIO bypass 仍使用相同 request/response contract；
- `fence.i` 需要等待在途事务并失效相关状态。

因此，本文建立的不是一次性过渡接口，而是之后模块组合时的基本语言。

## 14. 工业界通常如何处理？

工业设计通常把处理器、Cache、interconnect 和 memory controller 分成独立 IP，以稳定的 transaction protocol 连接：

- 模块规格先定义 handshake、ordering、error、reset 和 performance；
- 简单 IP 使用 ready/valid 或厂内轻量协议；
- SoC 使用 AXI/AHB/APB、TileLink、CHI 等标准或内部协议；
- 多 outstanding/乱序响应使用 ID、tag 或 reorder state；
- latency-insensitive design 允许各模块独立插入 pipeline/register slice；
- DV 使用 protocol checker、assertion、scoreboard、random backpressure 和 coverage；
- performance model 统计 queue occupancy、latency、bandwidth 和 stall reason；
- CDC 场景还要通过 async FIFO/handshake synchronizer 处理跨时钟域，不能直接复用同步 ready/valid。

本教程只实现单时钟域、单 outstanding、顺序响应，但它已经包含工业接口设计最核心的三个问题：**transfer 何时发生、谁保存上下文、完成如何被证明**。

## 15. 工业界中的相关岗位

### CPU / Microarchitecture Engineer

负责取指、流水线、LSU、Cache 和 commit 等微架构。必须设计等待、backpressure、flush 与 response alignment，保证可变延迟不会破坏精确架构状态。

### Digital IC / RTL Design Engineer

把接口规格实现为可综合 RTL 和状态机，处理 handshake、payload stability、reset、error 及性能时序，并通过 lint/synthesis 检查实现质量。

### SoC Design Engineer

集成 CPU、interconnect、SRAM、UART、CLINT 和其他 IP。需要理解 master/slave、仲裁、地址译码、响应归属与错误传播。

### Design Verification Engineer

根据协议写 test plan、driver/monitor、scoreboard、assertion 和 coverage，通过随机延迟/backpressure、错误响应和长回归寻找 deadlock、丢请求、重复写等问题。

### Performance Verification / Modeling Engineer

建立 latency/bandwidth/queue 模型，分析 stall、CPI、Cache miss 和互联瓶颈，判断微架构优化是否真正改善系统性能。

## 16. 本增量的完成标准

在进入 AXI4-Lite 前，应满足：

- [ ] `ysyx_core` 不再依赖组合 DPI-C memory read；
- [ ] IFU/LSU 使用明确的 request/response handshake；
- [ ] 每个 port 最多一个 outstanding request；
- [ ] request/response 在 backpressure 时保持 payload；
- [ ] instruction 和 request metadata 被寄存保存；
- [ ] wait 状态不更新 PC/GPR/CSR，不 commit、不重复 store；
- [ ] load/store 在 response completion 时产生唯一 commit；
- [ ] `commit_pc/inst/is_mmio` 与真正完成的指令对齐；
- [ ] C++ backend 每个 transaction 只访问一次 PMEM/MMIO；
- [ ] 固定 1/5/10/20-cycle latency 下功能正确；
- [ ] 多个可复现 random seed 下无 deadlock/重复/丢失；
- [ ] 35 项 CPU tests 在 DiffTest 下通过；
- [ ] `hello`、RTC 和非法地址 error path 通过；
- [ ] 至少有 payload stability、outstanding 和 wait-no-commit assertion；
- [ ] 保存状态图、关键波形、回归矩阵和性能基线。

## 17. 本节真正需要记住的内容

1. 可变延迟不是“把数据延后一拍”，而是从组合函数调用转向 transaction protocol。
2. transfer 只发生在 `valid && ready` 的有效上升沿；backpressure 时 source 必须保持 payload。
3. request 被接受后，CPU 必须保存 outstanding instruction/request 的全部上下文。
4. 等待期间要冻结所有 architectural side effect，而不只是 PC。
5. load/store 只有在 response completion 后才能 commit；store 也需要完成响应。
6. DiffTest 按 commit 而非 RTL cycle 推进，因此 DUT 可以比 REF 多等待任意周期。
7. DPI-C `pmem` 可以继续作为 simulation backend，但不应继续隐藏在 core 的组合逻辑中。
8. 固定延迟验证正确性，随机 backpressure 暴露时序组合问题，assertion 固化协议不变量。
9. 先完成单 outstanding 简单接口，再进入 AXI、Cache 和流水线，可以显著降低调试复杂度。

完成这一增量后，NPC 才真正具备连接总线和存储系统的控制基础；后续 B1 的 AXI4-Lite 是对这个事务模型的协议化扩展，而不是从零开始的另一项工作。
