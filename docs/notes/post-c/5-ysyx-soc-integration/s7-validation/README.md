# M5 S7 验证记录

> 2026-10-29：M17 / S7 在约定范围内通过，采用 [cap90 200 MHz 基线](baseline/README.md)。电气规则及数据时序通过，coverage/告警审查完成；用户接受只记录 leakage 自动零目标，原始 DC CONSTRAINT_FAIL 保留。下一步 S8。

[实施与服务器命令](../7-synthesis-sta.md)说明 scope、端口预算和源码改动。本页保存已经执行的检查，不将 mock 报告中的数字作为真实 PPA。最终阅读入口为 [基线总结、关键路径与告警审查](baseline/README.md)、[派生审查数据](baseline/review.json)和[原始文件归档清单](baseline/archive.json)。下表前几项保留本地准备及前两轮的历史结果。

| 检查 | 实际结果 | 证据 |
| --- | --- | --- |
| 配置、源闭包、SDC 对象 | 20 个 SV 源；1 clock、11 活动输入、29 输出、19 禁用输入；只有 reset false path | [local-checks.log](local-checks.log) |
| 初始 flow 编排和 Tcl mock 回归 | 48 项通过；含旧范围拒绝、错误 Flash 宏/网表 top、reset/活动输入错误 case analysis 等负例 | 同上；mock 面积和 slack 仅为检查器输入 |
| 正式 Ultra / 功耗策略本地检查（2026-10-29） | `make -C npc/flow check test` 通过，51 项；报告开关不改变优化策略，策略/Ultra 失败时停止导出 | [实现与测试位置](../7-synthesis-sta.md#74-正式接入-ultra-与功耗策略本地已实施服务器待验证)；本次终端结果，不覆盖初始日志，不代表真实 EDA 结果 |
| 最大电容裕量 / 增量 DRC 本地检查（2026-10-29） | `make -C npc/flow check test` 通过，54 项；逐引脚比例、DC/PT 隔离、报告必需、写入/回读/保留失败及增量失败负例 | [实现与运行入口](../7-synthesis-sta.md#76-尝试-10-最大电容裕量与增量-drc-修复)；本次终端结果，真实属性可写性和电气修复效果待服务器验证 |
| 电容回读舍入修正（2026-10-29） | `make -C npc/flow check test` 通过，56 项；复现 `0.0194895 → 0.019490`，验证允许半个末位舍入、拒绝更大偏差及未施加/重复施加裕量 | [问题与修正](../7-synthesis-sta.md#76-尝试-10-最大电容裕量与增量-drc-修复)；本地 Tcl mock 验证，实际 DC/PT 修复效果待重跑 |
| 综合宏配置 | `SYNTHESIS NPC_FLASH_BOOT`、额外启用 DPI 宏仍由 SYNTHESIS 覆盖，两组通过 | [scope-check.json](scope-check.json)，逐项 warning 理由和源 hash |
| 仿真宏配置 | Flash 启动，无 DPI/有 DPI 两组通过，保留断言 | 同上 |
| 真实 DC/PT | 普通 compile / Ultra 两轮均执行完成，setup/hold 无违例；电气/功耗目标问题未关闭 | 见下方服务器证据；不将 COMPLETE 视为验收 PASS |
| cap90 真实 DC/PT 回传审查 | 94 个冻结输入/产物 hash 匹配；1321 个引脚收紧且两次回读通过；DC 仅 1 条 leakage 目标违例、PT 0 条违例；面积 9530.135856，最差 setup/hold +2.444726/+0.009693 ns | [第三轮分析](../7-synthesis-sta.md#77-cap90-回传电气规则通过ultra-漏电优化无法关闭)；未修改回传 manifest 的判定 |
| cap90 coverage 最终审查 | 9120 项 untested：2986 recovery/removal、5972 reset/set 脉宽、162 常量输出检查；禁用弧为 81 个常量输出，无 loop-breaking 标记；check_timing 成功 | [最终审查](baseline/README.md#4-9120-项-untested-的逐类处置)；reset 物理时序仍按既有 TODO 暂缓，已完成告警处置/归档 |

综合两组各 41 条已审查 lint warning，仿真两组各 30 条；详细原始日志分别为
[synthesis](synthesis.lint.log)、[synthesis_overrides_dpi](synthesis_overrides_dpi.lint.log)、
[simulation_no_dpi](simulation_no_dpi.lint.log)、[simulation_dpi](simulation_dpi.lint.log)。
这些 warning 仅按具体文件/信号分类，不对宽度、latch、未知模块等类别做全局豁免。

本地完整预处理结果留在 `npc/flow/build/s7-scope-check/`，不提交生成 RTL。
服务器 run 已独立冻结实际 RTL/配置/脚本和工具/库 hash；最终采用 cap90 作为数值的输入记录。
本次没有改动 CPU/SoC 功能 RTL，也没有重跑 S6 长系统测试。

## 服务器结果与诊断入口

结果数值、引脚对应关系、DC/PT 电容差异与待办集中记录在 [S7 第 7 节](../7-synthesis-sta.md#7-服务器迭代与当前问题2026-10-29)。两轮输入、原阶段产物的 manifest hash 已核对；后补 debug 是独立重读 DDC / 网表的诊断，不在原 manifest 的阶段产物清单内。

| 证据 | 阅读内容 |
| --- | --- |
| [首轮 manifest](../../../../../npc/flow/build/soc-cpu-tt-5ns-s7/manifest.json)、[PT 违例](../../../../../npc/flow/build/soc-cpu-tt-5ns-s7/reports/sta/checks/constraint_violations.rpt) | 普通 compile；7 条实际电容为零的输出 |
| [Ultra manifest](../../../../../npc/flow/build/soc-cpu-tt-5ns-s7-ultra/manifest.json)、[冻结综合脚本](../../../../../npc/flow/build/soc-cpu-tt-5ns-s7-ultra/inputs/npc/flow/02_syn/run.tcl) | 相同 RTL/库/SDC，仅改为 `compile_ultra -no_autoungroup` |
| [Ultra DC 违例](../../../../../npc/flow/build/soc-cpu-tt-5ns-s7-ultra/reports/syn/checks/constraint_violations.rpt)、[PT 违例](../../../../../npc/flow/build/soc-cpu-tt-5ns-s7-ultra/reports/sta/checks/constraint_violations.rpt) | 1 条漏电目标违例、9 条复位网络最大电容违例 |
| [DC debug](../../../../../npc/flow/build/soc-cpu-tt-5ns-s7-ultra/reports/debug/npc-s7-dc-capacitance.rpt)、[PT debug](../../../../../npc/flow/build/soc-cpu-tt-5ns-s7-ultra/reports/debug/npc-s7-pt-capacitance.rpt) | 同一组驱动/负载、库属性、网络属性与原始报告；两份均有完成标记，无 Error |
| [cap90 manifest](../../../../../npc/flow/build/soc-cpu-tt-5ns-s7-cap90/manifest.json)、[裕量报告](../../../../../npc/flow/build/soc-cpu-tt-5ns-s7-cap90/reports/syn/environment/max_capacitance_margin.rpt) | 第三轮输入/产物追溯；1321 个引脚的原上限、收紧值及回读 |
| [cap90 DC 约束](../../../../../npc/flow/build/soc-cpu-tt-5ns-s7-cap90/reports/syn/checks/constraint_violations.rpt)、[PT 约束](../../../../../npc/flow/build/soc-cpu-tt-5ns-s7-cap90/reports/sta/checks/constraint_violations.rpt)、[syn.log](../../../../../npc/flow/build/soc-cpu-tt-5ns-s7-cap90/logs/syn.log) | DC 仅 leakage 零目标，PT 无违例；日志 PWR-884 说明 Ultra 无法关闭漏电优化 |
| [cap90 coverage](../../../../../npc/flow/build/soc-cpu-tt-5ns-s7-cap90/reports/sta/checks/coverage_untested.rpt)、[禁用弧](../../../../../npc/flow/build/soc-cpu-tt-5ns-s7-cap90/reports/sta/checks/disable_timing.rpt) | 暂缓的 reset/set 时序和常量输出；无 loop-breaking 标记 |

上表保留原 run 定位入口；cap90 的最终证据已复制到 [baseline/](baseline/README.md)，共 72 份原始报告/日志/追溯文件、归档 hash 和派生审查统计。前两轮 debug 仍位于回传 build。人工验收依据完整审查与明确例外，不改写原 manifest 的自动状态。
