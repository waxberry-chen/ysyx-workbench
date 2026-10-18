# S3 基线候选：脚本交接与服务器重跑

2026-10-18。服务器同步和 DC/PT 执行由用户手动完成。本地诊断增强已完成，`make -C npc/flow check test` 的 39 项测试通过；它验证编排、解析和真实 Tcl 的 mock 衔接，不替代服务器 EDA 命令兼容性验证。新 run 先称“基线候选”，检查项关闭后才冻结为正式 S3 基线。

## 1. 本次新增诊断

| 文件（相对 run） | 用途 |
| --- | --- |
| `reports/syn/checks/high_fanout.rpt` | DC 实际 `high_fanout_net_threshold`、网络数量/名称、逐网连接明细 |
| `reports/sta/checks/disable_timing.rpt` | 定位 PTE-003 的禁用弧及原因 |
| `reports/{syn,sta}/checks/constraint_violations.rpt` | 完整约束违例，6 位小数；含最小电容，不能改称纯 timing 违例 |
| `reports/sta/timing/timing_{max,min}.rpt` 及四类路径 | 显式纳入正 slack，6 位小数；不再因全部满足而默认输出空报告 |
| `manifest.json` 中各阶段 `result` | 新增 `reported_constraint_violation_rows`；有打印违例行则记 `CONSTRAINT_FAIL`，时序失败仍优先记 `TIMING_FAIL` |

高扇出使用 `all_high_fanout -nets`，由工具变量决定阈值，查询整个层次；随后 `report_net -connections -verbose` 保存对象细节。不指定 `-through_buf_inv`，不改阈值、不将 clock/reset 设为 ideal 来消除告警。依据：[Synopsys Synthesis Commands，all_high_fanout](https://users.ece.utexas.edu/~mcdermot/vlsi1/VLSI2_SP_2017/synopsys/doc/Design_Compiler/syn_commands.pdf)。User Guide 未提供完整命令选项，新增命令仍需在服务器 DC V-2023.12-SP5 上验证。

报告是综合后状态；TIM-134 若来自优化中间状态，不能保证最终仍有同一对象。若它是时钟，结合 ideal-clock 假设和后续 CTS 处理；若是 reset/enable/普通数据，继续分析真实负载与分发结构。数量大不自动表示时序违例。

PT 代表路径用 `-slack_lesser_than 1.0e30`，WNS/TNS 查询继续用 `< 0`；依据为 PT L-2016.06 User Guide 正文 17-5 / PDF 637。该改动只修正报告筛选，不修改时序约束。PT `report_disable_timing` 也由 02 实验的 PTE-003 消息明确建议。

## 2. 建议提交拆分

以下为提交组织；第 1 项已提交为 `9ef59f2`，第 2 项已提交为 `e0d6ad2`，第 3 项待提交。本次 200 MHz 配置调整是这两项脚本提交之后的独立改动。

1. `refactor(flow): categorize reports and preserve run provenance`：报告分类、必需文件和递归 hash、旧 runner 保护、对应测试及目录说明。
2. `fix(flow): expose fanout and complete STA diagnostics`：高扇出/禁用弧、正 slack 路径与精度、电气违例评价、对应测试和本交接说明。
3. `docs(m4): archive RV32E synthesis and STA evaluation`：02 实验原始归档、分析、状态/计划与面试 QA。

前两项有共同修改的脚本/测试文件，拆分时按改动内容组织，并分别验证中间提交；不要简单按文件整批分配。`C906_TOP.sdc` 是用户拷入的参考输入，当前 flow 不 source 它，本次 flow 修复不要求将它纳入提交。site.local.tcl、DB、build 产物不纳入脚本提交；文档中的选定报告归档例外由原有归档规则管理。

## 3. 同步与执行

本轮候选目标改为 **200 MHz / 5 ns**，保持其余约束和实现策略不变。依据 02 实验 DC 最差 Reg2Out 路径：`opbuf → ALU/redirect → commit_redirect_reason[0]`，到达约 2.27 ns，输出预算 2.0 ns，setup uncertainty 0.2 ns。

```text
该路径在原网表下的周期需求 ≈ 2.27 + 2.00 + 0.20 = 4.47 ns
200 MHz / 5.000 ns：预计该路径 slack ≈ +0.53 ns
300 MHz / 3.333 ns：预计该路径 slack ≈ −1.14 ns
```

约 224 MHz 只是该路径在现有预算下的零裕量推算，不是实测 core Fmax。新周期会改变 DC 优化结果，PT 还需补齐正裕量与四类路径；当前仍为 TT、ideal clock、ZeroWireload，不能外推 post-route。300 MHz 可留作后续激进目标，本轮先用 200 MHz 建立可审查候选。I/O/reset min/max 仍为 0.2/2.0 ns，不通过缩小外部预算来获得通过结果；hold、DRV、coverage 和禁用弧问题仍需独立关闭。

本地提交完成后同步到服务器同一版本。保留服务器 `00_indata/configs/site.local.tcl`、DB 及旧 run；确认 DC/PT 路径和库路径仍正确，不覆盖私有环境配置。运行前检查 `git rev-parse HEAD` 和 `git status --short`，必要的本地修改应能解释；已有 runner 会保存 dirty patch/status。

在工程根目录执行：

```bash
make -C npc/flow check test
make -C npc/flow preflight SITE=00_indata/configs/site.local.tcl
make -C npc/flow all SITE=00_indata/configs/site.local.tcl RUN_ID=core-tt-200mhz-s3-candidate-01
make -C npc/flow inspect RUN=build/core-tt-200mhz-s3-candidate-01
```

`all` 顺序执行新的 synth + STA。若 RUN_ID 已使用，另取新 ID；不覆盖 01/02 实验。若改变脚本后继续检查旧 run，必须使用旧 run 自带 runner；新 run 的 `inspect` 只有在当前 runner 未变化时才可直接使用上述入口。

本轮设计约束的数值变化只有 period 从 10 ns 改为 5 ns；不改 RTL、I/O/reset 预算、WLM、功耗开关或综合策略。工具错误或新增命令不兼容时保留日志并报告，不删除诊断命令后将缺失检查算作通过。

## 4. 返回结果的阅读顺序与出口

1. `manifest.json`、`logs/syn.log`、`logs/sta.log`：确认工具执行和输入一致性；`COMPLETE` 不代表验收通过。
2. `reports/syn/checks/high_fanout.rpt`：确认 TIM-134 对象、驱动和连接，必要时对照综合日志。
3. `reports/sta/checks/`：先看电气违例精确数值，再看 coverage/untested、禁用弧、check_timing。复核 02 的 66 个 min-capacitance 对象和 5516 项复位/置位脉宽检查，不假定它们因报告改动消失。
4. `reports/sta/timing/`：检查全局、Reg2Reg/In2Reg/Reg2Out/In2Out 的 setup/hold 路径及实际裕量；某类无可分析路径时需解释，不强求每类都有路径。
5. `reports/syn/area/`、`summary/`、两阶段 `environment/`：核对面积、资源、库、单位和 ZeroWireload 模型；确认变化原因。

原始结果需按实验顺序归档，建立有对象、理由和证据的告警/例外处置记录。所有功能端点、DRV、未测试项和禁用弧审查完成后，再生成正式 S3 总结与基线结论；若有未解决问题，继续保留为诊断实验。功耗仍是可选粗估，未开启不阻塞面积/时序基线。
