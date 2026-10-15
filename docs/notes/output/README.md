# NPC：面向 SoC 集成的 RISC-V 处理器项目

> 更新：2026-10-15；Core/adapters 验收基线：`5b6f29c`。此处是持续更新的展示入口，不是完整 SoC 或 tapeout sign-off 声明。

## 项目简介

基于[一生一芯](https://ysyx.oscc.cc/docs/)推进的软硬件协同工程，重点是处理器 RTL、总线/互联、验证和 SoC 集成。软件与模拟器用于提供 workload 和参考行为，后续通过综合、STA 和性能实验评估架构取舍。

NPC 已从集中式多周期控制演进为单发射、顺序提交的弹性前后端：IFU、IFQ、opbuf、EXU、LSU 分别持有指令或访存上下文，由 commit/redirect 协调架构状态更新与控制流切换。当前已完成 IFU/LSU AXI4-Lite adapters、Arbiter、Xbar/default、SRAM/UART/CLINT，并接入 Core/B1 系统；[M3 功能/协议仿真验收](../post-c/3-axi4-lite-interconnect/signoff.md)通过，包含固定 RT-Thread workload。下一步准备综合/STA 实现基线。

## 当前可展示内容

| 主题 | 已有内容 | 边界 |
| --- | --- | --- |
| Core 微架构 | 弹性前后端、可变延迟访存、stale fetch 丢弃、精确访存异常 | 非经典五级流水；尚无 cache、多 outstanding |
| 总线接口与互联 | IFU/LSU AXI4-Lite adapters；standalone Arbiter、Xbar/default 已验证，见 [S2 报告](../post-c/3-axi4-lite-interconnect/2-xbar.md) | 完整 fabric 随机/必测合法交叉覆盖通过；无 burst、多 outstanding |
| RTL 设备 | SRAM byte mask、UART TX 事件、CLINT mtime，见 [S3 报告](../post-c/3-axi4-lite-interconnect/3-slaves.md) | 独立模块与 Core 系统测试通过；loader、输出 sink 和 AM 已适配，尚无 SRAM macro |
| 验证 | Verilator、commit trace、GPR/CSR DiffTest、模块测试、随机时序回归 | 必测功能 bins 已检查；不等于完整 ISA compliance 或 formal proof |
| 系统 workload | B1 的 CPU tests、hello、uptime、yield-os、有限 RT-Thread，见 [S5](../post-c/3-axi4-lite-interconnect/5-closure.md) | RT-Thread 为协作调度，无 RX/timer IRQ；ysyxSoC 待接入 |

最近 M3 验收中，**34/34 CPU tests 通过，DiffTest 开启**；原 `unalign` 不符合本项目异常策略，另以 cause 4/6 定向用例验证。S5 重跑 53 个固定时序系统程序，另做 add/bubble-sort 各 10 个延迟 seed、2 次有限 RT-Thread 和空参数 hello。完整 fabric 有 10 seeds、每 seed 至少 1000 笔完成与 69 reset 场景；不能表述成所有 CPU 用例都做过十轮随机测试。配置、实际波形、覆盖及本地归档见[证据索引](evidence-index.md)。

当前以 `riscv32e-npc` 为构建/workload 目标；RTL 仍有 32 项 GPR，尚未完成 RV32E 保留寄存器编码等合规收尾。尚无可对外引用的 DC/PrimeTime 面积与时序结果，也未完成 PnR。

## 阅读与展示材料

- [工程事实与证据索引](evidence-index.md)：从可陈述能力定位到源码、实验和验收依据。
- [开发路线](../post-c/roadmap.md)：当前主线、优先级、实验记录与 EDA 流程约束。
- [Core 架构导读](../post-c/1-memory-request/4-current-npc-architecture.md)：Phase 2B 架构快照；后续异常与 AXI 改动见证据索引。

本目录存放精选的项目简介、架构图/PPT、展示用波形、bug case 和简历素材；有实际材料时再创建 `figures/`、`cases/`、`slides/` 等子目录。保留图的可编辑源文件和导出版，并注明对应 RTL 版本。开发详录与实验原始结论仍放在所属阶段，避免维护两份结果。

## 贡献与使用边界

重点展示本工程中 Core 重构、接口实现、验证及后续集成的设计决策，具体改动以源码和 Git 记录为据。NEMU、AbstractMachine、测试程序与未来接入的 ysyxSoC 有课程/上游基础；区分自主实现、参考改造和直接复用，不将上游完整系统作为个人实现成果。

本目录是对外材料的出口，不代表整个仓库均适合公开。分享前检查第三方参考 RTL、旧 tapeout flow、工艺库和报告的可公开范围，去除敏感路径与配置。不设置固定的 job-release 时刻；有新的工程证据就更新，需要投递时再按目标岗位选材。
