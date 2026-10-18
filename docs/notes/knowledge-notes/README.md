# 工程知识笔记

用于回顾可跨阶段复用的概念和工程方法。具体实验的配置、指标及验收结论仍以各 milestone 的记录为准。

| 笔记 | 内容 |
| --- | --- |
| [从评估指标反推 SDC：首次综合 / STA 的约束设计](metrics-aware-sdc.md) | 首次编写前的参数表；指标与约束映射；IO min/max 推导；cap/slew/fanout、clock/reset 决策；注释模板及新模型接手指南 |
| [阅读综合网表与 STA 报告：层次、实例、引脚和网络](netlist-and-timing-report-navigation.md) | 从报告路径定位单元及连接；常见引脚命名；FF 的 `_reg` 名称；跨层追踪信号的方法 |
| [综合 / STA 可信度评估：依据、检查命令与 synth 03 实例](synthesis-sta-credibility.md) | 分析可信与约束达标的区别；DC/PT 命令及检查范围；coverage/false path；03 的最小电容、复位脉宽、高扇出与禁用弧定位 |
