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

## 2026-10-18：审阅并归档 02 RV32E / 无 M 的 DC/PT

- 审阅服务器拷回的 `core-tt-10ns-rv32e-nom`，按原字节归档 46 份报告/日志/追溯文件至 [02 实验](synthesis-results/02-rv32e-no-m/README.md)。原 run 的 36 项输入、21 项 syn 与 23 项 sta 产物 hash 全部匹配；17 份 RTL 快照与本地一致。
- 面积 9511.319905 library_area，比首次下降 72.9%；DC setup slack +5.53 ns，PT max/min WNS/TNS 为零。属于减少 GPR/删除 M 后的范围收敛，仍非同 ISA 优化对比。
- PT `constraints.rpt` 实际包含 66 条 min-capacitance，故新 flow 保留 `checks/constraint_violations.rpt` 命名。定位到 EXU buffer，其中 64 个子模块观察输出未使用。
- 正式基线尚受以下审查项阻塞：PT 多路径报告默认仅列负 slack，缺少正裕量路径；5516 项异步控制脉宽检查未测试；PTE-003 禁用弧原因与电气违例仍需服务器补报告。已查 PT 手册 PDF 637 确认多路径筛选默认行为，记录下一步，不修改旧报告。
- 本次仅更新审阅归档和文档/QA；没有修改 RTL、SDC 或 EDA 执行脚本，没有重跑 DC/PT。

## 2026-10-18：补齐 S3 候选重跑诊断

- 原 run 的 TIM-134 没有网络名称；新增 DC `checks/high_fanout.rpt`，记录实际工具阈值、层次网络名和连接明细，不预设 clk 为原因。综合后对象若与中间态不同，需结合日志解释。
- 修复 PT 多路径默认仅报告负 slack，代表路径显式纳入正裕量，负 slack 指标查询不变；新增 PT `checks/disable_timing.rpt`，DC/PT timing/constraint 报告改为 6 位小数。
- driver 将新报告纳入必需检查/hash，统计原始约束违例行数；即使 WNS=0，有电气违例仍记 `CONSTRAINT_FAIL`，时序失败优先记 `TIMING_FAIL`，没有自动 PASS。
- `make -C npc/flow check test`：39 项通过，覆盖非时钟高扇出对象/无对象、连接明细、正裕量路径与负 slack 指标查询区分、电气违例及新增报告缺失/错误。实际工具兼容性待服务器验证；没有修改 RTL、SDC、WLM 或历史 run。
- 用户确认自行同步和运行服务器；已提供 [提交拆分与运行说明](s3-rerun.md)。诊断增强尚待服务器同步及真实 DC/PT 验证；新 run 先作为 S3 候选，审查关闭后再冻结正式基线。

## 2026-10-18：S3 候选频率设为 200 MHz

- 根据最新 02 实验最差 Reg2Out 路径，到达 2.27 ns 加输出预算 2.0 ns、setup uncertainty 0.2 ns，原网表的该路径需要约 4.47 ns。选择 5 ns / 200 MHz，估计该路径裕量约 +0.53 ns；300 MHz 估计约 −1.14 ns，留待后续探索。
- `npc_core.tcl` 的 period 从 10.0 改为 5.0；I/O/reset min/max、uncertainty、slew、load、RTL、WLM 和综合策略不变。同步默认运行示例和 S3 候选 run 名称，保留历史 10 ns 实验快照。
- 这是待服务器重综合/PT 验证的目标，不是达到 200 MHz 或测得 Fmax 的声明；不代替 hold、电气约束、复位脉宽和禁用弧审查。

## 2026-10-18：审阅并归档 03 200 MHz 候选

- 用户拷回 `core-tt-5ns-baseline`；核验 36 项输入、22 项 syn 与 24 项 sta 产物 hash，17 份 RTL 快照与本地及 02 一致。按原字节归档 48 份报告/日志/追溯文件至 [03 实验](synthesis-results/03-200mhz-candidate/README.md)。
- 200 MHz 下 PT setup/hold slack 为 +0.531597/+0.013534 ns；内部 Reg2Reg 为 +1.600592 ns，经 ALU/redirect、IFQ 和 PC+4 回到 opbuf。面积仍为 9511.319905 library_area；没有新增架构优化或功耗评估。
- 新增报告真实执行成功：高扇出对象确认为 clk、1509 个负载；禁用弧 269 条 p、105 条 C，无 l/L loop-breaking 标记；正 slack 四类路径齐全。
- CONSTRAINT_FAIL 来自 66 个无负载 EXU buffer 的最小电容违例（required 0.410 fF）；64 个驱动未使用的子模块观察输出，2 个驱动 CSR 舍弃的 trap_epc 对齐位。5516 项复位/置位脉宽未测试项与 02 一致。
- 下一步处理无负载 buffer、完成结构告警及 reset 脉宽验证边界审查，再冻结正式 S3。本次只更新归档/文档/QA，没有修改 RTL、约束、执行脚本或重跑 EDA；原 run 和历史归档不变。

## 2026-10-18：按早期评估范围暂缓 reset 时序验收

- 用户明确要求参考 C906 的 reset false path；当前缺少实际 SoC/reset 源和 IO 时序，不继续填假设 release delay。SDC 仅增加 `set_false_path -from [get_ports rst_n]`，删除 reset input delay 及配置中的 reset_min/reset_max。RTL reset 功能、数据接口预算与其余时序设置不变。
- 新 run 不再声明 recovery/removal、reset→D/输出和脉宽已验证；coverage/untested 原样保留，例外不保证脉宽 untested 消失，也不自动豁免其他检查。66 条最小电容违例未处理。
- 新增 [reset TODO](reset-timing-todo.md)，记录机制明确后的脉宽/释放建模、例外撤销、验证与新 run 要求；同步计划、端口预算说明、flow 使用说明和知识笔记。01–03 归档保持不变。
- `make -C npc/flow check test`：40 项本地测试通过；新增负向测试拒绝例外遗漏、扩大到数据/所有输入和旧 reset 延迟回流。未执行真实 DC/PT，服务器由用户同步后以新 RUN_ID 运行。

## 2026-10-18：补充 LSU 使能网络电容对照诊断

- `core-tt-5ns-no-port-buffers` 的 PT 不再报告 66 条 min-capacitance，但 U13/ZN 驱动 54 个请求寄存器 E pin 和一个 buffer 输入，实际 0.088724 pF 超过 0.084770 pF；DC 同次无违例。未据此修改状态机或断言 CCS 是唯一原因。
- 新增 DC/PT 共用 `01_common/capacitance.tcl` 和必需报告 `checks/lsu_enable_capacitance.rpt`，由请求寄存器 E pin 追踪网络和分支，记录连接、reference、可用库/设计 pin 电容属性和模型设置；不硬编码 U13/n3。缺失属性与无匹配对象明确标记。
- `make -C npc/flow check test`：42 项通过，覆盖两分支/去重/改名、无 E pin、缺失属性、核心报告失败和必需产物检查。没有改 RTL/约束/综合策略或执行新 DC/PT。服务器运行说明见 [电容对照诊断](s3-capacitance-check.md)。

## 2026-10-18：LSU 最大电容局部修复实验待服务器验证

- 新返回的同名 run 确认 DC/PT 的连接、网络 min/max 电容、驱动库上限及 CCS 报告开关一致，但 DC 无违例、PT 一条 max-capacitance。标量与 rise 输入电容之差是检查口径的候选解释，尚未证明。
- 在 DC compile 前按 `core/u_lsu` 解析 design，施加 0.075 pF 最大电容目标，为已知负载差异留裕量；作用于 LSU 内部全部网络。目标缺失则停止，不绑定 U13/n3，不修改 RTL、库限制或 PT 验收口径。增加 DC `report_net -max_capacitance` 继续记录约束计算值。
- `make -C npc/flow check test`：43 项通过，覆盖局部作用域、compile 前施加、错误层次拒绝及 DC 专用报告。`git diff --check` 通过。实际负载分组、面积及时序变化需服务器新 run `core-tt-5ns-lsu-cap-margin` 验证，S3 仍未关闭；详见 [实验依据和验收](s3-capacitance-check.md#5-诊断返回与局部修复实验)。


## 2026-10-18：修正综合裕量的层次作用域

- 新返回 run（HEAD `e3ea746a`）确实执行了 LSU design 的 0.075 pF 赋值，但导出 SDC 没有保留约束，负载/违例/面积/最差时序未改善。对照 DC 手册 10-8–10-9、10-12，确认上一版没有正确处理 top-down compile 的子 design 约束语义。
- 改为对综合顶层设置 0.075 pF，并在 compile 前后读回实际属性；缺失/变化立即失败。明确覆盖全 core，可能影响 LSU 之外的面积与时序，PT 仍使用原 SDC/库验收。
- 纠正 `report_net -max_capacitance` 的解释：服务器 2023 版实际输出 Load/LoadUR 等列，没有旧手册中的 Required/Actual/Slack。未据此宣称查明 DRC 内部算法。
- 本地 43 项测试通过，包括 compile 后约束丢失的失败注入；真实优化效果仍待 `core-tt-5ns-top-cap-margin`，S3 未关闭。详见 [失败原因与修正](s3-capacitance-check.md#6-局部裕量未生效与顶层作用域修正)。


## 2026-10-18：改用 fanout 32 并保护时钟网络

- 核对 C906 公共 SDC 的 `MAX_FANOUT=32` 和综合入口的 ideal clock network 设置；按用户决定，以顶层 `max_fanout 32` 替代尚待服务器验证的顶层 0.075 pF 方案。
- DC 显式 `set_auto_disable_drc_nets -on_clock_network true`，沿用共享 SDC 的 ideal clock 时序；compile 前后核对顶层 fanout 和 clk 源网络 DRC 保护属性。reset/data 不新增 DRC 例外，库电容限制保留。
- 电容诊断增加库默认及各 pin 的 fanout_load，避免把 32 误读为固定 pin 个数。43 项本地测试通过，包含丢失 fanout/时钟保护的失败注入。效果待 `core-tt-5ns-fanout32` 服务器结果，S3 未关闭。[策略与验收](s3-capacitance-check.md#7-改用-max_fanout-32-并排除时钟-drc-修复)


## 2026-10-18：修正 clock DRC 属性不可查询导致的误阻塞

- 服务器 UID-101 表明 net `clk` 不暴露 `auto_disable_drc_nets`；此前将查询失败当作设置失败，是诊断脚本兼容问题。保留 clock DRC 命令和 fanout 32，将该属性改为 quiet 可选查询、缺失明确写 UNAVAILABLE，不能当作保护已通过。
- 命令失败、max_fanout 丢失、可读保护属性为 false 仍停止；默认 mock 改为复现服务器不可查询，而非假定返回 true。44 项本地检查通过，实际效果待新服务器 run。见 [兼容修正与边界](s3-capacitance-check.md#8-修正-clock-drc-属性查询的版本兼容问题)。


## 2026-10-18：验收并归档 S3 范围内基线

- 最新同名 run HEAD `9e449fac`，dirty 仅 Makefile SITE 默认值；37 输入、23 DC、25 PT 产物 hash 全部一致，17 份 RTL 与 03/本地相同。工具完成，DC/PT 均无约束违例；area 9242.855942，setup/hold +0.596843/+0.008754 ns。
- fanout 32 将 LSU 68 个 E pin 分为 25/25/18，PT 最大分支电容 0.0405621 pF，低于新驱动库上限 0.045377 pF。clk 直接驱动 1509 个 CP，与时序单元数一致；没有因该目标生成 clock buffer tree。
- 完整解析 coverage：9426 reset deferred + 24 mtvec[1:0] 常量条件禁用 = 9450 untested；其他检查 10730 met、0 violated。结构告警按连接分类，禁用弧只有 p/C，无 l/L。UITE-416 与两个常量 D 端的对应关系标为交叉证据推断，不冒充工具逐名证明。
- 新增 [04 原始归档](synthesis-results/04-200mhz-baseline/README.md)（51 文件、原字节/hash）及 [S3 结果](3-synthesis-sta.md)，更新计划/矩阵/路线/展示入口。工具 REVIEW_REQUIRED 不改写；人工接受当前 TT、ideal clock、ZeroWireload、reset deferred 的 core 基线，S6 最终复现/交接待完成。
- 本次未改 RTL/SDC/flow，未运行新 EDA 或重复功能测试；功能版本证据沿用 S2.5，不把 gate-level/formal/功耗/物理 sign-off 计入通过。

## 2026-10-19：S6 本地最终回归与复现交接

- 从干净 HEAD `415c87b` 重新执行 flow check/test（44 项）、ISA/异常契约、四组 synthesis scope、B1 signoff、legacy 定向/34 项 CPU/固定 trace/10 seeds，全部通过。使用既有增量构建目录，未声称全量 clean rebuild；功能输入与 04 相同。
- 再次核验 04 的 37 项输入、23 DC/25 PT 产物及 51 份长期归档 hash；32 份 NPC 输入快照仅 Makefile 默认 SITE 与当前不同，显式传 SITE 即可保持配置一致。17 份 RTL、设计 SDC/config 与实际 flow 执行代码一致。
- 新增 [S6 交接记录](6-reproduction.md)及 [14 份本地证据与 manifest](s6-validation/manifest.json)，固定命令、版本、退出码、原始日志/结果与 hash；修正 flow README 和展示证据索引中的过时候选状态及 reset 预算描述。
- 当前阻塞为 I12 的独立服务器新 run 复现：本地无 DC/PT、原 DB 与安装 setup，不能用 mock/旧报告 hash 检查替代。交接使用 `core-tt-5ns-s6-repro`，不覆盖 04；需核对面积、路径、coverage、负载和告警，而非只看零违例。
- S3 已验收结论保留；S6 本地完成、服务器待验，M4 总验收未关闭，不预填 `signoff.md`。没有修改 RTL、SDC、flow 执行脚本或历史 EDA 归档，也未代替用户提交/同步/执行服务器。

## 2026-10-19：S6 独立复现通过，M4 本轮验收关闭

- 用户回传 `core-tt-5ns-s6-repro`，北京时间 19:13 创建；DC/PT 均 COMPLETE、exit 0。服务器仍为 `9e449fac` 与相同 Makefile SITE 默认值修改，设计/site 求值及外部依赖 hash 与 04 一致；37 输入只有 run 路径变化。
- 两次输入/产物 hash 自洽，新 run 37 输入、23 DC/25 PT 产物核验通过。重新解析报告与 manifest 结果一致；43 份报告仅日期与 QoR 四行耗时不同，综合网表/导出 SDC 仅日期注释不同；DDC 未做语义比较。
- 面积 9242.855942、setup/hold +0.596843/+0.008754 ns、coverage 及负载分支全部复现 04。告警集合无新增或消失，延续相同 reset deferred、常量条件禁用和结构审查依据；原 REVIEW_REQUIRED 保留。
- 新增 [05 归档](synthesis-results/05-s6-reproduction/README.md)（52 份原始文件、comparison.json）和 [M4 signoff](signoff.md)，关闭 I12/S6，更新计划、矩阵、路线及展示入口。干净 run 不冒充干净 Git checkout，SITE 已记录差异不影响实际配置。
- 外部依赖检查依赖服务器阶段内原 driver 的前后核验；本地未访问服务器 DB/工具，也未收到单独 inspect 终端记录。未修改 RTL/SDC/执行脚本或运行产物，沿用本日已完成的 S6 功能回归；当前范围内无阻塞，下一步 M5。
