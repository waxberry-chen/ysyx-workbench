# GShare 增量状态与交接

> 2026-11-01；S0–S4 已完成，服务器 DC/PT 在约定范围内通过，无新增阻塞。**S5 最终冻结与交接尚待执行，本阶段尚未整体 sign-off。**

| 步骤 | 当前状态 | 阅读入口 |
| --- | --- | --- |
| S0 接口／输入基线 | 完成；六程序 OFF 与 M5 一致 | [合同与指标](0-contract-and-metrics.md) |
| S1 预测器单元 | 完成；预译码、两种表参数、PHT/GHR 独立模型 | [预测器](1-predictor.md) |
| S2 前端与恢复 | 完成；IFU scoreboard、EXU 定向及两项检查器负例 | [集成闭环](2-integration.md) |
| S3 系统功能 | 完成；新增定向及 M5 S3～S6 全部适用回归通过 | [功能验证](3-functional-validation.md) |
| S4 性能／面积时序 | 完成；18 次性能比较及同条件 OFF/GSHARE DC/PT 审查通过，保留 leakage/reset 例外 | [性能与 PPA](4-performance-ppa.md) |
| S5 最终冻结 | 功能、性能和 EDA 证据齐备；待最终冻结与交接 | [证据入口](validation/README.md) |

当前实现是 GShare + predecode，支持合法条件分支和 JAL 的提前取指；JALR 保留执行端恢复。默认候选为模式 2，可显式切回模式 0。未加入 BTB、RAS、cache、多 outstanding 或新的软件平台。

性能结论：固定六程序整体 OFF/GSHARE=1.114～1.201×；条件分支部分须看 JAL_ONLY/GSHARE=1.001～1.198×，不能混淆 JAL 提前处理与 GShare 的贡献。CPU 子系统 cell area 从 9583.727856 增至 11603.591918 library_area（+21.076%）；两组满足 5 ns，GSHARE 最差 setup/hold slack 为 +1.801808/+0.008700 ns。未测物理最高频率或功耗，不宣称面积效率提升。

本地证据：复用系统回归 146 次真实 SoC 正向运行、3,372,127 条差分提交、47 次 IRQ；新增 12 次错误路径／IRQ 对照、18 次三模式性能运行通过。原有 26 项预期失败检查及新增 2 项检查器负例通过；12 组 scope profile、57 项 flow mock 检查通过。完整统计见 [S3](3-functional-validation.md)及 [validation](validation/README.md)。

服务器审查输入固定为 `9d7c63d562c2298e7f00451eab37c946205733e8`；每组 98 个登记输入/产物 hash 匹配，源码与功能测量交接版本一致。DC 仅剩已接受的 leakage 零目标，PT 无约束违例；全部 untested 已按 reset/set deferred 和常量输出处置。原始状态及证据见 [PPA 审查](validation/ppa/README.md)。

**当前无未处置的功能或 S4 验收阻塞。**

剩余工作：

1. 按 S5 固定最终版本、核对文档/QA/图与复现入口，完成冻结交接；本轮只审查并归档回传结果，未另行执行 S5 发布复现。输入不变时无需再跑全套 DC/PT。
2. 最终冻结后转入 **[JOB-PREP-01：理解考察与简历 v1](../../output/interview-readiness.md)**。已有代码与结果不替代人类理解考察，不自动继续扩展 BTB/cache。

既有边界继续保留：instruction-address-misaligned trap 未在 M5 完整实现，本轮仅禁止对半字对齐目标提前预测；reset 物理时序、完整 SoC PnR 和功耗签核仍不在本轮范围。局部与系统验证不能据此宣称全 ISA 或物理 sign-off。
