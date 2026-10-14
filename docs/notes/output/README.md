# NPC：面向 SoC 集成的 RISC-V 处理器项目

> 更新：2026-10-14；已提交实现基线：`5b6f29c`。此处是持续更新的展示入口，不是完整 SoC 或 tapeout sign-off 声明。

## 项目简介

基于[一生一芯](https://ysyx.oscc.cc/docs/)推进的软硬件协同工程，重点是处理器 RTL、总线/互联、验证和 SoC 集成。软件与模拟器用于提供 workload 和参考行为，后续通过综合、STA 和性能实验评估架构取舍。

NPC 已从集中式多周期控制演进为单发射、顺序提交的弹性前后端：IFU、IFQ、opbuf、EXU、LSU 分别持有指令或访存上下文，由 commit/redirect 协调架构状态更新与控制流切换。当前已完成 IFU/LSU AXI4-Lite adapters，下一步是 Arbiter、Xbar 与最小 RTL slaves。

## 当前可展示内容

| 主题 | 已有内容 | 边界 |
| --- | --- | --- |
| Core 微架构 | 弹性前后端、可变延迟访存、stale fetch 丢弃、精确访存异常 | 非经典五级流水；尚无 cache、多 outstanding |
| 总线接口 | IFU/LSU 两套 AXI4-Lite master，独立 AW/W 握手、回压和错误传播 | C++ slave 为验证模型；RTL 互联/外设尚未完成 |
| 验证 | Verilator、commit trace、GPR/CSR DiffTest、模块测试、随机时序回归 | 不等于完整 ISA compliance 或 formal/coverage closure |
| 系统 workload | CPU tests、UART hello、RTC、yield-os | 当前 NPC harness 环境，不代表已接入 ysyxSoC |

最近阶段验收记录了 **34/34 CPU tests 通过，DiffTest 开启**；原 `unalign` 用例与项目的非对齐异常策略不兼容，另以 cause 4/6 定向测试验证。另有固定 `add` workload 的 10 个随机 seed 测试，不应表述为所有用例都做过十轮随机回归。结果、配置和复现入口见[证据索引](evidence-index.md)。本页整理已有记录，不代表本次重新执行了测试。

当前以 `riscv32e-npc` 为构建/workload 目标；RTL 仍有 32 项 GPR，尚未完成 RV32E 保留寄存器编码等合规收尾。尚无可对外引用的 DC/PrimeTime 面积与时序结果，也未完成 PnR。

## 阅读与展示材料

- [工程事实与证据索引](evidence-index.md)：从可陈述能力定位到源码、实验和验收依据。
- [开发路线](../post-c/roadmap.md)：当前主线、优先级、实验记录与 EDA 流程约束。
- [Core 架构导读](../post-c/1-memory-request/4-current-npc-architecture.md)：Phase 2B 架构快照；后续异常与 AXI 改动见证据索引。

本目录存放精选的项目简介、架构图/PPT、展示用波形、bug case 和简历素材；有实际材料时再创建 `figures/`、`cases/`、`slides/` 等子目录。保留图的可编辑源文件和导出版，并注明对应 RTL 版本。开发详录与实验原始结论仍放在所属阶段，避免维护两份结果。

## 贡献与使用边界

重点展示本工程中 Core 重构、接口实现、验证及后续集成的设计决策，具体改动以源码和 Git 记录为据。NEMU、AbstractMachine、测试程序与未来接入的 ysyxSoC 有课程/上游基础；区分自主实现、参考改造和直接复用，不将上游完整系统作为个人实现成果。

本目录是对外材料的出口，不代表整个仓库均适合公开。分享前检查第三方参考 RTL、旧 tapeout flow、工艺库和报告的可公开范围，去除敏感路径与配置。不设置固定的 job-release 时刻；有新的工程证据就更新，需要投递时再按目标岗位选材。
