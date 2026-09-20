# 可变延迟取指：实现 Review 与后续改进

本文记录第一版 instruction fetch request/response 实现通过 CPU tests 后，仍值得改进的部分，并说明是否需要为此改写 SystemVerilog，以及 assertion 在此类设计中的用途。

> 审阅基线（2026-09-17）：最近的已提交版本为 `b272322f5fdc`（`feat(p-c-1): i ram handshake support v1`）。本文后续改进目前仍位于 working tree；该 hash 只标识最初被审阅的已提交基线，具体状态应结合 `git status`/`git diff` 判断。

## 1. 当前实现处于什么状态

当前实现已经完成最小闭环：

- CPU 使用 `IF_REQ -> IF_WAIT -> EXEC` 控制取指、等待与提交；
- request/response 分别使用 valid-ready 握手；
- response handshake 时锁存指令；
- PC、GPR、CSR、trap/mret 和 data-memory enable 均由 `commit_wb` 门控；
- C++ memory model 独立位于 `npc/csrc/memory/ram_model.cpp`，使用跨 `cpu_exec()` 持久化的 `IDLE/WAIT/RESP` FSM；
- request handshake 时锁存地址并生成 latency，backend 每笔 transaction 只读取一次；
- response valid/data 保持到 response handshake；
- request ready、最大 response latency 和随机 seed 均可配置并记录；
- 修正 latency 计数器递减错误后，现有 CPU tests 可以通过。

CPU 已不再依赖“组合读、当拍得到指令”的假设；当前 C++ 模型也不再依赖 request 永远 ready 或 response 立即被接收。模型目前仍是 instruction port、single-outstanding slave，后续可复用同一 transaction contract 改造 load/store。

## 2. 建议改进项

### P0：把 C++ RAM 写成持久化 transaction FSM（已完成）

原实现的 `req_done`、地址和 latency 都是 `cpu_exec()` 局部变量，且产生 response 时没有检查 `if_rsp_ready`。现已改为生命周期独立于单次调试命令的对象：

```text
IDLE --req_fire--> WAIT --latency_done--> RESP --rsp_fire--> IDLE

req_fire = if_req_valid && if_req_ready
rsp_fire = if_rsp_valid && if_rsp_ready
```

每个状态只承担一种职责：

- `IDLE`：允许接收一个 request；只在 `req_fire` 时锁存地址并生成本次 latency；
- `WAIT`：递减 latency，不再观察或覆盖 request payload；
- `RESP`：保持 `if_rsp_valid=1` 和 `if_rsp_data` 不变，直到 `rsp_fire`；
- reset：显式清空 outstanding transaction 和所有输出。

这项改进解决三个隐患：

1. `if_rsp_ready=0` 时，当前实现会丢掉 response；
2. 多次执行 SDB 的 `si/c` 时，memory transaction 和随机序列不应随 `cpu_exec()` 被重新初始化；
3. 未来把同一模型用于 load/store 或 MMIO 时，backend read/write 必须对每笔 transaction 只执行一次，不能因等待而重复产生设备副作用。

### P0：明确每周期的仿真调度（已完成）

每个 cycle 已按以下顺序调度并写入注释：

```text
memory model drive inputs
-> RTL combinational eval
-> sample req_fire/rsp_fire
-> active clock edge
-> RTL sequential update
-> memory model state update
```

具体代码可以根据 Verilator harness 的结构调整，但必须能回答两个问题：握手在哪个 edge 被采样，以及 model 在什么时候改变 `valid/data`。不要让一次 helper 调用同时含混地完成 drive、sample 和 transaction 状态切换。

`single_cycle()` 现在会先保持 `clk=0` 完成 `drive -> eval -> dump`，采样 handshake 后再执行 rising-edge `eval -> dump`，因此 C++ memory input 的 setup value 可在 FST 中单独观察。寄存器更新及其引起的组合逻辑收敛仍显示在同一个 post-edge timestamp，不用于区分 delta-cycle。

### P1：扩大 backpressure 覆盖范围（已完成 request 侧）

`if_req_ready` 现由持久化 model 随机拉低，用于验证 requester 在 request stall 时保持 `valid/address`。参数通过 NPC 命令行传入：

```text
--ram-seed=SEED
--ram-max-latency=N
--ram-ready-percent=N
```

默认配置为 seed 42、最大等待 3 cycles、request ready 概率 75%。仿真结束时打印 request/response 数量和两侧 stall cycles，便于确认测试确实覆盖 backpressure。当前 CPU 在 `IF_WAIT` 中始终准备接收 response，因此 response stall 计数通常为 0；model 已能保持 response，主动随机化该方向留待 IFU 解耦后进行。

建议按以下顺序扩展：

1. 固定 latency 回归；
2. 随机 response latency；
3. 随机拉低 `if_req_ready`；
4. 若未来允许 response backpressure，再随机化 CPU 的 `if_rsp_ready`。

随机数发生器现使用 `std::mt19937`，仅在 model 初始化/reset 时设置 seed，不再随每次 `cpu_exec()` 重置。固定 seed 用于复现，变化 seed 用于扩大探索范围。

### P1：收紧 RTL 的接口与防错约束（已完成）

- [x] 将 `if_req_data` 改名为 `if_req_addr`，直接表达 payload 含义；
- [x] reset 期间强制 CPU request/response 控制信号及 memory-model 输出无效；
- [x] 保留组合逻辑默认赋值和 `case default`，避免 latch 和非法状态卡死；
- [x] 在 core/FSM 使用 `` `default_nettype none ``，避免拼写错误自动生成 wire；
- [x] `DEBUG` 下的 `putchar` 改用最终 store enable 与 `commit_wb`；
- [x] `PC_RST` 参数用于 PC reset value，并修正 data RAM mask 常量位宽告警。

### P1：加入少量协议 assertion

第一轮只需检查最关键的不变量：

1. request 被阻塞时，request valid 和 address 必须保持；
2. response 被阻塞时，response valid 和 data 必须保持；
3. PC/GPR/CSR/store/trap/mret 等副作用不得在 `commit_wb=0` 时发生；
4. memory model 最多只有一笔 outstanding request，且不能凭空产生 response。

不要一开始追求大量 assertion。先为最容易写错、且普通 testcase 不一定能立即暴露的协议规则建立护栏。

### P2：分层回归

建议至少保留以下层次：

- protocol-directed test：强制 request/response stall，专门观察握手和 payload stability；
- CPU tests：覆盖基本 ISA 与不同随机 seed；
- hello、RTC、yield-os：覆盖 MMIO、CSR/trap 和较长程序；
- DiffTest：在 commit 点检查 architectural state；
- waveform：只在失败时定位周期级原因。

## 3. 是否值得把 RTL 改成 SystemVerilog 风格

不需要为了本增量全面改写。当前文件本来就以 `.sv` 交给 Verilator，但继续使用 `wire/reg`、`always @(*)`、`localparam` 和普通 `case` 完全可行；只要组合赋值完整、时序逻辑使用非阻塞赋值、接口规则明确，就不会因为“写得像 Verilog”而降低功能正确性。

部分 SystemVerilog 语法确实能增强工具检查，但应按收益选择，而不是作为风格目标：

| 写法 | 实际收益 | 当前建议 |
| --- | --- | --- |
| `logic` | 一个类型可用于多数 net/variable 场景，减少声明选择 | 可用但非必要，`wire/reg` 更能显式区分连接与过程变量 |
| `always_comb` | 自动生成敏感列表，并可检查部分错误驱动关系 | 新代码可采用；已有完整的 `always @(*)` 无需专门重写 |
| `always_ff` | 强调寄存器只由一个时序过程驱动 | 当前寄存器多封装在通用 DFF module 中，收益有限 |
| `typedef enum logic` | 状态名、位宽和 waveform 可读性更好，lint 更容易检查 | FSM 扩大时值得使用；三个状态用 `localparam` 也足够 |
| `unique case` | 仿真器可对无匹配或多重匹配给出警告 | 可选；仍需理解 X 值行为，不能代替默认赋值 |
| SVA `assert property` | 自动检查跨周期协议和时序不变量 | 有直接验证价值，建议少量引入 |

对当前工程，优先级更高的是：禁止 implicit net、完善握手 model、增加 assertion。将所有 `reg` 替换成 `logic` 本身几乎不会带来功能收益。

## 4. Assertion 是什么

Assertion 是写在 RTL/verification code 中的“可执行规则”。仿真器在每个指定采样点自动检查规则；一旦不满足，就立即报告 assertion 名称和失败时间。

它通常不描述 CPU 要实现的新硬件功能，而是检查已有设计是否遵守约定。例如：

> 如果 master 已经给出有效 request，但 slave 本拍没有 ready，那么 master 下一拍必须继续保持 valid，且 address 不得改变。

普通 CPU test 只会在最终结果错误时失败，DiffTest 主要在 commit 点比较架构状态；assertion 可以在协议第一次被破坏的那个 cycle 就失败，因此更接近根因。三者不是替代关系：

```text
testcase 产生场景
assertion 检查周期级协议/微架构不变量
DiffTest 检查 commit 后的架构结果
```

## 5. `assert property` 语法入门

以当前 instruction request 为例：

```systemverilog
a_if_req_stable_when_stalled:
  assert property (@(posedge clk) disable iff (!rstn)
    if_req_valid && !if_req_ready
    |=> if_req_valid && $stable(if_req_addr));
```

逐项理解：

- `a_if_req_stable_when_stalled:`：给 assertion 命名，失败日志可直接指出是哪条规则；
- `assert property (...)`：声明需要持续检查的一条时序性质；
- `@(posedge clk)`：每个上升沿采样一次表达式；
- `disable iff (!rstn)`：reset 有效时不启动检查，并取消尚未完成的检查；
- `if_req_valid && !if_req_ready`：前件，即“本拍 request 正在等待”；
- `|=>`：非重叠蕴含；当前件在本拍成立时，后件必须在下一拍成立；
- `$stable(if_req_addr)`：本拍采样值必须和上一拍相同。

因此整条规则的含义是：若第 N 拍发生 request stall，则第 N+1 拍 `if_req_valid` 仍为 1，而且 request address 与第 N 拍一致。

常见符号还有：

- `A |-> B`：A 成立时，从同一拍开始检查 B；适合同周期关系；
- `A |=> B`：A 成立时，从下一拍开始检查 B；适合下一周期关系；
- `##1`：延后一拍；`##n` 表示延后 n 拍；
- `$past(x)`：x 在上一个采样点的值；
- `$stable(x)`：x 相对上一个采样点没有变化。

例如 response provider 也应满足相同的保持规则：

```systemverilog
a_if_rsp_stable_when_stalled:
  assert property (@(posedge clk) disable iff (!rstn)
    if_rsp_valid && !if_rsp_ready
    |=> if_rsp_valid && $stable(if_rsp_data));
```

架构副作用门控属于同周期关系，概念上可以写成：

```systemverilog
a_no_side_effect_without_commit:
  assert property (@(posedge clk) disable iff (!rstn)
    !commit_wb |-> !(gpr_write_en || csr_write_en || store_en || trap_en || mret_en));
```

这里的 `*_en` 应连接到真正送入状态单元的最终 enable，而不是 decoder 输出的 raw intent，否则检查的对象会错。

## 6. Assertion 放在哪里、如何启用

第一版可直接放在拥有相关信号的 module 内，并用宏控制：

```systemverilog
`ifdef ASSERT_ON
  // assert property ...
`endif
```

当前安装的 Verilator 5.008 支持 assertions；运行仿真时还需在 Verilator flags 中加入 `--assert`，并定义相应宏。后续若不希望 verification code 混在设计文件中，可以再使用独立 checker 和 `bind`，当前阶段没有必要先增加这层复杂度。

虽然 `assert property` 属于 SystemVerilog Assertions（SVA），它不要求主体 RTL 同时改成 `logic/always_ff/enum` 风格。可以继续保留传统 Verilog RTL，仅在验证边界使用少量 SVA。

## 7. 本轮验证结果（2026-09-18）

- `make lint`：通过；剩余告警为已有的未使用参数/位段，本轮已消除 data RAM mask 的位宽扩展告警。
- 完整清理并重建 Verilator 模型：通过。
- RV32E NPC 全量 CPU tests：35/35 通过。
- 压力配置 `seed=1, max_latency=10, ready=30%`：`bubble-sort` 通过，产生 306846 个 request stall cycles，且 request/response 计数一致。
- 在同一 NPC 进程中分多次执行 `si 1` 后再 `c`：正常 HIT GOOD TRAP，验证 transaction 状态和 RNG 不会因 `cpu_exec()` 返回而重置。
- `am-tests` interrupt/yield 启动 smoke test：运行 30 s 未观察到 abort；该 case 持续运行，不作为有限时长的 pass/fail 用例。

当前边界：当前 CPU 在 `IF_WAIT` 始终保持 `if_rsp_ready=1`，所以尚未主动覆盖 response stall；RAM model 已具备正确保持 response 的能力。`npc/Makefile` 已于 2026-09-20 将 `filelist.f` 展开为 RTL 依赖，修改 RTL 后不再需要额外执行 `make clean` 才能触发 Verilator 重建。

## 8. 后续顺序

1. 添加 request/response stability 两条 assertion；
2. 添加“无 commit 则无架构副作用”检查；
3. IFU 解耦后主动制造 response backpressure；
4. 使用多个固定 seed 回归，在失败时记录 seed 以便复现。

完成本轮改造后，这个增量的价值不再只是“给 RAM 加随机等待”，而是建立了一份可迁移到 D-port、总线 adapter、cache 和流水线前端的 transaction contract。
