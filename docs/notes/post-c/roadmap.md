# Post-C Roadmap：从弹性 RV32E Core 到可展示的 SoC/RTL 项目

> 规划更新：2026-10-29；M4 S2.5 ISA 收敛已完成本地验收，当前已建立 S3 范围内面积/时序基线，S6 已于 2026-10-19 完成最终回归与服务器独立复现，M4 本轮验收通过；M5 S0–S6 已完成，S7 本地准备完成、待服务器 CPU 子系统面积/时序结果；新增后期可选 RT-Thread 交互演示，M5 边界不变；M4 初始输入基线：`0fe53bf`（M3 功能/协议仿真验收后）
>
> 求职方向优先级：SoC/RTL Design > Design Verification > Physical Design  
> 本文用于决定 post-C 阶段的投入顺序。具体接口、地址映射和考核要求仍以开始该阶段时的最新版官方讲义与上游仓库为准。

对外展示统一从 [`docs/notes/output/`](../output/README.md) 进入；开发与实验详录留在所属阶段。按 2026-10-25 用户决定，本轮先完成 **M5 → 限定 GShare 增量 → 版本冻结 → 理解考察与简历 v1 → 投递与回顾并行**。实现期间继续积累证据，集中求职准备不占技术 Milestone 编号。

**冻结后的明确待办：[JOB-PREP-01：理解精髓与 DE/DV 能力复盘](../output/interview-readiness.md)。** M5 与 GShare 的验收交接都须保留这个入口；版本冻结后先开展该任务。下文 M6 I-cache / M7 深化是长期候选，不作为本轮简历 v1 的前置，也不自动紧接 M5 启动。

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
功能/协议仿真验收已完成
3-axi4-lite-interconnect：Arbiter -> Xbar -> SRAM/UART/CLINT/DECERR
        │               已建立 lint/SVA/随机回压基线
        ▼
已完成
4-pre-soc-signoff：DC/PT 面积与时序基线；DC 功耗粗估暂缓
        ▼
当前主线（S0–S6 完成，S7 本地准备完成、待服务器回传）
5-ysyx-soc-integration：AXI4 单拍子集封装 -> ysyxSoC 最小启动闭环
        │                    MROM/SRAM/UART/CLINT/DiffTest/RT-Thread
        ▼
限定 GShare 增量：功能回归 + 同条件性能/面积/时序对照
        │
        ▼
本轮冻结 -> JOB-PREP-01：理解考察与简历 v1 -> 投递与回顾
        │
        ▼
后续按需：6-icache-performance：trace/cachesim -> I-cache -> AXI burst
        │
        ▼
7-role-deepening：根据数据只选一条主攻
        ├─ RTL/CPU：弹性后端切级、forwarding/hazard、预测器深化
        └─ DV：AXI 子系统 UVM/coverage closure + 更深的 formal
```

核心调整有四点：

1. **AXI4-Lite 和 ysyxSoC 仍是最高优先级**，因为它们把 CPU 模块、互联、设备、软件和验证真正连成系统。
2. **验证和实现检查随设计推进**：日常优先 lint/单测/相关回归，稳定阶段补综合、STA、四值与适用的 formal；工具条件不足时明确待验，不把所有检查变成每次提交的前置条件。
3. **五级流水不再是近期必做的整核重写**。在 ysyxSoC 和性能基线完成后，根据 CPI/stall/关键路径决定是否把当前弹性后端继续切级。
4. **展示素材持续积累，本轮冻结后集中复盘**。按用户选择，在 M5 + 限定 GShare 增量完成后考察理解、生成简历 v1，再边投递边回顾；不等待所有长期扩展完成。

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
2. M3 已完成 Arbiter/Xbar、设备错误响应和系统级 address map 闭环，仍需补实现检查；
3. 还没有在 ysyxSoC 中完成 boot、UART、CLINT、AM 和 DiffTest 闭环；
4. 项目缺少持续保存的综合面积、关键路径、Fmax、STA 约束和网表/四值证据；
5. M3 已有 test plan、必测功能 bins 与仿真 closure，formal/四值/网表证据仍需区分并补齐；
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

本轮冻结前的优化只选限定 GShare 增量，单独明确功能验收与同条件性能/面积/时序对照；下面的 cache/burst 等为后续候选，不加入本轮截止范围。具体 GShare 计划在开始实施前编写，本文不预先宣称已完成或已有收益。

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
- [RT-Thread 交互控制台与应用演示](#后期可选rt-thread-交互控制台与应用演示)：接收终端命令、查看系统状态、启动简单程序；本轮冻结及求职准备后按需选择。

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

2026-10-14 已建立[设计与实施计划](3-axi4-lite-interconnect/plan.md)、[验收矩阵](3-axi4-lite-interconnect/test-plan.md)和[开发日志](3-axi4-lite-interconnect/dev-log.md)。

目前已完成 [S0 legacy 基线](3-axi4-lite-interconnect/0-baseline.md)、[S1 Arbiter](3-axi4-lite-interconnect/1-arbiter.md)、[S2 Xbar/default](3-axi4-lite-interconnect/2-xbar.md)、[S3 SRAM/UART/CLINT](3-axi4-lite-interconnect/3-slaves.md)、[S4 系统集成](3-axi4-lite-interconnect/4-integration.md) 和 [S5 closure](3-axi4-lite-interconnect/5-closure.md) 的对应验收；设计取舍记录在[阶段 Q&A](3-axi4-lite-interconnect/qa/README.md)。

2026-10-15：**M3 功能/协议仿真验收 PASS**，范围见 [signoff](3-axi4-lite-interconnect/signoff.md)。完整 fabric 随机/必测交叉覆盖、18 个 redirect 组合、RT-Thread 双线程各 100 次迭代与三段实际波形已完成。当前下一步为 **M4：最小综合/STA flow 与实现基线**；formal、四值、EDA/PPA 不混入 M3 仿真 PASS。

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

2026-10-15：已建立 [M4 S0–S6 计划](4-pre-soc-signoff/plan.md)及目录，完成 `npc/ref-flow` 的[本地初读](4-pre-soc-signoff/0-ref-flow-review.md)。先学习裁剪，再构建 `npc/flow/`；本次尚未修改源码或运行 EDA。首次以 `ysyx_core_axi4lite`（Core + adapters + Arbiter）评估，S3 取得面积/时序，可附带 DC `report_power` 假设活动粗估；原 S4 四值/网表和 S5 workload/PTPX 延后；不代表含 SRAM/外设的完整 SoC PPA。S0 的[流程图与逐级输入输出](4-pre-soc-signoff/0-flow-map.md)区分工艺库与 design；[缺失脚本清单](4-pre-soc-signoff/missing-inputs.md)仅核查 flow 脚本/编排配置。PDK 已在服务器，保留原路径；本地只做 flow 蒸馏，不复现旧工程。

2026-10-16：**[S1 本地出口通过](4-pre-soc-signoff/1-synthesis-scope.md)**：冻结 16 源文件与观察端口范围，隔离 DPI/SVA，GPR 改为显式复位并硬连 x0；两种宏配置的状态定向、B1 signoff、M2 定向和 legacy trace 通过。下一步 **S2 构建 NPC 最小 DC/PT flow 与数值 SDC**；没有新增 S1 阻塞，仍未运行 EDA。

2026-10-16：**[S2 本地实现/验证完成](4-pre-soc-signoff/2-flow.md)**：最小 DC/PT 入口、10 ns 试探约束、独立 run/输入快照/hash、失败传播与报告检查已建立，28 项本地测试通过。下一步服务器 S3 先 probe 核对库和工具，再综合/STA；未运行真实 EDA，没有新增面积/时序结果。

2026-10-17：**[首次综合已归档](4-pre-soc-signoff/synthesis-results/01-first-synthesis/README.md)**：DC 完成，10 ns setup/hold 失败，PT 未执行。先审查观察接口、长组合乘除法与约束，整理源版本和功能回归，再建立正式 S3 DC/PT 基线；当前结果仅作为首次诊断实验。所有需长期保留的综合实验加入[结果索引](4-pre-soc-signoff/synthesis-results/README.md)，保留失败证据和原始报告。频率目标需结合微架构与模型论证，不由工艺节点单独决定。

2026-10-18：**[S2.5 本地验收完成](4-pre-soc-signoff/2.5-isa-contract.md)**：移除 M、GPR 缩至 16 项，增加非法编码 cause 2 和明确的四 CSR 契约；独立译码/双平台异常程序、B1 signoff 与 legacy 影响检查通过。

2026-10-18：**[02 RV32E / 无 M 的 DC/PT 已归档](4-pre-soc-signoff/synthesis-results/02-rv32e-no-m/README.md)**：10 ns 无 setup/hold 违例，面积 9511.319905 library_area；仍有 66 条 min-capacitance 违例、5516 项复位/置位脉宽检查未测试，PT 正 slack 路径和禁用弧明细需补充。以上审查项关闭前不建立正式 S3 基线；历史 01 记录不变。

2026-10-18：**[03 200 MHz 候选已归档](4-pre-soc-signoff/synthesis-results/03-200mhz-candidate/README.md)**：5 ns 下 PT setup/hold slack +0.531597/+0.013534 ns、面积仍为 9511.319905 library_area。诊断增强已完成真实执行，确认高扇出 clk（1509 个负载）、禁用弧无 loop-breaking 标记。当前优先处理 66 个无负载 EXU buffer 的最小电容违例、复位脉宽覆盖及结构审查，尚不冻结正式 S3 基线。

2026-10-18 后续范围决定：按用户要求，早期 core 评估暂缓 reset 时序，对 rst_n 设置精确 false path，删除虚拟 release delay；脉宽/实际释放机制见 [reset TODO](4-pre-soc-signoff/reset-timing-todo.md)。历史 03 不改写，后续继续审查真实 coverage，电容违例与其他结构问题仍需处理。

2026-10-18：**[S3 core pre-layout 基线成立](4-pre-soc-signoff/3-synthesis-sta.md)**；[04](4-pre-soc-signoff/synthesis-results/04-200mhz-baseline/README.md) 在 TT / 200 MHz 下 DC/PT 无约束违例，面积 9242.855942 library_area，PT setup/hold +0.596843/+0.008754 ns。9426 reset deferred 与 24 常量条件禁用已分类，结构告警经审查；保留观察端口、ideal clock 和 ZeroWireload 边界，不外推物理或全 PVT sign-off。下一步 S6，M4 总验收尚未宣布完成。

2026-10-19：**[S6 与 M4 本轮验收通过](4-pre-soc-signoff/signoff.md)**；flow 44 项、ISA/异常、四组源闭包、B1 完整验收及 legacy 回归通过；[05 独立 synth/STA 复现](4-pre-soc-signoff/synthesis-results/05-s6-reproduction/README.md)与 04 的面积、时序、coverage、负载和告警一致。I12 关闭，无当前范围内阻塞；保留 reset、功耗及物理评估限制，下一步 M5。

这个里程碑防止“B1 仿真能跑，但接 SoC 时同时暴露协议、时序、复位和构建问题”。先建立最小实现基线，工作量取决于现有 RTL、工艺库和可复用 flow；不在取得工具与输入前承诺全部检查已可运行。

#### 工具与执行分工

- 暂定 [Design Compiler](https://www.synopsys.com/implementation-and-signoff/rtl-synthesis-test/design-compiler.html) 做综合、[PrimeTime](https://www.synopsys.com/implementation-and-signoff/signoff/primetime.html) 做 STA；**PnR 暂不实施，也不作为近期主线的依赖**。
- DC/PT User Guide 位于 `docs/userguide/`，通过 [M4 手册检索入口](4-pre-soc-signoff/manual-index.md)按主题/命令和 PDF 页码查阅；使用保留分页符的本地文本缓存，命令选项再按服务器实际版本帮助核对。
- 已提供 `npc/ref-flow` 的裁剪快照；先提取一个 top、一个 mode/corner 的最小路径，再逐项增加本项目需要的选项。重新审查 clocks、I/O delays、reset、false/multicycle paths；不继承旧工程未经解释的 waiver/约束。
- 脚本在本仓库维护，待实际导入时集中放在 `npc/flow/`；本地负责编辑和可执行的静态检查，用户同步到具备完整 EDA 的服务器运行。不提前搭建复杂的通用 flow 框架。
- 服务器按固定 RTL/脚本/SDC 版本运行，归档工具版本、库/PVT 标识、配置、命令和报告；详细结果归入本阶段，展示出口仅链接摘要。
- 仓库只存可共享的脚本与配置模板；工艺库与 license 留在服务器；本地蒸馏时保留脚本/配置中的服务器 PDK 路径，公开版本再处理机器路径和受限内容。迁移前检查可复用、可公开的范围。
- 无布局布线及提取寄生参数时，明确标注为 **pre-layout synthesis/STA**，记录互连估算与时钟假设；不得称为 post-route timing closure。脚本已编写、服务器已运行、检查通过分别记录，缺工具时标记待验。

#### 必做

- 明确 synthesizable core/top 与 Verilator-only harness 的边界；
- 为时钟、输入/输出延迟形成最小 SDC；false/multicycle path 仅在有设计依据时添加；
- 检查 latch、组合环、下降沿逻辑、隐式位宽转换和未驱动信号；
- 检查 reset 后所有 control/valid/owner 状态，数据寄存器依赖 valid 屏蔽；
- 固化 `lint -> unit -> random -> system -> synth -> sta` 的可重复命令。

本轮按用户决定只完成 DC/PT 面积与时序基线；`report_power` 为附带参考，记录活动/频率/负载/PVT 等假设，不能称为 workload 实测功耗。四值/网表 smoke 与 PTPX 活动分析延后，不作为本轮出口；相应验证能力仍标记未执行。

#### 关于 CDC/RDC

如果当前设计只有一个同步时钟域，就在 sign-off 报告中如实写明“无功能性 CDC”，并审查 reset deassertion 方式。不要为了简历关键词人为制造异步域；等真实 SoC 外设或时钟域出现后，再实现 synchronizer/async FIFO 并做对应检查。

#### 出口

- 生成的 RTL 不依赖 DPI-C 才能综合；
- 工具报告和日志路径固定，可由干净工作区复现；
- 已知 warning 有逐项说明，而不是全局屏蔽；
- DC/PT 基线有版本号和结果摘要，明确未做四值/网表动态验证与物理实现。

### Milestone 5：完成 `5-ysyx-soc-integration` / B2

2026-10-19：已建立 [M5 目录](5-ysyx-soc-integration/README.md)、[S0–S8 设计与验收计划](5-ysyx-soc-integration/plan.md)和[验收矩阵](5-ysyx-soc-integration/test-plan.md)。当前 S0 尚未执行；下一步固定上游契约、生成环境、reset/IRQ 和内存预算，再实施原生 AXI4 单拍接口。原版学习入口采用 2607 C5，B2 保留为本工程沿用的阶段称呼。

2026-10-19：**[M5 S0 完成](5-ysyx-soc-integration/0-upstream-contract.md)**。固定ysyxSoC `df38a4d...`及递归依赖/补丁，重新生成成功，61-port ABI与静态展开核对通过；地址/reset/IRQ/模型缺口已记录，确定4MiB PSRAM路线。无阻止S1的外部依赖；下一步S1原生AXI4单拍transport。默认错误响应/空外设、真实XIP和PSRAM颗粒仍须分别在S2/S4落实，不代表SoC功能已验收。

2026-10-20：按用户决定，M5 直接升级当前接口，不维护 B1/SoC 两套 transport。B1 是接入前的历史系统测试；S1 迁移有效的 CPU/协议检查，取消旧 B1/legacy 兼容验收要求。历史 RTL、M3/M4 报告通过对应 Git revision 复现，当前只推进 SoC 接口。

2026-10-20：**[M5 S2 完成](5-ysyx-soc-integration/2-bringup.md)**，S1 接口已接入真实 SoC。MROM ebreak、UART TX=A、SRAM 和精确错误路径通过；新增 SoC guard、事件调度与 backing，S1 完整回归通过。当前无阻塞，下一步 S3 AM/SRAM/DiffTest。

2026-10-20：**[M5 S3 完成](5-ysyx-soc-integration/3-runtime-difftest.md)**。新增 `ARCH=riscv32e-ysyxsoc`、真实 SRAM poison/data/bss 初始化与独立 NEMU profile；31个正向workload全部提交差分、最终SRAM比较通过，含24个CPU tests和sieve/fib smoke。普通指令结果扰动、遗漏copy/clear、容量超限负例均有效，S2回归通过；无整状态skip、无当前阻塞。下一步S4真实Flash/PSRAM启动；完整benchmark/RTT与timer IRQ仍待后续。

2026-10-26：**[M5 S4 完成](5-ysyx-soc-integration/4-boot-memory.md)**。真实 SPI/XIP、Flash → SRAM/4 MiB PSRAM、普通存储差分与最终 RAM 比较通过；34个适用CPU tests、RT-Thread协作容量workload及启动/容量负例通过，S1/S2/S3回归通过。实际静态RAM42,992 B，无当前阻塞；下一步S5 timer interrupt，未宣称抢占RTOS完成。

2026-10-28：**[M5 S5 完成](5-ysyx-soc-integration/5-timer-interrupt.md)**。CPU 内部 CLINT、mie/mip、精确 timer IRQ/MRET、AM 上下文和 RTT tick smoke 已接通；6 个 SoC 程序的 139,396 条提交与 17 次 IRQ 全部差分，10 个随机延迟 seed 和 2 个检测负例通过。修复连续 redirect 丢失旧取指响应的死锁；S1–S4 功能回归通过。当前无阻塞，下一步 S6 完整抢占/阻塞唤醒与资源水位，之后 S7 新范围综合。RT-Thread BSP 改动附主仓库可重放补丁，不把单线程 tick 当成完整 RTOS 验收。

2026-10-28：**[M5 S6 完成](5-ysyx-soc-integration/6-system-validation.md)**。68 个真实 SoC 正向运行、1,824,069 条提交与 30 次 IRQ 全部差分；有限双线程无主动 yield 抢占、sleep 唤醒、分栈/heap、528 字节实际 UART 和系统随机等待验收通过。无新增功能 RTL 修改或未处置功能阻塞，下一步 S7 CPU 子系统 DC/PT，随后 S8 干净复现与交接。

#### 架构建议

保留 IFU/LSU 的 local req/rsp 语义边界，直接将现有 adapters、仲裁和顶层升级为面向 ysyxSoC 的 AXI4 单拍接口。当前 Lite 读接口不传 size，且 adapter 已对齐地址，必须在 adapter 内保留原始信息，不能只在最外层补端口。不新增 Lite/AXI4 模式选择或旧地址兼容层；B1 的有效测试检查点迁移到新接口，旧系统仅作历史复现。

```text
IFU/LSU semantic state
        │ local req/rsp
        ▼
升级后的 AXI4 adapters + core Arbiter
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

上游入口：[OSCPU/ysyxSoC](https://github.com/OSCPU/ysyxSoC)。官方文档也明确提醒设备和地址空间可能变化，接入时应重新核对 [2607 C5 SoC 计算机系统](https://ysyx.oscc.cc/docs/2607/c/5.html)，并以固定 revision 的源码与生成结果为准。

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

M5 规划补充：Flash → SRAM 是最小启动出口，不意味着所有 workload 都能放进讲义中的 8 KiB SRAM。现有 B1 RT-Thread 静态线程栈已达 16 KiB，另要求 heap > 32 KiB；S0 必须核算新 workload 容量，默认预期 S4 需要 PSRAM 承载 RT-Thread。只有证明专用 workload 的容量及验证能力足够，才可免去 PSRAM；不无记录扩大 SRAM 或取消系统验收。详见 [M5 容量与启动设计](5-ysyx-soc-integration/plan.md#33-地址容量和启动)。

S0 实际决策：已有RT-Thread ELF静态段42,932B，采用4MiB PSRAM；Flash → SRAM保留为小程序启动出口，完整系统程序走Flash → PSRAM。实际地址容量和模型缺口以 [S0契约](5-ysyx-soc-integration/0-upstream-contract.md)为准。

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

### 后期可选：RT-Thread 交互控制台与应用演示

2026-10-27 记录，**尚未实施，不改变 M5 的 S0–S8 范围或验收条件**。本轮仍按 M5 → 限定 GShare → 冻结 → [JOB-PREP-01](../output/interview-readiness.md) 推进；交互演示是后期候选，不要求先完成 M6/M7，也不作为简历 v1 的前置。

**版本与运行模型明确为：RT-Thread Standard（标准版）的裁剪配置，RV32E、单核、M-mode、无 MMU，内核与应用线程共享地址空间。** 本地 `rt-thread-am` 的 [版本定义](../../../rt-thread-am/include/rtdef.h) 为 5.0.1；当前 workload 从该源码树选择内核子集，并使用[独立 rtconfig.h](../../../npc/tests/b1-rtthread/include/rtconfig.h)，没有启用 `RT_USING_SMART`。裁剪成小配置不等于已经迁移到 Nano 发行版。

| 版本 | 主要定位 | 与本选项的关系 |
| --- | --- | --- |
| RT-Thread Nano | 极简实时内核，支持多线程、同步通信等，不要求 MMU | 可作轻量 RTOS 参考；本工程无需另换 Nano 源码来实现简单交互 |
| RT-Thread Standard | 可裁剪内核与设备框架、FinSH/MSH 等组件，不以 MMU 为前提 | 沿用本地版本，按需加入 shell、驱动与应用，作为本选项的目标 |
| RT-Thread Smart | 在标准版基础上引入用户态应用、系统调用与独立地址空间；其 MMU 方案用于地址转换和隔离 | 不纳入本选项，不追加虚拟内存与用户进程移植 |

版本划分参考 [RT-Thread 官方文档说明](https://gitee.com/rtthread/docs-online/blob/master/README.md)。**能输入命令、运行多线程程序，不要求 MMU；MMU 解决的是虚拟地址映射与隔离等问题。** 本选项的程序共享内存，没有独立进程地址空间；“以后增加 ELF loader”也不自动意味着改用 Smart，动态加载与地址空间隔离应分别设计。

目标是让 SoC 具备可操作的计算机使用体验：从 Flash 启动 RT-Thread，在终端输入 `help/version/ps/free` 等简单命令，查看线程和内存，启动一个测试或小程序，完成后返回 shell；后台线程可继续运行。

**先支持“命令调用已链接进镜像的程序入口或创建线程”。** 可选择适配后的 AM 程序，约定参数、返回和资源释放，避免沿用 `halt/ebreak` 结束整个系统。若希望从文件中加载独立 ELF，再增加程序来源、loader、ABI/重定位和生命周期管理；这是更进一步的选项。命令行本身不要求文件系统，也不等于支持全部 RT-Thread 组件。

#### 硬件支持与增量边界

下表区分“当前已具备”与“既定计划完成后具备”：截至本记录，M5 S0–S6 已验收，有限双线程抢占/阻塞唤醒、UART TX 和资源检查通过；交互功能仍是后期选项。

| 所需能力 | 当前或既定 roadmap 的覆盖 | 此可选项需要额外完成的工作 |
| --- | --- | --- |
| 执行代码、访问数据、保存上下文 | 已有 RV32E、栈/heap、同步 trap/MRET 和协作式线程切换 | 按现有 ISA/ABI 编译所选组件与程序；基础交互无需增加 M/C、MMU 或用户态 |
| 启动和运行存储 | S4 已有 16 MiB Flash 只读镜像、8 KiB SRAM、4 MiB PSRAM 及真实搬运启动 | 复用 `flash-psram`，重新核算 shell、程序及各线程的栈/heap 预算；不预设需要 SDRAM |
| tick、临界区、抢占与超时 | M5 S5/S6 已完成 CLINT `mtimecmp/MTIP`、CPU 精确中断、AM 中断开关和有限 RT-Thread 抢占/阻塞唤醒 | 检查新增 shell/IPC/驱动所用接口，增加后台线程与交互并行的测试；不能将有限 workload 通过等同于所有内核 API 已验证 |
| UART 双向通信 | 上游 UART16550 RTL 已有 RX/TX，M5 已验证真实 TX；RX 输入闭环尚未完成 | harness 将终端字符编码为 RX 引脚波形并实时显示 TX；驱动读取真实 UART 接收寄存器，提供缓冲和 shell 输入通知 |
| 外部设备中断 | 当前 M5 不开放外部 IRQ，也不实现 PLIC | 第一版可用定时轮询线程接收 UART 并唤醒 shell；若选择 UART IRQ，再补外部中断接线、CSR/入口、ISR 和参考同步。PLIC 按多中断源管理需求另行决定 |
| 文件与持久化存储（进一步选做） | 当前 Flash 路线仅支持读取，PSRAM 是易失 RAM；M5 不提供文件系统 | 需要文件命令时接文件系统与存储后端；如要求修改文件并在复位后保留，再实现 Flash 擦写或其他可写非易失介质 |

#### 软件、仿真与验证补充

- **接入 shell 和设备框架：** 单独配置 FinSH/MSH、console、所需 IPC 与组件初始化。现有 [S4 RT-Thread workload](5-ysyx-soc-integration/s4-validation/README.md) 只运行有限内核子集；旧 [BSP uart.c](../../../rt-thread-am/bsp/abstract-machine/src/uart.c) 的 `_uart_getc()` 返回固定命令字符串，不能当作真实 RX。无字符时应等待，有字符后通知并唤醒 shell，不能只替换一次读取函数。
- **接好构建与布局：** 参考 [extra.ld](../../../rt-thread-am/bsp/abstract-machine/extra.ld)，将 `FSymTab` 命令表、`.rti_fn*` 初始化表等纳入当前链接布局，核对 `KEEP`、VMA/LMA 和启动复制范围；补齐所选命令依赖的 libc/BSP 占位函数。
- **保留自动化入口：** 在 [SoC harness](../../../npc/csrc/soc/main.cpp) 中同时支持人工输入和按仿真时间回放字符，输入经过真实 UART RX；沿用设备输入同步与 DiffTest 检查。交互会话支持主动退出，回归保留有界超时与明确 PASS。

最小验收：人工输入和自动回放均能执行若干内置命令；至少一个程序运行后返回 shell 并可再次启动；无输入时其他线程仍能推进；连续输入、编辑/回车及缓冲边界有检查；保留 UART RX/TX、命令输出和线程进度证据。外部 ELF 加载、文件系统、网络及图形等按实际需求另立范围。

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

### 子步骤实施文档：以理解与学习为目标

适用于每个 Milestone 内 S0、S1 等子步骤的实施文档，例如 [M5 S2 实现与源码导读](5-ysyx-soc-integration/2-bringup.md)。**核心要求是讲清“做了什么、修改了什么，并让读者理解这些改动如何工作”。** 文档面向具备相关基础、但没有参与本次开发或阅读聊天记录的人；读后应能学到实现方法、对照源码复核，并继续维护工程。

按功能或一条完整的工作路径组织内容，覆盖以下问题：

| 读者需要理解什么 | 撰写要求 |
| --- | --- |
| 本步做了什么，为什么需要做 | 交代前置状态、要解决的具体问题和实现后的行为；区分本步新增/修改、前步复用、上游已有及后续计划 |
| 修改在哪里，各部分负责什么 | 将功能对应到源码文件及函数、模块、信号或配置项，提供可点击的链接和关键符号；说明文件之间的分工，跨层修改要串起各层关系 |
| 改动如何工作 | 沿一个典型请求、数据流、状态转移或工具流程解释输入、处理过程和输出；结合具体例子讲清关键条件、必要的错误/复位分支及设计取舍 |
| 阅读这段实现需要什么知识 | 在文档开头解释本步新增、影响理解的术语和概念；正文首次使用时结合具体行为说明接口语义和用途，按需要使用图、表或短代码片段 |
| 怎样知道实现正确，有哪些边界 | 将功能对应到测试入口、独立预期、观察位置和结果证据，解释测试证明了什么；明确尚未实现或验证的部分，原始结果通过链接引用 |

**学习效果优先于形式完整。** 文件清单、diff、命令和PASS汇总应配合必要的因果解释；不能用“新增模块X、测试通过”代替对工作原理的说明。篇幅和结构随改动复杂度调整：简单修改可用几段说明，跨模块实现再增加源码索引、时序/状态图和阅读路线；不要求每篇都套相同章节、抄录大段源码或扩写成通用教材。

**新增术语要先讲明白，再用于解释实现。** 开头用简短说明或“相关术语”表给出英文/缩写、中文含义及本步中的具体作用；不能只展开英文全称，或用另一个未经解释的术语代替定义。例如 `preempt` 应说明是“线程未主动让出 CPU，却被调度切走”，再对应到 timer IRQ 如何触发线程切换。正文中的新文件名、函数名若承载新概念，也要说明它是什么、为什么需要它。已有术语可链接到此前解释，保留本篇理解所需的简短提示；没有新增概念的小修改不必凑术语表。

完成子步骤时同步更新实施文档，后续实质改动修订相应说明。源码定位优先保留稳定的符号名，行号作为辅助；历史验收证据保留版本语境。小修正可并入已有文档，不要求每次提交新建一篇。

自查标准：**读者能否说明本步新增的行为、沿源码走完一条关键路径、解释主要改动的理由，并找到验证依据？** 若只能知道“完成了哪些任务”，还需要补充实现解释。`dev-log`记录推进过程，实施文档负责系统讲解，验收归档保存证据，三者通过链接关联。

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

本轮在 M5 + GShare 冻结后，按 [JOB-PREP-01](../output/interview-readiness.md) 集中检查“能独立解释与推导、能定位证据、能完成小变化并验证”，再从已有素材选取 2～3 条简历描述和少量图/案例。工程验收与个人理解考察分别记录；代码通过测试不自动代表本人已掌握。

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

开发期间出现以下情况时先做必要收尾，再继续主线；本轮冻结后另按 JOB-PREP-01 集中开展理解考察与简历准备：

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
    ├── 4-pre-soc-signoff/         # DC/PT 面积时序；DC 功耗粗估为附带项
    ├── 5-ysyx-soc-integration/    # B2 wrapper/boot/interrupt/system closure
    ├── 6-icache-performance/      # trace/cachesim/I-cache/burst/metrics
    └── 7-role-deepening/          # pipeline/BPU 或 focused DV，按证据选择
```

目录编号与 milestone 编号严格一一对应。每个目录至少维护一份明确的 plan/spec 和独立的 `dev-log.md`；需要冻结接口、测试矩阵、sign-off 报告或性能结果时，再在该目录增加专题文件。未开始的 milestone 不预先创建空目录和空模板。

子步骤实施文档遵循上文[“以理解与学习为目标”](#子步骤实施文档以理解与学习为目标)的要求，兼顾功能说明、源码导读与验证依据。

阶段面试问答使用各 Milestone 内的 `qa/` 目录，以 `qa/README.md` 为入口，按上文“阶段面试 Q&A”规则随有价值的进展维护。

原计划的独立 `6-job-ready-release` 技术目录已取消，未创建的 I-cache/深化阶段保留编号 6/7。2026-10-25 新约定的集中求职准备由 `docs/notes/output/interview-readiness.md` 承担，不恢复该技术目录；GShare 增量的目录和编号在其实施计划中确定，不在此预建空目录。

## 9. 最近三个行动

1. 按 [M5 S6 交接](5-ysyx-soc-integration/6-system-validation.md)推进 S7：冻结 CPU 子系统的 scope/filelist，补齐 AXI、clock/reset 与端口时序预算，复用 DC/PT flow；
2. 用户在服务器执行 synth/STA 并回传，检查面积、时序、电气规则、coverage 和关键路径；M5 首个评估范围是 CPU 子系统，不是 whole-SoC；
3. 按 M5 S8 完成冻结版本的干净构建复现和验收交接；保留 M4 04/05 历史基线，固定后续 GShare 对照所用的程序、存储和统计条件。

在这三项完成前，不启动 GShare、经典五级流水重写、D-cache 或大规模外设扩展。

之后按本轮顺序完成限定 GShare 增量并冻结版本，进入 **[JOB-PREP-01](../output/interview-readiness.md)**。验收交接和决定下一步工作时检查该待办，避免直接转入新的技术扩展而遗漏理解考察与简历 v1。
