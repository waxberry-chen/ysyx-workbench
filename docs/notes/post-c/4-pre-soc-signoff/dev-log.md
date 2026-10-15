# M4 开发日志

## 2026-10-15：计划与参考 flow 初读

- 输入 HEAD `0fe53bfcdbb1193b94415a9bb8382bcd7d71b4cf`；工作区已有用户修改 `npc/.gitignore` 和未跟踪 `npc/ref-flow/`，保持原样。
- 阅读 roadmap/output、ref-flow 指令、DC/STA/PX/GLS 主要入口及配置，确认该拷贝缺少实际工艺库和若干 launcher；完成 [参考审查](0-ref-flow-review.md)及 [文件清单](missing-files.csv)。
- 建立 [S0–S6 计划](plan.md)：以现有 core AXI 顶层作为首次面积/时序/功耗边界；S3 首次 A/时序，S5 增加 workload P。
- 发现 GPR/CSR 无条件 DPI、regfile initial/x0 语义需先处理；本轮仅记录，不修改源码。非 TOPO flow 不将 SRAM/LEF/SPEF 作为首次 core 评估依赖。
- 本地 PATH 工具检查：`tclsh` 可找到，DC/PT/VCS/Xrun/Icarus/FM 未找到；没有连接服务器或执行 EDA，没有新仿真/PPA 结果。
- 初版曾将服务器库/工具的本地缺失列为阻塞；该口径已按下面的用户澄清修正，不再作为 S0 蒸馏阻塞。
- 验证限于文档链接、CSV 字段/文件存在性和 diff 检查；没有因文档变更重跑 M3。

## 2026-10-15：收窄缺失清单，补齐 S0 流程契约

- 用户明确本地只做 flow 蒸馏，不复现运行；PDK 在服务器，保留原路径。missing-files 仅用于核查 flow 相关脚本。
- 删除清单中的工艺库、工具、C906 design 数据、待建 NPC 文件与运行产物；按已读主链补齐 QRC/dataset 脚本引用，现为 14 项脚本/编排配置。
- 新增 [0-flow-map.md](0-flow-map.md)：根 Makefile 执行图、实际数据流图、逐级输入输出分类、DC/PnR 子步骤及 NPC 蒸馏路径。明确 GLS 用综合网表、PX 根入口缺失，以及 FM/QRC/dataset 的推断边界。
- 更新 plan/README/roadmap：S0 出口是本地学习与蒸馏文档，服务器 preflight 后移至实际运行准备；当前无必须等待补拷的本地蒸馏阻塞。
- 未改 RTL/ref-flow/库路径，未执行 EDA；只验证文档链接、脚本缺失事实与清单范围。

## 2026-10-15：核对新补拷脚本

- 原清单 7 项已补齐：R01/R03/R04/R05/R06/R09/R12；保留编号并标记 `copied`，原有 7 项仍为 `not_copied`。
- 从新脚本调用中新增 R17 `11_sim/syn/regress/report_gen.pl`，以及 R18 `11_sim/pnr/run_simv.sh`（仅 `--level pnr` 分支）；清单共 16 项，剩余 9 项待补。
- PDK 及其路径配置、design RTL/TB、运行产物未加入清单。只做静态阅读与存在性检查，没有执行新脚本。
- `0-flow-map.md` 的缺失描述保留为初读快照，最新补拷状态以 CSV 为准；后续深入蒸馏时再更新具体阶段契约。

## 2026-10-15：收敛为 DC/PT 基线，功耗仅附带粗估

- 用户决定本工程当前只完成 DC/PT 面积与时序基线；采纳 DC `report_power` 简要估算作为附带参考，不建立独立活动/GLS/PTPX 功耗链。
- 保留阶段编号，当前链为 S0–S3 → S6；原 S4 四值/网表与 S5 workload/PTPX 延后，不作为本轮验收条件。S1 的 DPI/上电语义修复、相关 RTL 回归及综合/SDC 检查继续必做。
- 更新 plan、test-plan、roadmap、目录入口、NPC 流程图及 Q&A；完整 ref-flow 图仍作为学习资料保留。
- DC 功耗记录活动/频率/load/PVT/互连假设及 warning；工具或模型不支持时标记未评估，不阻塞面积时序。未执行 EDA，未修改源码或参考 flow。

## 2026-10-15：建立 DC/PT 本地手册检索缓存

- 从 `docs/userguide/` 的 DC P-2019.03（792 页）和 PT L-2016.06（1066 页）运行 `pdftotext -layout -enc UTF-8`，缓存写入 `.cache/`，分别保留 792/1066 个 `\f`。PDF 与全文缓存沿用现有 Git 忽略规则。
- 新增 [manual-index.md](manual-index.md) 和 [manuals.py](manuals.py)：支持 build/check、带 PDF 页码的字面搜索、按页阅读；本地 manifest 保存 PDF/文本 hash、版本与分页信息。
- 为 M4 的库配置、SV/link、SDC、wire load、综合/面积、STA coverage 和附带功耗建立实际页码入口；强调 DC 功耗命中的 TOPO 上下文不应套用到普通综合。
- README/plan/参考审查/roadmap 接入检索入口。后续先读本地小节，记录版本与页码，再按服务器工具帮助核对选项；未执行任何 EDA 流程。
- 检查：两本缓存 hash/分页数通过，命令搜索与按页读取通过；文档链接、索引页码及缓存忽略状态已核对。
