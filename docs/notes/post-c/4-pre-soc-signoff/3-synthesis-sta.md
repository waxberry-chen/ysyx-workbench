# S3：core pre-layout 综合 / STA 基线

2026-10-18。[04 基线审查与原始证据](synthesis-results/04-200mhz-baseline/README.md)支持建立本轮正式面积/数据时序基线；[S6](6-reproduction.md) 已于 2026-10-19 完成本地最终回归与服务器独立复现，详见 [M4 总验收](signoff.md)。

| 项目 | 结果 |
| --- | --- |
| 设计 | RV32E 无 M/C；Core + adapters + Arbiter；保留观察端口 |
| 条件 | TT / 0.9 V / 25°C，200 MHz，ideal clock，ZeroWireload |
| cell area | 9242.855942 library_area |
| PT 最差 setup / hold slack | +0.596843 / +0.008754 ns |
| 内部 Reg2Reg max slack | +1.678541 ns |
| DC/PT 约束违例 | 0 / 0 |
| coverage | 10730 met，0 violated；9426 reset deferred + 24 常量条件禁用 |

fanout 32 将 LSU 使能负载分为 25/25/18，消除此前的 max-capacitance。时钟仍直接驱动 1509 个 CP pin，没有按普通 fanout 目标生成时钟缓冲树。先前的 66 条 min-capacitance 也未再出现。

全局关键路径仍包含观察输出预算；内部功能路径单独记录用于优化。基线接受的是当前模型和范围，不是 reset、全 PVT 或 post-route sign-off；未评估功耗、四值、GLS/FM。工具 REVIEW_REQUIRED 原样保留，人工审查结论与原始工具状态分开。

冻结源 `9e449fac5b8abe863c6bd5c90f79a1c4230607a1`，dirty 仅 Makefile 的 SITE 默认值；37 项输入与 48 项 DC/PT 产物 hash 核对通过。17 份 RTL 与既有验证版本和 03 一致。配置、coverage、warning 分类、关键路径及 51 份原始归档均见 [04](synthesis-results/04-200mhz-baseline/README.md)。
