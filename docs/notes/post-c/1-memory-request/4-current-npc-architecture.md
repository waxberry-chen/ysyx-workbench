# 当前 NPC 微架构导读

> 本文对应 2026-09-21 完成 Phase 2B 后的 RTL。它描述的是**当前已经实现并通过验证的结构**，不是后续 AXI、异常或分支预测计划。

## 1. 这次重构解决了什么问题

早期 NPC 是一个由全局状态机控制的多周期处理器：取指、执行、等待数据访存都写在同一个 FSM 中。它可以运行程序，但有三个明显问题：

1. memory latency 一变化，整个 core 的控制状态都要跟着修改；
2. fetch、decode、execute 之间没有稳定的 transaction/context 边界；
3. 将来接入 AXI、加入预测或改变 backend 时，很容易再次大改全核。

当前 NPC 将状态分散到真正拥有它的模块：

- IFU 管理 instruction-memory transaction 和预测取指 PC；
- IFQ 保存已经取回、尚未进入 backend 的指令；
- opbuf 保存当前 backend 指令的完整执行上下文；
- EXU 决定执行结果、commit 和 redirect；
- LSU 独立管理 data-memory transaction；
- core 顶层只连接模块并保存 architectural state。

因此当前结构可概括为：

> **RV32E、单发射、顺序提交、弹性前后端、IFU/LSU 各单 outstanding、集中 commit/redirect 的小型处理器。**

它不是经典五级流水，但已经具备现代模块化处理器最基本的 transaction、backpressure、context、commit 和 flush 概念。

这里的 RV32E 指当前构建与 workload 目标。RTL 中 GPR 物理上仍有 32 项，也尚未实现“RV32E 指令引用 x16～x31 时触发非法指令异常”的完整合规行为，因此不应把它理解为已经通过 ISA compliance 的严格声明。

## 2. 总体结构

```text
                 speculative frontend

  imem req/rsp                        instruction context
       │                                      │
       ▼                                      ▼
┌──────────────┐     ┌────────────┐     ┌───────────────┐
│ IFU          │────►│ 2-entry IFQ│────►│ decode/regread│
│ fetch PC     │     │ {pc, inst} │     │ + WB bypass   │
│ REQ/WAIT/DROP│     └────────────┘     └───────┬───────┘
└──────▲───────┘                                │ decoded context
       │ redirect + flush                       ▼
       │                                ┌───────────────┐
       └────────────────────────────────│ 1-entry opbuf │
                                        └───────┬───────┘
                                                │ stable operation
                                                ▼
                 in-order backend        ┌───────────────┐
                                        │ EXU / commit  │
                                        │ ALU / branch  │
                                        └───┬───────┬───┘
                                            │       │
                                  CSR/GPR ◄─┘       └─► LSU ─► dmem
                                     architectural state
```

当前最多可以同时存在：

- opbuf 中 1 条正在执行或等待的指令；
- IFQ 中 2 条已经取回的年轻指令；
- instruction memory 中 1 笔已发出、尚未返回的取指 transaction。

但是 backend 同时只处理 opbuf 中的一条指令，所有指令严格按程序顺序 commit。因此不需要 ROB、scoreboard 或 OITF。

## 3. 先理解 ready/valid

IFU、IFQ、opbuf、EXU 和 LSU 之间主要使用 ready/valid 握手。对一个接口：

```text
producer: valid + payload
consumer: ready
transfer/fire = valid && ready
```

含义如下：

| 信号组合 | 含义 |
| --- | --- |
| `valid=0` | producer 当前没有有效 transaction |
| `valid=1, ready=0` | consumer 暂时接不下；producer 必须保持 valid 和 payload |
| `valid=1, ready=1` | 本周期握手，在下一个 active edge 完成 transaction 转移 |

最重要的规则不是“尽快把 ready 拉高”，而是：

> 一旦 producer 宣布某份 payload 有效，在握手前就不能偷偷换成另一份 payload。

这使每个模块可以独立停顿。memory 慢时，LSU 可以等待；backend 慢时，IFQ 可以暂存；IFQ 满时，IFU 可以停止发新请求，而不需要一个全局 FSM 指挥所有模块。

### 3.1 什么叫 elastic

这里的“弹性”是指 stage 之间带有 storage 和 ready/valid 控制：

- 下游可通过 `ready=0` 施加 backpressure；
- 上游在 stall 时保持 transaction；
- 不同 stage 可在同一周期分别 push/pop；
- 一个 stage 停顿不会让其他模块丢失上下文。

“弹性”不等于“多发射”或“乱序”。当前 NPC 仍是单发射、顺序执行。

## 4. 三种 PC 不要混在一起

当前设计中至少有三种与 PC 有关的状态：

| 名称 | 所在位置 | 作用 |
| --- | --- | --- |
| `fetch_pc_q` | IFU | 下一笔计划发出的预测取指地址 |
| `request_pc_q` | IFU | 已被 memory 接受、正在等待 response 的请求地址 |
| `commit_pc` | core | architectural progress 所在的 PC，只在 commit 时更新 |

`fetch_pc_q` 是 speculative state。当前预测策略为 static not-taken，所以每接受一次取指请求就先加 4。它可以跑到尚未 commit 的指令前面，也可能指向错误路径。

`request_pc_q` 是 transaction context。response 返回时只有 instruction data，没有再次附带地址，因此 IFU 必须记住“这份 response 属于哪个请求 PC”。

`commit_pc` 才代表架构执行进度：

```text
reset: commit_pc = 0x8000_0000
commit edge: commit_pc <= commit_npc
no commit: commit_pc remains unchanged
```

在 commit edge 之前，`commit_pc` 与即将提交的 `op_pc` 相等；该 edge 之后，它变成下一条 architectural PC。C++ harness 正是利用这个时序，在 edge 前记录本条指令的 PC/inst，在 edge 后读取更新后的 GPR/CSR/PC 并进行 DiffTest。

## 5. Frontend：IFU 与 IFQ

### 5.1 IFU 为什么需要自己的状态机

instruction memory 不是组合 ROM，而是 request/response 设备。一笔取指会经历：

```text
REQ --request handshake--> WAIT --response handshake--> REQ
```

`ysyx_ifu` 的三个状态是：

- `REQ`：尝试发送 `imem_req_valid/imem_req_addr`；
- `WAIT`：请求已被接受，等待对应 response；
- `DROP`：redirect 已发生，但旧请求无法取消，等待旧 response 返回后丢弃。

IFU 同时最多保留一笔 outstanding transaction。这里 outstanding 的意思是：request 已经握手，但对应 response 尚未握手完成。

### 5.2 为什么请求前要检查 IFQ 空间

IFU 只有在 `ifq_in_ready=1` 时才允许发起新请求。这相当于在发请求时确认未来 response 有存放空间。

当前只有一笔 outstanding，而且等待 response 期间没有其他 producer 会填充这个位置，所以正常 response 返回时一定可以被接收。这个规则称为 credit/resource reservation，它避免了“memory 已经返回数据，但 CPU 没地方放”的死锁风险。

### 5.3 IFQ 保存什么

当前 IFQ 深度为 2，每项保存：

```text
{instruction PC, instruction bits}
```

IFQ 对 backend 输出一个 instruction context：

```text
if_ctx_valid/ready
if_ctx_pc
if_ctx_inst
if_ctx_error       // 当前固定为 0
if_ctx_pred_taken  // 当前固定为 0
if_ctx_pred_npc    // 当前为 pc + 4
```

错误和预测字段虽然尚未真正使用，但提前形成了稳定接口。未来加入 access fault 或 BPU 时，不需要重新定义 frontend/backend 边界。

### 5.4 redirect 为什么需要 DROP

假设 IFU 已经向地址 A 发出请求，此时 backend 发现分支实际跳到 B。CPU 可以清空 IFQ，却不能假设外部 memory 会取消 A：

```text
request A accepted
        │
        ├── branch redirect to B
        │
old response A returns
        │
        └── consume and discard; then request B
```

因此 IFU 进入 `DROP`。旧 response 仍正常握手，以便结束这笔 transaction，但不会进入 IFQ。之后才从 redirect target 继续取指。

## 6. Decode、寄存器读取与 opbuf

IFQ head 进入 backend 前，组合逻辑完成三件事：

1. `ysyx_idu` 产生 ALU、branch、load/store、GPR、CSR、trap 等控制；
2. `ysyx_gen_imm` 生成立即数；
3. `ysyx_regfile` 读取 `rs1/rs2`。

这些结果连同 PC、instruction 和预测信息一起写入 `ysyx_opbuf`。当前 opbuf 保存一份 277-bit context，核心内容是：

```text
identity:    pc, inst
prediction:  fetch_error, pred_taken, pred_npc
datapath:    immediate, ALU selects/control, rs1/rs2 data
control:     branch/jump, GPR writeback, load/store, CSR, trap/mret
indexes:     rs1, rs2, rd
```

### 6.1 为什么不能只保存 instruction

如果 load 正在等待 memory，而 decoder 已经看到下一条 instruction，那么 decoder 输出和 register-file 地址都会改变。EXU 若继续直接读取这些组合信号，就可能把“老指令的 PC”与“年轻指令的 operand/control”拼在一起。

opbuf 的意义是：

> 一条指令一旦进入 backend，它的身份、操作数和控制信息就是一份不可拆分的稳定 context。

当 `op_valid && !op_ready` 时，整份 context 必须保持不变。

### 6.2 为什么需要 writeback-to-read bypass

一条普通 ALU 指令 commit 时，opbuf 可以在同一周期接收下一条指令。假设：

```asm
addi x1, x0, 1
add  x2, x1, x1
```

在第一条指令 commit 的 edge 前：

- register file 中的 `x1` 还是旧值；
- 第一条的 `gpr_write_data` 已经由组合逻辑算出；
- 第二条正在读取 `x1` 并准备写入 opbuf。

因此 core 检查 `gpr_write_idx == dec_rs*_idx`，命中时直接把本周期 writeback value 送入新 context。这是一个边界 bypass，不是完整五级流水 forwarding network。

## 7. Backend：EXU 与集中 commit

`ysyx_exu` 只消费 opbuf，不直接观察 IFU 或 decoder 的瞬时输出。它完成：

- ALU operand 选择和运算；
- branch condition 与 target 计算；
- CSR read/modify/write 数据计算；
- GPR writeback 选择；
- LSU operation 发起与等待；
- `commit_npc`、redirect 和 commit metadata 生成。

### 7.1 单发射、顺序提交是什么意思

单发射表示 backend 每周期最多接收一条新指令。顺序提交表示程序中的老指令未完成时，年轻指令不能越过它更新 architectural state。

当前 opbuf 只有一项，所以这个约束很直接：

- 普通 ALU/branch/CSR 指令可立即完成；
- load/store 等待 LSU response 时，opbuf 保持占用；
- 年轻指令只能停在 IFQ；
- 当前指令 commit 后，opbuf 才能被下一条替换。

### 7.2 commit 是什么

commit 表示一条指令的结果在本 edge 正式成为 programmer-visible architectural state。当前由同一个 `commit_valid` 对齐：

- architectural PC 更新；
- GPR writeback；
- CSR write/trap/mret 更新；
- trace 和 DiffTest 记录；
- redirect 生效；
- memory instruction 对外报告完成。

内部组合信号变化、IFU 发出请求、ALU 算出结果都不算 commit。对当前核而言，“没有 commit 就不能推进 architectural PC/GPR/CSR”是最重要的精确状态原则。

## 8. 三类指令怎样流动

### 8.1 普通 ALU 指令

以 `add x3, x1, x2` 为例：

```text
IFU request -> memory response -> IFQ
    -> decode + read x1/x2
    -> opbuf stores complete context
    -> EXU computes result, commit_valid=1
    -> active edge writes x3 and updates commit_pc
```

opbuf 的 `out_ready` 等于 EXU 的 `commit_valid`。因此本条指令被消费的同一周期，opbuf 可以接收 IFQ 中的下一条 context，不必插入一个清空周期。

### 8.2 Load/store 指令

memory 指令的完整路径是：

```text
opbuf
  │ effective address = rs1 + immediate
  ▼
EXU sends one LSU operation
  ▼
LSU: IDLE -> REQ -> WAIT -> RESP
                 │       │
                 │       └─ buffered result to EXU
                 └───────── dmem request/response
  ▼
EXU commits only when LSU response is valid
```

LSU 在接受 operation 时锁存 direction、address、type 和 write data。此后即使上游组合信号变化，外部 transaction payload 也不会改变。

LSU 的状态含义：

- `IDLE`：可接受 backend operation；
- `REQ`：保持 dmem request，直到 memory ready；
- `WAIT`：请求已接受，等待 response；
- `RESP`：结果已缓存，等待 backend 接收。

load 数据的 byte/halfword sign/zero extension 在 LSU 收到 response 时完成。store 也要等 response 后才 commit，因而不会让年轻指令越过尚未确认完成的 store。

当前 C++ RAM model 会为每笔 request 随机化 request-ready 和 response latency，并保证一次 accepted request 只调用一次 memory backend。这可以暴露“stall 时地址改变”或“同一 store 执行多次”等错误。

### 8.3 Branch、jump、trap 与 mret

这些指令在 EXU 统一计算 `commit_npc`：

```text
trap             -> mtvec
mret             -> mepc
JAL/taken branch -> pc + immediate
JALR             -> (rs1 + immediate) & ~1
otherwise        -> pc + 4
```

控制流改变时，EXU 在 commit 周期产生 `redirect_valid/redirect_target`。IFU 随即：

1. 将 fetch PC 改为 target；
2. flush IFQ 中的年轻指令；
3. 丢弃已经发出但尚未返回的旧路径 response。

当前 opbuf 的 `flush` 固定为 0 并不是遗漏。产生 redirect 的指令正是 opbuf 中最老、正在 commit 的指令，它应该正常出队；同周期 IFU 的 FIFO 因 flush 而压低 `if_ctx_valid`，不会把错误路径年轻指令写入 opbuf。因此需要清空的是 IFQ 和 stale fetch，而不是正在提交的 opbuf entry。

## 9. Architectural state 与 speculative state

理解 CPU 时可以把状态分为两类。

### 9.1 Programmer-visible architectural state

- GPR；
- `mstatus/mtvec/mepc/mcause`；
- architectural PC；
- 已按程序顺序完成的 memory side effect。

软件、DiffTest 和 ISA 规范关心的是这些状态。

### 9.2 Microarchitectural/speculative state

- IFU 的 `fetch_pc_q/request_pc_q/state_q`；
- IFQ 内容和读写指针；
- opbuf valid/context；
- EXU 的 `mem_wait_q`；
- LSU state 和已锁存 request/response。

这些状态帮助硬件应对 latency 和并发，但通常不直接暴露给程序。redirect 可以丢弃错误路径的 microarchitectural state，却不能撤销已经 commit 的 architectural state。

## 10. RTL 与 C++ harness 如何配合

当前 core 对外有两组简化 memory channel：

```text
imem_req / imem_rsp
dmem_req / dmem_rsp
```

C++ `ram_model.cpp` 是它们的 slave model。每个仿真周期大致按以下顺序进行：

```text
clk=0: C++ drive ready/valid/data -> RTL combinational settle
       sample handshakes and commit metadata
clk↑ : RTL registers update; transaction/commit occurs
       C++ RAM model advances its transaction state
clk=0: RTL settles to post-edge values
```

`cpu_exec()` 在调用 `single_cycle()` 前读取 `commit_valid/commit_pc/commit_inst`，因为它们描述“即将在本次上升沿提交的指令”；上升沿后再读取 GPR/CSR 和更新后的 PC，交给 DiffTest 对比。

这也是为什么验证框架应观察 commit boundary，而不是依赖 IFU/IFQ/opbuf 的具体划分：只要新微架构仍提供相同 architectural commit 语义，harness 就无需随内部 stage 重写。

## 11. Assertions 在检查什么

当前 assertions 主要检查接口不变量，而不是某个测试程序的预期答案：

| 检查 | 可发现的错误 |
| --- | --- |
| stalled request/context 保持 | `ready=0` 时地址、数据或指令偷偷变化 |
| response 必须对应 outstanding | 无请求却收到/消费 response |
| memory commit 必须有 LSU response | load/store 提前提交 |
| opbuf stall 时保持完整 context | 等待期间混入年轻指令信息 |
| commit PC 等于 architectural PC | 提交顺序或 PC 对齐错误 |
| bypass 后 operand 等于 writeback data | 相邻 RAW 使用旧寄存器值 |
| stale fetch 不进入 IFQ | redirect 后执行错误路径 |

assertion 的价值在于尽量靠近错误发生的第一个周期报错。DiffTest 可能要等错误结果写入 GPR 后才发现 mismatch，而协议 assertion 往往能直接指出是哪条 holding/ownership 规则被破坏。

## 12. 如何观察和验证

推荐从小到大验证：

```bash
make -C npc lint
make -C npc primitive-test
make -C npc ifu-test
make -C npc lsu-test
make -C npc exu-test
```

随后运行单项和完整 CPU tests：

```bash
make -C am-kernels/tests/cpu-tests ARCH=riscv32e-npc ALL=add run
make -C am-kernels/tests/cpu-tests ARCH=riscv32e-npc run
```

观察波形时，建议按 transaction/context 分组，而不是一次铺开所有信号：

1. IFU：`imem_req_*`、`imem_rsp_*`、`state_q`、`fetch_pc_q`；
2. instruction context：`if_ctx_*`；
3. opbuf：`op_valid/op_ready/op_pc/op_inst`；
4. LSU：`lsu_req_*`、`dmem_req/rsp_*`、LSU state；
5. retirement：`commit_valid/pc/inst/npc`、GPR/CSR write；
6. recovery：`redirect_valid/target` 与 IFQ flush。

对任意异常现象，优先回答四个问题：

1. request 在哪个 edge 握手？
2. response 属于哪笔 request？
3. 当前 context 存在哪个寄存器/FIFO 中？
4. architectural state 到底在哪个 commit edge 改变？

## 13. 当前设计有意保留的限制

当前结构已经适合继续演进，但还不是完整 SoC core：

- instruction/data 接口还是自定义简单 channel，不是 AXI4-Lite；
- IFU 和 LSU 各只支持一笔 outstanding；
- 分支预测固定为 not-taken；
- fetch/data response 尚无 error 字段，access fault 尚未走精确 trap；
- 没有 cache、乘除法、多发射、乱序执行或中断输入；
- IFQ/opbuf 很小，目标是建立清晰边界，不是追求最终性能；
- CSR/特权功能只覆盖当前 workload 需要的最小集合。

这些限制多数是刻意控制复杂度。下一阶段首先补齐精确 memory error；再把 IFU/LSU 外部接口适配为 AXI4-Lite，加入 Arbiter、Xbar 和最小 peripheral system。

## 14. 源码阅读顺序

建议按数据流阅读，而不是从文件名猜功能：

1. [`ysyx_core.sv`](../../../../npc/vsrc/core/ysyx_core.sv)：先看模块连接、architectural state 和 commit；
2. [`ysyx_ifu.sv`](../../../../npc/vsrc/core/ysyx_ifu.sv)：理解 fetch transaction、IFQ 和 redirect；
3. [`ysyx_gnrl_primitive.sv`](../../../../npc/vsrc/gnrl/ysyx_gnrl_primitive.sv)：理解 `ysyx_gnrl_rv_reg` 与 FIFO；
4. [`ysyx_opbuf.sv`](../../../../npc/vsrc/core/ysyx_opbuf.sv)：看完整 operation context；
5. [`ysyx_exu.sv`](../../../../npc/vsrc/core/ysyx_exu.sv)：看完成条件、commit 和 redirect；
6. [`ysyx_lsu.sv`](../../../../npc/vsrc/core/ysyx_lsu.sv)：看 data transaction ownership；
7. [`ram_model.cpp`](../../../../npc/csrc/memory/ram_model.cpp)：看 variable latency slave 如何驱动握手；
8. [`sim.cpp`](../../../../npc/csrc/sim.cpp)：看 commit、仿真 edge 与 DiffTest 的对应关系。

## 15. 与工业界设计的关系

通用思想与真实处理器一致：

- 用 ready/valid 划分模块责任；
- transaction 发出后保存 owner/context；
- stalled payload 必须稳定；
- speculative frontend 与 architectural commit 分离；
- redirect/flush 只清除年轻指令；
- verification 以 commit 和协议 invariant 为核心。

真实高性能 CPU 会加入更深流水、多 outstanding、cache、TLB、BPU、scoreboard/ROB 和复杂异常恢复，但这些机制仍建立在相同的 ownership、context、backpressure 和 precise commit 原则上。

## 16. 工业界中的相关岗位

- **Digital IC / RTL Design Engineer**：实现和维护 IFU、EXU、LSU、FIFO、流水控制及总线接口，需要正确处理 stall、flush 和时序边界。
- **CPU / Microarchitecture Engineer**：定义指令如何在 frontend/backend 中流动，权衡 buffer、并发度、恢复代价和性能。
- **SoC Design Engineer**：将 core 的 transaction 接口连接到 Arbiter、Xbar、memory 和 peripherals，并保证 ownership 与错误响应正确。
- **Design Verification Engineer**：设计随机 backpressure、协议 assertions、reference model 和 coverage，寻找重复 transaction、丢 response、错误提交等 corner case。

## 17. 真正需要记住的内容

1. 当前 NPC 不是传统五级流水，而是一个小型 elastic frontend/backend。
2. ready/valid 的核心是“只有 handshake 才转移，stall 时 payload 保持”。
3. IFU 拥有 speculative fetch，opbuf 拥有当前 operation，LSU 拥有 data transaction。
4. context 必须整体保存，不能在 stall 后重新拼接当前组合信号。
5. architectural state 只在 commit edge 更新；DiffTest 也应以 commit 为边界。
6. redirect 清除年轻 IFQ/stale fetch，不清除正在 commit 的最老 opbuf instruction。
7. 单发射并不妨碍 fetch/execute overlap；它只是限制 backend 同时处理和提交的指令数。
8. 先把 transaction、ownership 和 precise commit 做正确，再增加 AXI、BPU 或更高并发度。
