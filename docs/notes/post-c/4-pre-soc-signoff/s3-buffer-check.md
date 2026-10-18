# S3 下一次 run：诊断无负载 buffer

2026-10-18。用户手动 commit、同步服务器并执行。本次脚本准备已完成，**不预先宣称 66 条最小电容违例已修复**；真实结果需新 DC/PT run 验证。

## 1. 这次改了什么

DC 仍使用普通 `compile -map_effort medium`，撤去原来的：

```tcl
set_fix_multiple_port_nets -all -buffer_constants
```

DC P-2019.03 正文 11-32–11-33 说明，默认可用网表 assign 表达 input→output 直通及多输出共网；上述修复设置可引入 buffer。03 中 66 个无负载输出 buffer 与 EXU 的直通接口重合，因此先撤去这一强制处理，检验它是否导致或保留了这些冗余单元。

普通 compile 仍可为真实时序/负载需要插 buffer。没有禁止所有 buffer、手工删除指定实例、改 RTL/顶层观察范围、添加虚构负载或降低库限制，也没有同时启用跨层重连、flatten 或 compile_ultra。网表出现直通 assign 本身不代表无驱动；需要检查实际驱动/消费者和 PT link。后续 PnR 若要求规范这类连接，再按实际后端要求处理并重测。

另外一项已授权的变更是 [reset 时序暂缓](reset-timing-todo.md)：SDC 仅对 rst_n 设置 false path，删除旧 reset_min/reset_max 及 reset input delay；保留真实 coverage。它与电容问题独立，不能把 reset 路径减少计作 buffer 优化收益。

相对 03，RTL、5 ns 周期、数据 I/O min/max、slew/load、TT 库、WLM 和功耗开关不变；多端口网络处理与 reset 评估范围有变化。自定义设计配置也需移除旧 reset_min/reset_max 字段，site.local.tcl 不受该字段变更影响。

## 2. 同步和执行

只同步提交的源码/脚本/说明，保留服务器 site.local.tcl、DB 和历史 build。原 run 继续使用冻结配置；不要将新 STA 接到 03 的旧 run 上。

在工程根目录执行：

```bash
git rev-parse HEAD
git status --short
make -C npc/flow check test
make -C npc/flow preflight SITE=00_indata/configs/site.local.tcl
make -C npc/flow all SITE=00_indata/configs/site.local.tcl RUN_ID=core-tt-5ns-no-port-buffers
make -C npc/flow inspect RUN=build/core-tt-5ns-no-port-buffers
```

`all` 会重新综合并运行同一 run 的 PT。若 RUN_ID 已存在，使用新编号；不覆盖 03。syn.log 应出现 `NPC_SYN_POLICY: no explicit multiple-port-net repair; feedthrough assigns allowed`，用于确认新策略实际执行。

## 3. 返回结果如何验收

| 证据 | 需要确认 |
| --- | --- |
| manifest、syn/sta 日志 | 执行完整、源版本和配置正确，无 link/命令错误；不能只看退出码 |
| `outputs/core.v` | 原 EXU 无负载 buffer 是否减少/消失；按连接追踪，不依赖 U4 等实例名不变 |
| `reports/syn/checks/check_design_post.rpt` | 未连接/无负载告警变化是否合理，无新增未驱动、多驱动或意外结构问题 |
| `reports/sta/checks/constraint_violations.rpt` | 66 条 min-capacitance 是否消失、有无新对象及其他电气或时序违例 |
| `reports/sta/checks/coverage*.rpt` | reset 范围内的项记录 deferred；其他 untested/漏约束不得自动豁免；不要求 5516 项必须变成零 |
| `reports/sta/timing/` | 全局和分类路径、setup/hold 裕量；reset 路径排除会改变端点集合，不能全部归因于优化 |
| `reports/syn/area/`、`reports/*/environment/` | 面积与资源变化合理，top/库/模型一致，顶层观察范围未意外裁掉 |

如果违例仍在，保留失败结果并继续定位：是同一类无负载连接仍被保留，还是其他真实驱动端也不满足下限。下一步可单独评估 `compile_advanced_fix_multiple_port_nets` 的跨层重连（需确认 boundary optimization 条件），或整理确属冗余的 RTL 接口；本次不将它们混入同一实验。

只有电气问题和本轮其余审查项关闭后，才能冻结正式 S3；本轮 reset 时序的 deferred 范围仍需在结论中明确。

## 4. 本地验证

`make -C npc/flow check test` 已通过，40 项测试验证配置、reset 例外对象范围、真实 Tcl 与 mock 的衔接、报告/违例解析及追溯。mock 不再接受原多端口网络修复命令，防止测试默默保留旧策略。这些检查不模拟 DC 优化，不证明 min-capacitance 已消除，也不预测新的面积/时序结果。
