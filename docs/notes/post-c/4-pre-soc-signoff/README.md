# M4：DC/PT 面积与时序基线

2026-10-16：S0 初读和 **S1 综合范围/复位语义/RTL 回归已完成**，下一步 S2 最小 DC/PT flow。S1 输入 HEAD 为 `1ccf39d22f0107fbb5eb2a5327fe304942376d3e`；尚未运行 EDA，没有面积/时序结果。

- [DC/PT 手册检索入口](manual-index.md)：本地缓存、命令搜索、按 PDF 页阅读及版本引用规则；使用 `manuals.py` 查询。
- [S1 综合范围与验证](1-synthesis-scope.md)、[逐端口预算接口](s1-port-budget.csv)：独立 filelist、DPI/SVA 宏、GPR reset、审查与回归证据。
- [计划与分步出口](plan.md)：当前链 S0–S3 → S6；S3 取得面积/时序，可附带 DC 功耗粗估；原 S4/S5 延后。
- [ref-flow 流程图与逐级输入输出](0-flow-map.md)：执行依赖、实际数据流，以及工艺库/design/flow 分类。
- [ref-flow 学习与裁剪](0-ref-flow-review.md)：实际入口、可复用组织方式和迁移问题。
- [缺失 flow 脚本说明](missing-inputs.md)、[脚本清单 CSV](missing-files.csv)：只核查未拷贝的 flow 脚本/编排配置，不含 PDK、工具或 design 数据。
- [验收矩阵](test-plan.md)：I04/I05 的 S1 检查通过，I02/I03 完成本地部分；DC/PT 仍待验。
- [开发日志](dev-log.md)、[阶段 Q&A](qa/README.md)。

本地进行 flow 蒸馏和相关 RTL 检查，不复现旧 flow；PDK 在服务器，保留脚本原路径。`npc/flow/` 已有范围说明和综合 filelist，DC/PT 执行脚本与数值 SDC 待 S2 建立；取得结果时再增加 `3-synthesis-sta.md` 和 `signoff.md`，不预填结果模板。工艺库与运行产物保留在服务器，摘要和 manifest 回到本目录。
