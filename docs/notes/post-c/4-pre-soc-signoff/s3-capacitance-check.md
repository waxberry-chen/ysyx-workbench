# S3：对照 DC/PT 的 LSU 使能网络电容

2026-10-18。`core-tt-5ns-no-port-buffers` 中原 66 条 min-capacitance 不再出现，但 PT 报告 `core/u_lsu/U13/ZN` 的 max-capacitance：required 0.084770 pF、actual 0.088724 pF，超出约 4.66%；DC 同次报告无约束违例。

原网表的 U13 是 INVD1，输出 n3 实现 `req_valid & req_ready`，直接驱动 54 个请求寄存器 E 引脚（32 个地址、22 个写数据）及一个 buffer 输入，后者驱动另一使能分支。这是驱动负载问题的候选，不是状态机功能错误的证据。

## 1. 本次只补报告

新增 [共享诊断 Tcl](../../../../npc/flow/01_common/capacitance.tcl)，由 DC 综合完成后、PT 更新时序后调用。没有改 RTL、SDC、扇出/电容限制、CCS 设置、综合策略或驱动尺寸。本次不预先采用 `set_max_fanout 32`。

两个阶段分别输出：

```text
reports/syn/checks/lsu_enable_capacitance.rpt
reports/sta/checks/lsu_enable_capacitance.rpt
```

它们进入必需产物检查及 manifest 的递归 hash。发现报告缺失、为空或核心命令错误，不能把该阶段当作完整执行。

## 2. 如何定位及记录哪些内容

从 `core/u_lsu/req_*_q_reg*/E` 实际引脚反查网络，覆盖地址、写数据、类型和写使能寄存器。按网络去重后分别报告，因此包含 buffer 后的使能分支，不绑定 U13/n3。

| 报告字段 | 用途 |
| --- | --- |
| stage/tool_version/library/configured_capacitance_unit | 确认工具、库与单位；单位同时对照 environment 报告 |
| report_capacitance_use_ccs_receiver_model | 工具暴露该变量时，记录 CCS receiver 电容报告策略；不修改变量 |
| timing_max_capacitance_derate | 记录可见的最大电容限制缩放设置 |
| enable_pin_count、anchor、enable_net_count | 确认匹配范围与分支；网络名变化时可用对应寄存器 E pin 对齐两阶段 |
| NET / report_net 原始输出 | 驱动与负载连接、工具报告的网络电容；作为比较计算结果的主要证据 |
| 网络可用属性 | wire/total capacitance 的 min/max；不存在时明确写 UNAVAILABLE |
| PIN 的方向、reference 和可用属性 | 列出每个实际连接，记录设计 pin 的电容限制及可用 CCS total capacitance 属性 |
| direct_output/input_pin_count | 当前网络的直接驱动/负载 pin 数，不穿透 buffer 合并计数，也不等于库 fanout_load 之和 |
| LIB_PIN 的方向、电容和 min/max capacitance | 对照驱动 pin 的库限制和接收 pin 的库输入电容，同类型库引脚去重打印 |

库 `capacitance` 是库 pin 属性，不能直接当作该实例在 CCS 模型下的有效负载；库 `max_capacitance` 也不能自动替代工具最终采用的有效限制。需联合原始 `report_net` 和 `constraint_violations.rpt` 判断。

不同版本/对象不一定暴露全部属性：可选属性查询没有值时打印 UNAVAILABLE，不当作零，不由 mock 填充“真实数据”。若请求寄存器被映射为 DFF + mux、改名或展开，可能找不到 E pin；报告会明确写 `NPC_CAP_NO_ENABLE_PINS` 并要求审查网表，不声称电容正常。

当前定位依赖 LSU 请求寄存器的 RTL 派生名及库的 E pin 命名，适用于此次问题。它不是通用全芯片违例定位器；顶层结构或映射类型变化时需调整选择范围。

## 3. 服务器执行与比较顺序

用户同步新脚本后，在工程根目录运行：

```bash
make -C npc/flow check test
make -C npc/flow all SITE=00_indata/configs/site.local.tcl RUN_ID=core-tt-5ns-cap-diagnostic
make -C npc/flow inspect RUN=build/core-tt-5ns-cap-diagnostic
```

使用新 RUN_ID，不编辑旧 run 的冻结输入。先检查两份新报告均生成且命中预期 E 引脚，再依次比较：

1. 同一寄存器组是否连接同一组驱动/分支，直接负载数是否一致。
2. 驱动 reference、库最大电容与工具有效要求是否一致。
3. 总负载、线电容、库输入电容和可用 CCS 电容属性是否一致。
4. 单位、模型开关及环境设置是否解释差异；不能看到 CCS 库名就直接断定原因。

PT L-2016.06 正文 9-7 / PDF 309 说明 CCS receiver 模型会影响电容报告，且不同工具可能不一致。此处是调查依据，不是本次差异的既定结论。若新增命令/属性在服务器不支持，保留报告/log 中的具体信息继续定位；本地没有实际 DC/PT。

数据充分后再选择修复：例如综合阶段采用合理的 fanout 控制促使负载分组、增强驱动，或处理具体模型差异。不能通过关闭检查、放宽库限制或把数据使能设为 false path 来消除告警。所有修复都需重看 max/min timing、其他电气违例和面积。

## 4. 本地验证与范围

`make -C npc/flow check test`：42 项通过。真实 Tcl + mock 验证两个阶段均能追踪改名后的驱动和两条使能分支、共享网络去重、库限制和缺失属性表达；另覆盖没有 E pin、核心报告命令失败、报告缺失/错误及产物追溯。

mock 数值只用于检查脚本，不是 NPC 的新测量。本次没有重新综合或运行 PT，也没有关闭当前 max-capacitance 违例。reset 时序继续遵循 [已有 deferred 范围](reset-timing-todo.md)，并保留全部 coverage 供审查。

## 5. 诊断返回与局部修复实验

本节保留第一版修复的计划与假设；后续实测未生效，原因和当前方案见 §6。

服务器于 2026-10-18 23:15–23:16 重跑并返回同名 `core-tt-5ns-no-port-buffers`，manifest HEAD 为 `23e87ac290e5693832a074bf3ed6a6ef8c940639`。新增诊断已正常生成；下面是该次返回事实，不是后续修复的结果：

- DC/PT 的 68 个 E pin → net 对应关系相同：n2 有 14 个直接负载，n3 有 55 个（54 个 E pin + U3/I）。
- n3 的 min/max 总电容两边均为 0.0800439/0.0887239 pF，线电容均为零，U13/ZN 的库上限均为 0.084770 pF。两边 `report_capacitance_use_ccs_receiver_model` 均为 true。
- DC `report_constraint` 无违例；PT 仍有一条 max-capacitance，actual 0.088724 pF，slack −0.003954 pF。setup/hold 最差 slack 为 +0.513496/+0.008754 ns，cell area 为 9230.759940（沿用库面积口径）。原 66 条 min-capacitance 未再出现。
- 用 DC 库 pin 的标量 capacitance 估算：`54 × 0.001542 + 0.001111 ≈ 0.084379 pF`，低于上限；用 rise 输入电容累加约为 0.088724 pF，与 PT 违例值吻合。这是 DC 检查口径不同的线索，尚不能证明其内部算法；可选 CCS 属性 UNAVAILABLE 也不是零。

现在可直接进行负载修复实验，不必先穷尽工具内部差异。修改 [DC 入口](../../../../npc/flow/02_syn/run.tcl)，在 compile 前对 `core/u_lsu` 引用的 **design** 设置 `set_max_capacitance 0.075`。这是 LSU 全部内部网络的综合目标，不是只约束 n3；其他模块没有新增此目标。通过 RTL 实例名解析 design，找不到唯一对象就停止，不绑定映射后的 U13 或具体库驱动型号。

0.075 pF 比本次违例驱动的库上限低约 11.5%，为此次约 5.2% 的标量/rise 电容差异留出额外空间。它是基于当前库和负载的实验裕量，不是通用工艺值，也不保证其他驱动/负载组合自动通过。依据 DC P-2019.03 正文 8-8，design 约束与库约束并存时取较严格者；由 compile 自行决定缓冲、负载分组或单元选择。

原计划让这个目标只用于 DC 优化并保存在其数据库/导出约束中；后续实测导出 SDC 没有保留该目标（见 §6）。PT 继续重放原始 SDC 并检查原库规则。没有修改 RTL、CCS 开关、reset 例外或库限制。另在 DC 诊断中增加 `report_net -max_capacitance`（手册正文 8-9），尝试查看约束计算明细；实际版本的输出格式与旧手册示例不同（见 §6）。

同步后用新 run 保留对照：

```bash
make -C npc/flow all SITE=00_indata/configs/site.local.tcl RUN_ID=core-tt-5ns-lsu-cap-margin
make -C npc/flow inspect RUN=build/core-tt-5ns-lsu-cap-margin
```

验收时检查 DC log 的 `NPC_SYN_POLICY` 记录、LSU 使能分支/负载是否变化，以及 PT 全部 max/min 电容、电气规则和 setup/hold 是否满足。比较面积、critical path 与 coverage；不能仅凭旧 U13 名字不再出现就宣布修复。reset deferred 和常量导致的 untested 仍按既有规则审查。

本地 `make -C npc/flow check test` 共 43 项通过，验证配置/SDC 和 Tcl 控制流；mock 检查裕量仅施加到 DC 的 LSU design、先于 compile、目标缺失时停止，并检查 DC 专用电容报告不进入 PT。实际修复效果待服务器 DC/PT，S3 暂不标记通过。


## 6. 局部裕量未生效与顶层作用域修正

本节的顶层电容目标是中间方案；尚未收到对应服务器结果，现按用户决定由 §7 的 fanout 策略替代。

2026-10-18 23:27–23:29，用户再次返回同名 run，manifest HEAD 为 `e3ea746a77aca522539f7f0103df88f16ff4739f`。37 个输入及 DC/PT 的 23/25 个产物 hash 核对通过，快照 DC 脚本与本次修正前工作区一致；log 第 528 行确实执行了 `NPC_SYN_POLICY: LSU design ysyx_lsu max_capacitance=0.075 pF`。同步、脚本选择没有问题。

然而 `outputs/dc.sdc` 没有导出 `set_max_capacitance`，n3 仍有 55 个负载，PT 仍为 0.084770/0.088724 pF，面积和最差 setup/hold slack 与上次记录一致。这次失败应先归因于**约束作用域不适合当前 top-down compile**，而不是把裕量继续调小。

DC P-2019.03 正文 10-8–10-9 说明顶层约束驱动层次综合；10-12 明确指出顶层 compile 后不保留子 design 约束。先前把属性赋给 `ysyx_lsu` design 并打印成功消息，不能证明顶层综合使用了该约束。旧 mock 只核对赋值对象和调用顺序，没有模拟 DC 的层次约束行为，因此 43 项通过也未证明修复有效。上一版将局部目标会被保留视作既定事实，是脚本设计判断错误。

修正为：

```tcl
set_max_capacitance 0.075 [current_design]
```

此时 current_design 必须为 `ysyx_core_axi4lite`，目标覆盖整个 core。该方案保留现有一次顶层 compile 流程；不单独综合 LSU，不冻结单元，不引入块级时序预算。代价是可能改变 LSU 以外的单元、缓冲和面积，必须重新比较 PPA。它仍是 DC 优化裕量，PT 不放宽原库检查。

新增 `check_syn_cap_margin` 在 compile 前后从顶层读取 `max_capacitance`，缺失或变化则停止，成功时记录 `NPC_SYN_CAP_MARGIN: pre_compile/post_compile ... actual=0.075 pF`。属性保留只能证明目标存在，不能证明优化已达标；仍须检查 DC 违例报告及 PT。

同时纠正报告解释：DC V-2023.12-SP5 的 `report_net -max_capacitance` 实测显示 `Load/LoadUR/LoadUF/LoadLR/LoadLF` 等列，保留两位小数，并未输出旧手册示例中的 Required/Actual/Slack。不能据此宣称已查明 DC 的精确 DRC 实际值。该视图继续保存，但不作为修复成功判据。

本地 `make -C npc/flow check test`：43 项通过。mock 改为检查顶层目标和实际属性读回，新增 compile 后属性丢失的失败注入；这仍是控制流验证，不能代替服务器优化和 STA。

建议服务器新 run：

```bash
make -C npc/flow all SITE=00_indata/configs/site.local.tcl RUN_ID=core-tt-5ns-top-cap-margin
make -C npc/flow inspect RUN=build/core-tt-5ns-top-cap-margin
```

核对 pre/post 属性读回、导出 SDC 中的顶层 max-capacitance、DC/PT 违例、LSU 分支连接、全 core 面积/时序变化及 coverage。原 run 留作失败对照，S3 继续待验收。


## 7. 改用 max_fanout 32 并排除时钟 DRC 修复

用户希望优先通过 fanout 分组解决 LSU 使能网络的集中负载，避免额外的统一电容上限影响可正常驱动较大负载的单元。当前 DC 脚本撤去 0.075 pF 目标，改为：

```tcl
set_max_fanout 32 [current_design]
set_auto_disable_drc_nets -on_clock_network true
```

参考依据不只是后端脚本：[C906 公共 SDC](../../../../npc/ref-flow/00_indata/SDC/C906_TOP.sdc) 第 34 行设置 `MAX_FANOUT 32`、第 84 行施加到 current_design；[C906 综合入口](../../../../npc/ref-flow/04_syn/c906-project/01_flow/05_run_compile.tcl) 第 18 行还用 `set_ideal_network [all_fanout -flat -clock_tree -levels 0]` 标记时钟网络。NPC 采用显式关闭 clock DRC 修复的方式，不复制其 gating 或其他综合设置。

时钟的两层处理应分开理解：

- **时序模型**：现有共享 SDC 创建 core_clk，保留 ideal clock、指定 clock transition/uncertainty/source latency；没有真实时钟树或 propagated clock。
- **综合修复策略**：`set_auto_disable_drc_nets -on_clock_network true` 禁止 DC 为时钟网络修复包括 max-fanout 在内的 DRC，避免按数据网络目标给 clock 插缓冲。它不会改变 clock 的 ideal/propagated 时序属性。依据 DC P-2019.03 正文 8-13–8-14；手册推荐该选项以覆盖完整时钟网络，而不是仅依赖默认的旧 `-clock` 行为。

当前 RTL 只有直接分发的 clk，没有时钟门控/mux。compile 前后要求顶层 `max_fanout=32` 保留；clk 源网络的 `auto_disable_drc_nets` 仅作可选查询，当前 DC 实测不暴露该属性时写 UNAVAILABLE（见 §8），不能视作保护已验证。若属性可读且为 false，仍停止；同样信息写入 `checks/high_fanout.rpt`。这是对当前结构的验证，未来增加 clock gating/mux 后还需核查整条时钟网络；CTS/后端阶段应按实际时钟树流程重新设置，不能把早期排除当作物理时钟验收。

DC 手册 8-6–8-7 规定，fanout 是接收端库 `fanout_load` 的总和；32 不是未经核查的 32 个引脚保证。诊断报告新增 library 的 `default_fanout_load` 和各库 pin 的 `fanout_load`，供服务器核对实际权重。UNAVAILABLE 不代表 0 或 1；本地没有用 mock 权重推断真实库值。

该目标作用于整个 core 的普通网络，可能改变 reset 和其他高扇出控制信号的缓冲/面积。reset false path 只排除既定时序路径，不将 reset 理想化，也不豁免其 DRC。数据/控制网络继续检查库 max/min capacitance、transition 等规则。`high_fanout_net_threshold=1000` 是工具报告/建模阈值，不是新设的 `max_fanout=32` 优化规则；不能要求原高扇出报告列出所有超过 32 的网络，需同时看 DC constraint 报告。

本地 `make -C npc/flow check test`：43 项通过，包括顶层 fanout 读回、compile 后 fanout 或 clock DRC 保护丢失时拒绝交付、DC 专用策略不进入 PT，以及非单位 fanout_load 的报告表达。本地测试不证明服务器已分组或 PT 电容已满足。

同步后运行：

```bash
make -C npc/flow all SITE=00_indata/configs/site.local.tcl RUN_ID=core-tt-5ns-fanout32
make -C npc/flow inspect RUN=build/core-tt-5ns-fanout32
```

验收：核对 pre/post `NPC_SYN_FANOUT` 和 `NPC_SYN_CLOCK_DRC`、实际库 fanout 权重、LSU 分支驱动/负载、DC fanout 与所有电气违例、PT max/min capacitance 和 setup/hold、面积与 coverage；检查没有因数据 fanout 目标创建时钟缓冲树。S3 仍待真实结果。


## 8. 修正 clock DRC 属性查询的版本兼容问题

服务器报告 `UID-101: Attribute 'auto_disable_drc_nets' does not exist on net 'clk'`，随后脚本在 pre_compile 停止。这来自新增检查，并不是 max_fanout 32 不合法，也不能据此认定 `set_auto_disable_drc_nets -on_clock_network true` 执行失败。旧手册描述了该内部属性，但不能保证服务器版本允许通过 get_attribute 查询；之前的 mock 固定返回 true，掩盖了这项兼容问题。

保留 fanout 目标和 clock DRC 设置命令。对该属性使用 `get_attribute -quiet` 可选查询：抛查询异常或返回空值时输出 `UNAVAILABLE; review clock connectivity`，继续综合；有效 false 或非空非法值仍拒绝继续。命令本身的错误、顶层 max_fanout 丢失、clock source net 缺失仍是硬失败，未扩大任何 DRC 豁免。

日志另行记录 requested policy，区分“已发出设置命令”和“属性读回验证”。不得把 UNAVAILABLE 写成 true 或声称时钟保护已证实；需结合综合网表与 high_fanout 连接报告确认时钟没有因 fanout 目标插入缓冲。当前不引入未经服务器确认的替代查询命令。

本地 `make -C npc/flow check test` 共 44 项通过。默认 mock 改为重现服务器属性不可用，另覆盖命令本身失败、可读 false、fanout 丢失；实际 DC/PT 结果仍待服务器。建议新 RUN_ID `core-tt-5ns-fanout32-v2`，保留本次失败 run 的日志。
