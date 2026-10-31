# GShare BPU：条件分支预测与 JAL 提前处理

> 2026-10-31：RTL 已实现，S0–S3 与三模式性能实验通过，S4 的服务器 DC/PT 待验，S5 尚未关闭。本目录是 M5 之后、版本冻结之前的限定增量，不占用长期候选 M6 I-cache / M7 深化的编号。

本轮采用 **GShare predictor + predecode（mini decoder）**：在取指响应返回时识别条件分支和 JAL，选择下一取指地址；执行端核对预测并训练预测器。保留当前 Fetch 单 outstanding、IFQ 两项、opbuf 单项及顺序执行／提交结构，不引入 BTB。

主要术语：

| 名称 | 本阶段含义 |
| --- | --- |
| BPU | Branch Prediction Unit，分支预测单元；本轮包含方向预测及配套目标选择 |
| predecode / mini decoder | 前端预译码，只提取条件分支／JAL 类型与目标偏移，不替代执行端完整译码 |
| taken / not-taken | 条件分支跳转／顺序执行 |
| GHR | Global History Register，保存最近若干条已提交条件分支的实际方向 |
| PHT | Pattern History Table，保存 2-bit 饱和计数器；用 PC 与 GHR 的异或结果索引 |
| BTB | Branch Target Buffer，缓存分支 PC 对应的目标等信息，本轮不实现 |
| outstanding | 已发出但尚未完成的事务；当前 Fetch 最多一笔，外部 AXI 读写也合计最多一笔 |
| metadata | 随指令保存的预测信息，如预测方向、下一 PC、查询索引 |
| misprediction / redirect | 预测与实际不符／重定向前端并清理错误路径；异常等也可产生 redirect |

阅读入口：

- [设计与实施计划](plan.md)：范围、架构、预测／训练／恢复规则、改动位置、分步出口。
- [验收矩阵与比较口径](test-plan.md)：功能检查、性能统计、DC/PT 条件与证据要求。
- [开发日志](dev-log.md)：决策和实际推进记录。
- [阶段 Q&A](qa/README.md)：设计取舍与实测结果的解释。
- [实施状态与交接](signoff.md)：S0–S5 的实际进度及剩余工作。
- [S0 合同](0-contract-and-metrics.md) → [S1 单元](1-predictor.md) → [S2 集成](2-integration.md) → [S3 功能](3-functional-validation.md) → [S4 性能／PPA](4-performance-ppa.md)。

输入为 [M5 sign-off](../5-ysyx-soc-integration/signoff.md)、[M5 比较合同](../5-ysyx-soc-integration/comparison-contract.md)及 [S7 cap90 基线](../5-ysyx-soc-integration/s7-validation/baseline/README.md)。本阶段完成后进入 [JOB-PREP-01：理解考察与简历 v1](../../output/interview-readiness.md)，不自动扩展 cache、BTB 或流水线。

本地功能回归与精选证据归档已完成。固定六程序性能实验已完成，整体加速比 1.114～1.201×；服务器 DC/PT 由用户手动运行并回传，新硬件的面积／时序待验。入口与证据见上表及 [validation](validation/README.md)。
