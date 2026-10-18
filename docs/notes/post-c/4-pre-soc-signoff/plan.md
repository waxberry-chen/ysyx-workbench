# M4 设计与验收计划

> 2026-10-18；状态：S0/S1、S2 已完成；首次 DC 综合已归档，S2.5 ISA 范围与异常语义收敛已完成本地验收，下一步为正式 S3 基线前的准备审查。PT/正式基线/S6 待实施；原 S4/S5 延后。
> 初始规划输入 HEAD：`0fe53bfcdbb1193b94415a9bb8382bcd7d71b4cf`；S1 输入 HEAD 与修改/验证记录见 [S1 综合范围](1-synthesis-scope.md)。ref-flow 保持原样。
> 配套：[手册检索入口](manual-index.md)、[参考审查](0-ref-flow-review.md)、[缺失 flow 脚本说明](missing-inputs.md)、[流程图与输入输出](0-flow-map.md)、[验收矩阵](test-plan.md)、[总路线](../roadmap.md)。

## 1. 目标和评估范围

从 `npc/ref-flow` 学习可解释、可复现的 DC/PT 最小路径，在 `npc/flow/` 建立 NPC 自己的实现流程。本轮只完成一个 top、一个 functional mode、一个 PVT 的 **DC 综合面积与 PT pre-layout 时序基线**。功耗仅在综合流程中附带执行 `report_power` 作简要估算，不建立活动生成、GLS + PTPX 或独立功耗 flow。PnR、CTS、QRC、UPF、多电压、自动 clock gating、self-gating/ECO 和 dataset/training 不属于本阶段主线。

默认首个 top 为现有 `ysyx_core_axi4lite`：包含 Core、两个 adapter 和 Arbiter，保留现有 commit/monitor 输出并计入面积与约束；不包含 Xbar、SRAM、UART、CLINT、pad 和测试平台。后续若去掉观察端口，另立配置重新测量，不能与此基线混用。报告标题必须写明“Core + adapters + Arbiter”，不能写完整 SoC PPA。

选择该范围的原因：它具有实际的单 master 边界，能复用 M3 行为契约，同时不会把 1 MiB 仿真 SRAM 阵列综合成大规模触发器而掩盖 core 成本。B1 整体的宏映射是后续独立任务；当前 SRAM 为组合数组读、按 byte 写，要核对宏的读延迟、端口、mask 和容量后才能替换，提供若干旧 C906 SRAM `.db` 不等于完成映射。小容量触发器 SRAM 实验如需运行必须独立命名，不能冒充默认 1 MiB 系统。

冻结初始策略：单时钟、单电源、无新增 gated clock、非 topographical DC；优先从可用 TT 库中选择一个明确的 Vt 家族。参考配置列出了 TT 0.9 V / 25°C，工艺库已在服务器并保留原路径；首次综合已使用 RVT/TT 候选并确认 `tt0p9v25c`、ns/pF 与 `ZeroWireload`；面积暂记 `library_area`。S2 已选单 RVT/TT 候选路径，并冻结 10 ns 试探周期及数值 I/O/load/slew/uncertainty，见 [数值约束](2-flow.md#2-数值-sdc-与适用边界)。服务器执行前仍需 probe 核对库单位、operating condition 和实际模型；不照搬 C906 的目标和 margin。跨 corner sign-off 不属于单 corner 基线结论。

查阅 DC/PT 命令与约束时遵循 [手册检索约定](manual-index.md#5-后续搭建-flow-的查阅约定)：先检索本地分页缓存，再按页阅读相关小节；记录手册版本、正文页及 PDF 页，适用模式与服务器工具版本分别核对。查询工具会校验 PDF/缓存 hash，手册更换后需重建并复核索引。

## 2. 先修清楚的 RTL 与环境边界

以下为 S0 发现的问题，现已在 [S1](1-synthesis-scope.md) 落实修复与审查：GPR/CSR DPI 与 SVA 隔离、GPR 硬件复位、独立 filelist、reset/端口预算接口和回归已完成。下列保留原问题背景：

- `ysyx_regfile.sv` 和 `ysyx_csr.sv` 无条件导入 DPI 并在 `initial` 中调用；不能只给 DC 定义 `SYNTHESIS` 就宣称已去除 DPI。
- regfile 用 `initial` 清零所有 32 项，读 x0 也来自数组。需要保证 x0 在硬件上恒零，其他 GPR 的上电值与 reset 策略明确；评估保留硬件复位还是由启动代码初始化的成本与软件依赖。不得简单包掉整个 `initial` 后忽略 x0/X 问题。
- `filelist-b1.f` 包含不在首个 top 层次中的旧 DPI RAM、B1 slaves 等；新建明确的 synthesis filelist，审查 SV 依赖、宏定义及 include，而不是直接复用 Verilator 的整套选项。
- 当前有 `posedge clk or negedge rst_n`，这里的 negedge 是异步复位，并非下降沿功能时钟。逐个检查 control/valid/owner reset，未复位数据必须被有效位屏蔽；单时钟不等于无需 RDC 审查。

本地进行 flow 蒸馏、源码修改、静态检查与可用 RTL 回归，不复现运行 ref-flow，也不以本地库文件或 EDA 工具存在性作为出口。PDK 相关文件已在服务器，保留现有脚本路径；后续 NPC 实现与服务器执行按 S1–S3/S6 推进，运行时再记录版本/license/输入检查结果。

## 3. 实施顺序与出口

| 步骤 | 工作 | 出口与依赖 |
| --- | --- | --- |
| S0 学习与 flow 蒸馏 | 输出 ref-flow 执行顺序图与数据流图；记录每一级的入口、输入、输出；区分工艺库、design、flow 控制和工具环境；核查未拷贝的 flow 脚本；明确 NPC 裁剪范围 | `0-flow-map.md`、`0-ref-flow-review.md`、`missing-files.csv`、`manual-index.md` 与本地手册缓存；保留服务器库路径，推断处有标注；本地无需补 PDK、安装 EDA 或复现旧 flow |
| S1 可综合与上电语义 | 去除实现路径 DPI 依赖；明确 x0/GPR/reset 语义；独立 filelist；审查 latch/环/位宽/未驱动/隐式初始化；形成 SDC 端口预算表 | lint 与受影响定向/系统回归通过；DIFF/harness 路径仍可运行；新增初始化策略有说明；四值动态验证延后，不能把两值回归写成 X 验证 |
| S2 最小 NPC flow | 创建 `00_indata`、`01_common`、`02_syn`、`03_sta` 入口所需文件；库先于 elaborate/link；实现 preflight、失败退出、每次独立 run、manifest 与报告检查 | 缺文件/缺变量/错误 top 能提前失败；本地静态检查与后续服务器 preflight/工具语法检查分开记；工艺库路径显式配置，design 路径适配 NPC，无隐式 fallback |
| S2.5 ISA 范围与异常语义收敛（本地验收完成） | 移除 M；GPR 收敛到 RV32E 的 16 项；明确合法编码与 CSR 支持范围，补齐非法指令检测和精确异常；同步 harness/DiffTest 与测试 | 按下表分项实施和回归；无 M 的仿真/综合行为一致，高寄存器编码不发生别名访问；合法/非法指令及 CSR 语义有独立预期测试；最终源版本与 ISA 清单固定后进入 S3 |
| S3 综合与 STA 基线 | DC 分析/展开/映射，导出网表/SDC/DDC；PT 读同一网表和库，ideal clock，无 SPEF；报告 max/min、约束覆盖、area/关键路径 | **正式面积与时序基线**；先完成 S2.5 并通过下述基线准备审查；link 无未解析引用，无非预期 latch/环/未约束功能端点；WNS/TNS 如实记录，未达标实验先归档为诊断结果，不自动提升为正式基线或 timing PASS |
| S4 四值与网表 smoke（延后） | 原计划保留为后续验证方向，本轮不搭建四值/门级仿真环境 | 不作为本轮 DC/PT 基线出口；未执行状态明确保留，不能声称网表等价或 X 验证通过 |
| S5 活动与 PTPX（延后） | 本轮不生成功耗专用 VCD/SAIF、不建 PTPX flow；DC 简要估算并入 S3 | 不作为本轮出口；后续有具体低功耗优化问题时再启动 |
| S6 基线归档 | 固化相关 RTL 回归、synth/STA 入口，复查 warning/waiver，归档 manifest、报告、指标、Q&A | 面积/时序基线可复现；DC 功耗为附带估算，可标记不支持/未评估；不要求完成原 S4/S5 |

保留 S3–S6 原编号，以 S2.5 插入新增步骤；当前执行链为 **S0 → S1 → S2 → S2.5 → S3 → S6**。S0/S2 本地蒸馏不等待工艺文件补拷，库路径沿用服务器配置；服务器执行前核对 DC/PT 和对应逻辑库。四值/GLS/PTPX 工具与单元仿真模型不再构成本轮依赖。首次评估的主体为面积与时序，不承诺完整 PPA 或物理实现 sign-off。

### S2.5：ISA 范围与异常语义收敛

2026-10-18：[实施契约与验收证据](2.5-isa-contract.md)已记录，A–D 本地验收通过；完整特权架构及 EBREAK/取指目标对齐等限制见该报告，不声明完整 ISA compliance。

目标为 **RV32E 基础整数指令 + 明确列出的 CSR/机器态能力，不含 M/C**，与 NPC 的 `-march=rv32e_zicsr -mabi=ilp32e` 软件目标对齐。软件目标不是 RTL 已合规的证明；S1/首次综合保留的 32 项 GPR 和组合 M 运算仅作为历史输入保留，不再作为正式 S3 的目标配置。

以下按顺序独立修改、验证，避免一次同时改变译码、寄存器布局和参考接口而难以定位问题：

| 子项 | 实施范围 | 验收重点 |
| --- | --- | --- |
| A：移除 M 并拒绝其编码 | 删除 MUL/MULH/MULHSU/MULHU、DIV/DIVU、REM/REMU 的 ALU 实现；完整识别 `opcode=0x33, funct7=0x01`，八种 funct3 均触发 cause 2；仿真/综合采用同一行为 | 八条编码全部覆盖，含 rd=x0、普通 rd 和源/目的重叠；相邻合法 ADD/SUB/移位不误报；无乘除余硬件残留，软件乘除余仍正确 |
| B：16 项 GPR | 仅提供 x0–x15，保持 x0 恒零；对实际使用的 rd/rs1/rs2 检查高寄存器编码；同步 reset、DPI、harness、状态展示、DiffTest 适配及手写测试 | 本工程将 x16–x31 保留编码明确处理为非法指令，不截断成低寄存器别名；按指令格式区分寄存器与立即数字段，CSR zimm 也不能误判为 rs1；检查 16 项数组访问边界，禁止原 32 项 memcpy/遍历越界 |
| C：合法编码检查 | 按支持清单精确检查 opcode/funct3/funct7、移位立即数、load/store 宽度、JALR 和 SYSTEM 编码；明确保留/不支持编码的拒绝策略 | 覆盖合法指令及邻近非法编码，不能依赖默认 ALU 结果静默提交；非法访存编码不发 LSU 请求，也不等待不存在的响应；不把项目对保留编码的处理策略泛化为所有规范的强制要求 |
| D：CSR/机器态契约 | 列出 CSR 地址、权限、位语义及读写规则；核对六条 Zicsr 指令、零操作数的读写抑制、只读写入限制及支持的 trap/MRET 行为；本工程对未实现 CSR 地址显式报非法，不默认返回 mstatus | 检查正常读写/置位/清位、立即数形式、无写入条件和非法访问；普通 CSR 写入与 trap 对 mepc/mcause/mstatus 的合法更新分开验证；未满足完整 Zicsr/机器态要求时列明缺口，不宣称完整合规 |

共同验收与边界：

- 非法指令必须形成精确异常：`mepc` 指向该指令，`mcause=2`，更新声明支持的 trap 状态并跳转到 `mtvec`；抑制原指令的 GPR/普通 CSR 写入和数据访存副作用。取指错误优先于对错误返回数据的非法编码判断；被 redirect 取消的指令不得产生异常。
- 定向程序用 `.word` 嵌入非法编码，handler 独立检查 cause/EPC、寄存器保持和内存副作用，调整 `mepc` 后 MRET 恢复；同时做译码/EXU 定向检查、lint/综合宏检查和受影响的 CPU/系统回归，最终保留 B1 signoff 与 legacy 影响检查结果。
- 现有 DiffTest 会根据 DUT 的 exception/cause 向参考端注入异常，因此它只能帮助检查异常后的状态，不能独立证明非法检测正确。上述合法/非法测试必须有独立预期；不为 NPC 裁剪而全局删除 NEMU 的 M 支持。若保留参考接口的 32 槽状态结构，明确其与 16 项硬件 GPR 的适配规则。
- CSR 审查不等于“异常时完全不访问 CSR”，也不等于引入完整 S/U 模式或所有可选 CSR。明确 EBREAK 当前的仿真退出约定与硬件 breakpoint 行为边界，避免更严格的 SYSTEM 译码无意破坏测试退出；未实现的机器态能力记录为限制。
- 分项维护 ISA/CSR 支持清单、实现决定与回归证据。S2.5 结束后固定实际源版本、编译参数、GPR 数量与观察 scope，再进行新的 S3 run；本步骤允许诊断综合，但不提前宣布正式基线通过。

首次综合记录保持原样。去掉 M、缩减 GPR 属于 ISA/实现范围收敛，后续面积/时序变化需标明功能范围差异，不能称为相同 ISA 下的乘除法优化；多周期 M 单元留待确有需求时另立优化实验。

### 正式 S3 基线前的准备审查

[01 首次综合](synthesis-results/01-first-synthesis/README.md) 已验证真实 DC 路径并暴露组合除余和观察接口问题；它是独立的首次综合记录，不能用后续正式基线覆盖。当前先处理以下事项：

1. 明确 core 功能/观察边界、输出采样与有效条件，冻结正式 scope 和 SDC；观察端口裁剪或时序改变必须独立命名，不能对照不同范围直接宣称优化收益。
2. 按 S2.5 移除 M 并收敛 RV32E/CSR 行为，再审查剩余 ALU、地址/异常共用路径。当前不新增多周期 M 单元，也不扩展为 cache 或整核流水线重写；后续若重新引入 M，单独记录频率、面积及 CPI/吞吐代价。
3. 整理实际源版本（本次服务器需移除 `` `default_nettype none `` / `` `default_nettype wire `` 才能综合，详见首次综合记录），补齐失败证据与长期兼容方案，并完成隐式网络检查和受影响的功能回归；分类处理结构、signed/width 与约束告警。无依据不得添加 false path/multicycle 或隐藏慢端点。
4. 在测量前明确目标频率及接口预算，以新 run 完成 DC/PT 四类路径、setup/hold/DRV 和 coverage 审查，再冻结正式基线。数百 MHz 是待论证的目标，不是由 28 nm 节点自动保证的验收值；功耗未评估不阻塞本轮面积/时序基线，也不能声称完整 PPA 正常。

旧网表的 PT 可用于诊断，后续每次改动按[结果索引](synthesis-results/README.md)归档。未达标数据保留；目标或 scope 调整需写明理由并重新测量。当前实现/模型问题尚未关闭，不因工具返回 COMPLETE 即进入正式基线归档。

## 4. SDC 与结果契约

以 `clk` 创建唯一功能时钟，列出所有 AXI 输入/输出及 commit/monitor 观察输出。输入 delay 需有 max/min，输出 delay、驱动或 slew、负载均有单位和依据；不得用遗漏约束让路径消失。报告 Reg2Reg/In2Reg/Reg2Out/In2Out，确认实际端点数与预期一致。

`rst_n` 的异步 assertion、外部同步 deassertion 假设和 recovery/removal 检查需分开记录。不能复制 `set_false_path -from [all_inputs]` 或无理由屏蔽整个 reset 网络；确需例外时写精确对象、设计原因和替代验证。没有功能依据就不添加 multicycle/false path。无布局时使用 ideal clock，明确 clock uncertainty、latency 和 transition 的假设。

DC/PT 必须记录互连模型：若库具备并采用 wire-load，写明具体名称和设置；若 PT 使用零线延迟/仅引脚负载等模型，明确偏乐观的边界，并解释两工具模型差异。没有 SPEF 不应伪造输入或使用 C906 寄生参数。单个 target 的 WNS 不能直接包装为测得 Fmax；如需频率探索，固定其余配置，保存每个点的重综合/STA 结果，区分约束目标与通过的探索点。

### 附带的 DC 功耗估算

综合后可输出 `report_power` 与 `report_power -hierarchy`，现有参考 `05_run_compile.tcl` 已有这两个命令。本轮使用显式、可复现的活动假设，不导入 workload 波形；命令/选项、单位和支持能力以服务器 DC 版本及库模型为准。

- 记录 PVT/Vt、时钟频率、I/O load/slew、互连估算方式，以及信号 toggle rate/static probability 的值、单位和来源；时钟与功能模式下 reset 单独处理，不能给所有端口套同一活动值。
- 说明哪些活动由用户设定、工具默认或传播估计。报告 internal、switching、leakage 与 total（工具支持的项目），同时保留层次分布及相关 warning。
- 标题统一写 **“DC pre-layout 功耗粗估（假设活动，非 workload）”**。该数字不是程序运行功耗、能量/指令或硅后实测，也不能证明毛刺/时钟树/真实互连功耗。
- 相同配置下的前后结果只用于初步筛选；活动相关性和结构变化可能影响估算，不能仅凭很小的差值宣称低功耗优化成功。
- 若工具 feature/license 或库 power model 不支持，记录“功耗未评估”，不新增工具依赖，不阻塞面积/时序基线验收；功耗结果始终与 A/时序的必做检查分开。

方法依据：[Synopsys 对活动假设、默认标注与综合后功耗差异的说明](https://www.synopsys.com/articles/understanding-power-profile.html)。采用本方案的目的为低成本提供附带参考，精度边界由活动与模型决定，不由报告命令名称决定。

## 5. 脚本目录与运行产物（S2 已实现，本地验证通过）

```text
npc/flow/
├── README.md / Makefile       # 使用说明与 check/probe/synth/sta/clean 等入口
├── 00_indata/
│   ├── configs/              # design 与 site 配置；私有 site 不入库
│   ├── filelists/core.f      # 引用 npc/vsrc 的 SV 源闭包
│   ├── constraints/core.sdc  # clocks / IO / reset
│   └── DB/STD_NEW/           # 用户拷入的工艺 DB，不入库
├── 01_common/                # driver、共享 Tcl、manifest/报告检查
├── 02_syn/                   # DC probe / 综合
├── 03_sta/                   # PT pre-layout 分析
├── 04_tests/                 # 本地 mock / 契约检查
└── build/<RUN_ID>/           # 每次 run 的快照和产物
```

[S2](2-flow.md) 已创建最小执行入口、数值约束与本地测试；[flow README](../../../../npc/flow/README.md) 是实际使用入口。本地 mock 检查不代表真实工具已跑通。运行目录为服务器可配置的 `<RUN_ROOT>/<run_id>/`，内含 `inputs/ logs/ reports/ outputs/ manifest.json`；默认产物目录为 `npc/flow/build/`。每次运行独立，禁止默认复用旧网表；输入 hash 不匹配即失败。按 2026-10-17 的目录约定，DB 默认放在 `00_indata/DB/STD_NEW/`，也支持外部服务器绝对路径；本地检查仍不要求 PDK 存在。`clean RUN_ID=...` 可显式删除一个 run 后重用 ID，其他 run 和输入不受影响。若以后公开脚本，再单独处理路径脱敏。

manifest 至少含 RTL commit/dirty patch、filelist/define/参数、top/观察端口策略、脚本/SDC/库 hash、工具版本、PVT/Vt、互连/时钟假设、命令、退出码、日志路径、网表 hash；附带功耗增加活动假设及其来源；没有 workload/窗口/活动映射结果。工艺数据只存服务器，文档保存必要的可共享标识。

## 6. 完成标准与后续

固定配置下能从干净运行目录重建网表与报告，所有 warning 有处置；综合/STA 无结构性漏检，RTL 修复的相关功能回归通过。四值/网表动态验证明确为延后项。报告面积单位/层次、WNS/TNS/违例端点、关键路径起止点与逻辑、附带功耗估算假设或未评估原因。结果不要求优于旧核，但要能回答下一步优化依据。

本阶段允许上述基线准备所需的观察接口、算术实现和约束纠正；先保留首次综合，再建立稳定基线，不为追求数值扩展 cache/gating 或整核流水线重写。后续进入 M5 的 ysyxSoC 接口/启动工作；完整 B1/SoC 的 SRAM/外设实现范围另立配置，不能沿用 core 基线标题。发现外部阻塞及时记录，能独立开展的工作继续推进。
