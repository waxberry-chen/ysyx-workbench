# M5 S7 验证记录

> 2026-10-29：仅完成本地准备检查；DC/PT 未运行，M17 待验。

[实施与服务器命令](../7-synthesis-sta.md)说明 scope、端口预算和源码改动。本页保存已经执行的检查，不将 mock 报告中的数字作为真实 PPA。

| 检查 | 实际结果 | 证据 |
| --- | --- | --- |
| 配置、源闭包、SDC 对象 | 20 个 SV 源；1 clock、11 活动输入、29 输出、19 禁用输入；只有 reset false path | [local-checks.log](local-checks.log) |
| flow 编排和 Tcl mock 回归 | 48 项通过；含旧范围拒绝、错误 Flash 宏/网表 top、reset/活动输入错误 case analysis 等负例 | 同上；mock 面积和 slack 仅为检查器输入 |
| 综合宏配置 | `SYNTHESIS NPC_FLASH_BOOT`、额外启用 DPI 宏仍由 SYNTHESIS 覆盖，两组通过 | [scope-check.json](scope-check.json)，逐项 warning 理由和源 hash |
| 仿真宏配置 | Flash 启动，无 DPI/有 DPI 两组通过，保留断言 | 同上 |
| 真实 DC/PT | 待服务器运行回传 | 预期 run：`soc-cpu-tt-5ns-s7`，尚无实际结果 |

综合两组各 41 条已审查 lint warning，仿真两组各 30 条；详细原始日志分别为
[synthesis](synthesis.lint.log)、[synthesis_overrides_dpi](synthesis_overrides_dpi.lint.log)、
[simulation_no_dpi](simulation_no_dpi.lint.log)、[simulation_dpi](simulation_dpi.lint.log)。
这些 warning 仅按具体文件/信号分类，不对宽度、latch、未知模块等类别做全局豁免。

本地完整预处理结果留在 `npc/flow/build/s7-scope-check/`，不提交生成 RTL。
服务器 run 将独立冻结实际 RTL/配置/脚本和工具/库 hash；以它作为最终数值的输入记录。
本次没有改动 CPU/SoC 功能 RTL，也没有重跑 S6 长系统测试。
