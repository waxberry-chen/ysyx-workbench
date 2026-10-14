# Post-C Roadmap：从弹性 RV32E Core 到可展示的 SoC/RTL 项目

> 规划更新：2026-10-14；实现基线：`5b6f29c`（AXI4-Lite 阶段验收）
>
> 求职方向优先级：SoC/RTL Design > Design Verification > Physical Design  
> 本文用于决定 post-C 阶段的投入顺序。具体接口、地址映射和考核要求仍以开始该阶段时的最新版官方讲义与上游仓库为准。

对外展示统一从 [`docs/notes/output/`](../output/README.md) 进入；开发与实验详录留在所属阶段。优先推进 RTL 主线，同步积累证据，不设置独立的 job-release 阶段，也不把整理简历变成等待完整 SoC/PPA 的串行任务。

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
已完成
2-axi4-lite：IFU/LSU AXI4-Lite adapters，保留 local req/rsp 边界
        │
        ▼
当前主线
3-axi4-lite-interconnect：Arbiter -> Xbar -> SRAM/UART/CLINT/DECERR
        │               同步建立 lint/SVA/随机回压基线
        ▼
4-pre-soc-signoff：综合/STA/四值/网表 smoke + 可复现质量门
        ▼
5-ysyx-soc-integration：AXI4 单拍子集封装 -> ysyxSoC 最小启动闭环
        │                    MROM/SRAM/UART/CLINT/DiffTest/RT-Thread
        ▼
6-icache-performance：已有统计扩展 -> trace/cachesim -> I-cache -> AXI burst
        │
        ▼
7-role-deepening：根据数据只选一条主攻
        ├─ RTL/CPU：弹性后端切级、forwarding/hazard、再考虑 GShare/BTB
        └─ DV：AXI 子系统 UVM/coverage closure + 更深的 formal
```

核心调整有四点：

1. **AXI4-Lite 和 ysyxSoC 仍是最高优先级**，因为它们把 CPU 模块、互联、设备、软件和验证真正连成系统。
2. **验证和实现检查随设计推进**：日常优先 lint/单测/相关回归，稳定阶段补综合、STA、四值与适用的 formal；工具条件不足时明确待验，不把所有检查变成每次提交的前置条件。
3. **五级流水不再是近期必做的整核重写**。在 ysyxSoC 和性能基线完成后，根据 CPI/stall/关键路径决定是否把当前弹性后端继续切级。
4. **展示素材持续积累、按需包装**。需要投递时对已有证据做一次简短评估并生成简历，不以任一 milestone 或工具流程全部完成为前提。

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

### P0：近期主线，形成 SoC/RTL 工程闭环

- 冻结并整理当前 core refactor；
- 明确 ISA 合规口径：补齐 RV32E 对 x16～x31 编码的非法指令检查，或准确调整项目描述；
- AXI4-Lite IFU/LSU master adapters；
- 2-to-1 Arbiter、Xbar、SRAM/UART/CLINT/DECERR；
- 随机回压、协议断言、错误注入和基本功能覆盖；
- 对外完整 AXI4 单拍封装并接入 ysyxSoC；
- MROM/SRAM/UART/CLINT、AM、DiffTest、hello/RT-Thread 闭环；
- lint、综合、STA、四值检查和至少一个网表 smoke test；
- 架构图、test plan、结果表和一篇完整 bug story。

### P1：量化优化，增强设计深度

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
- 后续确有物理实现需求时再裁剪既有 flow；近期不实施 PnR。

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

### Milestone 2：完成 `2-axi4-lite` adapters（已完成）

已有实施细节以 [`2-axi4-lite/plan.md`](2-axi4-lite/plan.md) 为准。这个 milestone 只负责把 IFU/LSU 的 local transaction 转换成两套 AXI4-Lite master，不混入 Arbiter、Xbar 或设备。

2026-09-28 已完成实现与功能/协议 sign-off；结果和可重复回归入口见
[`2-axi4-lite/4-signoff.md`](2-axi4-lite/4-signoff.md)。更深的 coverage/formal 项与下一阶段
interconnect system-level test plan 合并实施。

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

2026-10-14 已建立[设计与实施计划](3-axi4-lite-interconnect/plan.md)、[验收矩阵](3-axi4-lite-interconnect/test-plan.md)和[开发日志](3-axi4-lite-interconnect/dev-log.md)；当前为计划状态，RTL 与新增验收入口尚未实施。

同日已完成 [S0 基线保存与最小回归](3-axi4-lite-interconnect/0-baseline.md)，可进入 S1 Arbiter 实现；该结果仅验证 legacy 基线，不代表 M3 互联系统已通过。

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

这个里程碑防止“B1 仿真能跑，但接 SoC 时同时暴露协议、时序、复位和构建问题”。先建立最小实现基线，工作量取决于现有 RTL、工艺库和可复用 flow；不在取得工具与输入前承诺全部检查已可运行。

#### 工具与执行分工

- 暂定 [Design Compiler](https://www.synopsys.com/implementation-and-signoff/rtl-synthesis-test/design-compiler.html) 做综合、[PrimeTime](https://www.synopsys.com/implementation-and-signoff/signoff/primetime.html) 做 STA；**PnR 暂不实施，也不作为近期主线的依赖**。
- 用户提供可复用的旧 tapeout flow 后，先提取一个 top、一个 mode/corner 的最小路径，再逐项增加本项目需要的选项。重新审查 clocks、I/O delays、reset、false/multicycle paths；不继承旧工程未经解释的 waiver/约束。
- 脚本在本仓库维护，待实际导入时集中放在 `npc/flow/`；本地负责编辑和可执行的静态检查，用户同步到具备完整 EDA 的服务器运行。不提前搭建复杂的通用 flow 框架。
- 服务器按固定 RTL/脚本/SDC 版本运行，归档工具版本、库/PVT 标识、配置、命令和报告；详细结果归入本阶段，展示出口仅链接摘要。
- 仓库只存可共享的脚本与配置模板；工艺库、license、机器路径及受限旧项目内容留在服务器/私有配置中。迁移前检查可复用、可公开的范围。
- 无布局布线及提取寄生参数时，明确标注为 **pre-layout synthesis/STA**，记录互连估算与时钟假设；不得称为 post-route timing closure。脚本已编写、服务器已运行、检查通过分别记录，缺工具时标记待验。

#### 必做

- 明确 synthesizable core/top 与 Verilator-only harness 的边界；
- 为时钟、输入/输出延迟形成最小 SDC；false/multicycle path 仅在有设计依据时添加；
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

不要把 ysyxSoC 的完整 AXI4 信号直接扩散回 IFU、LSU。保留 local req/rsp 边界，但不承诺 B2 只改最外层 wrapper：当前 Lite 读接口不传 size，且 adapter 已对齐地址，无法在下游还原窄 MMIO 读。先核对目标设备要求，必要时从 local 边界增加原生 AXI4 单拍 adapter；B1 的 Lite 系统继续作为独立验证对象。

```text
IFU/LSU semantic state
        │ local req/rsp
        ▼
transport adapters + core Arbiter
        │ single-outstanding；保留目标协议需要的 address/size
        ▼
ysyx top wrapper / AXI4 single-beat interface
        │ LEN=0；ID/width/size/burst 按目标契约映射
        ▼
ysyxSoC
```

这样做有三个收益：

- ysyxSoC 顶层端口或生成方式变化时，主要改 wrapper；
- 当前 core 仍用已经验证的 single-outstanding 语义；
- 后续 I-cache 需要 burst 时，扩展 refill transport/仲裁及顶层能力，不重写整个 core 控制；不能假设 burst 信息能穿过既有 Lite 接口。

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
- 对明确的可综合 core/wrapper/互联边界完成综合/STA；说明是否包含上游 IP、SRAM macro 或模型，不将仿真 top 的结果当作完整 SoC 实现结果。

### Milestone 6：完成 `6-icache-performance`

#### 为什么排在 ysyxSoC 后

- 已经有真实 memory hierarchy 和可校准延迟，cache 收益不再是假设；
- 完整 AXI4 接口能支持 burst refill，不必先围绕 AXI4-Lite 做一个即将重写的版本；
- SoC baseline 已固定，能比较 AMAT、CPI、Fmax 和面积；
- `fence.i`、不可缓存 MMIO、access fault 等系统问题都有实际环境。

#### 顺序

1. 在已有 cycle/commit/stall 统计上补齐 branch redirect、cache hit/miss 等事件计数，明确重叠和统计口径；
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

### Milestone 7：进入 `7-role-deepening`，按证据选择深化方向

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
- 对同一 workload 比较 `执行时间 = cycles / 运行频率`，同时报告面积与时序代价；不得用 `Fmax × IPC × area` 作为越大越好的指标。

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
- 复用既有 flow 完成 floorplan/place/CTS/route，工具届时确定；
- 针对 congestion/timing 的 RTL 反馈修改。

它目前排在 SoC/RTL 与 DV 之后，不应阻塞主线。

## 6. 贯穿所有阶段的质量门

每个 milestone 按同一模板说明适用项，区分 PASS、FAIL、待验和不适用（附理由），不要求每次小改动都执行所有层级。缺少服务器工具不阻塞不依赖其结果的 RTL 开发，但不得据此声称综合/STA 已通过。

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

### 实验记录的最低要求

实验继续保存在所属阶段，如 [`2-axi4-lite/4-signoff.md`](2-axi4-lite/4-signoff.md)，不另建一套全局实验日志。下列字段按实验类型适用；不适用项可省略，缺失项标记未记录，不能推测补填历史数据。

| 类别 | 必须留下的信息 |
| --- | --- |
| 版本与范围 | 日期、实验问题、baseline/candidate commit；未提交修改须有可定位的 patch；top、配置参数及实际包含的模块 |
| 软件与仿真 | workload/ELF 或 bin hash、编译参数、模拟器/参考模型版本、DiffTest 开关、latency/ready/error 配置、seed 集合、终止条件 |
| 实现流程 | DC/PT 版本、flow/SDC 版本、库/PVT 标识、时钟/I/O/例外约束、SRAM 实现、互连估算方式；区分 pre-layout/post-route |
| 结果与复现 | 命令/入口、通过与排除项、cycles/commits/CPI/计数定义，或 area/WNS/TNS/关键路径/未约束路径检查；摘要及原始报告归档位置 |
| 结论与限制 | 改善或退化、适用 workload、尚未验证之处；区分实测、估算与推断，记录下一步决策 |

- 单个 `add` 样本不代表全程序性能；不同模型的相同 seed 不保证相同随机时序。优化对比优先补确定性延迟对照，再扩展 workload/seeds。
- 各 stall counter 可重叠时不直接相加解释 CPI；Fmax 需说明推导方法和约束，仅达到某个 target 不代表测得最大频率。未做有条件说明的功耗分析，不声称完整 PPA 改善。
- 重要结果摘要随文档入库；大日志/波形留在可定位的服务器归档或制品目录，并记录标识/hash，不能仅依赖随时可清理的 `build/`。对外版本只使用可公开的信息。

### 持续积累展示素材

[`docs/notes/output/`](../output/README.md) 保存项目简介、[证据总索引](../output/evidence-index.md)以及精选图/PPT、bug case 和简历素材。它只引用阶段实验，不复制维护另一份结果表。重要功能或优化验收后补充证据链接、更新状态；普通小提交不要求编写展示文章。

需要投递时，检查“能解释设计与取舍、能定位证据与个人贡献、能说明限制”，从已有素材选取 2～3 条简历描述和少量图/案例即可。功能阶段仍保留技术验收与基线，不等同于求职资格门槛。

### 阶段面试 Q&A

每个 Milestone 在所属目录的 `qa/README.md` 维护与该阶段相关、具有面试价值的问答，例如 `3-axi4-lite-interconnect/qa/README.md`。首次有实际内容时创建，内容较多后再按主题拆分，并由 README 索引。

按“有价值的进展”新增或修订问答：重要接口或架构决策、代表性 bug 的定位与修复、阶段验证或性能实验结论，以及对实现边界或替代方案的新理解。**不是每次推进、每次提交都必须记录；普通小改动或没有新增认识时无需更新，也不为凑数量重复生成问题。**

每个问题围绕本工程的真实设计，记录面试问题、可在 30～60 秒内讲清楚的简短回答、必要的深入追问与方案取舍，以及源码、测试、波形或实验记录的证据链接。明确区分已实现、已验证、计划与知识拓展，不能把计划中的能力描述为已完成；已有事实和结果通过链接引用，不复制维护另一套实验记录。

阶段验收时检查问答与最终实现是否一致，修订过时回答或标明历史版本。优先积累能够解释个人设计决策并提供工程证据的问题，不要求整理通用题库。

## 7. 投入比例与停止条件

### 当前 RTL/SoC 主线期间

建议按总投入比例控制范围：

- AXI adapters/Arbiter/Xbar/设备：约 30%；
- ysyxSoC、AM、boot、interrupt：约 30%；
- 验证、formal、综合/STA、四值/网表：约 25%；
- 文档、指标和作品包装：约 15%。

这不是日历承诺，而是防止 90% 时间都投入 RTL feature、最后没有验证和可展示证据。

### 暂停扩展、补齐证据的触发条件

出现以下情况时先做必要收尾，再继续主线；不要求额外组织一次正式 job-release：

- 新功能开始同时跨 core、bus、SoC 和 software 多层修改；
- 当前 milestone 已通过但文档和结果表尚未整理；
- 连续增加功能却没有新的 benchmark、coverage 或 PPA 数据；
- 为接入第二、第三种外设/存储器而重复已有能力；
- 下一项工作无法对应目标岗位的一项明确能力或一个可验证问题。

## 8. 建议目录演进

现有目录保持不动，后续开始对应阶段时再创建：

```text
docs/notes/
├── output/                       # 对外展示入口、证据索引与精选素材
└── post-c/
    ├── roadmap.md
    ├── 1-memory-request/          # elastic core + precise memory exception
    ├── 2-axi4-lite/               # IFU/LSU AXI4-Lite adapters
    ├── 3-axi4-lite-interconnect/  # Arbiter/Xbar/minimal B1 slaves
    ├── 4-pre-soc-signoff/         # SDC/synthesis/STA/4-state/netlist smoke
    ├── 5-ysyx-soc-integration/    # B2 wrapper/boot/interrupt/system closure
    ├── 6-icache-performance/      # trace/cachesim/I-cache/burst/metrics
    └── 7-role-deepening/          # pipeline/BPU 或 focused DV，按证据选择
```

目录编号与 milestone 编号严格一一对应。每个目录至少维护一份明确的 plan/spec 和独立的 `dev-log.md`；需要冻结接口、测试矩阵、sign-off 报告或性能结果时，再在该目录增加专题文件。未开始的 milestone 不预先创建空目录和空模板。

阶段面试问答使用各 Milestone 内的 `qa/` 目录，以 `qa/README.md` 为入口，按上文“阶段面试 Q&A”规则随有价值的进展维护。

原计划的独立 `6-job-ready-release` 已取消，未创建的 I-cache/深化阶段顺延为 6/7。展示入口放在与 `post-c/` 平级的 `docs/notes/output/`，不占用技术 milestone 编号。

## 9. 最近三个行动

1. 进入 `3-axi4-lite-interconnect`，先冻结 arbitration/address-map 契约和最小测试矩阵，再实现 Arbiter/Xbar/slaves；
2. 同步积累展示证据；用户提供旧 flow 后裁剪 DC/PT 的最小综合/STA 路径，在服务器运行前将结果标记为待验，不阻塞无依赖的 RTL 工作；
3. 提前核对并固定 ysyxSoC revision 与接口契约，特别是窄 MMIO 读的地址/size 语义；当前 Lite adapter 已对齐地址，不能假设最外层固定 SIZE wrapper 能恢复这些信息。明确边界后再按 M5 实施集成。

在这三项完成前，不启动 GShare、经典五级流水重写、D-cache 或大规模外设扩展。
