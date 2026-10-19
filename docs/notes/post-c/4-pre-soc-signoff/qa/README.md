# M4 面试 Q&A

2026-10-19：以下包含规划、S1/S2/S2.5 取舍及综合实验。04 已建立 TT / 200 MHz 下的 S3 core pre-layout 基线，05 独立复现通过，S6 与 [M4 本轮验收](../signoff.md)完成；reset 时序继续暂缓。各问题分别注明证据边界，按有价值的进展更新，不要求每次推进新增问题。

## 1. 为什么不把参考 flow 整体复制后只改 top 名？

参考工程的 STA 依赖布局后网表/SPEF，默认综合还启用 clock gating，并带有旧 top 的时钟和 margin。NPC 首次要建立可解释的 core 基线，所以保留配置、分阶段执行、报告和归档的组织方式，重建独立的 SV filelist、SDC、pre-layout STA；测试平台按后续验证需求另行适配。每项输入都需要对应当前 DUT。

追问：已经具体发现什么？库配置晚于 elaborate/link、非 TOPO DDC 目录创建条件、旧 strip_path 与强制初始化等。证据：[参考审查](../0-ref-flow-review.md)。这些是静态审查发现，未声称已在 EDA 工具中复现。

## 2. 没有 SPEF 能做 PPA 吗？

可以先做带明确假设的综合面积、pre-layout 时序和功耗估算；必须说明互连模型、ideal clock、PVT、I/O 条件和活动来源。没有布线/时钟树，结果不能代表 post-route 时序或实际功耗。只有 area 和 timing 报告时，只能称面积/时序基线。

追问：WNS 可以直接换算 Fmax 吗？单个 target 不能证明最大可实现频率；需解释路径类型和时序预算，必要时在相同配置下做约束探索。证据：[结果契约](../plan.md#4-sdc-与结果契约)。

## 3. 为什么首次不综合带 1 MiB SRAM 的 B1 top？

当前 SRAM 是仿真可用的 RTL 数组，没有完成真实宏映射。直接综合可能得到大量触发器和 mux，主要衡量存储器展开代价。首轮选 Core + adapters + Arbiter 边界，先建立可比较的 core 基线；完整 B1 要另行确定 macro 接口、容量、mask、读延迟和视图，不能只加载 SRAM 库就认为映射完成。

追问：观察端口会影响面积吗？会影响逻辑保留与输出路径，因此首轮保留现有端口并约束/计入范围，以后裁剪要单独命名配置。证据：[评估范围](../plan.md#1-目标和评估范围)。

## 4. Verilator 能跑，为什么还要检查上电和四值行为？

S1 前的 regfile 用 initial 清零，x0 读取也依赖数组；这不等于标准单元硬件上电后必为零。S1 已将 x0 两个读口固定为零、x1–x31 改为显式异步复位，DPI 仅在仿真宏下导出指针；定向测试覆盖重复 reset 清除脏状态。但 Verilator 是两值仿真，不能据此宣称 X 安全，四值动态验证仍延后。

追问：所有寄存器都要复位吗？需逐类判断控制/valid 的可知性和数据是否在有效前被写入，不能用一刀切的复位或忽略 X 代替设计。例如 IFQ 只复位指针/count，空队列屏蔽 data，storage 无需清零。S1 的静态审查和功能回归已经通过，原 S4 动态验证延后。证据：[S1 状态审查](../1-synthesis-scope.md#3-gpr-策略与状态审查)。

## 5. 接手一个 flow，为什么要分别画执行顺序和数据流？

Makefile 的依赖只说明先运行哪个阶段，真正的数据契约要看脚本读了哪个文件。当前参考链让 sim 在 STA 后执行，但 sim 仍读综合网表；不能据此声称它验证了 post-route 结果。蒸馏时需要同时明确入口、输入/输出和配置来源。

追问：SPEF 是 PDK 吗？不是，它是具体 design 的提取产物；QRC tech 才是工艺输入。工艺库路径可以保留，旧设计的寄生、波形和 SDC 不能拿来替代 NPC 数据。证据：[流程图与输入分类](../0-flow-map.md)。

## 6. 为什么本轮只附带 DC report_power，不建 GLS + PTPX？

当前要建立可复现的面积与时序基线，尚无必须用真实活动验证的低功耗优化目标。DC 可以在映射网表上依据库模型和活动假设作简要估算，成本较低；但必须记录频率、toggle rate/static probability、负载、PVT 和互连模型，不能把估算称为程序运行功耗。

追问：同配置下功耗变小能说明优化有效吗？只能初步筛选，默认/传播活动可能不能反映控制相关性或结构变化。将来针对 gating/operand isolation 等做优化 case 时，再决定是否引入真实活动与门级对照。本轮可交付“DC/PT 面积时序基线 + DC 功耗粗估”，不声称完整 PPA 验收。证据：[当前计划](../plan.md#附带的-dc-功耗估算)。

## 7. 为什么本次复位全部 GPR？是不是最省面积的方案？

这次优先保留 NPC/NEMU 首次启动后的确定性状态，不改变启动汇编和 DiffTest 契约。新增 reset 也使运行中再次复位能清空 GPR；x0 的硬连零独立于数组初始化。S1 当时的代价包括 31×32 个可写位（S2.5 后为 15×32）的复位能力和 reset 网络负载，不能宣称面积最优；数值要等 DC 映射。

追问：以后可以取消吗？可以作为独立优化 case，但要证明其他 GPR 在有效读取前完成初始化，并同步启动代码/参考状态。不能只删除 initial 后以两值仿真默认零作为证据。[S1 决策与测试](../1-synthesis-scope.md)。

## 8. 综合配置能通过 lint，是否说明已经可综合且得到 RV32E 面积？

还不能。S1 确认的是源闭包、宏隔离、reset 契约与相关功能回归，首次 DC 已完成 analyze/elaborate/link 和映射，但这属于额外的实测证据，不能由 lint 推导。首次综合的实现保留 32 项 GPR 和组合 M 运算（S2.5 已移除 M 并缩为 16 项，02/03 已取得对应 DC/PT 实测）；软件用 RV32E 编译并不会把这些硬件自动裁掉。报告必须写实际 top、参数、观察端口和硬件范围，不能根据软件 ARCH 命名芯片面积。

## 9. flow 返回 0 就代表 timing PASS 吗？

不代表。工具可能输出 Error 但不以非零码退出，脚本也可能未生成全部产物；即便运行完整，WNS、coverage 或 DRV 仍可能不合格。S2 同时检查退出码、完成标记、原始日志、报告和网表，PT 输入还必须匹配本 run 的 hash。执行完成与结果评价分开：负 slack 保存为 TIMING_FAIL，零 WNS 仍需检查未约束/untested、warning、时钟和 DRV，不能自动签出 PASS。

追问：本地 mock 测试证明了什么？证明缺输入/坏产物会失败以及脚本衔接正确，不证明 DC/PT 命令支持、库可用或时序正确。[S2 验证边界](../2-flow.md#5-本地验证与未验部分)。

## 10. 为什么起始目标用 10 ns？没有 SPEF 时如何说明时序数字？

10 ns 是冻结其余假设后开始测量的试探目标，没有测得 100 MHz 的含义。当前还明确了 I/O min/max、slew/load、uncertainty 和 reset release 条件。DC/PT 使用同一单库和 WLM 策略并保存实际报告；若库无 WLM，就明确工具的无模型行为及其乐观性，不能把报告命令的输出当作 post-route 结论。

追问：换周期后直接复用旧结果可以吗？不能。需要新的配置/run，并区分只改 STA 条件与重新综合的结果；输入/网表 hash 保证不会误用旧网表。[S2 数值假设](../2-flow.md#2-数值-sdc-与适用边界)。

## 11. 28 nm 的 core 为什么连 100 MHz 都没达到？

工艺节点不决定组合逻辑深度。首次综合保留了组合除法/取余，最差路径经过 `rem_80`，到达 15.09 ns，而观察输出预算只允许 7.8 ns。ALU 占面积 64.7%，四套 div/rem 共占 40.4%，这给出了具体改进对象。迭代单元可缩短单周期路径并共享硬件，但增加运算周期；应同时比较频率、CPI/吞吐与面积。[首次综合证据](../synthesis-results/01-first-synthesis/README.md)

## 12. 最差路径结束于 debug/commit 输出，可以直接不约束它吗？

必须先定义芯片实际接口及采样契约。若观察信号仅服务仿真，可以设计独立生产 scope，但要单独测量并标明范围，不能把隐藏路径当作同范围优化。本次内部寄存器端点也有 −5.83 ns setup 违例，因此移除观察端口不能证明 core 时序通过。逻辑上互斥的控制是否使某条路径不可达，需要具体证明，不能凭信号名称添加 false path。

追问：首次综合是否一定成为正式基线？不一定。本次保留为诊断记录；先完成接口、实现和约束审查与必要改进，再冻结正式 DC/PT 基线。这样既保留了真实失败结果，也明确了后续优化的比较条件。

## 13. 删除乘除法后程序中的乘除运算怎么办？面积下降算架构优化吗？

NPC 的软件目标是 RV32E、ABI 为 ilp32e，AM 链接软件乘除辅助例程；删除的是 RTL 对 M 编码的支持，C 程序仍可通过基础整数指令完成运算。本次 CPU tests 的 div、matrix-mul、mul-longlong 等通过，但执行周期不等同于硬件 M 单元。

从首次综合的 32 GPR/M 改成 16 GPR/无 M，属于功能范围收敛，不能宣传为相同 ISA 下的 PPA 优化。后续若做多周期乘除器，需要固定 ISA 和 workload，同时比较面积、频率及 CPI/吞吐。[S2.5 范围与证据](../2.5-isa-contract.md)

## 14. 缩小 GPR 数组为什么不能简单截掉寄存器索引最高位？

截断会让 x26 别名写到 x10；本项目选择把实际使用 x16–x31 的指令判非法。还必须按格式区分操作数与立即数：I 型 rs2 位置是立即数，CSR zimm=31 也不是 x31。物理数组只读写 16 项，DiffTest 接口仍保留 32 槽并把高半部填零；接口布局与硬件寄存器数量是不同契约。

## 15. DiffTest 通过能证明非法指令实现正确吗？

不能单独证明。当前异常由 DUT 的 cause 注入参考端；漏报或错报可能让参考沿着 DUT 的错误决定执行。因此增加独立掩码表 oracle 和带 `.word` 的自检查程序：handler 检查 cause/EPC/mstatus，返回后检查寄存器和内存，外部再核对精确 trap 地址及 LSU 请求总数。两个平台各验证 97 个预期非法 trap，取指错误优先级和失效上下文另由 EXU 定向测试覆盖。

追问：CSR 合规只是“非法时禁止访问 CSR”吗？不是。非法指令仍必须更新 trap CSR；要禁止的是原指令的普通写入。合法指令还需区分 RW/RS/RC、寄存器/立即数、零源写抑制及 WARL；六条操作通过不代表整个特权架构已实现。[CSR 边界与测试](../2.5-isa-contract.md#2-csr-与-trap-契约)

## 16. WNS/TNS 都为零，为什么还不能宣布 STA 基线通过？

本 flow 的 WNS 是最坏负裕量，无违例时归零，不反映实际剩余正裕量。还要看电气约束、分析覆盖率和禁用时序弧。02 实验的 setup/hold 都通过，但有 66 条最小电容违例、5516 项异步控制引脚脉宽检查未测试，以及 PTE-003 待定位。

追问：`check_timing succeeded` 与 coverage 的 `no_clock` 冲突吗？不冲突。本次未测试项是 CDN/SDN 的低脉宽检查，不是数据寄存器全部缺时钟；recovery/removal 通过也不能证明复位有效脉宽足够。[02 实验](../synthesis-results/02-rv32e-no-m/README.md)

## 17. 为什么 report_timing 指定多条路径，却一条都没有？

本次 PT 在 `-max_paths > 1` 时默认只报告负 slack，全部满足便输出空报告。审阅关键路径需要显式纳入正 slack；计算 WNS/TNS 时则应继续只枚举负 slack 端点。必须核对报告头部实际筛选条件，不能把“没有打印路径”当作“设计没有关键路径”。依据：PT User Guide L-2016.06，正文 17-5 / PDF 637，与本次 PT T-2022.03-SP5 输出一致。

## 18. 高扇出告警是否意味着时钟时序失败？

先定位对象。03 的 `all_high_fanout` 和连接报告确认只有 clk 超过阈值 1000，负载 1509；当前使用 ideal clock，未建立物理时钟树。高扇出近似下打印的聚合电容不能直接当作实际时钟树电容，数量大也不自动意味着 setup/hold 失败。应分别看数据路径、时钟模型和后续 CTS 的负载/延迟，而不是调高阈值隐藏告警。[03 高扇出证据](../synthesis-results/03-200mhz-candidate/README.md#3-高扇出与-pte-003-已有明确对象)

## 19. PTE-003 是否证明有组合环？最小电容违例能用 false path 解决吗？

PTE-003 的通用消息同时提及 loop 与常量传播，必须查 `report_disable_timing`。03 的打印记录只有 `p`/`C`，没有 `l/L`，因此不能据此声称工具发现了组合环。与此同时，CONSTRAINT_FAIL 来自另一份报告中的 66 条最小电容违例：EXU 无负载 buffer 的实际电容打印为零，库要求约 0.410 fF。

这些 buffer 驱动未使用的子模块输出或被对齐逻辑舍弃的位；应检查连接及无用逻辑清理，不能用 false path 或虚构负载代替电气问题修复。setup/hold 满足与这些问题并不矛盾。[03 电气与覆盖率证据](../synthesis-results/03-200mhz-candidate/README.md#4-constraint_fail-的原因与剩余审查)

## 20. 为什么后来允许对 rst_n 设置 false path？

这是用户明确选择的早期评估边界：当前没有真实 SoC/reset 源和 IO 时序，暂缓 reset 时序验收，保留 core 数据时序评估。它不是因为脉宽已被证明满足，也不是“出现 untested 就可以设 false path”。仅排除 rst_n 发起路径，包含 recovery/removal 与 reset→D/输出；旧 release delay 移除，RTL reset 功能不变。

脉宽 untested 可能仍存在，继续保存原始 coverage；明确归属 reset 的项登记 deferred，其他缺口不自动豁免。实际 reset 机制明确后撤销/缩小例外并补建模和验证。[范围及恢复条件](../reset-timing-todo.md)

## 21. 模块 input 直通 output 必须插 buffer 吗？接到顶层会变成无驱动吗？

不必。`assign commit_pc = op_pc;` 描述的是连接，模块边界本身不需要硬件实现。综合网表可以保留直通连接，以 `assign` 表达。当前 flow 显式使用 `set_fix_multiple_port_nets -all -buffer_constants`，会处理包括 input→output 直通（feedthrough）和多输出共网在内的连接，插入 buffer 是其处理方式之一；工具也可能为时序或负载要求插 buffer。因此不能理解成“只要经过模块端口就必须插 buffer”。依据：DC P-2019.03，正文 11-32–11-33。

追问：不插 buffer，就没有无负载问题了吗？要区分连接状态和多余单元：

```text
寄存器 Q ─┬─→ 功能逻辑
          └─→ buffer → 未使用的 EXU 输出
```

这里 buffer 有输入驱动，但输出无消费者。若无用 buffer 和观察分支被清理，便不再有这个悬空单元输出接受最小电容检查；这不意味着凭空增加了负载。若未使用端口仍保留，也可能继续有结构提示。其他驱动端是否满足电气约束仍需重新检查。

| 概念 | 含义 |
| --- | --- |
| 无驱动 | 网络没有有效信号来源 |
| 无负载 | 有信号来源，但没有消费者或建模负载 |
| 直通连接 | 中间没有逻辑单元，驱动通过连线传递 |
| 顶层输出 | 设计边界，外部接收负载通常通过 SDC 建模 |

如果连接是 `寄存器 Q → EXU 输出 → core 输出 → 顶层观察输出`，信号仍由寄存器 Q 驱动，不会因为跨层或没有 buffer 就变成无驱动。当前 SDC 的 `set_load 0.01 [all_outputs]` 为顶层输出设置了 0.01 pF 外部负载；实际驱动单元需承担这条连接上的负载。

03 的 64 位观察输出没有被父层继续使用，另外 2 位 `trap_epc[1:0]` 被 CSR 对齐逻辑舍弃。尤其顶层 `commit_pc` 由 architectural PC 寄存器驱动，并非 EXU 的同名输出直通上去。多端口网络修复是排查 buffer 来源的方向，尚未通过对照综合证明它就是全部 66 个无负载 buffer 的根因；后续应检查网表及 PT，不靠虚构负载或硬编码实例名删除单元。[03 实验证据](../synthesis-results/03-200mhz-candidate/README.md#4-constraint_fail-的原因与剩余审查)、[层次与引脚阅读方法](../../../knowledge-notes/netlist-and-timing-report-navigation.md)


## 22. 综合脚本设置约束没有报错，为什么结果仍可能不变？

命令执行、属性存在、优化采用目标、最终满足目标是不同层次的证据。首先核对冻结脚本/log，随后检查约束施加的对象、当前 design 和综合策略，再在 compile 前后读取属性并查看导出 SDC/报告，最后看网表和 PT 实际结果。

本工程曾对子 design `ysyx_lsu` 设置 0.075 pF 最大电容，随后从顶层 compile；log 打印成功，但导出 SDC 没有该约束，PT 的 LSU 使能网络违例不变。DC 手册 P-2019.03 10-8–10-9、10-12 说明，顶层约束驱动层次综合，子 design 约束不在顶层 compile 后保留。修正为顶层目标并增加前后属性读回，但作用域扩大至全 core，需重新比较面积和时序。

本地 mock 可以检查作用域选择、命令顺序和失败处理，却不能证明真实 DC 的层次优化语义。若属性读回正常，仍需通过约束报告和 PT 判断是否达标。[本次失败与修正记录](../s3-capacitance-check.md#6-局部裕量未生效与顶层作用域修正)


## 23. max_fanout 32 会让综合器给时钟插缓冲吗？

普通数据网络与时钟网络应采用不同策略。当前在 DC 顶层设置 `set_max_fanout 32`，同时用 `set_auto_disable_drc_nets -on_clock_network true` 显式禁止时钟网络 DRC 修复；clock 时序继续采用共享 SDC 的 ideal 模型，真实时钟树留待 CTS。

ideal/propagated clock 是时序分析模型，DRC 修复开关是综合优化策略，二者不能混为一谈。DC 手册 P-2019.03 8-13–8-14 说明，切换 clock DRC 修复不会自动改变 ideal timing；推荐 `-on_clock_network` 覆盖完整时钟网络。当前在 compile 前后读取 fanout 约束；clk 源网络保护属性在服务器 DC 上不可查询，因此只记录 UNAVAILABLE，需检查实际网表/连接，不能据此断言保护失效或已经生效。后续若加入 clock gating/mux，要重新审查整条树。

32 是库 fanout_load 之和，不一定等于 32 个输入 pin；其通过也不保证 max-capacitance 或 slew 通过。reset false path 不代表 reset 网络免于 fanout/电容修复，其他高扇出控制网络仍可能因这个全局目标增加缓冲。当前 [C906 公共 SDC](../../../../../npc/ref-flow/00_indata/SDC/C906_TOP.sdc) 也设置 32；数值借鉴仍须用本工程的库和 PT 结果验证。[当前实验](../s3-capacitance-check.md#7-改用-max_fanout-32-并排除时钟-drc-修复)


## 24. coverage 只有 53% met，为什么这次仍能建立基线？

看每一项为何未测试，以及基线到底承诺什么。04 的 9450 untested 已逐条分类：9426 是明确排除的 reset 脉宽/释放时序，24 是 mtvec[1:0] 固定为零后不可能激活的条件检查；其他 10730 项 met，0 violated。不能把所有 untested 一概叫 reset waiver，也不能因百分比低就推断有一半功能数据路径缺约束。

本轮只接受 TT、ideal clock、ZeroWireload 下的 core 面积/数据时序基线，并未接受真实 reset 或物理 sign-off。工具的 REVIEW_REQUIRED 保留，人工审查与其分开记录。后续若出现不同的 untested 对象/原因必须重新审查，不能沿用一个总数豁免。[04 coverage 和告警审查](../synthesis-results/04-200mhz-baseline/README.md#4-9450-项-untested-的逐类处置)
