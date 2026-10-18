# 04：200 MHz core 综合 / STA 基线

2026-10-18。**本次结果支持建立 S3 的 pre-layout core 面积与数据时序基线。** DC/PT 无约束违例，PT setup/hold 最差 slack 为 **+0.596843 / +0.008754 ns**，cell area 为 **9242.855942 library_area**。结论限 TT、5 ns、ideal clock、ZeroWireload；reset 时序按用户决定 deferred，不是全 PVT、功耗或物理 sign-off。

工具的 `REVIEW_REQUIRED` 状态原样保留。本记录是对报告、告警与例外的人工审查结论，不改写 manifest，不把工具 COMPLETE 自动等同于通过。S6 的最终复现/交接仍待完成。

## 1. 冻结输入与追溯

| 项目 | 本次值 |
| --- | --- |
| 原 run | `npc/flow/build/core-tt-5ns-no-port-buffers`（用户复用名称，以本次 manifest/hash 区分） |
| 运行时间 | 北京时间 2026-10-18 23:50:55 创建；DC/PT 报告约 23:51–23:52 |
| HEAD | `9e449fac5b8abe863c6bd5c90f79a1c4230607a1` |
| dirty | 仅 Makefile 默认 SITE 从 example 改为 local；实际 site 单独冻结 |
| Top / scope | `ysyx_core_axi4lite`；Core + IFU/LSU adapters + Arbiter；保留观察端口；无 Xbar/SRAM/外设 |
| ISA / 参数 | S2.5 的 16 GPR、无 M/C、限定 CSR/异常能力；IFQ_DEPTH=2，PC_RST=0x80000000；SYNTHESIS 宏 |
| 工具 | DC V-2023.12-SP5；PT T-2022.03-SP5 |
| 库 / 条件 | `tcbn28hpcplusbwp12t40p140tt0p9v25c_ccs` / `tt0p9v25c`；TT、0.9 V、25°C；site 声明 RVT |
| 单位 | ns / pF；面积沿用 library_area，未确认 μm² |
| 时钟 | 5 ns；ideal；setup/hold uncertainty 0.2/0.05 ns；transition 0.1 ns；source latency 0 |
| 数据接口 | min/max input/output delay 0.2/2 ns；input transition 0.1 ns；所有输出 load 0.01 pF |
| reset | 仅 `set_false_path -from [get_ports rst_n]`；无虚构 release delay；保留输入 slew |
| 综合 | 普通 `compile -map_effort medium`；顶层 max_fanout=32；显式关闭 clock network DRC 修复；无强制 multi-port buffer |
| 互连 / 功耗 | DC/PT ZeroWireload，无 SPEF/布局/CTS；power_enable=0，未评估功耗 |

37 项输入、23 项 DC 产物、25 项 PT 产物 hash 全部核对通过。17 份 RTL 快照与本地及 03 完全一致，可沿用 [S2.5 功能验证](../../2.5-isa-contract.md)的设计版本证据；本次没有重跑 RTL 功能回归，也没有执行网表等价验证。服务器工具/DB hash 已记录，未在本地重新访问外部工具和库。

依据：[manifest](provenance/manifest.json)、[dirty patch](provenance/dirty.patch)、[原始 SDC](provenance/core.sdc)、[DC 导出 SDC](provenance/dc.sdc)、[运行脚本](provenance/syn.tcl)。输入没有因这次审阅而更改。

## 2. 电容修复与时钟网络

上一轮有 54 个 E pin + 一个 buffer 输入集中在 n3，PT 为 0.088724 pF，超过 0.084770 pF。当前 max_fanout 32 已在 compile 前后读回为 32.000000，并写入导出 SDC；实际映射发生变化：

| LSU 使能分支 | 直接 E pin 数 | 驱动 | 最大总电容（pF） | 驱动库上限（pF） |
| --- | ---: | --- | ---: | ---: |
| n1 | 25 | U3 / CKND0 | 0.0405621 | 0.045377 |
| n2 | 25 | U4 / CKND0 | 0.0405621 | 0.045377 |
| n3 | 18 | U5 / CKND0 | 0.0292047 | 0.045377 |

68 个请求寄存器 E pin 全部覆盖，DC/PT 连接和电容相符。DC 库 default_fanout_load=1，PT E pin fanout_load=1；未查询到的属性仍标 UNAVAILABLE。原 66 条 min-capacitance 和后来的 1 条 max-capacitance 均未出现。依据：[DC 诊断](reports/syn/checks/lsu_enable_capacitance.rpt)、[PT 诊断](reports/sta/checks/lsu_enable_capacitance.rpt)、[DC 约束](reports/syn/checks/constraint_violations.rpt)、[PT 约束](reports/sta/checks/constraint_violations.rpt)。

clock DRC 属性仍不可查询，不能声称属性读回成功。但 [high_fanout](reports/syn/checks/high_fanout.rpt) 的实际连接显示：clk 直接驱动 **1509 个 CP pin**，与 1509 个时序单元一致，没有出现为 fanout 32 分组的时钟缓冲树。clock network delay 仍为 ideal 0；TIM-134/135 的阈值 1000 及聚合电容近似不是物理时钟树数据。CTS 后的 clock DRC 不在本轮范围内。

## 3. 面积与真实关键路径

叶级单元 **6909**，其中组合 **5400**、时序 **1509**；cell area **9242.855942**。相比上一轮记录的 9230.759940 增加 **12.096002 / 0.131%**。该上一轮目录已被同名 run 覆盖，比较依据是[诊断记录](../../s3-capacitance-check.md)，不能声称仍有该轮完整原始网表可供逐单元对照。

相比已归档 03，面积下降约 **2.823%**，但同时包含撤去强制端口 buffer、reset 评估边界调整和 fanout 策略变化，不作为单一 RTL 架构优化收益。依据：[area](reports/syn/area/area.rpt)、[QoR](reports/syn/summary/qor.rpt)。

PT max/min 的 WNS/TNS/负 slack 端点数均为 0。实际正裕量如下：

| 路径分类 | 最差 max slack（ns） | 最差 min slack（ns） |
| --- | ---: | ---: |
| Reg2Reg | +1.678541 | +0.008754 |
| In2Reg | +2.544242 | +0.162200 |
| Reg2Out | +0.596843 | +0.222797 |
| In2Out | No constrained paths | No constrained paths |

In2Out 为空与当前寄存接口及 reset false path 的分析范围相符；03 中该类最差路径来自 rst_n。本轮不把它解释为“0 ns 组合延迟”或凭空改善的性能。[check_timing](reports/sta/checks/check_timing.rpt) 没有未约束功能端点或缺时钟项。

全局 setup 最差：opbuf `data_q_reg_145_`（alu_rhs_imm）→ EXU 选择/ALU/redirect → `commit_redirect_reason[0]`；到达 **2.203157 ns**，要求 **2.8 ns**，slack **+0.596843 ns**。该观察输出保留真实数据锥及 2 ns 输出预算，没有用 false path 隐藏它。

内部 Reg2Reg 最差：同一起点经 ALU/redirect/IFU 的 next-PC 逻辑，到 opbuf `data_q_reg_210_`（pred_npc[31]），slack **+1.678541 ns**。后续 core timing 优化应同时看这条内部反馈路径与观察接口路径，不能把全局输出路径倒数称为内部 Fmax。

hold 最差：LSU `req_addr_q_reg_14_` → LSU adapter `request_addr_q_reg_14_`，slack **+0.008754 ns**。这是当前模型下通过，8.754 ps 不构成 CTS/布线后裕量承诺。

依据：[全局 max](reports/sta/timing/timing_max.rpt)、[全局 min](reports/sta/timing/timing_min.rpt)、[内部 max](reports/sta/timing/Reg2Reg_max.rpt)、[输入 max](reports/sta/timing/In2Reg_max.rpt)及各分类原始报告。

## 4. 9450 项 untested 的逐类处置

coverage：20180 项，10730 met，0 violated，9450 untested。对详细报告逐条汇总并核对总数，不将整个 untested 总数一概称为 reset waiver。

| 检查 / 原因 | 数量 | 本轮处置 |
| --- | ---: | --- |
| CDN/SDN min_pulse_width / no_clock | 6672 | reset 脉宽 deferred |
| recovery / no_startpoint_clock | 1377 | reset 释放 deferred |
| removal / no_startpoint_clock | 1377 | reset 释放 deferred |
| setup / constant_disabled | 4 | mtvec[1:0] 的 D/E 条件检查不可激活 |
| hold / constant_disabled | 4 | 同上 |
| recovery、removal / constant_disabled | 2 + 2 | 同两位寄存器的条件检查 |
| min_pulse_width / constant_disabled | 12 | 同两位：CDN 8 项、CP 4 项 |

**9426 项 reset deferred + 24 项已解释的常量条件禁用 = 9450。** `mtvec` 只支持 Direct mode，RTL 将写入低两位清零；网表 `gen_csr_1__csr_dfflr` 的 dnxt[1:0] 连接 Logic0。对应两个 enabled FF 保留在网表中，PT 禁用不可能成立的条件弧。这些记录不表示其他寄存器缺时钟，也不要求为了清零 coverage 计数而虚构约束。

依据：[coverage](reports/sta/checks/coverage.rpt)、[完整 untested](reports/sta/checks/coverage_untested.rpt)、[派生统计](review.json)、[reset TODO](../../reset-timing-todo.md)。保留 1379 个异步控制引脚的真实库条件项；本轮不声称 reset 脉宽或释放时序通过。

## 5. 结构与其他告警审查

DC post-check 未报告 latch、未驱动、多驱动或组合环；脚本另检查未映射叶单元和 latch，失败则不交付。剩余告警按实际连接分类：

| 类型 | 数量 | 审查结论 |
| --- | ---: | --- |
| LINT-28 未连接端口 | 157 | immediate 生成不使用 opcode 7 位；EXU pred_taken/pred_npc 33 位仅断言使用；CSR trap_epc 低 2 位对齐；其余为常量 +4 加法器的 B 端及 DW 的模式/进位/未使用结果端 |
| LINT-2 无负载网络 | 129 | AXI PROT/地址对齐常量 26；EXU 未用观察输出 64；opbuf 调试 rs1/rs2 index 10；decoder 恒零 trap_cause 位 29。不是无驱动，PT 无电气违例 |
| LINT-29 直通连接 | 195 | 模块连接与 adapter/观察输出；未强制插端口隔离 buffer |
| LINT-31 共网输出 | 317 | 广播响应、读写复用及常量输出共网；不是多个逻辑源相互驱动 |
| LINT-52 常量输出 | 56 | AXI PROT/对齐位、预测未跳转、有限异常 cause 编码 |
| LINT-33 同单元多个 pin 共网 | 26 | 常量、相同上下文与运算输入连接；不是组合反馈 |

预映射 LINT-1 无消费者中间算子在映射后不再报告。ALU VER-318 来自 `$signed(alu_src0) >>> ...` 的 32 位结果赋给 unsigned 32 位输出，保留位模式；符号右移语义是设计所需，功能回归版本未改变。ELAB-311 是完整状态枚举后的 default 分支，保留源代码防御分支，不关闭 warning。UCN-1/VO-4 与多端口共网及导出 assign 一致，PT 成功 link。

DDB-24 出现在同一 DB 的第二次 Loading，属于库重复载入的内存数据库替换提示；脚本没有向工艺 DB 写出的命令，driver 在阶段前后复核外部 DB hash，实际流程通过核对并进入 PT。不能仅按消息中的 “Overwriting design file” 推断磁盘工艺库被改写。UCN-4 出现在 `change_names -rules verilog` 的命名替换阶段；保留该配置告警，导出网表已由 PT 成功读取/link，没有未解析引用。两项均不作为本次时序/面积阻塞，后续可整理重复加载与命名规则而不改变此基线。

PT PTE-003 的 [禁用弧报告](reports/sta/checks/disable_timing.rpt) 为 **257 条 p + 101 条 C**（含重复条件弧记录），没有 l/L loop-breaking 或用户禁用弧标记。DC TIM-216 仅点名 rst_n，无 input delay 是已记录的 reset 范围决定。

UITE-502 是 Top-N 路径打印数量上限；独立全量负 slack 统计无违例。UITE-416 只出现在以 `all_registers -data_pins` 为终点的分类报告，提示 2 个 invalid endpoints；与两个常量 D 端及其 coverage 条件禁用相符，**具体端点对应关系属于交叉证据推断，工具未在该 warning 中列名**。它不是 check_timing 的 unconstrained endpoint 报告；全局 coverage 已逐条解释，因此作为非阻塞的报告筛选告警记录，后续增强诊断可补逐名查询，不假称已得到该 warning 的逐对象证明。

## 6. 基线资格与后续

I01/I02/I03/I06/I07/I08 在当前 scope 下通过审查；I06 的 reset deferred 和常量条件禁用按上表登记。I05 沿用同版本 S2.5 回归，未声称本次重跑；I09/I10、功耗、全角、CTS/布线、真实 reset 仍未评估。

可以以本次数据开展后续 timing/area 优化对照，无需继续为清零无害 warning 修改 RTL。下一步 S6 固化最终回归/复现入口及阶段总结；需要纯功能端口或不同 I/O 预算的实验应另立 scope，不能混入本基线比较。

按原字节归档 **51 份**报告、日志与追溯文件，映射/大小/SHA-256 见 [archive.json](archive.json)；review.json 是派生审查结果。未复制工艺 DB/完整库报告及网表/DDC，完整 run 仍需保留；原网表 hash 已在 manifest 中。没有修改运行产物、RTL、SDC 或 flow 脚本，也没有在本地执行新的 EDA。
