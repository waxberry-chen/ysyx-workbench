# 01：首次综合

2026-10-17。**DC 综合完成，10 ns 目标下 setup/hold 均未满足；PT 未执行，功耗未评估。本次作为首次实现诊断记录，不作为正式 S3 综合/STA 基线。**

原 run：`npc/flow/build/core-tt-10ns-split/`。原始 manifest 的执行状态为 `COMPLETE`、评价为 `REVIEW_REQUIRED`；本文依据 DC 报告明确记录 timing FAIL，不改写原 manifest。归档时所有原 run 输入及 synthesis 产物与 manifest 中 hash 一致；没有重新执行 EDA 或验证服务器外部工具/DB 当前内容。

## 1. 输入与范围

| 项目 | 实际值 |
| --- | --- |
| Top | `ysyx_core_axi4lite`：Core + IFU/LSU AXI adapters + Arbiter |
| 保留范围 | commit/monitor 输出、32 项 GPR、组合 M 运算；不含 Xbar/SRAM/外设 |
| 源版本 | `04397db2a95077de0ec4ae47dad1cd5e575a153a` **加未提交修改** |
| 工具 | DC V-2023.12-SP5，普通 wire-load 综合，`compile -map_effort medium` |
| 库 | `tcbn28hpcplusbwp12t40p140tt0p9v25c_ccs`；条件 `tt0p9v25c`，TT/0.9 V/25°C；site 声明 RVT |
| 单位 | ns、pF；面积为 `library_area`，未证实 μm² |
| 时钟 | 10 ns；ideal clock；setup/hold uncertainty 0.2/0.05 ns |
| I/O | input/output/reset min/max 0.2/2.0 ns；输出负载 0.01 pF，含观察端口 |
| 互连 | 实际选中 `ZeroWireload`，top mode，无布局/CTS/SPEF |
| 功耗 | `power_enable=0`，`NOT_EVALUATED` |

完整依据：[原 manifest](provenance/manifest.json)、[配置](provenance/design-config.tcl)、[site](provenance/site-config.tcl)、[输入 SDC](provenance/core.sdc)、[DC 导出 SDC](provenance/dc.sdc)。

不能仅用 HEAD 代表本次源代码。服务器 [dirty patch](provenance/dirty.patch) 包含多处移除 `default_nettype` 指令及 site 配置变化，详见 [原工作区状态](provenance/git-status.txt)。

### 本次 DC 兼容处理：移除 default_nettype 指令

用户确认：本次服务器 DC 综合在保留 `` `default_nettype none `` 和 `` `default_nettype wire `` 时会报错，移除这两条指令后才综合成功。因此，本记录的面积/时序结果对应**移除指令后的实际输入**，不能表述为原始 HEAD 未经修改即可综合。

现有 dirty patch 可核对移除位置，成功运行版本为 DC V-2023.12-SP5；此前失败运行的具体错误码、原始日志和最小复现尚未纳入本归档。这里只记录本次环境的实际处理，不据此断言所有 DC 版本均不支持这两条指令，也不预判报错根因。

`` `default_nettype none `` 用于禁止隐式网络，`` `default_nettype wire `` 恢复默认网络类型；它们不是功能逻辑。移除后不能再依赖这些指令发现未声明或拼错的网络名称，也不能仅凭综合成功证明实现等价。正式基线前应整理失败证据及长期兼容方案，对最终输入补做 lint/隐式网络检查和相关功能回归，并固定对应源版本；本次综合结果不替代该验证。

## 2. 指标与主要问题

| 指标 | DC 结果 |
| --- | ---: |
| Total cell area | 35080.415848 `library_area` |
| 组合 / 时序面积 | 28749.335966 / 6331.079882 |
| 叶子 / 时序单元数 | 23835 / 2021 |
| Setup critical slack | −7.29 ns |
| Setup TNS / violating paths | −9958.09 ns / 1807，DC QoR 原始口径 |
| Hold worst violation / total / count | −0.03 ns / −0.24 ns / 19，按报告精度 |
| Max transition / capacitance 违例 | 0 / 0 |

依据：[area](reports/area.rpt)、[qor](reports/qor.rpt)。DC QoR 末尾也用正数表示违例幅度，不能把该行的 `WNS: 7.29` 误读为正 slack。此处路径数/TNS 不冒充 PT 的去重端点统计；层次面积不能把父子项重复求和。`Total area: undefined` 与零 net-area 模型相关，不否定有效的 cell area，也不提供芯片面积。

### 组合除法/取余是主要面积与时序问题

ALU 为 22706.208，占全核约 64.7%；四套有符号/无符号 div/rem 共 14178.696，占约 40.4%；两套乘法共 6999.888，占约 20.0%。GPR 占 17.5%，arbiter 占 1.7%。[资源报告](reports/resources.rpt) 表明 div/divu/rem/remu 分别实现，没有合成一个共享商余数单元。

最差路径为 `opbuf data_q_reg_146_ → 操作数选择 → rem_80 → ALU 结果选择 → commit_is_mmio`。取余模块出口约 15.04 ns，总到达 15.09 ns，要求时间 `10 − 0.2 − 2 = 7.8 ns`，slack −7.29 ns；QoR 记录 705 级逻辑。[max 原始报告](reports/timing_max.rpt)

这是真实组合实现和当前约束下的结果，不是“28 nm 工具测错”。后续优先评估共享商/余数、多周期迭代 M 单元、乘法实现与地址/分支运算分离。多周期方案会改变请求/完成、背压、redirect/异常取消以及 CPI；不能只报告频率收益。

### 观察接口影响最差路径，但不是唯一原因

前 20 条 max 路径终点均是 commit 输出。共用的 ALU 结果还连接地址、MMIO、异常和 redirect 逻辑，可能产生需要审查控制相关性的路径。正式接口应说明哪些信号是芯片功能输出、哪些仅服务仿真观察，以及它们的采样周期和有效条件。

但 [constraints](reports/constraints.rpt) 中内部 opbuf 寄存器端点已有 −5.83 ns setup 违例；裁去观察端口不能据此宣称 core 达到 100 MHz。若更改观察范围/增加寄存器/拆分地址计算，必须以新配置和 run 比较。未经功能可达性证明，不能把经过除法的地址/异常路径直接声明为 false path。

### Hold 与约束/结构告警仍需处理

[min 报告](reports/timing_min.rpt) 的最差路径为 opbuf 寄存器 Q 经保持 MUX 返回自身 D：到达约 0.12 ns，hold 加 uncertainty 要求约 0.15 ns。降低频率不解决这类短路径问题，需用 PT 复核并决定修复方式；部分标为 VIOLATED 的 `0.00` 是打印精度不足。

本 run 未触发未映射叶子或非预期 latch 的失败检查；[check_timing](reports/check_timing.rpt) 未报告环/未约束端点，但尚无 PT coverage。综合后仍有 62 个 unloaded inputs、483 个 unconnected ports、426 个 unloaded nets、26 个同一单元多引脚共网告警，详见 [check_design_post](reports/check_design_post.rpt)，不能视为已完成 waiver。

[日志](logs/syn.log) 另有 ALU signed→unsigned（VER-318）、case default 不可达（ELAB-311）、命名规则（UCN-4）、重复读库（DDB-24）、时钟高扇出（TIM-134）告警。高扇出时钟连接 2021 个时序单元，当前没有 CTS；需逐类判断语义和模型影响，不批量关闭告警。

## 3. 正式基线前的处理顺序

1. 冻结本记录，保留原始失败证据。可对旧网表补做 PT 作为诊断，结果仍属于本实验，不能改称正式基线。
2. 审查观察/功能输出、实际采样契约、地址/异常相关路径，确定正式评估 scope 与 SDC；定义预期算术延迟和架构边界。
3. 对长组合 M 运算、共享数据通路等明显问题形成独立改动与对照实验；保留面积、时序及周期/CPI 代价。先处理实现合理性，再冻结用于后续细化优化的基线。
4. 整理源版本/工具兼容改动，完成受影响的定向、DiffTest/系统回归；审查 signed/width、warning 与例外。
5. 新建 run 执行 DC + PT，核对四类路径、setup/hold/DRV、coverage、实际模型与单位，再建立正式 S3 基线。

“数百 MHz”可作为后续设计目标，但当前没有依据将其作为 TSMC 28 nm 的必达门槛。正式基线的目标应在实验前明确；目标不满足时继续记录失败和原因，不靠收窄报告或换松约束宣称通过。当前未评估功耗，因此不能要求或声称完整 PPA 已处于正常范围。

## 4. 归档范围

原始报告、日志、manifest、实际配置/约束和 dirty patch 均按字节复制，清单与 hash 见 [archive.json](archive.json)。保留面积、QoR、资源/引用、max/min、全部约束违例、综合前后结构检查、时序检查、design 模型、版本与功耗关闭状态；没有改写或裁短原始路径报告。

未复制 DB/完整库报告、网表/DDC 和完整 RTL/flow 输入快照；原 manifest 保留其相应 hash/路径。审阅本记录不依赖原 build 目录，重新执行则需要恢复原始输入、匹配工具/工艺库及相应运行环境。尚无 PT、功耗或新功能回归结果。
