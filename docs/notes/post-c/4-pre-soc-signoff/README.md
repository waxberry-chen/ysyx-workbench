# M4：DC/PT 面积与时序基线

2026-10-18：S0/S1、S2 flow 与 S2.5 ISA 收敛已完成本地验收。**[S3 core pre-layout 基线已建立](3-synthesis-sta.md)**：[04 实验](synthesis-results/04-200mhz-baseline/README.md) 在 TT / 200 MHz 下 DC/PT 无约束违例，setup/hold slack +0.596843/+0.008754 ns，面积 9242.855942 library_area。coverage 与结构告警已分类；reset 时序明确 deferred，不外推全 PVT 或物理 sign-off。下一步 S6 最终复现/交接。

后续范围更新：按用户决定，04 及后续同范围 run 暂缓 reset 时序验收，仅对 `rst_n` 设置 false path；旧 release delay 已移除。脉宽、释放及实际 reset 机制列为 [reset TODO](reset-timing-todo.md)，不再作为本轮必须完成的物理时序验收项；原始 coverage 仍需审查，历史 03 结果不改写。

- [综合结果记录](synthesis-results/README.md)：逐次保存实验；[01 首次综合](synthesis-results/01-first-synthesis/README.md) 含总结、关键原始报告与追溯信息，明确不作为正式 S3 基线。
- [DC/PT 手册检索入口](manual-index.md)：本地缓存、命令搜索、按 PDF 页阅读及版本引用规则；使用 `manuals.py` 查询。
- [S1 综合范围与验证](1-synthesis-scope.md)、[逐端口预算接口](s1-port-budget.csv)：独立 filelist、DPI/SVA 宏、GPR reset、审查与回归证据。
- [S2 最小 flow 与服务器交接](2-flow.md)：运行入口、数值 SDC、输入/产物追溯、失败处理和本地 mock 验证边界；[报告分类与阅读顺序](../../../../npc/flow/README.md#报告目录与阅读顺序)。
- [S2.5 ISA/CSR 契约与验收](2.5-isa-contract.md)：移除 M、16 项 GPR、非法指令精确异常、CSR 与跨层适配。
- [计划与分步出口](plan.md)：当前链 S0 → S1 → S2 → S2.5 → S3 → S6；S3 取得面积/时序，可附带 DC 功耗粗估；原 S4/S5 延后。
- [S3 基线候选重跑](s3-rerun.md)：诊断增强、建议提交拆分、用户手动同步/执行命令及报告审查顺序；新增诊断已在 03 实验完成服务器实测。
- [ref-flow 流程图与逐级输入输出](0-flow-map.md)：执行依赖、实际数据流，以及工艺库/design/flow 分类。
- [ref-flow 学习与裁剪](0-ref-flow-review.md)：实际入口、可复用组织方式和迁移问题。
- [缺失 flow 脚本说明](missing-inputs.md)、[脚本清单 CSV](missing-files.csv)：只核查未拷贝的 flow 脚本/编排配置，不含 PDK、工具或 design 数据。
- [验收矩阵](test-plan.md)：S1 与 S2 本地检查通过，已有 DC/PT 实测，04 已完成当前范围的覆盖率/电气约束及告警审查。
- [开发日志](dev-log.md)、[阶段 Q&A](qa/README.md)。

本地进行 flow 蒸馏和相关 RTL 检查，不复现旧 flow；PDK 在服务器，保留脚本原路径。`npc/flow/` 已有 DC/PT 入口、数值 SDC、preflight/manifest 与本地检查；真实工具兼容性和库属性在服务器核对；S3 结果见 `3-synthesis-sta.md`；`signoff.md` 留待 S6 完成后再写，不预填结论。完整工艺库/网表/DDC 等运行数据保留在服务器；选定原始报告、日志、配置/manifest 和总结归档到本目录的 `synthesis-results/`。
