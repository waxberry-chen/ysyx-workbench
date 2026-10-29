# NPC：面向 SoC 集成的 RISC-V 处理器项目

> 更新：2026-10-30；[M5 S0–S8 已验收](../post-c/5-ysyx-soc-integration/signoff.md)，M4 core 历史基线独立保留。当前具备真实 SoC 功能验证与 CPU 子系统 pre-layout 面积/时序证据；不代表完整 SoC 物理 sign-off。

> 2026-10-25 求职准备安排：本轮 **M5 + 限定 GShare 增量验收并冻结后**，开展 [JOB-PREP-01：理解精髓与 DE/DV 能力复盘](interview-readiness.md)，整理简历 v1，再边投递边回顾。当前仅计划已记录，理解考察尚未开展。

## 项目简介

基于[一生一芯](https://ysyx.oscc.cc/docs/)推进的软硬件协同工程，重点是处理器 RTL、总线/互联、验证和 SoC 集成。软件与模拟器用于提供 workload 和参考行为，后续通过综合、STA 和性能实验评估架构取舍。

NPC 已从集中式多周期控制演进为单发射、顺序提交的弹性前后端：IFU、IFQ、opbuf、EXU、LSU 分别保存指令或访存上下文，由 commit/redirect 协调架构状态与控制流。当前 [M5 总验收](../post-c/5-ysyx-soc-integration/signoff.md)覆盖原生 AXI4 单拍接入 ysyxSoC、MROM/SRAM、Flash→SRAM/PSRAM 启动、精确 timer IRQ、AM 上下文和有限 RT-Thread 抢占/唤醒。S8 完成干净功能构建，并修复旧二进制路径依赖后补测通过；CPU 子系统已有 [S7 200 MHz 基线](../post-c/5-ysyx-soc-integration/s7-validation/baseline/README.md)。下一步先制定限定 GShare 计划，随后进行相同条件的功能/性能/面积/时序对照。

## 当前可展示内容

| 主题 | 已有内容 | 边界 |
| --- | --- | --- |
| Core 微架构 | 弹性前后端、可变延迟访存、stale fetch 丢弃、精确访存异常 | 非经典五级流水；尚无 cache、多 outstanding |
| 总线接口与互联 | [原生 AXI4 单拍](../post-c/5-ysyx-soc-integration/1-axi4-interface.md)、仲裁、内部 CLINT 路由、SoC 默认错误/权限保护 | 保留 byte address/size/lane；全局单 outstanding，无 burst/interleaving；B1/Lite 为历史配置 |
| 设备/存储 | 4 KiB MROM、8 KiB RTL SRAM、Flash XIP、4 MiB PSRAM、实际 UART TX；[S4](../post-c/5-ysyx-soc-integration/4-boot-memory.md) | 复用上游控制器并完成所需改造/模型；没有 SRAM macro 或完整 SoC PPA |
| 验证 | Verilator、commit trace、GPR/CSR DiffTest、模块测试、随机时序回归 | 必测功能 bins 已检查；不等于完整 ISA compliance 或 formal proof |
| 系统 workload | 34 个适用 CPU tests、三种启动布局、timer IRQ、有限 RTT 抢占/唤醒/资源检查、随机 AXI 等待和实际 UART | S8 共112次真实SoC正向运行，108次差分/2695308条提交/47 IRQ；含跨阶段重复程序，无交互 shell |
| 综合 / STA | [M5 S7 基线](../post-c/5-ysyx-soc-integration/s7-validation/baseline/README.md)：TT 200 MHz，area 9530.135856 library_area，setup/hold +2.444726/+0.009693 ns，电气违例0 | CPU+adapters/arbiter/router/CLINT；ideal clock/ZeroWireload；reset deferred，Ultra leakage零目标有记录处置；无功耗/PnR结论 |

历史 M3 验收中，**34/34 CPU tests 通过，DiffTest 开启**；原 `unalign` 不符合本项目异常策略，另以 cause 4/6 定向用例验证。S5 重跑 53 个固定时序系统程序，另做 add/bubble-sort 各 10 个延迟 seed、2 次有限 RT-Thread 和空参数 hello。完整 fabric 有 10 seeds、每 seed 至少 1000 笔完成与 69 reset 场景；不能表述成所有 CPU 用例都做过十轮随机测试。配置、实际波形、覆盖及本地归档见[证据索引](evidence-index.md)。

当前以 `riscv32e-ysyxsoc` 为构建/workload 目标，旧 `riscv32e-npc` 使用历史版本复现；[M4 S2.5](../post-c/4-pre-soc-signoff/2.5-isa-contract.md) 已移除 M、收敛为 16 项 GPR，补齐非法编码检测和限定的 CSR 契约，双平台回归通过；仍不声明完整 ISA/特权架构合规。[首次综合](../post-c/4-pre-soc-signoff/synthesis-results/01-first-synthesis/README.md) 的旧 32 GPR/M 配置未达 10 ns；[02 RV32E / 无 M](../post-c/4-pre-soc-signoff/synthesis-results/02-rv32e-no-m/README.md) 已执行 DC/PT，面积为 9511.319905 library_area，10 ns 无 setup/hold 违例。[03 200 MHz 候选](../post-c/4-pre-soc-signoff/synthesis-results/03-200mhz-candidate/README.md) 在相同 RTL/scope 下收紧为 5 ns，PT setup/hold slack 为 +0.531597/+0.013534 ns，面积不变；该轮仍有 66 条最小电容违例与复位脉宽覆盖/结构审查项。后续 04 已关闭当前范围内的电气和结构审查，建立正式 S3 基线；PnR 尚未实施。01 与后续实验的 ISA 范围不同。后续早期评估按用户决定暂缓 reset 时序，适用范围与恢复验收条件见 [reset TODO](../post-c/4-pre-soc-signoff/reset-timing-todo.md)；不改变历史实验结论。

## 阅读与展示材料

- [工程事实与证据索引](evidence-index.md)：从可陈述能力定位到源码、实验和验收依据。
- [理解精髓与 DE/DV 能力复盘](interview-readiness.md)：冻结后的准备阶段、考察标准、执行方式及待办；工程测试结果与个人理解结果分开记录。
- [开发路线](../post-c/roadmap.md)：当前主线、优先级、实验记录与 EDA 流程约束。
- [Core 架构导读](../post-c/1-memory-request/4-current-npc-architecture.md)：Phase 2B 架构快照；后续异常与 AXI 改动见证据索引。

本目录存放精选的项目简介、架构图/PPT、展示用波形、bug case 和简历素材；有实际材料时再创建 `figures/`、`cases/`、`slides/` 等子目录。保留图的可编辑源文件和导出版，并注明对应 RTL 版本。开发详录与实验原始结论仍放在所属阶段，避免维护两份结果。

## 贡献与使用边界

重点展示本工程中 Core 重构、接口实现、验证及后续集成的设计决策，具体改动以源码和 Git 记录为据。NEMU、AbstractMachine、测试程序与已接入的 ysyxSoC 有课程/上游基础；区分自主实现、参考改造和直接复用，不将上游完整系统作为个人实现成果。

本目录是对外材料的出口，不代表整个仓库均适合公开。分享前检查第三方参考 RTL、旧 tapeout flow、工艺库和报告的可公开范围，去除敏感路径与配置。有新的工程证据就更新；本轮按上述冻结后的准备安排生成简历 v1，并按目标岗位选材。
