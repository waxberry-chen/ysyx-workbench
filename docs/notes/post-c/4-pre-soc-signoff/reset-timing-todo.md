# 早期评估的 reset 时序例外与后续 TODO

2026-10-18，用户明确决定：当前尚无 SoC 集成、实际 reset 源/释放机制及真实 IO 时序，先参考 C906 的做法，将复位相关时序排除在本轮 core 面积/功能数据时序基线之外。此决定从下一次 run 生效，不修改 01–03 的输入、报告或历史结论。

## 1. 当前实施范围

[core.sdc](../../../../npc/flow/00_indata/constraints/core.sdc) 对 DC/PT 共用以下精确例外：

```tcl
set_false_path -from [get_ports rst_n]
```

- 仅匹配顶层 `rst_n`，不匹配所有输入，也不复制 C906 的其他时钟域或测试模式例外。
- 排除 `rst_n` 发起的 recovery/removal、reset→寄存器 D、reset→输出等时序路径；这些项不再作为当前基线已验证的能力。
- 移除原 `reset_min=0.2`、`reset_max=2.0` 及对应 input delay，不继续宣称外部同步释放的数值模型已成立。
- 保留 reset 输入 slew 假设及 RTL reset 功能；没有 `set_case_analysis`，没有将复位逻辑综合成常量，也没有新增 reset synchronizer。
- 数据 I/O 的 min/max、slew/load，时钟周期/uncertainty 和其余约束保持原值。

参考依据为 [C906 SDC 的 Async Reset 段](../../../../npc/ref-flow/00_indata/SDC/C906_TOP.sdc)：在 block-level 输入端口情况下，其辅助函数展开为 reset 输入的 `-from` 例外。该参考只提供排除策略，不提供 NPC 复位脉宽正确性的证据。

## 2. 如何解释后续报告

这是**暂缓 reset 时序验收的范围决定**，不是“复位脉宽已满足”，也不是将所有 untested 自动豁免。

`set_false_path` 不会产生实际 reset 波形，因此不保证 5516 项脉宽 untested 消失；recovery/removal 的 coverage 状态和数据路径端点集合也可能变化。继续保留 `check_timing`、coverage/untested、禁用弧、constraint 和完整 max/min 报告，按下一次真实输出审查变化。

仅明确属于上述 reset 范围的检查可登记为本轮 deferred；其他缺时钟、未约束端点、异常禁用弧等仍需处理。66 条最小电容违例是独立问题，此次例外不解决它们。

新 run 应使用独立 RUN_ID，例如 `core-tt-5ns-reset-deferred`。因分析范围改变，reset 相关路径的消失或 slack 改善不能宣传为 RTL 优化；03 中 recovery/removal met 的结论仅适用于 03 的旧假设。历史 run 用其冻结版本管理，不用新 driver 改写。

## 3. 恢复 reset 时序验收的 TODO

触发条件：确定 SoC/reset controller、板级复位来源或真实 IO/时钟环境；最迟在声称 reset 时序 sign-off 前完成。

1. **定义实际机制**：复位来源、极性、有效阶段、各时钟域分发、异步 assertion/释放方式及 synchronizer；先确认事实，再写 SDC。
2. **建立脉宽契约**：读取实际库单元的清零/置位最小脉宽，明确外部和内部产生端的保证；在需要时考虑分布延迟、边沿不对称和 PVT，不由当前时钟周期任意填值。
3. **重新建立分析场景**：撤销或缩小本次 `-from rst_n` 例外，按实际释放机制设置约束，恢复适用的 recovery/removal、reset 数据路径和脉宽审查。确需保留的例外逐对象记录理由。
4. **验证复位行为**：覆盖启动、运行中复位、背压/未完成事务、最短有效脉冲和释放行为；结合实际机制决定 assertions、CDC/RDC、门级或物理分析证据。两值 RTL 仿真不独立证明亚稳态或引脚模拟脉宽安全。
5. **重跑并归档**：新建 run，审查 coverage 的新增/消失检查、时序和电气结果；记录哪些由 STA 验证、哪些由其他证据覆盖，再关闭本 TODO。

## 4. 本次验证边界

本地 SDC 对象契约要求：8 个数据输入和 24 个输出保留完整预算，只有 `rst_n` 可以 false path，不再填写 reset release delay。负向测试覆盖遗漏例外、错误排除数据/所有输入和旧复位预算回流。

本地 Tcl/mock 只验证命令连接和对象范围，不预测真实 PT coverage。服务器由用户同步后运行；本次不声称已有新的 DC/PT 结果，也不关闭实际 reset 安全性的 TODO。
