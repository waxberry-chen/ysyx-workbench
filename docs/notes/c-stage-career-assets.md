# C 阶段求职资产与后续高收益路线

> 更新日期：2026-09-13  
> 目标岗位：SoC/RTL Design > Design Verification > Physical Design  
> 用途：维护已经能够举证的能力、简历表述、展示材料和后续投入优先级。具体进度以各阶段总结与 sign-off 记录为准。

## 1. 当前定位

当前工程已经适合作为实习简历中的主要项目之一，推荐名称为：

> **基于 Verilator/NEMU DiffTest 的 RV32E 处理器与验证平台**  
> **RV32E RISC-V Processor and Differential Verification Platform**

它现阶段最有说服力的部分不是“完成了若干课程任务”，而是已经形成以下闭环：

```text
ISA/异常规格
  -> SystemVerilog RTL
  -> Verilator simulation harness
  -> NEMU reference model + commit-driven DiffTest
  -> trace / waveform / lint / regression
  -> AM test and RT-Thread workload bring-up
```

对 RTL/SoC Design，它证明了基本处理器设计、架构状态更新、异常控制流和软硬件集成能力；对 Design Verification，它证明了 reference model、checker、提交级比较、回归与首错定位能力。

必须同时明确当前边界：这是 **RV32E 单周期核及最小 M-mode 同步异常系统**，尚不是五级流水 SoC；未实现 AXI、Cache、异步 timer interrupt、抢占式调度、UVM/coverage、综合/STA/PPA 或完整 privileged architecture。

## 2. 已有可展示项

| 可展示项 | 当前证据 | 对应岗位能力 | 简历优先级 |
|---|---|---|---:|
| RV32E 单周期 CPU RTL | NPC 35/35 CPU tests，在 DiffTest 开启时通过 | RTL data/control path、译码、ALU、访存、branch/jump | P0 |
| commit-driven DiffTest | 逐提交比较 PC、GPR 和四个 CSR；NEMU REF 通过 `.so` 动态链接 | architectural state、reference model、checker、co-simulation | P0 |
| CSR 与同步 trap | `mstatus/mtvec/mepc/mcause`、`CSRRW/CSRRS/ecall/mret` | ISA state transition、控制优先级、精确状态更新基础 | P0 |
| Context switch 与 RT-Thread | NEMU/NPC 均启动 RT-Thread 5.0.1；NPC 全程 CSR DiffTest 无 mismatch | ABI、trap frame、stack、hardware/software bring-up | P0 |
| MMIO、UART、RTC | `hello` GOOD TRAP；AM RTC 连续读时正确 | address decode、MMIO side effect、SoC peripheral integration 基础 | P1 |
| ITrace、FST、边界检查和 lint | commit-driven trace、可复现波形、Verilator lint、BAD TRAP 退出 | debug methodology、design quality、failure triage | P0 |
| 跨层故障定位 | `csrr_wdata` implicit net、旧 REF `.so` ABI 不一致、DiffTest 时序分析 | root-cause analysis、接口契约、回归意识 | P0 |
| NEMU/AM 基础设施 | reference API、CTE、Context、trap.S、klib 和构建链 | C/C++、汇编、ABI、软件载荷构造 | P2：作为支撑，不单独主讲 |

现有长期材料入口：

- [C4 阶段总结](../notes/C4.md)：RV32E CPU、commit、DiffTest 和验证框架；
- [C5 阶段总结](../notes/C5.md)：MMIO、UART、RTC；
- [C6 开发日志](c6/c6-dev-log.md)：CSR、trap、Context、RT-Thread 和当前 sign-off 状态；
- [同步时序描述方法](synchronous-timing-description.md)：clock edge、state 和 cycle 的精确定义；
- [DiffTest 绘图建议](difftest-framework-figure-guide.md)：验证框架展示结构；
- [trap mechanism](c6/trap-mechanism.md) 与 [context switch](c6/context-switch-mechanism.md)：异常和上下文切换专题。

## 3. 简历写法

### 3.1 中文版本

建议保留三至四条，每条采用“设计/问题 + 方法 + 可量化证据”的结构：

- 使用 SystemVerilog 设计并验证 RV32E 单周期处理器，支持基础整数运算、访存、分支跳转及 UART/RTC MMIO；在 NEMU DiffTest 开启时通过 **35/35 CPU tests**。
- 实现最小 M-mode 异常机制，包括四个核心 CSR、CSR 原子读改写、`ecall/mret`、trap 状态更新和 next-PC redirect，并通过 RT-Thread workload 验证重复异常返回与 Context switch。
- 构建 instruction-commit-driven DiffTest 框架，通过动态链接 NEMU reference model 逐指令比较 PC、GPR 和 CSR architectural state，并集成 ITrace、FST 波形及 mismatch 首错定位。
- 完成 AbstractMachine Context 创建/保存/恢复，在 NEMU 与 RV32E NPC 上启动 **RT-Thread 5.0.1**；NPC 全程开启 CSR-aware DiffTest，执行预置 shell 命令无状态失配。

若版面只能容纳三条，可将第一、二条合并，保留 DiffTest 和 RT-Thread 两条；它们比普通“CPU tests 通过”更能区分同类教学项目。

### 3.2 English version

- Designed and verified a single-cycle RV32E processor in SystemVerilog with integer, control-flow, load/store, UART and RTC MMIO support; passed **35/35 CPU tests** with NEMU differential testing enabled.
- Implemented a minimal RISC-V M-mode trap path covering four architectural CSRs, atomic CSR read-modify-write, `ecall/mret`, trap-state updates and next-PC redirection.
- Built an instruction-commit-driven co-simulation framework that dynamically links a NEMU reference model and compares PC, GPRs and CSRs, with instruction trace and waveform-assisted first-failure debug.
- Brought up **RT-Thread 5.0.1** on both NEMU and the RV32E RTL simulator through AbstractMachine context creation/switching; completed the NPC workload under CSR-aware DiffTest without architectural mismatches.

### 3.3 不应过度表述

在对应功能和证据完成前，不使用以下说法：

- “五级流水处理器”“AXI SoC”“L1 Cache subsystem”；
- “完整 RISC-V 特权架构”“支持抢占式 RTOS/中断系统”；
- “UVM verification environment”“coverage closure”“formal verified”；
- “完成综合与时序收敛”“PPA optimized”；
- “完整工业级 SoC”。

范围描述准确是一项工程能力。面试中应主动说明：当前 C6 验证的是 all-M-mode 同步 trap 和协作式切换，timer IRQ 与精确异步中断属于后续 SoC 主线。

## 4. 值得准备的展示材料

### 4.1 项目展示 PDF/PPT

建议维护一份 6～8 页的母版，可按面试时间裁剪：

1. **Problem and scope**：项目目标、当前能力、明确不在范围内的功能；
2. **Processor architecture**：RV32E 单周期数据/控制通路，区分组合计算、时序状态和不可综合 harness；
3. **Verification framework**：guest software、AM、NPC harness、RTL、NEMU REF、dynamic linking 和 commit interface；
4. **Trap and context sequence**：`ecall -> mtvec -> trap.S -> handler -> selected Context -> mret`，标注 CSR 与 `sp` 变化；实现 RISC-V M-mode CSR、ecall/mret 与异常重定向，并通过 AM yield/context-switch 测试及 RTOS smoke workload 验证完整 trap-return 路径。
5. **Verification plan and results**：测试矩阵、35/35、hello、RTC、yield-os、RT-Thread、lint；
6. **Debug case study**：首错现象、波形/trace、根因、修复及防回归措施；
7. **Design boundaries and trade-offs**：为什么按 commit 对比、为什么 C6 只做最小 CSR、哪些工作主动延期；
8. **Next architecture**：AXI、五级流水、I-cache 和验证增强路线。

每张图必须回答一个工程问题，而不只展示模块位置。例如：

> Why can the same DiffTest framework verify both a single-cycle core and a future pipelined core?

答案应落到稳定的 commit contract 和 architectural state，而不是两种微架构逐周期一致。

### 4.2 优先整理的 debug case

#### Case A：`csrr_wdata` implicit net 导致 `mtvec=0`

- 现象：第一次 `ecall` 跳到地址 0，触发 MMIO/访存边界错误；
- 证据：CSR 波形、反汇编中的 `csrw mtvec`、lint `IMPLICIT/WIDTH` 告警；
- 根因：重构后拼写错误被 Verilog implicit wire 规则接受；
- 长期措施：lint gate、``default_nettype none``、明确接口命名和定向 CSR test。

#### Case B：DiffTest `.so` ABI 漂移产生随机 CSR mismatch

- 现象：REF CSR 为随机值，DUT CSR 为 0；
- 根因：调用方扩大 `CPU_state`/复制长度后没有重编译 REF 动态库；
- 关键认识：symbol 可由 `dlsym()` 解析不代表结构体布局和复制长度兼容；
- 长期措施：共享协议定义、`sizeof/offsetof` assertion、接收对象初始化、clean rebuild。

#### Case C：commit 与 MMIO 同步时机

- 说明 architectural state、当前提交指令、时钟沿前后状态和 REF step 的对应关系；
- 展示框架只依赖 commit/architectural state，MMIO 数据通过受控同步处理，而不依赖具体流水级；
- 作为未来单周期核迁移到流水线核时的验证契约。

### 4.3 Sign-off evidence package

每个主要里程碑至少保存：

- 版本号和依赖 commit；
- 一键复现命令及工具版本；
- verification matrix 与 PASS/FAIL 结果；
- 一份关键 trace 或波形；
- 一次有效 fault injection；
- 已知限制和未覆盖范围。

不把巨大 FST、构建目录或完整日志提交到源码仓库；保留裁剪后的截图、关键日志片段和生成方法。

## 5. 应成为长期记忆的内容

不需要记忆文件路径和课程步骤，应能够从以下原则重新推导实现：

1. 时钟沿、cycle interval、组合输出和寄存器状态如何准确描述；
2. architectural state 与 microarchitectural state 的边界；
3. commit 为什么是处理器 reference checking 的稳定接口；
4. CSR read-modify-write、trap entry 和 `mret` 的状态转移；
5. 为什么已处理 `ecall` 的 `mepc += 4` 是软件 policy，而非 `mret` 固定行为；
6. trap frame、Context、stack alignment 和 C/assembly ABI 为什么必须一致；
7. MMIO side effect、RAM access 与 DiffTest skip/synchronize 的区别；
8. 动态库 symbol ABI、结构体 layout 和 copy size 的契约；
9. 如何从第一个 architectural mismatch 反查 RTL 的错误提交；
10. 功能通过之后为什么还需要 lint、assertion、coverage、synthesis 和 STA。

每个主题准备三个深度：30 秒定义、3 分钟白板说明、10 分钟结合源码/波形复盘。面试官通常更关心“为什么这样设计、怎么知道它是对的、失败时怎么定位”，而不是代码行数。

## 6. C 阶段之上的高收益补充

当前招聘侧对 RTL/SoC Design 普遍强调 microarchitecture specification、SystemVerilog RTL、SoC integration、lint/CDC/RDC、synthesis/STA 和 PPA；DV 岗位强调 test plan、reusable testbench、stimulus/checker、assertion、coverage、regression 和 debug。参考当前官方岗位描述：[Apple Early-Career SoC Digital Design](https://jobs.apple.com/en-my/details/200664872-1731/early-career-soc-digital-design-engineer-m-f-d?team=HRDWR)、[Apple Design Verification](https://jobs.apple.com/en-ca/details/200658362/design-verification-engineer)、[NVIDIA Hardware Verification Internship](https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite/job/US-CA-Santa-Clara/NVIDIA-2027-Internships--Hardware-Verification_JR2023500?workerSubType=0c40f6bd1d8f10adf6dae42e46d44a17)。岗位链接会变化，只用于校准能力方向。

[B 阶段讲义](../lectures/ysyx/ysyx2306-b-stage.md) 与这些高收益增量高度重合：它能覆盖约 **80% 的方向选择**和 **60%～70% 的实现任务分解**，但不能替代 AXI 官方规范、模块级微架构设计以及工业级 DV/时序方法。B1、B3、B4、B5 与求职目标高度相关；B2 同时包含重要的 SoC 集成和较多板级/外设工作，需要按目标控制投入。

### 6.1 高收益增量与 B 阶段对应

| 求职增量 | 讲义对应 | 支持程度 | 仍需自行补充 |
|---|---|---:|---|
| 可变延迟 memory request/response | B1 §3.1～3.2 | 很高 | 具体接口契约、FSM 和 assertion |
| AXI4-Lite master、arbiter、Xbar | B1 §3.2～3.3 | 很高 | AMBA AXI4-Lite 规范、完整协议 checker |
| SRAM/UART/CLINT 与随机延迟 | B1 §3.2，B2 §4.2 | 很高 | `mtimecmp/mie/mip` 与异步 timer interrupt |
| ysyxSoC、bootloader、外部存储 | B2 | 高 | 取舍具体外设，不必并行实现所有存储器 |
| 性能计数器、基线和 PPA 意识 | B3 §5.1～5.2，B5 | 高 | 完整 SDC、CDC/RDC、功耗分析和 timing closure |
| 简单 I-cache 与设计空间探索 | B3 §5.3～5.4 | 很高 | 更复杂 refill、non-blocking cache、D-cache |
| 五级流水、冒险和精确异常 | B4 §6.1～6.2 | 很高 | 具体 hazard matrix、模块接口和优先级规格 |
| forwarding、预测评估、`fence.i` | B4 §6.3～6.4 | 高 | GShare/BTB 细节、预测元数据和 GHR recovery |
| lint、四值/网表仿真和 CI | B5 | 高 | 商业工具流程、CDC/RDC、LEC、UPF |
| SVA、random、scoreboard、coverage | B1/B4 只给出原则 | 中低 | 可复用 SV/UVM 环境和 coverage closure |

讲义中的 RT-Thread 应继续被视为覆盖长控制流、总线延迟和 Context/异常路径的 **system workload**，而不是独立的软件项目亮点。

### 6.2 当前直接入口：C6 snapshot 后进入 B1

先用很短的窗口完成 C6 收口：

- 有效的 CSR RTL fault injection；
- 一份 `ecall -> trap -> handler -> mret` trace/波形；
- 固定当前回归命令、结果和 commit。

之后不再扩建 C6 软件，直接执行 B1。第一项增量详见[可变延迟 Memory Request/Response 教程](post-c/1-variable-latency-memory-request-response.md)。B1 的第一步不是立即拼接 AXI 信号，而是把 C 阶段零延迟 DPI-C 内存访问改造成显式 transaction：

1. 为 IFU、LSU 和 memory 写 request/response specification；
2. 明确 `valid/ready`、地址、数据、mask、error 和 response ownership；
3. 让 load 经历 request、wait、response、writeback；
4. 先接固定延迟 memory，再加入 5/10/20 周期和随机延迟；
5. 用现有 CPU tests、DiffTest、hello 和 RTC 保持架构回归；
6. 最后映射成 AXI4-Lite master/slave、arbiter 和 Xbar。

这一步直接解决 C 阶段 I/D RAM 零延迟、CPU 与存储系统强耦合的问题，并建立流水线、Cache 和 SoC 都依赖的 handshake/backpressure 基础。

### 6.3 B1：最高优先级的 SoC Design 增量

B1 应基本完整完成：

```text
IFU read master ----+
                     +---- arbiter ---- SRAM
LSU read/write ------+
                           |
                           +---- Xbar ---- UART
                                        CLINT
                                        error slave
```

必须能够解释并验证：

- AXI4-Lite 五通道为何彼此独立；
- 为什么 `valid` 不能等待 `ready`；
- AW/W 不同时到达时 slave 如何保存状态；
- arbiter 如何记住请求来源并路由返回响应；
- backpressure 下如何保持 payload 稳定；
- 非法地址如何返回 `decerr` 而不是被 CPU 提前吞掉；
- 固定/随机延迟下为何不会死锁、活锁或重复提交。

B1 的输出应包括总线接口规格、状态图、AXI/arbiter/Xbar RTL、随机延迟 regression、协议 assertion 和改造前后的周期数/Fmax 基线。这是当前从“教学单周期核”迈向 SoC RTL 最关键的一步。

### 6.4 B2：完成最小 SoC 闭环，选择性投入外设

高收益且建议完成：

- 接入 ysyxSoC，完成 MROM/SRAM 取指访存；
- 在 SoC 环境恢复 DiffTest；
- `mem-test` 和非法访问错误；
- bootloader、LMA/VMA、`.data` 搬运；
- UART16550；
- 选择一条 Flash/PSRAM/SDRAM 路径完成启动闭环。

若以官方 B 阶段考核为目标，还需满足 NVBoard 和外设验收。若以求职收益为目标，VGA、PS/2、游戏、大量 RT-Thread 外设软件和多套外部存储器不应同时展开；重点展示地址空间、boot flow、memory controller、总线集成和验证。

### 6.5 B3：用数据证明设计，而不只增加功能

B3 对简历价值很高，建议完整保留以下资产：

- cycle、instruction、IPC/CPI 和 stall-reason counter；
- 固定 workload、时钟和延迟模型的 microbench baseline；
- 综合频率、面积、关键路径和估算运行时间；
- 可参数化的简单 I-cache；
- hit rate、miss penalty、AMAT 和配置对比；
- DiffTest + random/formal 中至少两类验证；
- cachesim 或等价设计空间探索。

讲义选择先在较简单的核上验证总线和 I-cache，再进入流水线。这比同时调试 cache refill、pipeline stall 和 flush 风险更低，适合作为第一次完整实现的顺序。

### 6.6 B4：RTL/CPU Design 的主体项目

B4 是与 CPU/RTL Design 最直接对应的阶段：

- 每级 pipeline register 和 `valid`；
- 结构、数据、控制冒险；
- conservative stall 到 forwarding 的增量优化；
- load-use、branch flush 和 store side effect；
- CSR/trap 信息随指令流动；
- 精确异常和错误路径不得更新 architectural state；
- `fence.i`、I-cache invalidation 和 pipeline flush；
- DiffTest、随机指令、assertion/formal 与 performance counter 联合验证。

C6 的异常知识在此转化为真正的微架构问题：异常在哪一级发现、何时允许提交、`mepc` 对应哪条指令、branch redirect/trap/stall 的优先级如何定义，以及年轻指令和在途 store 如何被取消。RT-Thread 仍只作为长回归载荷，不单独作为简历 bullet。

### 6.7 B5：从 B1 起持续执行的质量门禁

B5 包含 lint、latch/negedge 清理、四值仿真、综合、网表仿真、顶层接口和 CI。它不应等到项目末尾才执行：

- B1 起保持 lint 无新增有效 warning；
- 每个主要模块稳定后跑 synthesis，观察面积和关键路径；
- pipeline/cache 引入后增加四值仿真，检查 reset、`valid` 和 X propagation；
- 每个 milestone 固定可复现命令和回归结果；
- B5 最后只做接口、命名、网表和提交规范收口。

讲义能够提供开源 flow 的闭环，但 CDC/RDC、完整 SDC、LEC、UPF 和工业 PPA closure 需要另行补充。

### 6.8 推荐实际顺序与求职 MVP

课程原顺序为：

```text
B1 AXI -> B2 SoC -> B3 performance/I-cache
       -> B4 pipeline -> B5 sign-off
```

结合求职目标，推荐：

```text
C6 snapshot
  -> B1 完整总线闭环
  -> B2 最小 SoC + 一条外部存储路径
  -> B3 counters + synthesis baseline + I-cache/formal
  -> B4 五级流水 + 精确异常
  -> B5 最终收口
  -> GShare/BTB 或深入 AXI DV 二选一
```

其中 B5 的 lint/synthesis/regression 从 B1 起并行执行。求职 MVP 可描述为：

> RV32I 五级顺序流水核 + precise M-mode trap + AXI4-Lite SoC + SRAM/UART/CLINT + I-cache + DiffTest/SVA/random backpressure + synthesis/STA/PPA evidence

RT-Thread 作为验证 workload 证明系统能运行长程序，但不作为 MVP 的技术中心。若额外完成 `mtimecmp/mie/mip`、异步 timer interrupt 和抢占切换，再单独描述中断/RTOS 支持。

### 6.9 讲义之外的差异化方向

偏 RTL/CPU Design：

- instruction buffer/decoupled frontend；
- GShare、BTB 和预测元数据传递；
- misprediction redirect 与 GHR recovery；
- 分支准确率、IPC、面积和关键路径对比。

偏 SoC/DV：

- 多 slave interconnect、仲裁和 error response；
- SystemVerilog protocol assertions；
- constrained-random backpressure、scoreboard 和 functional coverage；
- starvation/fairness、transaction ownership 和长期回归；
- 选择 AXI 或 cache 建立范围受控的 UVM block-level environment。

以当前 `Design > Verification` 的目标，主体选择流水线 + I-cache，同时把 AXI interconnect 验证做深；不为“看起来工业”而立即重写整个 CPU 验证框架。

### 6.10 建议延期或止损

- 复杂 NEMU/AM 软件、完整 libc、图形栈和文件系统；
- VGA、游戏和大量应用移植；仅在官方考核需要时做最小验收；
- D-cache，尤其 write-back/write-allocate，在流水线和 I-cache 稳定前不启动；
- A/F、U-mode、PMP、MMU/Linux，在求职 MVP 完成前不扩展；
- 同时实现 Flash、PSRAM、SDRAM 三套路径；
- 没有指标、验证计划或对比基线的功能堆叠。

C/C++、Python/TCL 和基础设施仍应服务于测试生成、自动回归、reference model 和结果分析，但不替代 RTL/微架构主线。

## 7. 资产维护规则

每完成一个硬件里程碑，同步更新以下六项：

1. **Spec**：功能、接口、状态、时序、异常与未定义行为；
2. **Figure**：一张可以独立讲清问题的架构或时序图；
3. **Verification plan**：feature、stimulus、checker、assertion、coverage goal；
4. **Sign-off**：commit、命令、结果、已知限制；
5. **Bug story**：现象、first failure、根因、修复、防回归；
6. **Metrics**：tests、coverage、CPI/IPC、stall、hit rate、area、Fmax 等适用指标。

简历只抽取稳定完成且有证据的内容；展示材料保留设计取舍和 debug 过程；学习笔记保存可迁移的原理。三者不应混成一份不断膨胀的开发日志。

建议时间分配：RTL/微架构 **60%～65%**，验证与自动化 **25%～30%**，文档与展示 **10%～15%**。绘图是本项目的优势，但完成标准应是“帮助评审者快速理解设计和证据”，不是单纯追求页面数量。
