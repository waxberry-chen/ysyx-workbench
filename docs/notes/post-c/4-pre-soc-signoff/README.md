# M4：DC/PT 面积与时序基线

2026-10-15：已建立计划，并完成本地 ref-flow 初读；尚未实施 NPC flow、修改 RTL 或运行 EDA。输入基线为 `0fe53bfcdbb1193b94415a9bb8382bcd7d71b4cf`，功能证据继承 [M3 signoff](../3-axi4-lite-interconnect/signoff.md)。

- [DC/PT 手册检索入口](manual-index.md)：本地缓存、命令搜索、按 PDF 页阅读及版本引用规则；使用 `manuals.py` 查询。
- [计划与分步出口](plan.md)：当前链 S0–S3 → S6；S3 取得面积/时序，可附带 DC 功耗粗估；原 S4/S5 延后。
- [ref-flow 流程图与逐级输入输出](0-flow-map.md)：执行依赖、实际数据流，以及工艺库/design/flow 分类。
- [ref-flow 学习与裁剪](0-ref-flow-review.md)：实际入口、可复用组织方式和迁移问题。
- [缺失 flow 脚本说明](missing-inputs.md)、[脚本清单 CSV](missing-files.csv)：只核查未拷贝的 flow 脚本/编排配置，不含 PDK、工具或 design 数据。
- [验收矩阵](test-plan.md)：当前均未执行，禁止用脚本存在代替验证通过。
- [开发日志](dev-log.md)、[阶段 Q&A](qa/README.md)。

本地只做 flow 蒸馏，不复现旧 flow；PDK 在服务器，保留脚本原路径。当前维护规划文档和本地手册查询工具，尚未创建 NPC EDA flow。实际脚本后续集中放在 `npc/flow/`，规划见 plan；取得结果时再增加 `3-synthesis-sta.md` 和 `signoff.md`，不预填结果模板。工艺库与运行产物保留在服务器，摘要和 manifest 回到本目录。
