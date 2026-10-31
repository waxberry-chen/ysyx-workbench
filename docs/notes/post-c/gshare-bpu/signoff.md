# GShare 增量状态与交接

> 2026-10-31；本阶段**尚未整体 sign-off**。S0–S3、本地归档与三模式性能实验已完成；新增硬件的服务器 DC/PT 对照待验。

| 步骤 | 当前状态 | 阅读入口 |
| --- | --- | --- |
| S0 接口／输入基线 | 完成；六程序 OFF 与 M5 一致 | [合同与指标](0-contract-and-metrics.md) |
| S1 预测器单元 | 完成；预译码、两种表参数、PHT/GHR 独立模型 | [预测器](1-predictor.md) |
| S2 前端与恢复 | 完成；IFU scoreboard、EXU 定向及两项检查器负例 | [集成闭环](2-integration.md) |
| S3 系统功能 | 完成；新增定向及 M5 S3～S6 全部适用回归通过 | [功能验证](3-functional-validation.md) |
| S4 性能／面积时序 | 18 次固定输入性能比较完成；DC/PT 待验 | [性能与 PPA](4-performance-ppa.md) |
| S5 最终冻结 | 本地文档／证据已归档；最终冻结等 S4 DC/PT 审查 | [证据入口](validation/README.md) |

当前实现是 GShare + predecode，支持合法条件分支和 JAL 的提前取指；JALR 保留执行端恢复。默认候选为模式 2，可显式切回模式 0。未加入 BTB、RAS、cache、多 outstanding 或新的软件平台。

性能结论：固定六程序整体 OFF/GSHARE=1.114～1.201×；条件分支部分须看 JAL_ONLY/GSHARE=1.001～1.198×，不能混淆 JAL 提前处理与 GShare 的贡献。尚无新增面积、最高频率或功耗结论。

本地证据：复用系统回归 146 次真实 SoC 正向运行、3,372,127 条差分提交、47 次 IRQ；新增 12 次错误路径／IRQ 对照、18 次三模式性能运行通过。原有 26 项预期失败检查及新增 2 项检查器负例通过；12 组 scope profile、57 项 flow mock 检查通过。完整统计见 [S3](3-functional-validation.md)及 [validation](validation/README.md)。

**当前无本地功能阻塞；唯一验收待办是服务器 DC/PT 新结果。**

剩余工作：

1. 用户同步并运行 [S4 的两条 DC/PT 命令](4-performance-ppa.md#3-服务器面积时序对照)，回传 OFF 与 GSHARE run；助手审查面积、时序、DRC、coverage 和告警后决定验收。
2. 最终冻结后转入 **[JOB-PREP-01：理解考察与简历 v1](../../output/interview-readiness.md)**。已有代码与结果不替代人类理解考察，不自动继续扩展 BTB/cache。

既有边界继续保留：instruction-address-misaligned trap 未在 M5 完整实现，本轮仅禁止对半字对齐目标提前预测；reset 物理时序、完整 SoC PnR 和功耗签核仍不在本轮范围。局部与系统验证不能据此宣称全 ISA 或物理 sign-off。
