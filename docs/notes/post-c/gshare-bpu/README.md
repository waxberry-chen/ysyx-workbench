# GShare BPU：条件分支预测与 JAL 提前处理

> 2026-11-01：S0–S4 已完成；三模式功能/性能及 OFF/GSHARE 同条件 DC/PT 审查通过，S5 最终冻结尚未关闭。本目录是 M5 之后、版本冻结之前的限定增量，不占用长期候选 M6 I-cache / M7 深化的编号。

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

本地功能回归与固定六程序性能实验完成，整体周期加速比 1.114～1.201×；服务器 DC/PT 已回传审查，CPU 子系统面积增加 21.076%，两模式均通过 5 ns 数据时序与电气检查，保留 leakage 零目标及 reset 物理时序例外。入口与证据见上表、[validation](validation/README.md)及 [PPA 审查](validation/ppa/README.md)。
