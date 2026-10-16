# M4：DC/PT 面积与时序基线

2026-10-17：S0/S1 与 S2 flow 已完成，服务器首次 DC 综合已取得面积/时序报告，10 ns setup/hold 未满足。当前进入正式 S3 基线前的接口、算术实现与约束审查；PT 尚未执行，正式基线尚未建立。

- [综合结果记录](synthesis-results/README.md)：逐次保存实验；[01 首次综合](synthesis-results/01-first-synthesis/README.md) 含总结、关键原始报告与追溯信息，明确不作为正式 S3 基线。
- [DC/PT 手册检索入口](manual-index.md)：本地缓存、命令搜索、按 PDF 页阅读及版本引用规则；使用 `manuals.py` 查询。
- [S1 综合范围与验证](1-synthesis-scope.md)、[逐端口预算接口](s1-port-budget.csv)：独立 filelist、DPI/SVA 宏、GPR reset、审查与回归证据。
- [S2 最小 flow 与服务器交接](2-flow.md)：运行入口、数值 SDC、输入/产物追溯、失败处理和本地 mock 验证边界。
- [计划与分步出口](plan.md)：当前链 S0–S3 → S6；S3 取得面积/时序，可附带 DC 功耗粗估；原 S4/S5 延后。
- [ref-flow 流程图与逐级输入输出](0-flow-map.md)：执行依赖、实际数据流，以及工艺库/design/flow 分类。
- [ref-flow 学习与裁剪](0-ref-flow-review.md)：实际入口、可复用组织方式和迁移问题。
- [缺失 flow 脚本说明](missing-inputs.md)、[脚本清单 CSV](missing-files.csv)：只核查未拷贝的 flow 脚本/编排配置，不含 PDK、工具或 design 数据。
- [验收矩阵](test-plan.md)：S1 与 S2 本地检查通过，已有首次 DC 实测，PT、告警关闭与正式基线仍待验。
- [开发日志](dev-log.md)、[阶段 Q&A](qa/README.md)。

本地进行 flow 蒸馏和相关 RTL 检查，不复现旧 flow；PDK 在服务器，保留脚本原路径。`npc/flow/` 已有 DC/PT 入口、数值 SDC、preflight/manifest 与本地检查；真实工具兼容性和库属性在服务器核对；取得结果时再增加 `3-synthesis-sta.md` 和 `signoff.md`，不预填结果模板。完整工艺库/网表/DDC 等运行数据保留在服务器；选定原始报告、日志、配置/manifest 和总结归档到本目录的 `synthesis-results/`。
