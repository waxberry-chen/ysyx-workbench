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

## 2026-10-16：S1 综合范围与复位语义完成

- 输入 HEAD `1ccf39d22f0107fbb5eb2a5327fe304942376d3e`，开始时工作区干净。创建 `npc/flow/README.md`、16 项 `filelists/core.f`，保留观察输出、32 项 GPR 与现有组合 M 运算。
- `NPC_SIM_DPI` 控制 GPR/CSR 指针导出；正常 harness 显式启用，`SYNTHESIS` 优先关闭 DPI/SVA。GPR 增加硬件异步复位、x0 双读口固定零；CSR alias 用于实际读口消除冗余告警。
- 新增源闭包/宏矩阵/lint 检查与 GPR/CSR 状态定向。首次构建因 ccache 临时目录受沙箱限制失败，获准后正常完成；测试开发时修正了连续 trap 后 MIE/MPIE 状态的预期/前置设置，最终两种配置均通过。
- B1 signoff（53 系统 + 23 closure、必测覆盖）、M2 定向与 legacy add trace 均通过；trace hash 与原基线相同。保存本地 `artifacts/m4-s1-20261016/` 证据。
- 新增 [S1 设计与验收记录](1-synthesis-scope.md)、34 端口 [预算接口 CSV](s1-port-budget.csv)，同步入口/计划/验收矩阵/roadmap/Q&A。未修改 ref-flow 或 PDK 路径，未执行 DC/PT，不声称四值或综合网表验证通过。
- 当前无 S1 未解决阻塞；下一步 S2 构建 DC/PT 脚本、数值约束和 preflight/manifest。S3 才取得首次面积与时序结果。

## 2026-10-16：S2 最小 NPC flow 本地实现与验证

- 输入 HEAD `235f60619d2ae32a57ee2520cfd76f1a6a9f326f`，开始时工作区干净；只新增 flow/测试与更新文档/忽略规则，未改 RTL、ref-flow 或 PDK 路径。
- 建立 config/site、DC probe/synth、PT STA、共享约束、Python launcher/preflight/manifest/报告检查。冻结 10 ns 试探目标及数值接口假设，候选库为单 RVT/TT；正式运行前必须确认库内部名称、条件和单位。
- 独立 run、源码与脚本快照、库/工具/产物 hash；拒绝复用旧网表、覆盖已尝试阶段及忽略工具错误。输出 COMPLETE 与 TIMING_FAIL/REVIEW_REQUIRED 分开，零 WNS 不自动视为 signoff PASS。
- 本地 `make -C npc/flow check test`：28 项通过，包括失败注入、SDC 完整性和真实 Tcl 的 mock 命令执行；含 endpoint 去重和可选功耗失败不阻塞主流程。
- 设计/手册依据和服务器步骤见 [2-flow.md](2-flow.md)。证据归档 `artifacts/m4-s2-20261016/`。没有 EDA 或新 RTL 仿真结果；本地 S2 无阻塞，下一步服务器 S3。

## 2026-10-16：补充 S2 新手向脚本注释

- 为 Makefile、配置、Python driver、共享 Tcl、probe/DC/PT/SDC 和测试入口补充中文注释；从输入输出、命令作用和设计理由解释各步骤，新增 [阅读顺序](../../../../npc/flow/README.md#新手阅读顺序)。
- 对照本地 DC/PT User Guide 与 ref-flow 的阶段注释，解释库角色、展开/link/映射、ideal clock/WLM、I/O min/max（含 output min 的符号）、reset recovery/removal、WNS/TNS 与 coverage。注释附相关手册版本及 PDF 页码，不将参考工程的 margin/derate 搬到 NPC。
- 与修改前快照比较，13 个脚本的 Python 可执行 token 或 Tcl/Make 非注释行完全一致；`make -C npc/flow check test` 的 28 项检查通过。只增加注释和导航，没有改变参数/执行行为或新增 EDA 结果；原 S2 归档保留为当时快照。

## 2026-10-16：修正 EDA 工具符号链接入口

- 用户报告服务器 probe 退出 1，日志为 `The  script is not supported.`。发现 preflight 用 `Path.resolve()` 改写可执行路径，会丢失依赖调用名分派的 launcher 入口；是否为服务器此次故障的确切原因，仍需核对失败 manifest 的 `stages.probe.argv[0]` 与服务器工具链接。
- 增加共享 launcher 的受控模拟回归，要求以 `dc_shell`/`pt_shell` 名称调用；旧实现 probe 失败。改为仅用 `os.path.abspath()` 绝对化路径，保留符号链接入口，同时继续对目标文件内容求 hash。
- 修复后 `make -C npc/flow check test` 共 29 项通过，覆盖 probe/synth/STA 的工具分派。没有执行真实 EDA；服务器同步修复后须用新 run ID 重试，旧失败快照保持原样。

## 2026-10-16：根据服务器 probe 报告修正版本与库报告命令

- 读取用户带回的 `npc/build/flow/lib-probe/`：DC 启动 banner 为 V-2023.12-SP5，工艺库成功载入；`version.rpt` 含 CMD-005（未知 `version`），`library_standard.sldb.rpt` 含 UIL-29（synthetic library 应使用 `report_synlib`）。该 run 虽退出 0 且写完成标记，仍不是成功 probe；报告中的 Error 必须判失败。
- 共享初始化改为 `puts [get_app_var sh_product_version]`；DC 枚举到的 `.sldb` 用 `report_synlib`，工艺库/gtech 继续用 `report_lib`，PT 不走 synthetic 分支。`report_synlib standard.sldb` 依据 DC P-2019.03 PDF 429；新命令仍待服务器实际重跑验证。
- 本次工艺报告确认内部名 `tcbn28hpcplusbwp12t40p140tt0p9v25c_ccs`，条件名 `tt0p9v25c`，P/V/T 为 1.00/0.90 V/25 °C，单位 ns/pF，并包含 `ZeroWireload` 模型。模型存在不等于后续 design 已选中它；未据此自动修改 site 审核标记或宣称完成时序评估。
- 原 mock 虚构了 `version` 命令，且没有枚举 `standard.sldb`，因此未覆盖这两个真实兼容问题。收紧 mock 后旧脚本失败；修复后 probe/synth/STA 控制流通过，并增加“退出 0、完成标记存在、错误只在报告中”的拒绝回归。
- `make -C npc/flow check test` 共 30 项通过。未修改旧 run 快照/报告，未执行新的真实 DC/PT；服务器同步后使用新 run ID 验证。

## 2026-10-17：编号 flow 目录、集中输入与 run 清理

- 按用户要求改为 `00_indata/{configs,constraints,filelists,DB}`、`01_common`、`02_syn`、`03_sta`、`04_tests`；RTL 仍在 `npc/vsrc` 唯一维护，由 filelist 引用并冻结到 run。更新 Tcl/Python/Makefile 与 S1 检查的路径。
- 默认 run 根目录改为 `npc/flow/build`；S1 scope 检查产物放到其下 `scope-check`。DB 示例默认相对 site 配置定位 `00_indata/DB/STD_NEW`，仍允许外部绝对路径；私有 site 与 DB/构建产物均忽略提交。旧 run 原位保留，不改绝对路径 manifest。
- 新增 `make -C npc/flow clean RUN_ID=...`，只删指定 run，可清理失败产物后复用 ID，不依赖 SITE/EDA 可用性；拒绝空 ID、路径穿越、run 符号链接、无效 manifest 和 RUNNING 阶段。自定义/旧 RUN_ROOT 必须显式指定，清理会删除该 run 的诊断证据。
- 快照改为枚举维护的脚本/输入目录，排除 build 与工艺数据，避免迁入 flow 后递归归档旧 run。新增失败 run 清理/重跑、删除边界和快照排除回归。
- `make -C npc/flow check test`：33 项通过；`make -C npc synthesis-scope-check`：四种宏配置全部通过。未运行真实 DC/PT，服务器需迁移私有 site 和 DB 路径后继续；没有本地实施阻塞。

## 2026-10-17：归档首次综合，增加正式基线准备审查

- 用户要求将 `core-tt-10ns-split` 作为“首次综合”而非正式 S3 基线。新增 `synthesis-results/` 索引与 `01-first-synthesis/`，保存总结、23 份原始报告/日志/追溯文件和逐文件 SHA-256；归档前核对原 run 全部输入和 synthesis 产物 hash。
- 记录 cell area 35080.415848（library_area）、setup −7.29 ns、hold 约 −0.03 ns、组合 div/rem 面积占比 40.4%、观察路径及内部端点违例；PT/功耗仍未评估。保留 dirty patch，明确 HEAD 加未提交修改才是本次输入。
- 更新 plan/test-plan/README/roadmap：先审查观察接口、算术实现和约束，整理源版本与回归，再建立正式 DC/PT 基线。28 nm/数百 MHz 不作为无依据的通过保证，不通过删除慢路径或松约束掩盖失败；增加相关面试 Q&A。
- 本轮仅文档与结果归档，未修改 RTL/flow 或原 run，未执行新的 EDA/功能测试；核查归档内容、hash、链接与 diff。

## 2026-10-17：首次综合编号与 DC 兼容处理补记

- 跟随用户将结果目录改名为 `01-first-synthesis`，同步结果标题、索引和 M4/roadmap/Q&A 的全部引用；原始报告、配置、manifest 和 archive hash 保持不变。
- 用户确认本次 DC 在保留 `default_nettype none` / `default_nettype wire` 指令时会报错，移除后才综合成功。首次综合总结明确该处理属于实际输入的一部分，并区分用户确认的运行事实、已有 dirty patch 和尚未归档的失败日志/错误码。
- 正式基线准备增加对应失败证据、长期兼容方案及隐式网络/lint 与功能回归要求；不将本次现象推广为所有 DC 版本的限制。本轮仅更新文档。

## 2026-10-18：S2.5 ISA/异常收敛与跨层验证

- 移除八条 M 的 ALU 实现，精确检查合法 opcode/funct3/funct7；高 GPR、非法访存/SYSTEM、未实现 CSR 地址触发 cause 2，不发 LSU 请求/普通写回。GPR 缩为 16 项，保留显式 reset/x0，harness 按 16 项读取、32 槽参考 ABI 高半部补零。
- 补齐六种 Zicsr，四 CSR 明确 M-only/WARL/Direct/IALIGN=32 契约；NEMU 同步合法操作而保留 M。修复 DiffTest 在 reset 前复制全零状态的问题，改为复制 post-reset 状态；CSR DPI 指针保持连接寄存器存储。
- 新增 360,192 项独立译码检查、双平台各 97 个非法 trap 和合法 CSR 程序；状态两宏、EXU、四宏 scope 检查通过。B1 signoff 的 53 系统/23 closure/C01–C13 全通过；legacy M2 定向、34 CPU tests、trace 和 10 seeds 通过。
- mstatus reset=0x1800 导致旧 trace hash 变化；逐条逆向还原 CSR 尾部后精确重现旧 hash，再更新当前 Makefile。历史验收和首次综合不改写。详细契约、测试命令、证据入口与限制见 [S2.5 报告](2.5-isa-contract.md)。
- 无新增实施阻塞，未运行新 DC/PT。完整特权架构、硬件 EBREAK 和控制流目标未对齐异常仍是明确限制；下一步先完成正式 S3 的接口/约束准备审查。

## 2026-10-18：flow 报告按用途分类

- 用户指出报告混放不易查找；新 run 按 environment、summary、checks、timing、area、power 分类，probe 只输出 environment。将 `constraints.rpt` 明确命名为 `checks/constraint_violations.rpt`，区别于输入约束和导出 SDC。
- 同步 DC/PT/probe、必需报告检查、指标读取及测试；manifest 递归记录嵌套报告，继续校验失败阶段和可选功耗诊断。`inspect` 与 STA 一样要求 runner 匹配冻结版本，避免新解析器误读旧布局；旧 run 与首次综合归档不修改，使用其归档 runner。
- `make -C npc/flow check test`：36 项通过，含真实 Tcl + mock 命令衔接、嵌套文件 hash/篡改检测、嵌套报告缺失/错误、旧 runner 保护。仅调整输出组织，不新增时序检查或修改 SDC/RTL；未运行真实 DC/PT，无新增阻塞。

## 2026-10-18：补齐 S3 候选重跑诊断

- 原 run 的 TIM-134 没有网络名称；新增 DC `checks/high_fanout.rpt`，记录实际工具阈值、层次网络名和连接明细，不预设 clk 为原因。综合后对象若与中间态不同，需结合日志解释。
- 修复 PT 多路径默认仅报告负 slack，代表路径显式纳入正裕量，负 slack 指标查询不变；新增 PT `checks/disable_timing.rpt`，DC/PT timing/constraint 报告改为 6 位小数。
- driver 将新报告纳入必需检查/hash，统计原始约束违例行数；即使 WNS=0，有电气违例仍记 `CONSTRAINT_FAIL`，时序失败优先记 `TIMING_FAIL`，没有自动 PASS。
- `make -C npc/flow check test`：39 项通过，覆盖非时钟高扇出对象/无对象、连接明细、正裕量路径与负 slack 指标查询区分、电气违例及新增报告缺失/错误。实际工具兼容性待服务器验证；没有修改 RTL、SDC、WLM 或历史 run。
- 用户确认自行同步和运行服务器；已提供 [提交拆分与运行说明](s3-rerun.md)。诊断增强尚待服务器同步及真实 DC/PT 验证；新 run 先作为 S3 候选，审查关闭后再冻结正式基线。
