# AXI4-Lite 阶段 2：LSU Adapter 工作记录

> 完成日期：2026-09-28  
> 基线提交：`9afcc3b78dc9ae0b4d30ea16c2fd5217cd1972c2`  
> 状态：Stage 2 complete；无阻塞项。

## 1. 完成内容

本阶段完成两项相互依赖的工作：

1. CPU 在发出 memory request 前识别 load/store address-misaligned exception；
2. 将 LSU local request/response 转换为 AXI4-Lite `AR/R/AW/W/B` channels。

```text
EXU -- aligned operation --> LSU -- dmem req/rsp --> LSU AXI4-Lite adapter
 │                                                    │
 └-- misaligned: precise trap                         └-- AR/R/AW/W/B
```

主要文件：

| File | Purpose |
| --- | --- |
| `npc/vsrc/core/ysyx_exu.sv` | 在 AXI/LSU request 前产生 cause 4/6 |
| `npc/tests/address_misaligned.S` | load/store misaligned 端到端测试 |
| `npc/vsrc/bus/ysyx_lsu_axi4lite_adapter.sv` | read/write AXI4-Lite adapter |
| `npc/tests/ysyx_lsu_axi4lite_adapter_tb.sv` | adapter standalone directed test |
| `npc/scripts/tests.mk` | 新增 misaligned 与 adapter 测试目标 |

## 2. Address-misaligned 精确异常

### 2.1 判定位置和规则

EXU 已经算出 load/store effective address，也是决定是否向 LSU 发请求的最后一级。因此
alignment 在 EXU 判定，而不是等 adapter assertion 或 slave error：

```text
byte:     always aligned
halfword: address[0]   == 0
word:     address[1:0] == 0
```

非法 load 产生 `mcause=4`，非法 store 产生 `mcause=6`。它们与 AXI response error
严格分离：

| Error source | Request issued | `commit_mem_error` | `mcause` |
| --- | --- | --- | --- |
| address misaligned | no | 0 | load 4 / store 6 |
| AXI/local response error | yes | 1 | load 5 / store 7 |

### 2.2 精确状态

misaligned instruction 在统一 commit 边界完成，并满足：

- `mepc` 保存 faulting instruction PC，PC redirect 到 `mtvec`；
- load 不写 GPR，store 不产生 memory side effect；
- 不拉高 `lsu_req_valid`，因此不会形成 partial store；
- trace 保留 `mem_valid`、load/store 类型及原始 effective address；
- `mem_error=0`，通过 exception cause 区分于 AXI access fault；
- DiffTest 不执行 reference 中的 faulting instruction，而调用 `difftest_raise_intr(4/6)`。

新增 `make -C npc address-misaligned-test`，分别执行 misaligned word load/store。测试
检查 `mcause`、`mepc`、GOOD TRAP、trace exception record，并确认日志中的 D-RAM
request 数为 0。

## 3. LSU AXI4-Lite Adapter

### 3.1 Transaction FSM

adapter 是全寄存、single-outstanding 设计：

```text
read : IDLE -> SEND_AR -> WAIT_R -> HOLD_RSP -> IDLE
write: IDLE -> SEND_WRITE -> WAIT_B -> HOLD_RSP -> IDLE
```

request 在 `IDLE` 被捕获，AXI response 也先进入寄存器，再通过 local response 交给
LSU。这样 local 与 AXI 两侧可以独立 backpressure，且 AXI input 不形成到 AXI output
的组合路径。

### 3.2 AW/W independence

AXI write address 和 write data 是两个独立 channel。`SEND_WRITE` 使用两个状态位：

```text
aw_pending_q = AW 尚未 handshake
w_pending_q  = W  尚未 handshake
```

任一 channel 完成后立即清除自身 pending，并停止拉高对应 VALID；另一个 channel 可继续
等待。只有两者都完成后才进入 `WAIT_B`。因此支持：

- AW-first；
- W-first；
- AW/W 同周期；
- 任一 channel 任意长时间 stall；
- 已完成 channel 不会因为另一 channel stall 而重复产生 side effect。

### 3.3 Byte lane

AXI4-Lite 数据宽度固定为 32-bit。adapter 将 local effective address 对齐到 word
boundary，并用 lane shift 表达窄访问：

```text
AXI address = {local_addr[31:2], 2'b00}
WSTRB       = base_strobe << local_addr[1:0]
WDATA       = local_wdata << (8 * local_addr[1:0])
local_rdata = RDATA >> (8 * local_addr[1:0])
```

| Access | Legal offset | `WSTRB` |
| --- | --- | --- |
| byte | 0/1/2/3 | `0001/0010/0100/1000` |
| halfword | 0/2 | `0011/1100` |
| word | 0 | `1111` |

adapter 只把 read bytes 移到 bit 0；signed/unsigned extension 仍由 LSU 根据原 instruction
type 完成。`ARPROT/AWPROT=3'b001`，表示 privileged、secure、data。

### 3.4 Response 和 reset

- `RRESP/BRESP=OKAY` 映射为 `dmem_rsp_error=0`；其余编码均映射为 1；
- store 的 local response data 固定为 0；
- R/B response 分别只能在已有 read 或 AW/W 均完成后接受；
- local response 在 backpressure 下保持 valid/data/error；
- shared reset 会放弃 outstanding 或 partial write，清空 AW/W pending 和 response buffer。

## 4. Assertions 与 directed test

adapter assertions 覆盖：

- local size 只允许 byte/half/word 且地址自然对齐；
- AR、AW、W payload 在 stall 下保持稳定；
- local response 在 stall 下保持稳定；
- R/B 必须对应合法 outstanding transaction；
- `WAIT_B` 必须已经完成 AW 和 W；
- 非 idle 时拒绝第二笔 local request。

`make -C npc lsu-axi4lite-adapter-test` 覆盖：

| Scenario | Result checked |
| --- | --- |
| byte load, offset 3 | aligned AR address，RDATA 右移 24 bit |
| halfword load, offset 2 | RDATA 右移 16 bit，SLVERR 传播 |
| byte store, AW-first | lane 1，AW 不重复，等待 W 后才接收 B |
| halfword store, W-first | lanes 2/3，W 不重复，等待 AW 后才接收 B |
| word store, AW/W same cycle | full strobe，DECERR 传播 |
| local response stall | data/error 保持稳定 |
| reset after AW, before W | partial transaction 被清除，回到 idle |
| handshake scoreboard | 完整 transaction 中 2 AR/2 R、3 AW/3 W/3 B，无重复或丢失 |

## 5. 回归结果

| Verification | Result |
| --- | --- |
| core / LSU adapter lint | PASS；仅有既存 `ysyx_gen_imm.inst[6:0]` warning |
| primitive / IFU / LSU / EXU directed tests | 全部 PASS |
| IFU 与 LSU adapter tests | 全部 PASS，assertions ON |
| instruction/load/store access-fault | PASS，`mcause=1/5/7` |
| load/store address-misaligned | PASS，`mcause=4/6`，D-RAM requests = 0 |
| 普通 RV32E CPU tests | 除旧 `unalign` 外 34/34 PASS，DiffTest ON |
| fixed-seed `add` | seeds 1～10、max latency 7、ready 50%，全部 GOOD TRAP |
| hello/UART | 参数输出正确，GOOD TRAP |
| yield-os/CSR DiffTest | 5 s 内持续交替输出 `AB`，无 mismatch/assertion |

adapter 尚未接入 core，普通 aligned workload 的 timing 不应改变。固定 `add` 复测仍为：

```text
commits = 1095
cycles  = 5121
CPI     = 4.677

full trace SHA-256:
a066cd4ab6b90481d155cdabd533de2138e3e6c6c3e192fe653835772cf42c66

architectural fields SHA-256:
bbf8496edf2329d695eb4437641ced89bba9cf0b6006f1a0b5955c32941e9284
```

旧 `cpu-tests/unalign` 要求跨 word boundary 的访问成功，与当前选择的 architectural
exception 语义冲突，因此不再属于普通成功路径回归；它由新的 cause 4/6 测试替代。

## 6. 阶段结论

Stage 2 已关闭，当前无阻塞项。IFU/LSU adapters 都已经在 frozen local interface 上
独立验证，但尚未接入 `ysyx_core`。下一步 Stage 3 应：

1. 在 core 内实例化两个 adapter，对外暴露两套 AXI4-Lite master；
2. 把 C++ RAM model 从 local req/rsp slave 改为五个 AXI channel 的 slave；
3. 独立随机化 AR/R/AW/W/B timing，并保留 error injection 和统计；
4. 重新运行 34 项普通 CPU tests、misaligned/access-fault、AM workloads 和 DiffTest；
5. 记录 adapter 引入的固定 cycles/CPI 变化。
