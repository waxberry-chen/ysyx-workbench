# ref-flow 初读与迁移取舍

2026-10-15，只读审查。本地为用户裁剪拷贝，包含脚本和目录骨架，不能据目录存在判断旧项目输入/结果完整。没有启动工具或连接参考文档中的远端；这些路径只用于识别依赖。本次优先审查根 Makefile、`03_scr/env/auto.tcl`、DC 00–05、STA scripts、PT power 参数脚本和 syn 仿真 Makefile/README。未对大量 SG/ECO 历史分支逐个验收。

DC/PT 命令语义与模式限制后续通过 [本地手册索引](manual-index.md)核对；参考脚本本身不能代替工具手册或实际版本的帮助。

以下路径均相对 `npc/ref-flow/`。配置和脚本为主要依据；`03_scr/README.md` 的通用 Kconfig 示例不一定与当前 `auto.tcl` 一致。

## 1. 实际依赖与值得保留的内容

根 Makefile：`syn → formality_r2n → pnr → formality_n2n → qrc → sta → sim → px → dataset`，另有 single/range 入口。NPC 裁剪成 `preflight → synth → sta`，四值/网表与 power 按各自依赖进入，避免把首次时序变成全物理流程的终点。

| 参考文件 | 可提取的内容 | NPC 处理 |
| --- | --- | --- |
| `Makefile` | `FLOW_TAG`、分阶段日志、耗时记录、`pipefail` | 保留运行标识和失败传播思想；移除绝对 PROJECT_ROOT、PnR/QRC/dataset 强依赖；检查报告而不只看 shell 退出码 |
| `03_scr/env/auto.tcl` | 将 top、库、PVT、工具和产物路径集中配置 | 拆成可共享设计配置和私有 site 配置；不用混合 C906 路径的整份配置 |
| `04_syn/c906-project/01_flow/00_flow_entry.tcl` | 工具配置、WORK、日志/报告/网表分目录、SVF | 在 NPC 中让库配置先于 analyze/elaborate/link；运行目录隔离 |
| `01_lib_setting.tcl` | target/link/synthetic library；逻辑/物理模式分支；check_library | 首轮 explicit DB list、一个 Vt/PVT；缺库失败；不用 broad glob 和 SRAM 默认混入 target_library |
| `02_read_verilog.tcl`、`03_read_sdc.tcl` | 文件清单、展开/link、约束导入、saif_map 起点 | 使用 SystemVerilog 与经审查 filelist；实际检查 link/timing，不复制 C906 filelist parser |
| `05_run_compile.tcl` | 网表/DDC/SDC 导出；max/min timing、QoR、resources、reference、power 报告 | 按 NPC 需要保留；关闭 baseline gating，补 hierarchical cell area、coverage、未解析单元与 unconstrained 判定 |
| `08_sta/c906_2_4/scripts/sta*.tcl` | corner 选择、库/netlist/SDC 输入、session、报告 | 重建 pre-layout 入口；post-route 网表/SPEF/propagated clock 全部由显式模式控制 |
| `09_px/pt_power_param.tcl` | netlist/SDC/wave 覆盖参数；可关闭 parasitics；time_based/averaged；输出控制 | 优先于缺失的默认 px 入口作为学习样本；改 DUT 层次和活动类型，补 annotation coverage，去除硬编码 strip_path |
| `11_sim/syn/Makefile`、README | netlist + 单元模型 + TB；有限 case；波形收集 | 用 NPC AXI 环境/AM 输入；冻结唯一 netlist，禁止自动退回旧网表；重写初始化和 X 检查策略 |

## 2. 不能照搬的具体问题

1. DC 主入口先 source `02_read_verilog.tcl`（内含 elaborate/link），之后才设置库。新的 flow 必须提前配置库和 search path；静态发现此顺序不代表已在服务器复现失败。
2. `analyze -format verilog` 与逐行读取 filelist 不适合作为 NPC `.sv` 清单的既定解析方式。需要验证注释、空行、相对路径、include 和 define，避免带入仿真 DPI 文件。
3. `LOW_POWER_MODE=0` 时仍配置 gating/operand isolation 等优化；`COMPILE_GATE_CLOCK=1` 默认打开。不能把“没开 UPF”误认成“没有低功耗变换”。首个基线保持无新增 gated clock。
4. `05_run_compile.tcl` 仅在 TOPO 分支创建 MIDDATA/DDC，却在分支外复制 `.ddc`；干净非 TOPO 运行需修正目录创建。saif map 输出也未按 TAG 隔离，NPC 必须绑定 run_id。
5. TOPO 分支含删除 work 目录逻辑；NPC 不复用该清理模式。`QRC_TLUPLUS_MAX` 指向 cbest、MIN 指向 cworst，命名/映射需依据实际工艺说明核对，本阶段非 TOPO 不使用它们。
6. STA 固定 `postroute.v.gz` 和 QRC SPEF，并调用 `set_propagated_clock`。`timing_margin.tcl` 硬编码 `CPU_CLK`、uncertainty、derate；这都不是 NPC 的已确认约束。
7. STA 配置使用 `STA_SEARCH_PATH`，入口未见把它明确赋给工具 search_path；其目录是 DB/STD，而 DC/PX 主要用 DB/STD_NEW。需要统一实际库路径，不能仅替换 top 名。
8. 根 Makefile 的 px 指向缺失的 `09_px/time_based_power.tcl`；已存在的 `pt_power_param.tcl` 可学习，但硬编码 C906 strip_path 且 `read_vcd -rtl`，不能直接用于 NPC gate-level VCD。
9. syn 仿真有 `+vcs+initreg+0`、random init、`+notimingchecks`、`+nospecify` 等设置。无 SDF 功能 smoke 可有明确的简化模型，但四值上电测试不能靠强制清零通过；必须分别配置与说明。
10. 当前参考主入口包含多个不存在的 launcher/辅助文件。复制整个 Makefile 会制造无关依赖；补齐所有旧文件也不能自动解决 NPC RTL、SDC 和测试平台适配。

## 3. 脚本缺口与服务器输入的边界

本地 `00_indata/DB`、`LIB`、`SDC`、`TF`、`QRC`、`MW`、`VLG` 下未发现实际文件；目录骨架仍在。用户已确认这些工艺文件在服务器，保留脚本中的路径，不列入 missing-files，也不作为本地蒸馏阻塞。各类输入角色见[流程图与输入输出](0-flow-map.md)；[文件清单](missing-files.csv)仅记录已引用但未拷贝的 flow 脚本/编排配置。

后续服务器上的首次 core synthesis/STA 使用相匹配的逻辑库、工具、NPC RTL/SDC/脚本；不需恢复 C906 RTL、SDC、SPEF、SRAM 库全集、PnR 或 SG 数据。功耗与 GLS 再增加对应模型/活动。参考文件本身已包含受限工艺标识和旧机器路径，后续公开版只选可共享内容，不将该快照默认为可公开资产。
