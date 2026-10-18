# 从评估指标反推 SDC：首次综合 / STA 的约束设计

本文面向第一次为 RTL 编写 DC/PT 约束的人，也可作为新模型接手工程时的工作指南。目标是在首次综合前，把时序目标、接口环境、电气规则、时钟和 reset 的处理方式准备完整，让工具在明确的条件下优化，并让 STA 检查这些条件。

**“初版写完整”不等于“一次运行就收敛”。** 组合逻辑可能确实太长，负载可能确实太大；合理约束的作用是提前告诉工具目标，并使失败具有明确含义，而不是保证任意 RTL 都能通过。

本文主要适用于普通标准单元综合、单时钟、pre-layout 的 core/block 评估。多时钟、宏单元、DFT、低功耗和布局后分析需要扩展。以 [NPC S3 基线 04](../post-c/4-pre-soc-signoff/synthesis-results/04-200mhz-baseline/README.md)为实例；**不修改该基线，也不把其中的假设当成所有工程的默认值。** 报告验收方法另见[综合 / STA 可信度评估](synthesis-sta-credibility.md)。

## 1. 先理解：约束文件要告诉工具什么

SDC 不只是“设置一个时钟周期”。开始写之前，需要准备四类信息：

| 类别 | 回答的问题 | 例子 | 信息通常来自哪里 |
| --- | --- | --- | --- |
| 功能与时序关系 | 哪个边沿发起，哪个边沿接收，何时必须完成？ | 时钟周期、生成时钟、接口 delay、真正的多周期关系 | 架构、接口协议、时钟方案 |
| 外部环境 | 当前 top 外面怎样驱动、怎样接收？ | 输入 slew / driving cell、输出 load、外部时钟相位 | 上下游模块、IO/封装/板级模型；早期可用明确假设 |
| 工艺库规则 | 单元在哪些负载和边沿范围内允许使用？ | max/min capacitance、max transition、FF 的 setup/hold/pulse width | 当前 corner 的 `.lib` / `.db` |
| 额外优化策略与分析边界 | 希望综合如何组织电路，哪些内容本阶段尚不分析？ | 数据 max fanout、预留裕量、pre-CTS clock DRC 策略、reset 暂缓范围 | 工程目标、实现阶段、已批准的范围决定 |

前两类缺失，工具很难猜对工程环境；第三类往往由库自动提供，**没有手写 `set_max_capacitance` 并不等于没有电容约束**；第四类需要设计者主动决定，不能等出现某条违例才临时补一个让数字变绿的值。

文件也应有边界：共享 SDC 放 DC/PT 都应采用的时序和环境条件；DC 脚本放优化策略；库/PVT/互连模型在 flow 初始化中设置。它们合起来才是完整的分析条件。

## 2. 指标 → 约束 → 参数依据 → 验收证据

下面这张表应在第一版 SDC 之前填写。某项最终不需要新增命令，也应能回答“库已提供”“本设计不适用”或“本阶段明确暂缓”。

| 最终考核项 | 初始阶段需要准备的约束或模型 | 参数如何确定 | 主要检查证据 |
| --- | --- | --- | --- |
| Reg2Reg setup、目标频率 | `create_clock`；setup uncertainty；必要的 clock latency / generated clock | 性能目标、波形、时钟关系和时钟裕量预算 | `report_clock`、max `report_timing`、`report_constraint` |
| Reg2Reg hold | hold uncertainty；真实的早/晚时钟关系；库 hold 检查 | 时钟方案与库；不能靠加长周期代替 | min `report_timing`、hold violations |
| In2Reg / In2Out | `set_input_delay -min/-max`；输入 slew 或 driving cell | 外部发起端最早/最晚到达，参考时钟与边沿 | `report_port -input_delay`、分类 timing |
| Reg2Out / In2Out | `set_output_delay -min/-max`；`set_load` | 外部连线、接收端 setup/hold 和输入电容 | `report_port -output_delay`、分类 timing |
| max transition | 库上限；输入/时钟实际 slew 模型；有依据时补 `set_max_transition` | 库默认/引脚规则、接口 slew 要求及预留裕量 | transition violations、路径 transition、port drive |
| max capacitance | 库各驱动 pin 上限；互连和端口 load；必要的额外 max cap；数据 fanout 策略 | 库允许负载、接收 pin 电容、估计线电容、外部负载 | cap violations、驱动 pin limit、实际负载组成 |
| min capacitance | 库各驱动 pin 下限；合理的端口/观测信号与 buffer 策略 | 库表征范围、真实连接/外部负载 | min-cap violations、无负载输出和连接检查 |
| max fanout | 库规则（若有）；必要时 `set_max_fanout` | 工艺/设计经验、接收 pin 的 fanout weight、电容粗估 | fanout violations、实际分支和 fanout load |
| clock pulse width / minimum period | 时钟周期与 waveform；库 timing checks；必要时更严格的项目要求 | 占空比、库 CP pin 规则 | 相应 constraint 检查与 analysis coverage |
| clock gating | 正确识别 gated clock 和使能关系；库/项目 gating checks | ICG 单元、门控方案、使能协议 | gating setup/hold、时钟传播与 coverage |
| reset recovery/removal | 按 reset 类型建模释放与时钟关系，或明确暂缓 | reset 源、同步释放方案、分析模式 | recovery/removal timing 与 coverage |
| reset pulse width | 库异步控制 pin 检查 + 实际 reset 最短有效脉宽保证 | reset 控制器、时钟/计数规则、外部规格及验证 | pulse-width coverage；必要的专门验证证据 |
| 未约束/未测试路径 | 完整时钟、端口分组、模式与有理由的 exceptions | RTL 和接口清单；不能按报告数量猜 | `check_timing`、`report_analysis_coverage`、例外/禁用弧报告 |
| 面积 | 综合 scope、映射库和时序/电气条件；有面积预算时再考虑 DC 面积目标 | 单元面积单位和项目预算 | `report_area`；SDC 本身不能保证面积最优 |
| 功耗 | 上述条件之外，还要有活动率、工作负载、功耗模型与分析模式 | SAIF/VCD 或明确的活动假设 | 功耗报告及其输入；仅写 SDC 不够 |

这里的“DRC”是综合/STA 中的 **design rule constraints**，如 slew、capacitance、fanout；不是版图阶段检查线宽、间距的几何 DRC。setup/hold、recovery/removal、pulse width 则属于时序检查，不能把所有 violation 都理解为数据路径太慢。

## 3. 动笔前的参数表：缺什么就明确缺什么

每个值至少记录：**对象、数值/选择、单位、来源、状态**。状态建议用“已确认 / 早期假设 / 本阶段暂缓 / 不适用 / 待确认”。库已经提供的规则也记来源，不必重复写一遍 `set_*`。

| 必填主题 | 首次运行前要回答的问题 |
| --- | --- |
| 设计范围 | top 是 core 还是 SoC？综合宏是什么？保留哪些 debug/commit 输出？哪些 memory 真正进入综合？ |
| 库与单位 | target/link library、PVT、VT 是什么？time/capacitance 单位？面积单位是否确认？宏模型是否齐全？ |
| 互连模型 | WLM、物理估算还是提取寄生？DC/PT 如何保持一致？ZeroWireload 会遗漏什么？ |
| 时钟 | 每个时钟的源、周期、波形、边沿关系？分频/门控/复用是否存在？是否 pre-CTS？ |
| 时钟裕量 | setup/hold uncertainty 各是多少、包含哪些误差？source/network latency 分别怎样处理？ |
| 数据输入 | 按接口分组；参考哪个时钟/边沿？每组 min/max arrival、slew 或驱动单元？ |
| 数据输出 | 每组 min/max delay、外部 load？观察端口是否采用同样的接口预算？ |
| 特殊端口 | reset、scan、test mode、异步输入、inout 如何处理？是否有显式的 mode 约束？ |
| 电气规则 | 库有哪些 max/min cap、max transition、fanout 规则？是否需要项目级的更严限制？ |
| 优化策略 | 数据 fanout 初值及依据？clock/constant/reset 网络如何分别处理？是否需要端口 buffer？ |
| 例外 | 哪些路径为何不需要普通单周期检查？证据、准确对象、恢复分析的条件是什么？ |
| 输出证据 | timing、DRC、coverage 各由哪个报告验收？不能只留 Top 20 setup/hold paths。 |

找不到真实 IO 时序，可以建立“当前用于 block 比较的接口假设”；找不到 reset 机制，可以在被允许的早期 scope 内暂缓。**不能把“待确认”悄悄变成 0、默认 false path 或空对象。** 若实际 clocks、宏的 timing model、单位等关键条件不明，就应报告阻塞，而不是称其为可信的全设计评估。

## 4. 时序预算怎么填：先画边界，再写 min/max

### 4.1 时钟周期、uncertainty、latency 和 slew 各管什么

- `create_clock -period T -waveform {rise fall}`：定义边沿发生时间。没有特殊需求时可用 50% 占空比，但要把它认定为假设；时钟脉宽检查与 waveform 有关。
- `set_clock_uncertainty -setup/-hold`：为相应检查留裕量。setup 与 hold 的误差预算不同，不宜简单共用一个大数字。
- `set_clock_latency -source`：时钟到达当前设计边界之前的延迟。network latency 是设计内部时钟网络延迟；二者不能混填。
- `set_clock_transition`：ideal clock 到单元处的 slew 假设，影响库时序值；它不是 latency，也不是 uncertainty。
- pre-CTS 没有实际 clock tree，可使用 ideal clock 和有依据的裕量；post-CTS 应根据实际网络采用 propagated clock，重新整理 latency/uncertainty，避免重复计算。

以同一上升沿时钟域、忽略 skew/source 差异的简单模型为例：

```text
setup: T >= tCQ_max + tComb_max + tSetup + U_setup
hold:  tCQ_min + tComb_min >= tHold + U_hold
```

所以缩短周期主要压缩 setup 预算；延长周期通常不能解决同边沿 hold。真实 STA 还包含 launch/capture clock path、边沿关系、derate 等，以上公式用于理解和起草预算，不代替工具计算。

### 4.2 输入：arrival 和 slew 是两件事

在已处理好参考时钟相位的简单同步接口中：

```text
input_max = 外部发起 FF 的 tCQ_max + 外部数据路径最大延迟
input_min = 外部发起 FF 的 tCQ_min + 外部数据路径最小延迟
```

例如外部最大 tCQ 为 0.25 ns，最大数据路径为 0.55 ns，则 input_max 为 0.80 ns。若最小值分别为 0.08、0.12 ns，则 input_min 为 0.20 ns。时钟相位/板级 clock skew 需要按所选参考时钟统一处理，不能遗漏或在两处重复计入。

`set_input_delay` 说明信号**何时到达**；`set_input_transition` 说明边沿**变化多快**。只写前者会缺少输入驱动环境，只写后者则没有接口时序预算。

输入驱动模型选择：

| 已知条件 | 建议方式 | 注意事项 |
| --- | --- | --- |
| 只有接口 slew 规格，或明确做固定 slew 的早期比较 | `set_input_transition` | 合法的边界假设；不会随本设计输入负载自动调整外部 driver |
| 已知真实外部标准单元/等效驱动与库 | `set_driving_cell` | 确定库、cell、输出 pin/相关 arc，以及该 cell 输入端的 rise/fall slew |
| 只有合适的等效输出电阻模型 | `set_drive` | 属近似模型；需确认单位及适用范围 |

不要为了“像参考 flow”随便选一个 buffer 当 driving cell，也不要在同一组端口叠加多个驱动模型而依赖命令顺序。PT 会为 driving cell / drive resistance 计算负载相关的端口延迟；此时 input delay 中不应重复包含同一部分延迟，见手册 PDF 150–151。

### 4.3 输出：output min 的符号尤其容易写错

对外部接收 FF，简化公式是：

```text
output_max = 外部数据路径最大延迟 + 接收 FF 的 setup
output_min = 外部数据路径最小延迟 - 接收 FF 的 hold
```

例如外部路径最大/最小为 0.40/0.05 ns，接收端 setup/hold 为 0.15/0.10 ns，则 output_max=0.55 ns、output_min=-0.05 ns。外部线延迟为零且 hold=0.10 ns 时，output_min=-0.10 ns。

**正的 output_min 并不表示同样数值的正 hold 要求。** NPC 当前 +0.2 ns 是既有接口假设，不能解释为“外部要求保持 0.2 ns”。

`set_output_delay` 决定时间预算；`set_load` 决定电气负载。两个都要考虑，不能互相替代。

### 4.4 什么时候可以用周期百分比

尚无真实上下游、只做 block 预算分配时，可以定义 input_max/output_max 占周期的一定比例，但需说明预算分给谁。比如 T=5 ns，input/output max 都为 2 ns、setup uncertainty 为 0.2 ns，则简化预算大致为：

| 路径 | 剩余预算，尚需计入相关单元/内部路径延迟 |
| --- | --- |
| Reg2Reg | 4.8 ns，供 tCQ、组合逻辑和 setup 使用 |
| In2Reg | 2.8 ns，供内部路径与接收 setup 使用 |
| Reg2Out | 2.8 ns，供 tCQ 与内部数据路径使用 |
| In2Out | 0.8 ns，若确有该类单周期组合路径 |

这说明“输入、输出都留 40%”有实际含义，不能只看单条命令数值是否常见。min delay、hold 和真实外部负载通常不能机械地按同一百分比生成。

若接口条件已经固定，更改 core 频率时应保留这些真实外部条件。随周期一起缩小 IO delay，会同时改变接口要求，测得的不再只是 core 的频率变化。

## 5. 电气规则怎么提前准备：capacitance、fanout 与 transition

### 5.1 先知道库提供了什么

在 `.lib` 可用时查库定义；只有 `.db` 时，用当前工具支持的 library report 和 `get_lib_cells` / `get_lib_pins` / `get_attribute` 查询。**先查本版本支持的属性和命令，不假定 DC/PT 全部相同。** NPC 的 library probe 与诊断可作为入口，见 [flow](../../../npc/flow/README.md)。

重点记录：

1. time/capacitance 单位和 PVT；下面的 0.01 只有在单位为 pF 时才表示 10 fF。
2. 库级 default_max_transition、default_max_fanout、default_fanout_load 等是否存在。
3. 常用驱动输出 pin 的 max/min capacitance，以及接收 pin 的 capacitance、rise/fall 差异和 fanout_load。
4. 普通数据 pin、clock pin、异步控制 pin 的差别；FF 的 setup/hold、recovery/removal、pulse width 等库 timing checks。

属性可能不存在，也可能有库默认值或模型相关的等效值。“查询不到”不能直接推成 0 或“无限制”。特别是 min/max cap 常与具体驱动 pin 有关，不能从一个 buffer 的报告抽出一个数就当整个库的统一规则。

### 5.2 max capacitance：约束真实负载，而非选一个恰好过关的数

用于理解和预估的模型为：

```text
C_load ≈ Σ 接收 pin 电容 + 线电容 + 设计边界外的负载
```

库/CCS 模型、rise/fall、分析条件会影响实际数值；标量求和仅用于估计。`set_load` 填的是边界外负载，避免把内部已建模的负载再算一次。WLM/SPEF 提供互连模型；ZeroWireload 不意味着接收 pin 电容为零。

初版策略可按以下顺序确定：

1. **保留库的驱动上限作为硬性检查依据。** 不设置更宽松的用户值来“覆盖”库要求。
2. 为真实输出填写外部负载，明确内部互连估算；没有这些条件，负载估计就不完整。
3. 对寄存器使能、广播控制等预期高负载信号，事先选择数据 fanout 策略，允许综合分支、缓冲、调整驱动。
4. 若项目希望预留模型误差/后续互连裕量，再设有依据的额外 max cap，说明依据和对象。它是项目预算，不能称为库本身要求。

`set_max_capacitance C [current_design]` 可以作为 DC 的设计级额外上限，但用一个统一 C 约束所有数据驱动会影响许多网络。库内驱动能力差别大时，更需要解释为什么采用全局值；不要仅因为某条线超过 0.08477 pF，就盲目给全设计设 0.075 pF。

参数应从“预期负载 + 驱动选择 + 预算”出发。若没有足够依据，明确采用库上限，加合理的数据 fanout 策略，比凭空制造一个“安全 cap”更可解释。即使如此，最终仍要单独验收 capacitance。

### 5.3 fanout：是负载组织策略，不是电容的替代单位

```text
fanout_load(net) = Σ 接收端 fanout_load
```

该值无量纲；只有每个接收 pin 的权重都为 1 时，才近似等于负载 pin 数。`set_max_fanout 32` 不是“最多 32 fF”，也不保证各分支小于库的 max capacitance。

选择初值时，先查库权重和代表性接收 pin 电容，再做量级估计：

```text
N_budget ≈ (候选驱动 Cmax - 预计线电容 - 其他负载 - 预留量) / 代表性接收 pin 电容
```

这是选策略的粗估，不是约束保证：映射后驱动、负载和分支结构可能改变，pin 权重也未必为 1。若出现数百个相同 E pin 集中在一个控制信号上，初版就应考虑 fanout 策略，而不是只约束输入/输出。

NPC 当前选择 32，是早期数据控制网络的综合策略，结合参考 flow 和本工程映射结果验证有效。它不是 28 nm 的标准常数。以实际 E pin rise 电容约 0.00162248 pF 估算，32 个约为 **0.051919 pF**，已超过某个 CKND0 的 0.045377 pF 上限；当前工具形成的分支为 25/25/18，才使对应电容满足要求。

不要把 `high_fanout_net_threshold` 当作 `set_max_fanout`：前者影响高扇出网络的处理/估算，后者是优化约束。clock 网络的千级 fanout 也不能与普通数据网络按同一策略处理。

### 5.4 max transition：环境值和允许上限要分开

`set_input_transition 0.1` 表示输入实际按 0.1 ns slew 分析；`set_max_transition 0.1` 则要求相关对象的 slew 不超过 0.1 ns。把“当前输入假设”复制成“全设计最大允许 slew”没有自然依据。

先使用库规则；如需更严格的接口/实现预算，再设项目级上限。检查库 timing table 的 slew 范围也有帮助，但表格采样轴端点不能未经确认直接当成 DRC limit。最差 slew 还受驱动、负载和互连影响，需与 cap/fanout 一起评估。

### 5.5 min capacitance：不要用虚假负载修报告

某些驱动输出要求最小负载，与库表征/有效使用范围有关。没有接收者的 buffer 输出，或只有极轻负载的强驱动，可能低于该下限。

首次综合前应检查观察端口、废弃低位、跨层直通输出和强制 buffer 策略：

- 真实存在的外部观察接口：保留，并填写真实或明确假设的负载。
- 仅供仿真的观察逻辑：如果评估 scope 决定去掉，应通过清晰的综合开关去掉，并检查功能与综合边界。
- 无实际用途的内部输出：允许优化处理，避免未经需要强制为所有 multi-port nets / constant ports 加 buffer。
- 真实轻负载：需要合适的驱动单元或实现修复；不能随意增加 `set_load` 假装存在物理接收者。

这里通常不是“缺了一个 `set_min_capacitance` 数值”。库已提供下限时，首先应避免创造无用途、无负载且被保留的驱动。

**命令兼容性陷阱：** DC P-2019.03 User Guide（PDF 226）说明 `set_min_capacitance` 用于 input/inout ports，不能施加到 design；PT L-2016.06 的相关说明允许 design 对象。因此不要把 `set_min_capacitance X [current_design]` 当成可直接共享的 DC/PT 写法。用现有库规则，并按实际工具版本核对确需添加的命令。

## 6. 时钟和 reset 必须在第一版单独决策

### 6.1 pre-CTS clock：时序模型与 DRC 修复是两回事

给数据设计加 max fanout 后，应同时明确 clock 网络的处理。ideal clock 表示时钟传播时序的模型，不能单凭这个词推断所有 clock 网络都不会被 DRC 优化。

当前 NPC 在 DC 中使用：

```tcl
# DC 的综合策略：此阶段不通过普通数据 DRC 优化来构建 clock tree。
# create_clock 等时钟定义应已加载；仅适用于本阶段的 pre-CTS 决策。
set_auto_disable_drc_nets -on_clock_network true
set_max_fanout 32 [current_design]
```

DC 手册推荐 `-on_clock_network` 以覆盖完整时钟网络；旧 `-clock` 处理可能不穿过时钟逻辑。该命令不自动改变 ideal/propagated timing 模型。`set_ideal_network` 是另一种有更广泛影响的机制，使用前要理解传播与 DRC 豁免范围，不必为保险把几种写法全部堆上。

CTS 后需要面对真实 clock load、transition、capacitance、skew 与 pulse width，不能继续用 pre-CTS 的豁免代表 sign-off。也不能把 LSU enable、reset 等高扇出控制线冒充 clock 或 ideal network 来消掉违例。

### 6.2 reset：先判断类型，再决定约束

| reset 情况 | 初版约束/分析选择 | 必须补充的信息 |
| --- | --- | --- |
| 同步 reset | 通常按同步数据/控制路径做 setup/hold | 参考时钟、输入 arrival/slew；不能因名字叫 reset 就 false path |
| 异步 reset，释放与时钟关系有定义 | 分析适用的 recovery/removal，并验证有效脉宽 | reset 源、到达关系、极性、最短有效脉宽 |
| 异步置位、同步释放架构 | 明确同步器边界与其异步部分的处理；保留需要分析的下游释放路径 | 同步器结构、reset tree、CDC/RDC 与脉宽验证计划 |
| 早期 core，没有 reset 源/SoC 方案 | 在允许的评估 scope 内明确暂缓，并给出具体 exception/TODO | 暂缓哪些检查、为什么、何时恢复；不能宣称 reset 已通过 |

recovery/removal 关心异步控制**释放与有效时钟边沿的间隔**；pulse width 关心 reset **有效电平持续多久**。前者的例外不等于后者的保证。

当前 NPC 属最后一类，已明确采用：

```tcl
# 仅为当前早期 core 评估范围；真实 reset 方案明确后重新建模。
set_false_path -from [get_ports rst_n]
```

这会排除相关路径的普通时序要求，但不会让 reset 脉宽自动得到验证，也不保证 coverage 里不再出现 untested。NPC 当前仍保留这些原始检查，并在 [reset TODO](../post-c/4-pre-soc-signoff/reset-timing-todo.md)中记录后续工作。

不要为了让脉宽变成 tested，就给一个非周期 reset 随便 `create_clock`；也不要默认用 `set_case_analysis` 把 reset 固定在无效电平，因为这会改变被分析/优化的模式。若需要静态模式分析，应明确该模式与 reset 专门验证之间的分工。

### 6.3 哪些设计不能直接套单时钟模板

存在以下情况时，先扩展时钟/接口表再写约束：

- 分频/倍频、门控、时钟 mux：定义实际生成关系与模式，使用适用的 `create_generated_clock` 等机制。
- 外部接口时钟不宜等同于 top 的物理时钟：可用 virtual clock 表达外部参考，明确它与内部时钟关系；不是多造一个硬件 clock。
- 真正异步时钟域：结合同步器/握手方案选择 exceptions；`set_clock_groups -asynchronous` 不会证明 CDC 正确。
- 多边沿或多时钟作用于同一端口：按接口定义完整指定 delays，必要时使用 `-add_delay`，避免后一次命令覆盖前一次。
- 多周期协议：必须证明数据保持和采样使能关系，分别分析 setup/hold 的边沿变化；不要为修慢路径直接套一个 N / N-1 模板。
- inout、scan/test、低功耗、宏时钟：需要方向/模式/电源状态和相应 timing model，不能由 `all_inputs/all_outputs` 一把覆盖。

## 7. 一份可以据此填写的初版结构

### 7.1 文件分工与执行顺序

```text
库 / site / design 配置
  ├─ 库、PVT、单位、互连模型、综合 scope
  └─ 参数表：每个数值的来源和状态
        ↓
读取 RTL 或网表 → link → 确认 top/对象
        ↓
共享 SDC：时钟 → 数据接口 → 电气环境 → 有依据的 exceptions
        ↓
DC：综合专属优化策略 → compile → 导出网表/实际约束 → 报告
PT：载入对应网表/库/约束和互连模型 → update_timing → 报告
```

PT 应按 flow 的明确约定载入 DC 导出的约束及必要补充，或重建同等条件；不要混用不同版本参数，更不要无审查地叠加多份 SDC。DC-only 命令不应直接进入 PT 脚本。

### 7.2 共享 SDC 骨架：单时钟、固定输入 slew、普通同步数据接口

下面是**需要工程配置填充的模板**，不是可原样替换 NPC 文件的成品。`p` 字典中的参数必须先由第 3 节参数表确定；`data_in/data_out` 由顶层端口清单显式分组，时钟和特殊控制不混入数据组。示例只适用于同一 `core_clk` 参考边沿的接口。

```tcl
# 前提：设计已 link；库单位已核验；p 由已审阅配置创建。
# 参数缺失时 dict get 会报错，不静默采用 0。
set T [dict get $p period]
create_clock -name core_clk -period $T \
    -waveform [list 0 [dict get $p clock_fall]] [get_ports clk]
set c [get_clocks core_clk]

# clock_fall 来自占空比；例如明确采用 50% 时才取 T/2。
set_clock_uncertainty -setup [dict get $p uncertainty_setup] $c
set_clock_uncertainty -hold  [dict get $p uncertainty_hold]  $c
set_clock_transition [dict get $p clock_transition] $c
set_clock_latency -source -min [dict get $p source_latency_min] $c
set_clock_latency -source -max [dict get $p source_latency_max] $c

# 例：p 中的 data_input_ports / data_output_ports 是准确的端口名列表。
# 真实项目需检查 collection 非空、方向正确、各组不重复且完整覆盖。
set data_in  [get_ports [dict get $p data_input_ports]]
set data_out [get_ports [dict get $p data_output_ports]]
set_input_delay -clock core_clk -min [dict get $p input_min] $data_in
set_input_delay -clock core_clk -max [dict get $p input_max] $data_in
set_input_transition [dict get $p input_transition] $data_in
set_output_delay -clock core_clk -min [dict get $p output_min] $data_out
set_output_delay -clock core_clk -max [dict get $p output_max] $data_out
set_load [dict get $p output_load] $data_out

# 多个接口预算不同，就分别重复对应端口组的配置，不取同一个方便的全局值。
# 特殊控制输入也需建立 drive/slew 环境；按各自模式和时序关系另外处理。

# reset 在此处插入经过第 6 节决策的建模，不能默认 false path。
# 项目额外 max_transition / max_capacitance 也只在有来源时添加；
# 没有额外上限时记录“沿用库规则”，并确认库实际提供的规则。
```

不要只检查 Tcl 能执行：错误端口通配符、漏掉一个接口组、误将 reset 计入 data_in，都可能产生可执行但不完整的约束。端口清单是填参数的前置输入，而不是出报告后再补的工作。

### 7.3 DC 综合策略：在 compile 前确定

```tcl
# 前提：共享 SDC 已加载，当前 design 是正确的 top。
# 此示例只用于已选择 pre-CTS ideal-clock 评估策略的设计。
set_auto_disable_drc_nets -on_clock_network true

# 数值先在策略表中决定；不是通用默认 32。
set_max_fanout [dict get $p data_max_fanout] [current_design]

# 可选：仅当项目需要比库更严格的额外上限，且已确认对象/单位时：
# set_max_transition  [dict get $p project_max_transition] [current_design]
# set_max_capacitance [dict get $p project_max_capacitance] [current_design]

# 端口 buffer、constant buffer、面积目标等按设计交付需求选择。
# 不无条件加入 set_fix_multiple_port_nets -all -buffer_constants；
# 不把 set_max_area 0 当作每个设计都必须采用的 SDC 常识。
# 随后执行本工程选定的 compile / compile_ultra 及输出步骤。
```

如果数据 fanout、额外 cap/slew 约束需要由 PT 验收，应通过导出 SDC 或明确的 PT 设置保留对应要求。命令作用范围、综合模式支持情况以实际版本为准。诊断属性查不到时，可通过约束报告和网表连接验证，不能凭空假设一个同名属性必然存在。

### 7.4 第一版就安排哪些报告

| 阶段 | 最小证据集合 | 对初版约束的用途 |
| --- | --- | --- |
| 载入后、综合前 | 库/单位/PVT/WLM；`report_clock`；port input/output delay、drive/load；DC `check_design` | 发现时钟、端口、库模型和预算漏项 |
| DC 综合后 | `report_constraint -all_violators`；setup/hold paths；area/QoR；高扇出和关键电气负载诊断；导出 SDC | 检查工具是否在既定条件下优化，是否留下 DRC/timing 问题 |
| PT 分析后 | `check_timing`；`report_constraint -all_violators`；max/min timing 及路径分类；`report_analysis_coverage` | 分别验收约束达标和检查覆盖 |
| 有例外/禁用弧 | `report_exceptions`、`report_disable_timing` 等当前版本支持的报告；对应 detailed coverage | 确认没把本应分析的路径排掉，解释未测试项 |

`report_constraint` 的实际检查集合受工具、版本、库和已建立约束影响；需要按当前版本帮助补充相关检查类型和详细报告。只列 Top N timing paths 看不全 cap/slew/fanout，也无法判断 reset coverage；“无 violations”更不能证明漏掉的检查已通过。

### 7.5 填完以后应该是什么样：NPC 当前条件示例

下面展示参数表应有的具体程度。它整理现有基线的选择，**不是推荐给另一个设计的一组通用数值**。例如 IO 尚无真实上下游时，不能因数值已写入脚本就将状态升级为“已确认接口规格”。

| 项目 | 当前选择 | 依据 / 状态 |
| --- | --- | --- |
| 单位与 corner | ns、pF；TT、0.9 V、25°C | 库 probe 与配置；目前只覆盖此 corner |
| clock | clk，5 ns，默认 50% 占空比，ideal | 200 MHz 目标；pre-CTS 分析假设 |
| uncertainty | setup 0.2 ns；hold 0.05 ns | 早期裕量预算；不是实测 jitter/skew |
| source latency | min/max 都为 0 | 当前 block 参考时钟假设 |
| clock slew | 0.1 ns | ideal clock 的早期 slew 假设 |
| data input delay | min 0.2 ns / max 2 ns | 同步接口预算假设，尚非实际上游规格 |
| input drive | 数据/reset 固定 slew 0.1 ns | 未指定真实外部 driving cell |
| output delay | min 0.2 ns / max 2 ns | 既有接口预算；min 不代表正 0.2 ns hold |
| output load | 每个输出 0.01 pF，包括观察端口 | 早期外部负载假设；保留观察数据锥 |
| cap / slew 上限和 cap 下限 | 沿用库实际提供的规则，无额外全局 cap/slew 数值 | 仍需 DC/PT 报告独立验收；不表示库中所有可能规则都必然存在 |
| data fanout | 顶层 max_fanout=32 | 综合策略；实际映射和 PT cap 已验证通过 |
| clock DRC 修复 | DC 对 clock network 关闭 | pre-CTS 策略；不对 clock 执行普通数据 fanout 分组 |
| reset 时序 | 精确 `-from rst_n` false path；脉宽/释放暂缓 | 已明确的早期 scope；有恢复分析 TODO |
| 多端口强制 buffer | 不启用全局强制插入策略 | 观察/废弃输出的空载驱动问题；正常优化仍可用 buffer |
| 互连 | DC/PT ZeroWireload | 早期模型；不代表布线后延迟/电容 |

真实工程重做时，应先生成这样的表，再生成 Tcl。如果查库发现根本没有相关 slew 上限、或发现新的异步输入/生成时钟，就在初版阶段补决策，而不是把本表直接复制过去。

## 8. 用 NPC S3 倒推：如果重做，哪些应该一开始决定

| 本次遇到的现象 | 初版阶段应该完成的准备 | 不应得出的结论 |
| --- | --- | --- |
| 66 条 min-cap，其中包括观察输出/废弃低位相关的无负载 buffer | 先定观察接口 scope 与负载；审查是否需要强制 multi-port buffer；预先安排 min-cap 检查 | 给所有空载点随意补电容，或认为必须禁掉所有 buffer |
| LSU enable 驱动 54 个 E pin 加一个 buffer 输入，PT 约 0.088724 pF 超过 0.084770 pF | 在 RTL/寄存器结构审查时发现广播使能；库 pin 电容粗估；提前选数据 fanout 策略和 clock 保护方式 | FSM 天然不能解决；或只要 fanout=32，所有 cap 必然通过 |
| DC 没报 max-cap，PT 报了 | 两侧从第一版就保留 cap 验收及实际负载诊断；了解标量与 rise/fall 模型可能差异 | DC 通过意味着 PT 无需独立检查；实际差异根因仍需证据 |
| 顶层 max fanout 涉及 clock 网络处理 | 在加入数据约束的同一阶段决定 pre-CTS clock DRC 策略 | 时钟理想就不需要任何策略核对；或对 clock 强制普通 fanout=32 |
| 大量 reset pulse/recovery/removal untested | 写 SDC 前决定 reset 分析范围；没有真实机制时明确暂缓和恢复条件 | 一条 false path 能完成 reset 验证或使 coverage 全部变绿 |
| 全局关键路径到 commit 观察输出 | 在选频率前确定观察端口的 timing/load contract，同时保留内部 Reg2Reg 指标 | 直接用全局路径延迟倒数声称 core 内部 Fmax |

当前 04 的策略最终消除了 DC/PT 约束违例，但仍是 **TT、5 ns、ideal clock、ZeroWireload、reset 暂缓**的基线。最差 hold 只有约 8.754 ps，不能作为布线后 hold 裕量。更完整的早期 SDC 应让这些条件从第一次运行就清楚，而不是承诺它们等价于物理 sign-off。

## 9. 首次提交 SDC 前的完成清单

- [ ] 设计/接口清单明确；每个顶层端口都归入 clock、数据、reset、mode/test 等类别。
- [ ] 库/PVT/单位与互连模型明确；库电气规则已调查，缺失项没有静默当作无限制。
- [ ] 所有 clock 的周期、波形、关系和 slew 已决定；setup/hold 裕量分别有依据。
- [ ] 每组同步数据输入都有 min/max delay 和驱动环境；每组输出都有 min/max delay 和 load。
- [ ] output_min 符号已按接收端 hold 推导；参考时钟/相位/延迟未重复计入。
- [ ] 数据 fanout 策略和 cap/slew 规则在 compile 前确定；已说明哪些沿用库，哪些是额外预算。
- [ ] pre-CTS clock 与数据 DRC 策略分开；未将普通控制网理想化以规避检查。
- [ ] reset 的类型、释放与脉宽处理明确；暂缓项有范围和恢复条件。
- [ ] 观察接口与强制 buffer 策略已经审查，未通过虚假 load 掩盖无用途驱动。
- [ ] 所有 false/multicycle/mode 例外都有功能依据；不存在仅为消违例加入的例外。
- [ ] 初次运行就生成 timing、cap/slew/fanout 和 coverage 证据；不是等出问题才加报告。
- [ ] 参数表中的“待确认”已解决，或明确限制了本次结论；尚未准备好的内容按阻塞项报告。

## 10. 交给新模型时的任务说明模板

> 请先阅读本工程的 top RTL、filelist、综合宏、时钟/reset/接口定义、库 probe、参考 flow 与本笔记，再准备首次综合/STA 约束。
>
> 先产出“指标—约束/模型—对象—值/单位—来源—状态—验收报告”的表。逐项覆盖 clock、setup/hold、I/O delay、输入驱动、输出负载、cap/slew/fanout、reset、模式与 exceptions；库已自动提供的规则也记录来源。不要直接从参考 SDC 复制数值。
>
> 根据 RTL 和库，预估广播使能等高负载网络；给出数据 fanout 与额外电气限制是否需要的判断，并同时明确 clock 的处理。reset 必须独立分析，不能默认 false path。明确观察端口是否计入综合和接口预算。
>
> 再生成共享 SDC、DC 优化策略与参数配置；每个关键值标注是事实、早期假设还是项目预算。对缺少依据的项目提出具体缺失信息，不任意补 0 或用例外隐藏。
>
> 最后按第 9 节检查完整性，提供首次运行即应输出的报告集合。仅声称约束准备完整，不预先声称时序、电气或物理 sign-off 已通过。

## 11. 依据与继续查阅

使用仓库本地手册核对，检索方式见 [M4 manual-index](../post-c/4-pre-soc-signoff/manual-index.md)。以下均为 PDF 页序，不是正文页码；User Guide 版本早于本次服务器工具，完整参数和对象类型以实际版本 `help` / `man` 为准。

| 内容 | 阅读入口 |
| --- | --- |
| 库与设计环境、WLM | DC P-2019.03 PDF 111、193、202 起 |
| 设计规则、fanout、capacitance | DC P-2019.03 PDF 217 起；min capacitance 对象限制见 PDF 226 |
| clock DRC 修复与 ideal timing 的区别 | DC P-2019.03 PDF 229–230 |
| input/output delay、drive/slew | PT L-2016.06 PDF 147–151；output_min 公式见 PDF 149 |
| PT 电气规则 | PT L-2016.06 第 5 章；min capacitance 见正文 5-18 / PDF 162 |
| 时钟与路径例外 | PT L-2016.06 PDF 171、229 起 |
| coverage 与报告验收 | PT L-2016.06 PDF 633、656 起；[可信度评估笔记](synthesis-sta-credibility.md) |
| 当前 NPC 具体参数与脚本 | [core.sdc](../../../npc/flow/00_indata/constraints/core.sdc)、[设计配置](../../../npc/flow/00_indata/configs/npc_core.tcl)、[DC 脚本](../../../npc/flow/02_syn/run.tcl) |
| S3 具体问题与最终证据 | [capacitance 诊断](../post-c/4-pre-soc-signoff/s3-capacitance-check.md)、[04 基线](../post-c/4-pre-soc-signoff/synthesis-results/04-200mhz-baseline/README.md) |
