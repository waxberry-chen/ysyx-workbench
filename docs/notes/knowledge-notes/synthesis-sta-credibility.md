# 综合 / STA 可信度评估：依据、检查命令与 synth 03 实例

2026-10-18。适用于回顾 pre-layout RTL 面积与时序评估的方法。本文以 NPC 的普通 DC 综合 + PT STA 为例，不把单角、ideal clock、ZeroWireload 结果当作物理实现 sign-off。

后续范围决定（2026-10-18）：用户已选择在下一次早期 run 中对 rst_n 设置 false path，将 reset 时序登记为 deferred，见 [reset TODO](../post-c/4-pre-soc-signoff/reset-timing-todo.md)。这不改写本文 synth 03 的事实，也不代表脉宽验证通过；本次决定属于明确的评估范围调整。

## 1. “分析可信”与“设计达标”是两件事

**先确认分析对象和约束正确，再确认检查充分，最后判断约束是否满足；功能正确性需要另外的验证证据。**

| 层次 | 要回答的问题 | 主要依据 |
| --- | --- | --- |
| 功能正确 | RTL 是否符合预期？综合前后是否保持功能？ | RTL 定向测试/系统回归；综合前后等价检查等独立证据 |
| 分析可信 | 是否分析了正确的网表，模型与约束是否合理，检查是否充分？ | 输入追溯、link、结构检查、check_timing、coverage、例外和禁用弧审查 |
| 约束满足 | 当前模型下是否达到时序、电气及其他目标？ | report_constraint、具体路径、指标和有依据的豁免 |

正确发现负 slack 的 STA 可以是一份可信的失败实验；反过来，漏设时钟或错误排除路径后得到“零违例”，不能证明分析可信。`COMPLETE` 只说明执行完成，不能直接写成 `PASS`。

DC/PT 报告本身不能证明功能等价。当前 M4 没有执行完整的综合前后等价验证或 GLS，相关边界必须保留，不能用 setup/hold 满足替代它们。

## 2. 正式基线的评估依据

以下编号用于后面的 synth 03 对照。基线可以记录未达标数据用于诊断；若要声明“满足既定目标的正式基线”，还需完成相应验收。

| 编号 | 依据 | 需要确认什么 |
| --- | --- | --- |
| C1 | 输入、执行与产物可追溯 | RTL/宏/top/scope、源版本与 dirty 状态、工具/库/PVT/单位、SDC 和网表一致；日志、完成标记、报告与输入输出 hash 可核对 |
| C2 | 设计结构有解释 | 无未解析引用、非预期 black box/latch、多驱动、未驱动及组合环；未连接端口、常量裁剪、无负载网络等告警逐类审查 |
| C3 | 模型与约束符合接口意图 | 时钟、I/O max/min、slew/load、uncertainty、reset 契约有来源；明确 WLM/寄生及 ideal/propagated clock；无未解释的未约束功能端点 |
| C4 | 检查覆盖与例外有依据 | 无未经解释的 untested；false path、case analysis、禁用弧明确对象/模式/理由，必要时由其他验证补足 |
| C5 | 目标约束满足 | 无未处理、未批准豁免的时序/电气/其他约束违例；不能只看 setup WNS |
| C6 | 指标与结论可比较 | 面积/时序范围和单位明确，关键路径可解释；不由 Top-N 报告推导全量统计，不混比不同 ISA/scope，不超出模型声明频率 |

两个核心出口是：**没有未处理的约束违例；没有未经解释的未测试项。** 但它们必须建立在 C1–C3 的可信输入和合理约束之上。

不要求机械地消灭所有 warning 或把 coverage 改成 100%。若某项确实不适用，应留下：对象/数量、适用模式、技术依据、替代验证或为何无需验证、审查结论及重新审查的触发条件。解释了原因，不等于已经完成验收或批准豁免。

## 3. DC/PT 命令分别回答什么

下表的“当前 flow”指撰写时 NPC 的 [DC 脚本](../../../npc/flow/02_syn/run.tcl)、[PT 脚本](../../../npc/flow/03_sta/run.tcl) 与 [共享配置](../../../npc/flow/01_common/setup.tcl)。命令依赖已经正确加载设计、库和约束；不同工具及版本的选项不能照搬。

| 目的 | 命令 / 方法 | 当前 flow 与边界 |
| --- | --- | --- |
| 分析与解析设计 | DC：`analyze`、`elaborate`、`link`；PT：`read_verilog`、`link_design` | 已执行；解析成功不代表功能正确 |
| 检查结构 | DC：`check_design` | 综合前后各一次；保留报告并审查 warning，不只看返回值 |
| 检查未映射单元、latch | DC：`get_cells` 配合 `is_unmapped` 过滤；`all_registers -level_sensitive` | 当前 flow 显式拒绝未映射叶单元和非预期 latch |
| 确认模型 | `report_lib`、`report_design`；PT 另有 `report_units`、`report_wire_load` | 已保存；完整库报告不一定展开每个 pin 的全部属性 |
| 确认时钟和接口预算 | 核对 SDC；PT 可补 `report_clock`、`report_port -input_delay`、`report_port -output_delay` | SDC 已冻结；这里列出的补充报告尚未全部接入 flow |
| 检查分析设置 | DC：`check_timing`；PT：`check_timing -verbose` | 已保存；查缺失/异常设置，不能证明约束符合真实系统，也不能替代 coverage |
| 更新 PT 分析 | PT：`update_timing` | 在读网表、link、施加约束后执行；报告命令用于查看分析结果 |
| 查看约束满足情况 | DC/PT：`report_constraint` | 已用 `-all_violators` 保存完整违例报告，含电气与时序约束 |
| 查看具体时序路径 | DC/PT：`report_timing` | 已保存 max/min；PT 另分 Reg2Reg、In2Reg、Reg2Out、In2Out |
| 查看时序检查覆盖 | PT：`report_analysis_coverage` | 已保存汇总及 untested 明细；不是 RTL 仿真覆盖率 |
| 解释禁用时序弧 | PT：`report_disable_timing` | 已保存；用于定位 PTE-003，不能只根据 warning 文本判断存在组合环 |
| 审查时序例外 | PT：`report_exceptions`，结合 SDC 和匹配对象 | 补充诊断方法，尚未作为当前 flow 的独立报告；不能只由 coverage 推断例外正确 |
| 查看脉宽细节 | PT：`report_min_pulse_width` | 手册支持的补充诊断，尚未加入当前 flow；不会自动补齐缺失波形信息 |
| 定位高扇出对象 | DC：`all_high_fanout -nets`、`report_net -connections -verbose` | 已保存阈值、网络及连接；阈值告警本身不等于约束违例 |
| 核对面积和实现结构 | DC：`report_area -hierarchy`、`report_qor`、`report_resources -hierarchy`、`report_reference -hierarchy` | 已保存；cell area 不等于芯片面积，资源是否被意外裁掉也需审查 |
| 追溯与执行完整性 | flow driver 的版本/输入输出 hash、日志和必需产物检查 | 不是某一条 EDA 命令能完成的工作；退出码为 0 不自动代表成功或达标 |

工具发现的问题通常要联合解释。例如 `check_design` 的无负载网络、`report_constraint` 的最小电容违例、网表中的悬空输出，可能指向同一个实现问题。

## 4. report_constraint 的检查范围

它报告当前设计中适用约束的评价，约束可以来自逻辑库或用户设置。**不是只检查手写 SDC，也不是只检查 setup/hold。**

以下主要按 PT User Guide 的范围整理；某类约束是否存在、可分析及实际输出，取决于设计、库、模式和工具设置。

| 类别 | 检查内容 | 含义 |
| --- | --- | --- |
| 数据时序 | max_delay/setup | 数据是否到达太晚 |
| 数据时序 | min_delay/hold | 数据是否变化太早 |
| 异步控制时序 | recovery/removal | 异步控制释放与有效时钟边沿的关系是否满足要求 |
| 时钟门控 | clock-gating setup/hold | 门控使能是否在要求的时间窗口内稳定 |
| 波形时序 | minimum pulse width | 高/低电平是否持续足够长；库也可在异步控制引脚上定义脉宽检查 |
| 波形时序 | minimum period | 时钟周期是否小于单元允许的最小周期 |
| 特定单元时序 | maximum skew | 相关时钟引脚之间的偏斜是否超限 |
| 电气规则 | min/max capacitance | 驱动网络的负载电容是否在允许范围内 |
| 电气规则 | min/max transition | 引脚转换时间是否在允许范围内 |
| 电气规则 | min/max fanout | fanout load 是否在允许范围内；它可能是库属性之和，不一定等于引脚数量 |
| 设计目标 | maximum area | 已定义面积上限时，面积是否超过限制 |

电气规则常称 DRC/DRV，要与后端线宽、间距等**版图几何 DRC**区分。DC 还可能报告 `multiport_net`、`critical_range` 等综合相关项目；不能假定同名命令在 DC/PT 中的全部行为相同。

```tcl
# DC/PT：默认摘要，通常不是逐条列出全部违例。
report_constraint

# 当前 flow：列出违例对象，提高精度，避免长对象名换行。
report_constraint -all_violators -significant_digits 6 -nosplit

# 按类别定位。
report_constraint -min_capacitance -all_violators -significant_digits 6 -nosplit
report_constraint -max_transition -all_violators -significant_digits 6 -nosplit
```

`set_min_capacitance` 等命令是**设置要求**，`report_constraint` 是查看评价。库已有要求时，无需为了“开启检查”而重复设置。

## 5. coverage、false path 与具体路径报告

### 5.1 三种状态与未测试项

| 状态 | 含义 | 不能推导出的结论 |
| --- | --- | --- |
| met | 已分析，满足该项要求 | 不证明所有其他检查都覆盖 |
| violated | 已分析，不满足该项要求 | 不表示分析工具执行失败 |
| untested | 未得到该项满足/违反的评价 | 既不能算通过，也不能直接算时序违例 |

```tcl
# PT：先看全局，再读未测试项的 pin、check type、condition、reason。
report_analysis_coverage
report_analysis_coverage -status_details {untested}

# 可按类型继续定位。
report_analysis_coverage -status_details {untested} -check_type {setup}

# 补充脉宽诊断：只看 all_violators 不能代替 untested 审查。
report_min_pulse_width
report_min_pulse_width -all_violators
```

`check_timing` 成功和 coverage 存在 untested 可以同时发生。库或约束中根本没有建立的检查，也不应指望自动出现在 untested 列表中；仍需对照接口要求核对 C3。

### 5.2 false path 会不会成为 untested

**会有这种可能。** False path、禁用弧、case analysis 都可能让 timing check 不再被测试。coverage 统计的是检查项，不是每一条逻辑路径：同一端点只有部分路径被排除、其他路径仍接受检查时，不能期待每条 false path 都对应一条独立 untested 记录。

因此需要同时审查例外本身：理由是否成立、对象匹配是否准确、setup/hold 或特定边沿的作用范围是否正确、是否误排正常路径，以及是否需要其他模式或独立验证覆盖。`report_disable_timing` 用于禁用弧，`report_exceptions` 用于时序例外；两者不能互相完全替代。

不要为了消除负 slack 或提高 coverage 而添加 false path。比如复位脉宽没有被分析，给 reset 加 false path 不会证明脉宽足够，反而可能排除需要保留的 recovery/removal。

### 5.3 Top-N 路径与 WNS 的边界

```tcl
# PT 代表路径：显式包含正 slack；这里只限制展示数量。
report_timing -delay_type max -slack_lesser_than 1.0e30 \
    -max_paths 20 -significant_digits 6 -nosplit
report_timing -delay_type min -slack_lesser_than 1.0e30 \
    -max_paths 20 -significant_digits 6 -nosplit
```

本项目 PT 的多路径报告若不显式包含正 slack，全部满足时可能只打印“没有负 slack 路径”。这不代表没有关键路径。上述大阈值只控制显示，不修改 SDC。

当前 flow 的 WNS/TNS 是通过独立负 slack 端点查询计算的，不能从 Top-20 报告相加获得。WNS 无违例时归零，不能表示实际最差 slack 为 0。Reg2Reg 等四类路径便于解释内部/接口限制，但限定到 D pin 的分类也不能替代全局 recovery/removal 和 coverage。

## 6. 推荐审阅顺序

1. 核对 run 的 top/scope、输入版本、库/PVT/单位、时钟及互连模型，检查完整日志、执行状态和产物 hash。
2. 确认 link、映射和结构；审查未连接、未驱动、latch、常量裁剪及禁用弧。
3. 核对 SDC 的接口含义和实际对象，读 `check_timing`。
4. 读 coverage 和 untested 明细，检查模式、例外及未约束范围。
5. 读 `report_constraint`，区分时序与电气问题；再用具体路径、网络连接或库属性解释。
6. 阅读全局及分类的 max/min 路径、面积与资源，确认指标能支持结论。
7. 记录“已确认”“待查”“有依据的豁免”和“模型限制”；处理问题后用新 run 验证，不覆盖历史失败证据。

## 7. 实例：synth 03 为什么还只是基线候选

### 7.1 实验范围与结果

原 run 为 `npc/flow/build/core-tt-5ns-baseline`，完整审阅见 [03 归档](../post-c/4-pre-soc-signoff/synthesis-results/03-200mhz-candidate/README.md)。原始报告和追溯信息已长期保存，以下链接指向归档，不依赖临时 build 目录。

- Top 为 `ysyx_core_axi4lite`：Core + IFU/LSU adapters + Arbiter，保留观察输出，不含 SRAM/Xbar/外设；16 GPR、无 M/C。
- DC V-2023.12-SP5 / PT T-2022.03-SP5；TT 0.9 V、25°C；5 ns / 200 MHz；ideal clock、ZeroWireload、无 SPEF。
- Cell area 为 9511.319905 library_area；PT 最差 setup/hold slack 为 +0.531597/+0.013534 ns，内部 Reg2Reg setup 为 +1.600592 ns。
- DC/PT 执行均 COMPLETE；DC 为 REVIEW_REQUIRED，PT 为 CONSTRAINT_FAIL。功耗未评估。
- 原 run 的 36 项输入、22 项 syn 产物和 24 项 sta 产物 hash 核验一致；这支持 C1，但不代替功能等价或服务器 DB 的重新核验。

### 7.2 问题一：66 条最小电容违例

**不符合哪项：C5 的电气约束未满足；关联的结构清理也属于 C2 待审查范围。**

现象见 [constraint_violations.rpt](../post-c/4-pre-soc-signoff/synthesis-results/03-200mhz-candidate/reports/sta/checks/constraint_violations.rpt)：

```text
min_capacitance
Pin                  Required     Actual       Slack
core/u_exu/U4/Z       0.000410     0.000000    -0.000410 (VIOLATED)
```

单位为 pF，Required 为工具采用的有效下限 0.410 fF；Actual 为计算负载，Slack = Actual − Required。这是电气负载检查，不是 setup/hold slack。

定位过程为：`report_constraint` 找到 pin → 沿层次进入映射网表 → 读取 `.pin(net)` → 追踪父层负载 → 对照 RTL 的宏和位处理。方法详见 [网表阅读笔记](netlist-and-timing-report-navigation.md)。全部对象都是 EXU 内的 `BUFFD1BWP12T40P140` 输出 Z：

| 输出 | 数量 | 已确认的无负载原因 |
| --- | ---: | --- |
| EXU `commit_pc[31:0]` | 32 | 父层连接到未使用网络；RTL 中相关 `exu_commit_pc` 用于非综合断言，本次配置去掉该用途 |
| EXU `commit_mem_wdata[31:0]` | 32 | DEBUG/断言消费者在本次综合配置下移除 |
| EXU `trap_epc[1:0]` | 2 | CSR 对 EPC 执行 `& 32'hfffffffc`，映射逻辑不使用低两位 |

在当前 ZeroWireload 模型下，这些无接收负载的输出实际电容打印为零。前两项是子模块输出，不能误以为顶层同名观察信号丢失，也不能靠增加顶层 output load 修复。

**为什么会出现：** RTL 的消费者因宏配置/对齐语义消失，但映射结果仍保留输出 buffer。这个连接事实已经确认；具体是哪个综合步骤留下这些 buffer 尚未证明。层次优化、`set_fix_multiple_port_nets -all -buffer_constants` 与最终清理顺序是排查方向，不能直接认定某一条命令就是根因。

Required 的来源也要区分证据层次：当前冻结脚本没有 `set_min_capacitance`，因此指向库侧规则，但现有 `report_lib` 没有展开该 pin 属性。服务器可在加载同一库后进一步查询（此查询尚未实测）：

```tcl
set lp [get_lib_pins \
    tcbn28hpcplusbwp12t40p140tt0p9v25c_ccs/BUFFD1BWP12T40P140/Z]
get_attribute $lp min_capacitance
```

若返回约 0.000410，就直接确认对应属性；若未设置，应继续查适用默认值/工具规则，不能擅自把时序表第一个负载点当作该限制。最小电容要求描述库表征的允许负载下限，Actual 则来自接收引脚、互连及外部负载模型；两者不是同一来源。

后续应定位并消除无用 buffer，重新检查连接和约束；不要虚构负载或用 false path 隐藏问题。DC 本次没有报告这类违例而 PT 有，也需要保留差异；尚未证实具体原因，不能把它仅归结为显示精度，更不能因 DC 干净而忽略 PT。

### 7.3 问题二：5516 项异步清零/置位脉宽未测试

**未关闭哪项：C4 的覆盖审查；同时需要 C3 的复位接口契约。它不是 5516 条已测得的时序违例。**

[Coverage 汇总](../post-c/4-pre-soc-signoff/synthesis-results/03-200mhz-candidate/reports/sta/checks/coverage.rpt) 显示 17852 项检查中 12336 met、0 violated、5516 untested。setup/hold、recovery/removal、out_setup/out_hold 都 met；未测试项全部属于 min_pulse_width。

继续读 [untested 明细](../post-c/4-pre-soc-signoff/synthesis-results/03-200mhz-candidate/reports/sta/checks/coverage_untested.rpt)：

```text
arbiter/prefer_lsu_q_reg/CDN(low)
    min_pulse_width  sdf_cond(CP_D_SDFCHK)  untested  no_clock
```

逐项统计得到 1374 个 CDN（低有效清零）和 5 个 SDN（低有效置位），每个引脚有 4 个条件检查，共 `1379 × 4 = 5516`。它们分布于 GPR、opbuf、arbiter、adapter、CSR 等模块，不是 5516 个独立寄存器。

**为什么会出现：** 库定义了异步控制有效电平的最小宽度要求，而当前 SDC 只给 `rst_n` 设置相对 core clock 的输入延迟，没有描述一次复位从拉低到拉高之间的间隔。PT 缺少评价这些脉宽的波形依据，因而报告 `no_clock`。这不表示 FF 的 CP 引脚没有时钟约束。

| 复位要求 | 要知道什么 | 03 的状态 |
| --- | --- | --- |
| Recovery/removal | 释放边沿与有效时钟边沿的关系 | 在当前输入延迟假设下已检查，满足 |
| Minimum pulse width | 复位保持有效的持续时间 | 未测试 |

下一步应确定外部 reset 最小有效脉宽、库要求及相应验证证据，并声明本轮静态分析边界。功能仿真中“复位保持了若干周期”可以支持上层契约，但不能单独证明实际单元引脚上的模拟脉宽和分布效应。不能给 reset 虚构周期时钟，或直接添加 false path 来制造通过。本记录尚未批准豁免。

### 7.4 告警三：PTE-003 是否表示组合环

**对应 C2/C4：需要查明禁用弧；warning 本身不能判定结构或覆盖失败。**

PTE-003 的通用文字同时提到 loop breaking 和 constant propagation。用 `report_disable_timing` 生成 [明细](../post-c/4-pre-soc-signoff/synthesis-results/03-200mhz-candidate/reports/sta/checks/disable_timing.rpt)，本次 374 条打印记录中有 269 条 `p`（传播常量）和 105 条 `C`（条件弧），没有 `l/L` loop-breaking 标记。

原因是本次列出的常量/条件关系使相应弧不参与分析；不能从通用 warning 推导“存在组合环”。记录数包含重复条件弧，不等于独立路径数。这个疑点已有定位证据，但仍需确认常量裁剪符合设计意图；没有 l/L 也不等于完成所有结构证明。

### 7.5 告警四：高扇出究竟是什么

**对应 C2/C3：需要解释网络及估算模型；不自动构成 C5 违例。**

TIM-134 只报告高扇出数量，不能凭直觉归因。DC 的 `all_high_fanout -nets` 加 `report_net -connections -verbose` 生成 [high_fanout.rpt](../post-c/4-pre-soc-signoff/synthesis-results/03-200mhz-candidate/reports/syn/checks/high_fanout.rpt)，确认阈值为 1000，唯一超阈值对象为 clk，负载 1509。

大量 FF 直接连接同一个逻辑时钟，且本次还没有 CTS，因此产生高扇出提示。报告中的聚合电容 1001 伴随工具高扇出近似，不能当成实际时钟树的 1001 pF。当前 timing 使用 ideal clock；物理时钟分布要在后续 CTS/布线模型下验证，不应调高阈值掩盖告警。

### 7.6 报告完整性与最终判定

02 实验曾缺少正 slack 的 PT 代表路径；03 显式设置报告筛选后，全局及四类路径都有内容，关闭了这个报告缺口。UITE-502 提醒 Top-N 报告达到 `max_paths` 上限，不意味着其余端点都有违例；它也不替代独立的 WNS/TNS 和 coverage。

03 最差 setup 仍到达观察输出 `commit_redirect_reason[0]`；内部路径则经 ALU/redirect、IFQ 与 PC+4 回到 opbuf。两类都要保留，不能只删除观察路径就宣称 core 频率提高。最差 hold 约 13.5 ps，当前满足，不保证 CTS/布线后仍满足。

最终结论是：**03 已提供有追溯和定位证据的 200 MHz 候选结果；电气目标和覆盖/结构审查尚未全部关闭，不能标成正式基线 PASS。** DC 结构报告还含 157 个未连接端口、129 个无负载网络、26 个同单元多引脚共网项，应结合具体连接分类，不把这些 warning 数量直接等同于功能错误数量。

本文记录的是该次实验的诊断状态，没有修改 flow/RTL、执行服务器查询或重跑 EDA，也没有用后续猜测改写原始报告。

## 8. 手册依据与后续查阅

使用 [本工程手册检索入口](../post-c/4-pre-soc-signoff/manual-index.md) 查本地缓存，必要时回到 PDF。下面是已核对的主题位置：

| 主题 | 手册 | 正文页 / PDF 页 |
| --- | --- | --- |
| 最小电容为设计规则、表征下限与约束来源 | DC P-2019.03 | 8-10 / 226 |
| PT 最小电容约束与 report_constraint | PT L-2016.06 | 5-18 / 162 |
| 脉宽检查来自时钟约束或库单元输入要求 | PT L-2016.06 | 8-23 / 293 |
| CCS 对实际负载电容报告的影响 | PT L-2016.06 | 9-7 / 309 |
| PT 多路径报告与正 slack 筛选 | PT L-2016.06 | 17-5 / 637 |
| report_constraint 的范围与默认/违例输出 | PT L-2016.06 | 17-13–17-15 / 645–647 |
| report_min_pulse_width | PT L-2016.06 | 17-19 / 651 |
| coverage、未测试项和 false path 等影响 | PT L-2016.06 | 17-24–17-26 / 656–658 |

手册版本与 03 的服务器工具版本不同。当前脚本已经实测的命令与本文建议补查的命令要分开；具体新增选项和属性仍以对应服务器版本的 `help`/`man` 及实际输出为准。
