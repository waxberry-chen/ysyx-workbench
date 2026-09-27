# Post-C Roadmap：从弹性 RV32E Core 到可展示的 SoC/RTL 项目

> 状态基线：2026-09-28  
> 求职方向优先级：SoC/RTL Design > Design Verification > Physical Design  
> 本文用于决定 post-C 阶段的投入顺序。具体接口、地址映射和考核要求仍以开始该阶段时的最新版官方讲义与上游仓库为准。

## 1. 结论先行

当前 `1-memory-request` 的演化方向是正确的。它已经不再只是一次“给 RAM 加延迟”的局部练习，而是把原来的集中式多周期控制改造成了：

> **单发射、顺序提交、弹性前后端、IFU/LSU 各自持有事务状态、集中 commit/redirect 的小型处理器。**

这次重构不是偏离 B 阶段主线，而是在为 AXI backpressure、SoC 集成、cache miss 和以后进一步流水化建立稳定边界。现在最不划算的选择，是抛开这套结构再重写一个教科书式五级流水。

后续建议采用下面这条主线：

```text
已完成
1-memory-request：弹性前后端 + 精确访存异常
        │
        ▼
当前主线
2-axi4-lite：IFU/LSU AXI4-Lite adapters，保留 local req/rsp 边界
        │
        ▼
3-axi4-lite-interconnect：Arbiter -> Xbar -> SRAM/UART/CLINT/DECERR
        │               同步建立 lint/SVA/随机回压基线
        ▼
4-pre-soc-signoff：综合/STA/四值/网表 smoke + 可复现质量门
        ▼
5-ysyx-soc-integration：AXI4 单拍子集封装 -> ysyxSoC 最小启动闭环
        │                    MROM/SRAM/UART/CLINT/DiffTest/RT-Thread
        ▼
6-job-ready-release：冻结 Job-ready Release v1，开始正式投递
        │
        ▼
7-icache-performance：计数器 -> trace/cachesim -> I-cache -> AXI burst
        │
        ▼
8-role-deepening：根据数据只选一条主攻
        ├─ RTL/CPU：弹性后端切级、forwarding/hazard、再考虑 GShare/BTB
        └─ DV：AXI 子系统 UVM/coverage closure + 更深的 formal
```

核心调整有四点：

1. **AXI4-Lite 和 ysyxSoC 仍是最高优先级**，因为它们把 CPU 模块、互联、设备、软件和验证真正连成系统。
2. **lint、SVA、formal、综合、STA 和四值检查不是最后补票**，从 B1 起就作为每个里程碑的横向质量门。
3. **五级流水不再是近期必做的整核重写**。在 ysyxSoC 和性能基线完成后，根据 CPI/stall/关键路径决定是否把当前弹性后端继续切级。
4. **达到 Job-ready Release v1 后即可投递**。I-cache、流水深化和 UVM 是增强竞争力的后续版本，不应成为迟迟不整理项目、不开始投递的理由。

## 2. 判断依据

### 2.1 当前已经拥有的资产

根据 [`1-memory-request/3-core-microarch-refactor-plan.md`](1-memory-request/3-core-microarch-refactor-plan.md) 和 [`1-memory-request/4-current-npc-architecture.md`](1-memory-request/4-current-npc-architecture.md)，当前工程已经具备：

- IFU、2-entry IFQ、1-entry opbuf、EXU、LSU 的明确模块边界；
- request/response、ready/valid、backpressure、single-outstanding 和 response ownership；
- redirect 后丢弃 stale fetch response；
- architectural state 只在 commit 更新，load/store 等待响应后才提交；
- instruction/load/store access fault 的精确异常路径；
- commit trace、DiffTest、随机 memory latency 和现有 AM workload 回归；
- 相比重构前已经有可量化的 CPI/cycle 改善。

这些能力比“单周期核能跑程序”更接近真实 RTL 项目中的问题：持有上下文、处理停顿、控制 flush、划分事务责任以及定位跨模块 bug。

### 2.2 当前最重要的缺口

按求职展示价值排序，主要缺口是：

1. core 尚未通过标准 SoC 总线完成对外集成；
2. 还没有 Arbiter/Xbar、设备错误响应和系统级 address map 闭环；
3. 还没有在 ysyxSoC 中完成 boot、UART、CLINT、AM 和 DiffTest 闭环；
4. 项目缺少持续保存的综合面积、关键路径、Fmax、STA 约束和网表/四值证据；
5. 验证已经有 directed/random/assertion，但还缺 test plan、功能覆盖率和可陈述的 closure；
6. 性能数据目前能证明一次重构有效，但还不能说明瓶颈在哪里、下一项优化为何值得做。
7. “RV32E”项目标识与当前 32-entry GPR、尚未拒绝 x16～x31 编码的实现之间仍需统一，避免对外展示时形成合规性歧义。

### 2.3 求职收益校准

截至 2026-09-27 抽样的近期岗位要求中：

- NVIDIA 上海的 SoC ASIC Design/Verification 实习岗位同时强调 RTL、testbench/assertion/regression，以及 lint、formal、CDC/RDC、synthesis、STA 和 gate-level verification；
- Apple 的 CPU Microarchitecture/RTL 岗位强调从微架构规格到 RTL、PPA/timing、性能分析以及与验证和物理实现协作；
- Apple 的 Design Verification 岗位强调 coverage-driven test plan、可复用 UVM 环境、SVA、约束随机、回归和 AXI/bus fabric 经验。

因此，当前项目的最高边际收益不是继续增加 ISA 或软件功能，而是补齐：

> **标准总线与 SoC 集成 + 可综合/PPA 证据 + 系统化验证闭环 + 一项由数据驱动的微架构优化。**

岗位样本仅用于校准能力结构，不代表地域内全部招聘需求，且职位页面会随时间失效。参考：[NVIDIA SoC ASIC Design/Verification Intern](https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite/job/ASIC-Design-and-Verification-Intern--SOC---2027_JR2024860)、[Apple CPU Microarchitect/RTL Engineer](https://jobs.apple.com/en-us/details/200657634-0505/cpu-microarchitect-rtl-engineer-execution-load-store)、[Apple Design Verification Engineer](https://jobs.apple.com/en-us/details/200658028-0157/design-verification-engineer)。

## 3. 对早期路线的重新评估

[`../c-stage-career-assets.md`](../c-stage-career-assets.md) 的总体判断仍然有效：优先做 AXI/SoC、精确异常、可复现验证、性能和前端流程，不应过早投入 MMU/Linux、乱序、多发射或完整 D-cache。

需要随当前进度更新的部分如下：

| 早期设想 | 当前建议 | 原因 |
| --- | --- | --- |
| RAM 延迟接口是一个独立小阶段 | 将 `1-memory-request` 视为已完成的 core architecture milestone | 实际已形成稳定的 elastic frontend/backend，不应退回集中 FSM |
| B1 后可直接考虑 GShare/BTB | B1 后先接 ysyxSoC 并做 sign-off | SoC/AXI/PPA/验证闭环的求职收益更直接，预测器此时仍缺系统基线 |
| 五级流水是固定的后续大阶段 | 改为由 STA 和 stall 数据触发的 elastic backend 演进 | 避免为“看起来像流水线”再次整核重写；保留已有事务与 commit 语义 |
| B5 再集中做前端质量检查 | 从 B1 起每阶段做 lint/synthesis/STA/assertion，B5 只做最终 closure | 越晚处理时序、复位和 X 传播，返工范围越大 |
| B2 广泛接入各种设备 | 先完成 UART、CLINT 和一条外部存储路径 | GPIO/VGA/键盘对当前岗位目标的边际收益低于总线、内存和验证深度 |
| UVM 可作为独立大项目 | 先把现有 AXI 子系统做成有 test plan/scoreboard/coverage 的验证对象，再决定是否迁移到 UVM | 避免只搭 class 框架，却没有有价值的协议 corner case 和 coverage closure |

## 4. 路线优先级

### P0：必须完成，形成 Job-ready Release v1

- 冻结并整理当前 core refactor；
- 明确 ISA 合规口径：补齐 RV32E 对 x16～x31 编码的非法指令检查，或准确调整项目描述；
- AXI4-Lite IFU/LSU master adapters；
- 2-to-1 Arbiter、Xbar、SRAM/UART/CLINT/DECERR；
- 随机回压、协议断言、错误注入和基本功能覆盖；
- 对外完整 AXI4 单拍封装并接入 ysyxSoC；
- MROM/SRAM/UART/CLINT、AM、DiffTest、hello/RT-Thread 闭环；
- lint、综合、STA、四值检查和至少一个网表 smoke test；
- 架构图、test plan、结果表和一篇完整 bug story。

### P1：强烈建议，形成 Design-oriented Release v2

- 性能事件计数器和可重复 benchmark；
- trace 驱动的 cache 参数探索；
- 简易 I-cache、`fence.i`、miss/refill 和错误传播；
- 完整 AXI4 burst refill；
- 优化前后 cycles/CPI/Fmax/area/AMAT 对比；
- 为 FIFO/cache/arbiter 增加小规模 formal proof。

### P2：按岗位方向选做，不作为主线前置条件

- 依据关键路径拆分 elastic backend，加入 forwarding/hazard/precise flush；
- 依据 branch stall 占比加入 BTB/GShare；
- 为 AXI interconnect 建立一个聚焦、可复用的 UVM 环境并完成 coverage closure；
- 若确有多个时钟或复位域，再做真实 CDC/RDC 设计与检查；
- OpenROAD 等更完整的 PPA/物理实现探索。

### 暂缓

- 乱序、多发射、ROB、scoreboard/OITF；
- 多 outstanding 和复杂 AXI ID/乱序返回；
- D-cache/coherence；
- MMU、S/U mode、Linux；
- 同时实现 Flash、PSRAM、SDRAM 的完整控制器；
- 为了“功能很多”而堆 GPIO、VGA、游戏或新的软件栈；
- 没有基线和数据支持的性能优化。

## 5. 分阶段实施路线

### Milestone 1：冻结 `1-memory-request`（已基本完成）

#### 目标

把当前状态确认为一个可以独立讲清楚的版本，而不是仅作为 AXI 开发过程中的临时提交。

#### 收尾事项

- 让当前架构导读补充 Phase 3 access fault 的最终行为；
- 处理 RV32E 的 x16～x31 编码约束，确保项目名称、文档、编译目标和 RTL 行为一致；
- 固定一份回归结果：CPU tests、随机 latency seeds、hello、yield-os/RT-Thread 和 DiffTest；
- 保存重构前后 cycles/CPI 对比以及测试配置；
- 记录至少一篇 bug story，例如 stale response、opbuf context holding 或精确 store fault；
- 打 milestone tag，后续总线改造出现问题时可二分和对照。

#### 出口

- 文档描述与 RTL 一致；
- ISA 能力声明与实际实现一致；
- 基线能由单条或少量命令复现；
- 后续不再重新引入集中式 main FSM。

### Milestone 2：完成 `2-axi4-lite` adapters

已有实施细节以 [`2-axi4-lite/plan.md`](2-axi4-lite/plan.md) 为准。这个 milestone 只负责把 IFU/LSU 的 local transaction 转换成两套 AXI4-Lite master，不混入 Arbiter、Xbar 或设备。

#### 实现顺序

1. IFU read-only adapter，验证 `AR/R` 独立回压和 error response；
2. LSU adapter，分别验证 read 及 `AW/W/B`，覆盖 AW/W 任意先后；
3. 保持 IFU/LSU local req/rsp 边界不变，完成 core 双 master 集成；
4. 将现有 C++ RAM model 改为独立随机化五个 AXI channel 的 slave model；
5. 保存全寄存 baseline，再决定是否实现 fall-through/skid fast path；
6. 对比改造前后的 cycles、CPI、stall 和组合路径。

#### 必测 corner cases

- `ARREADY/RVALID/RREADY` 任意长时间停顿；
- `AW` 先于 `W`、`W` 先于 `AW`、二者同周期握手；
- `BREADY` 或 `RREADY` 回压时 response payload 保持；
- redirect 与旧 fetch response 并发；
- read/write `SLVERR/DECERR` 到精确 access fault 的映射；
- byte/half/word 的 lane、`WSTRB`、load extension；
- reset 发生在空闲、请求已接受及等待响应等状态时，行为有明确约定。

#### 验证交付物

- adapter 协议 test plan 和需求到测试的 traceability table；
- directed tests + 固定 seed random backpressure/error injection；
- scoreboard/reference memory model；
- SVA：payload holding、response requires outstanding、AW/W independence、FIFO 不上下溢；
- 最低限度的功能覆盖矩阵：transaction 类型 × stall 位置 × response；
- coverage 不绑定 UVM；若当前 simulator 不支持合适的 covergroup，可先用 monitor/counter 导出机器可读的 bin 命中结果；
- 对 adapter/FIFO 关键不变量做 bounded formal；若工具受限，至少保留属性和失败反例回归。

#### 出口

- IFU/LSU adapter standalone tests 与随机回压测试通过；
- core 对外暴露两套 32-bit、single-outstanding AXI4-Lite master；
- CPU tests、access-fault、hello、yield-os 与 DiffTest 回归通过；
- backend RTL 不引用任何 AXI channel 信号；
- 能用一段波形解释一次 AXI read 和 AW/W 任意先后的一次 AXI write。

### Milestone 3：完成 `3-axi4-lite-interconnect` / B1 system

这个 milestone 消费 Milestone 2 冻结的两套 master，把协议练习扩展为可独立验证的最小 AXI4-Lite system。

#### 实现顺序

1. 2-to-1 Arbiter 合并 IFU/LSU，请求接受后锁存 owner 至对应 response 完成；
2. Xbar 锁存目标 slave，连接 SRAM、UART、CLINT 和 default error slave；
3. 第一版允许全局 single-outstanding，先闭合 read/write ownership 与 forward progress；
4. 完成 B1 address map、byte lane、UART side effect、64-bit `mtime` 读取和非法地址 `DECERR`；
5. 基于综合与 CPI 数据，再决定是否增加 LSU 优先、公平性或 read/write 并行。

#### 必测 corner cases

- IFU/LSU 同时请求时 owner 不错配且无永久饥饿；
- AW/W 分离时，Arbiter/Xbar 的 owner/target 保持到 B response；
- 各 slave 独立 backpressure，response 不串路；
- 未命中地址产生 `DECERR`，不能静默成功或由 harness abort；
- UART store 只产生一次字符 side effect；
- reset、错误 response 和长时间 stall 后能恢复 forward progress。

#### 验证交付物

- system-level test plan、需求到 test/assertion/coverage 的 traceability table；
- Arbiter、Xbar、SRAM、UART、CLINT、default slave 的 directed tests；
- transaction scoreboard 和固定 seed 随机竞争/backpressure/error injection；
- SVA：owner/target holding、response requires outstanding、FIFO 不上下溢、accepted request 最终有 response capacity；
- 功能覆盖矩阵：master × transaction × route × stall point × response；
- 对 Arbiter/FIFO/route ownership 做 bounded formal 或保留可执行属性与反例回归。

#### 出口

- core 对外只剩一套 32-bit AXI4-Lite master；
- CPU tests、hello、RTC、yield-os/CSR DiffTest 和 RT-Thread workload 通过；
- 多 seed 随机竞争/回压下无 deadlock、livelock、重复 MMIO side effect；
- 所有非法地址和 slave error 都沿精确异常路径可观察；
- 能用一张图和波形解释 IFU/LSU 竞争、一次 AXI write 和一次 `DECERR`。

官方路线同样把 IFU/LSU 双 master、仲裁、随机延迟和 SoC 接入作为连续任务；Milestone 2/3 只是为提交、验证和文档管理而拆开，实施时仍应核对最新的 [B1 总线讲义](https://ysyx.oscc.cc/docs/2407/b/1.html)。

### Milestone 4：完成 `4-pre-soc-signoff`

这个里程碑工作量不应很大，它的作用是防止“B1 仿真能跑，但接 SoC 时同时暴露协议、时序、复位和构建问题”。

#### 必做

- 明确 synthesizable core/top 与 Verilator-only harness 的边界；
- 为时钟、输入/输出延迟和 false-path 形成最小 SDC；
- 检查 latch、组合环、下降沿逻辑、隐式位宽转换和未驱动信号；
- 检查 reset 后所有 control/valid/owner 状态，数据寄存器依赖 valid 屏蔽；
- 运行四值 smoke test，优先暴露 X optimism 和初始化依赖；
- 跑一次综合网表 smoke test；
- 固化 `lint -> unit -> random -> system -> synth -> sta` 的可重复命令。

#### 关于 CDC/RDC

如果当前设计只有一个同步时钟域，就在 sign-off 报告中如实写明“无功能性 CDC”，并审查 reset deassertion 方式。不要为了简历关键词人为制造异步域；等真实 SoC 外设或时钟域出现后，再实现 synchronizer/async FIFO 并做对应检查。

#### 出口

- 生成的 RTL 不依赖 DPI-C 才能综合；
- 工具报告和日志路径固定，可由干净工作区复现；
- 已知 warning 有逐项说明，而不是全局屏蔽；
- B1 release 有版本号和结果摘要。

### Milestone 5：完成 `5-ysyx-soc-integration` / B2

#### 架构建议

不要把 ysyxSoC 的完整 AXI4 信号直接扩散回 IFU、LSU。建议保留三层边界：

```text
IFU/LSU semantic state
        │ local req/rsp
        ▼
AXI4-Lite adapters + core Arbiter
        │ one 32-bit, single-outstanding AXI4-Lite master
        ▼
ysyx top wrapper / AXI4 single-beat subset mapping
        │ full AXI4 port: LEN=0, fixed ID/size/burst 等
        ▼
ysyxSoC
```

这样做有三个收益：

- ysyxSoC 顶层端口或生成方式变化时，主要改 wrapper；
- 当前 core 仍用已经验证的 single-outstanding 语义；
- 后续 I-cache 需要 burst 时，只扩展 refill 路径和顶层能力，不重写整个 core 控制。

这里的“仿照 RocketChip 生成 SoC 外层”应理解为：**复用上游生成的 SoC、遵守它的 BlackBox/top contract，并提供一个清晰的 CPU wrapper**。当前阶段不建议自己复制 RocketChip diplomacy、参数系统或重新搭建一个生成器框架。

#### 开始前先冻结外部契约

- 固定 ysyxSoC upstream commit/submodule revision；
- 阅读该 revision 的 README、CPU BlackBox、top module、address map 和生成命令；
- 记录 AXI data/address/ID width、reset polarity、clock、interrupt 和 memory map；
- 不把旧讲义中的地址或位宽直接当作当前事实。

上游入口：[OSCPU/ysyxSoC](https://github.com/OSCPU/ysyxSoC)。官方文档也明确提醒设备和地址空间可能变化，接入时应重新核对 [B2 SoC 计算机系统](https://ysyx.oscc.cc/docs/2407/b/2.html)。

#### Bring-up 梯子

每一级通过后再进入下一级：

1. reset PC 从 MROM 取到 `ebreak`；
2. 通过 UART 输出单字符 `A`；
3. SRAM stack 和最小 `mem-test`；
4. bootloader 完成 MROM/Flash LMA 到 SRAM VMA 的数据搬运；
5. ysyxSoC AM runtime、链接脚本和 `putch()`；
6. 恢复 MROM/SoC address space 下的 DiffTest；
7. `hello`、CPU tests、microbench smoke；
8. CLINT timer 和 machine timer interrupt；
9. RT-Thread，并保留随机总线延迟/错误测试。

#### 外设和外部存储器取舍

近期只把以下内容列为主线：

- MROM、SRAM；
- UART16550；
- CLINT/`mtime`，随后补 machine timer interrupt；
- 一条能形成启动闭环的外部存储路径。

默认先选 **Flash -> SRAM boot**，因为它能用较小范围证明 boot flow、LMA/VMA、MMIO 和软件/硬件协作。若最新版考核要求不同，以官方要求为准。SDRAM/AXI burst 可与后续 I-cache 阶段合并；不要在此阶段同时展开 Flash、PSRAM、SDRAM、VGA、PS/2 和 GPIO。

#### 出口

- 上游 revision、生成步骤和本地 patch 可复现；
- MROM/SRAM/UART/CLINT 和一条外部启动路径形成闭环；
- DiffTest、hello 和 RT-Thread 在 SoC 环境通过；
- timer interrupt 在 precise commit boundary 生效，trap/mret 可验证；
- 保留 SoC block diagram、boot sequence、address map、关键波形和 bug list；
- 完成 SoC 顶层综合/STA，说明 core 与 wrapper 的面积和关键路径。

### Milestone 6：完成 `6-job-ready-release` / Job-ready Release v1

达到 Milestone 5 后，项目已经覆盖 CPU microarchitecture、RTL、AXI、interconnect、SoC integration、firmware/runtime、verification 和 synthesis/STA。此时应冻结一个面向求职的 release，并开始投递。

#### Release 内容

- 一页项目总览：目标、架构、个人工作、规模和结果；
- core/AXI/SoC 三张层次清晰的图；
- 一张验证矩阵：功能、协议、随机、DiffTest、formal、四值、网表；
- 一张 metrics 表：cycles、CPI、Fmax、area、关键 stall；
- 两篇 bug story：现象、最小复现、根因、波形/断言、修复、回归；
- 一段短 demo：boot、UART、timer/RT-Thread；
- 可复现命令、工具版本、已知限制和下一步；
- 2～3 条有数字和验证证据的简历 bullet。

#### 推荐项目叙事

不要只写“实现 RV32E CPU”。更有区分度的叙事是：

> 从集中式多周期控制出发，为支持可变延迟 memory 和精确异常，将 core 重构为 elastic frontend/backend；随后实现 AXI4-Lite masters、互联和错误传播，接入生成式 ysyxSoC，并用 DiffTest、随机回压、SVA/formal、综合与 STA 完成验证和实现闭环。

### Milestone 7：完成 `7-icache-performance` / Design-oriented Release v2

#### 为什么排在 ysyxSoC 后

- 已经有真实 memory hierarchy 和可校准延迟，cache 收益不再是假设；
- 完整 AXI4 接口能支持 burst refill，不必先围绕 AXI4-Lite 做一个即将重写的版本；
- SoC baseline 已固定，能比较 AMAT、CPI、Fmax 和面积；
- `fence.i`、不可缓存 MMIO、access fault 等系统问题都有实际环境。

#### 顺序

1. 增加 cycle/commit、IFU wait、LSU wait、branch redirect、cache hit/miss 等事件计数；
2. 固定 microbench workload、memory delay 和综合约束；
3. 从 trace 建立 `cachesim`，先探索 line size/capacity/associativity；
4. 实现参数化的最小 I-cache，先 single-beat refill；
5. 验证 cacheable region、MMIO bypass、fault、redirect 和 `fence.i`；
6. 再实现 AXI burst refill，并校准 memory delay；
7. 用数据比较优化前后，而不是只报告“测试通过”。

#### 验证重点

- hit/miss/refill 状态与 IFU backpressure；
- redirect 发生于 miss/refill 期间；
- tag/data/valid 更新的原子性；
- faulting refill 不写入有效 cache line；
- `fence.i` 后不能命中旧指令；
- cacheable 与 device address 不混淆；
- formal 检查小参数 cache 的命中数据正确、invalid 不命中和 refill ownership。

#### 出口

- 至少完成一次参数设计空间探索；
- 报告 hit rate、miss penalty、AMAT、CPI、Fmax、area 和估算运行时间；
- 结论允许是“某配置不值得”，但必须有数据；
- 保留 single-beat 与 burst refill 的关键波形和对比。

### Milestone 8：进入 `8-role-deepening`，按证据选择深化方向

#### 主方向 A：RTL/CPU Design（优先）

不要预先承诺“做完整五级流水”。先看数据：

| 证据 | 下一步 |
| --- | --- |
| EXU/地址生成/commit 组合路径限制 Fmax | 在现有 opbuf/commit 语义上切分 elastic stage |
| backend 相关依赖停顿成为主要 CPI 损失 | 加 forwarding、hazard detection 和可验证的 stall/kill |
| branch redirect 占比高 | 先做小 BTB，再比较 bimodal/GShare；必须报告准确率和净收益 |
| memory stall 仍占主导 | 继续优化 I-cache/refill/burst，而不是先做预测器 |
| 乘除法软件序列占比显著 | 考虑多周期 M extension，并复用当前长延迟 operation 语义 |

若做 pipeline，目标应是“演进当前弹性核”，而不是另起炉灶：

- 保留 ready/valid 和局部 backpressure；
- 明确每级保存的完整 instruction context；
- redirect、exception、interrupt 只允许精确地更新 architectural state；
- 用 forwarding/stall/flush assertions 和 DiffTest 证明正确；
- 用 Fmax × IPC × area 证明切级是否真的有效。

#### 辅方向 B：Design Verification

在现有 AXI 子系统上做一个聚焦的 UVM/coverage 项目，而不是重建整个 CPU 仿真环境：

- DUT：AXI adapters + Arbiter + Xbar；
- reusable agents：IFU/LSU requester 或 AXI master/slave；
- sequence：独立 AW/W delay、response backpressure、竞争、DECERR、reset injection；
- scoreboard：transaction/ownership/reference memory；
- functional coverage：channel ordering、stall depth、response、size/strobe、route、arbitration；
- assertions/formal 与 simulation coverage 分工；
- 输出 coverage closure 报告及两个 coverage hole 的处理案例。

这条分支能直接补齐 DV 岗位关键词，但只有在 B1 已经有清楚的协议 test plan 后才值得投入。

#### Physical Design 延伸

若后续确认转向前端实现/物理设计，可在稳定 release 上增加：

- 更完整的 SDC 和多 corner STA；
- synthesis QoR、面积层次和 critical path 分析；
- OpenROAD floorplan/place/CTS/route 的可复现 flow；
- 针对 congestion/timing 的 RTL 反馈修改。

它目前排在 SoC/RTL 与 DV 之后，不应阻塞主线。

## 6. 贯穿所有阶段的质量门

每个 milestone 都按同一模板验收：

| 类别 | 必须回答的问题 |
| --- | --- |
| Specification | 接口、状态、错误、reset、corner case 是否写清楚？ |
| Functional | directed tests、CPU workload、DiffTest 是否通过？ |
| Protocol | backpressure、payload holding、ownership、error response 是否被检查？ |
| Random | seed、延迟分布、错误注入是否可复现？ |
| Coverage | 需求是否映射到 test/assertion/coverpoint？有哪些 hole？ |
| Formal | 哪些控制不变量适合 bounded proof？assumption 是否合理？ |
| Implementation | lint、latch、synthesis、STA、X-prop、netlist smoke 是否通过？ |
| Performance | cycles/CPI/stall/Fmax/area 相比 baseline 如何？ |
| Artifact | 架构图、波形、结果表、bug story 和复现命令是否齐全？ |

### 最小回归层级

```text
L0  module directed tests
L1  protocol random/backpressure/error injection
L2  core CPU tests + DiffTest
L3  AM hello/microbench/RT-Thread
L4  ysyxSoC boot + UART + interrupt
L5  lint + synthesis/STA + 4-state/netlist smoke
```

任何优化都先保存前一版结果，再在相同 workload、memory model、seed policy 和 timing constraint 下比较。

## 7. 投入比例与停止条件

### 到 Job-ready Release v1 之前

建议按总投入比例控制范围：

- AXI adapters/Arbiter/Xbar/设备：约 30%；
- ysyxSoC、AM、boot、interrupt：约 30%；
- 验证、formal、综合/STA、四值/网表：约 25%；
- 文档、指标和作品包装：约 15%。

这不是日历承诺，而是防止 90% 时间都投入 RTL feature、最后没有验证和可展示证据。

### 停止扩展并整理 release 的触发条件

满足以下条件就应先发布一个版本，而不是继续加功能：

- 新功能开始同时跨 core、bus、SoC 和 software 多层修改；
- 当前 milestone 已通过但文档和结果表尚未整理；
- 连续增加功能却没有新的 benchmark、coverage 或 PPA 数据；
- 为接入第二、第三种外设/存储器而重复已有能力；
- 下一项工作无法对应目标岗位的一项明确能力或一个可验证问题。

## 8. 建议目录演进

现有目录保持不动，后续开始对应阶段时再创建：

```text
docs/notes/post-c/
├── roadmap.md
├── 1-memory-request/          # elastic core + precise memory exception
├── 2-axi4-lite/               # IFU/LSU AXI4-Lite adapters
├── 3-axi4-lite-interconnect/  # Arbiter/Xbar/minimal B1 slaves
├── 4-pre-soc-signoff/         # SDC/synthesis/STA/4-state/netlist smoke
├── 5-ysyx-soc-integration/    # B2 wrapper/boot/interrupt/system closure
├── 6-job-ready-release/       # 架构、验证、PPA、bug stories、简历材料
├── 7-icache-performance/      # trace/cachesim/I-cache/burst/metrics
└── 8-role-deepening/          # pipeline/BPU 或 focused DV，按证据选择
```

目录编号与 milestone 编号严格一一对应。每个目录至少维护一份明确的 plan/spec 和独立的 `dev-log.md`；需要冻结接口、测试矩阵、sign-off 报告或性能结果时，再在该目录增加专题文件。未开始的 milestone 不预先创建空目录和空模板。

## 9. 最近三个行动

1. 按 [`2-axi4-lite/plan.md`](2-axi4-lite/plan.md) 完成 IFU adapter 的 standalone test，再做 LSU adapter；
2. 在 adapter 开发同时建立 B1 的 test matrix、SVA 和综合/STA baseline，不等到 Arbiter/Xbar 完成后补；
3. `3-axi4-lite-interconnect` 接近出口时再拉取并固定最新版 ysyxSoC revision，基于实际 top/BlackBox 接口编写 `5-ysyx-soc-integration` 的 integration spec。

在这三项完成前，不启动 GShare、经典五级流水重写、D-cache 或大规模外设扩展。
