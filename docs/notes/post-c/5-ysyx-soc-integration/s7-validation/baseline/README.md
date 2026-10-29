# M5 S7：200 MHz CPU 子系统面积 / STA 基线

2026-10-29。**M17 / S7 在约定范围内通过**，采用已回传的 `soc-cpu-tt-5ns-s7-cap90`。DC/PT 电气规则和数据 setup/hold 无违例；面积为 **9530.135856 library_area**，PT 最差 setup/hold slack 为 **+2.444726 / +0.009693 ns**。基线用于后续 GShare 在相同边界和约束下比较。

用户明确决定：Ultra 自动 leakage 零目标在文档中说明，不为清空报告而重新综合。原始 DC **CONSTRAINT_FAIL**、PT **REVIEW_REQUIRED** 及完整报告原样保存；本页是人工审查结论，不改写工具结果。reset 物理时序仍暂缓，功耗未验收；本结论不是全 SoC、全 PVT 或布局布线 sign-off。M5 S8 的干净复现与总交接仍待完成。

## 1. 固定输入、评估边界与归档方式

| 项目 | 基线条件 |
| --- | --- |
| 原 run / HEAD | `npc/flow/build/soc-cpu-tt-5ns-s7-cap90` / `11a2608c224f05ed46c2bee57805a5300aa35135` |
| Top | `ysyx_25030087`；CPU + IFU/LSU AXI adapters + arbiter + router + 内部 CLINT |
| 范围之外 | 上游 SoC 互联、reset 延长链、UART/SPI/PSRAM 控制器、存储颗粒和仿真模型 |
| ISA / 宏 / 参数 | RV32E、16 GPR、无 M/C；`SYNTHESIS NPC_FLASH_BOOT`；PC_RST=0x30000000；IFQ_DEPTH=2 |
| 工具 | DC V-2023.12-SP5；PT T-2022.03-SP5 |
| 库 / PVT | `tcbn28hpcplusbwp12t40p140tt0p9v25c_ccs` / `tt0p9v25c`；TT、0.9 V、25°C；site 声明 RVT |
| 单位 | ns、pF；面积保留 library_area，未将它擅自改写成 μm² |
| 时钟 | 5 ns / 200 MHz；ideal clock；setup/hold uncertainty 0.2/0.05 ns；slew 0.1 ns；source latency 0 |
| I/O | 输入、输出 min/max delay 均为 0.2/2 ns；输入 slew 0.1 ns；输出 load 0.01 pF |
| 禁用接口 | 19 个外部 IRQ/slave 输入字段 case analysis=0；内部 CLINT timer IRQ 保持活动 |
| Reset | 仅 `set_false_path -from [get_ports reset]`；保留 slew 和电气负载；没有 case analysis 或虚构 release delay |
| 综合 | `compile_ultra -no_autoungroup`，再执行 `compile_ultra -incremental -only_design_rule`；max_fanout=32；clock network 不按数据 DRC 修复 |
| 电容 | DC 会话内 1321 个库引脚最大电容收紧为原值的 90%；PT 独立按原始 DB 验收 |
| 互连 / 功耗 | ZeroWireload、top mode；无 SPEF/CTS；Ultra 自动 leakage 优化仍启用；可选功耗报告关闭 |

PT `report_design` 显示 analysis_type 为 `on_chip_variation`，但 min/max 均为同一个 TT 工作条件，未施加额外 early/late derate；这不构成多角或实际工艺变化验证。该报告的 `Pin Input Delays: None specified` 指 pin-level 项，不能据此认为顶层 port 没有 I/O delay；原始 SDC、导出 SDC 和路径中的 2 ns input external delay 均可交叉核对。

**追溯核对：**94 个 run 内冻结输入及阶段产物的 SHA-256 全部匹配 manifest。服务器外部库/工具 hash 保留原记录，原 runner 在阶段结束时再次核对；本地没有运行或重新访问服务器 EDA。归档的 72 份原始文件逐字节复制，映射及 hash 见 [archive.json](archive.json)，派生审查统计见 [review.json](review.json)。不归档 DB、DDC、生成网表或 alib/work 数据；网表 hash 保留在原 manifest 中。

21 份 RTL/include 快照中，20 份与 S6 源 hash 完全相同；`ysyx_core.sv` 将两条 redirect 连续赋值移至 wire 声明之后，表达式没有变化，见 [原始 dirty.patch](provenance/inputs/dirty.patch)。2026-10-29 审查时本地 core 仍是原赋值位置，CSR 另有注释变化，因此当时不能说本地 RTL 与服务器快照逐字节一致。本基线固定到服务器快照；本次未重跑功能仿真或网表等价验证。

**2026-10-30 补记：**用户明确这项移动是为解决 DC 对 `trap_target` 先引用、后声明的报错，并已提交为 `9912da3af499daff1d2e168fef244f113f946e4b`。提交版本、当前本地 core 和 cap90 快照逐字节一致，SHA-256 为 `7a7c4ec68510f926497a53bb70ed63715a51357d3f816a56c40a888505b75252`。修复已包含在基线内，无需重综合；原 manifest/dirty.patch 和 review.json 的历史状态不改写。原因及后续 RTL 写法见 [S7 §4.1](../../7-synthesis-sta.md#41-dc-前端兼容性先声明信号再引用2026-10-30-补记)。

阅读入口：[原 manifest](provenance/manifest.json)、[原始设计配置](provenance/inputs/design-config.tcl)、[site](provenance/inputs/site-config.tcl)、[SDC](provenance/inputs/npc/flow/00_indata/constraints/soc_cpu.sdc)、[DC 导出 SDC](provenance/dc.sdc)、[综合脚本](provenance/inputs/npc/flow/02_syn/run.tcl)、[STA 脚本](provenance/inputs/npc/flow/03_sta/run.tcl)。这些脚本是历史证据，保留原服务器绝对路径，不将归档目录冒充可直接续跑的 run。

## 2. 面积、电气与实际时钟连接

| 指标 | 结果及含义 |
| --- | --- |
| Cell area | 9530.135856；组合 4687.703964，时序 4842.431892 |
| 叶级单元 | 7258 = 5635 个组合 + 1623 个触发器；`report_area` 的 7284 还包含 26 个层次实例 |
| 时序单元组成 | 1422 个 DFCNQD1、71 个 DFSNQD1、130 个 DFQD1；分别为异步清零、异步置位、无异步控制的 DFF |
| 宏 / blackbox / latch | 宏和 blackbox 为 0；脚本的未映射/latch 检查通过，网表叶级均解析为本工艺标准单元 |
| DC 电气 / PT 约束 | 电气违例 0；DC 仅剩 leakage 优化目标一项，PT 全部约束违例 0 |
| Clock | 唯一高扇出网络为 `clock`；直接连接的 1623 个 CP 与全部触发器集合逐项一致，没有为 fanout=32 插入时钟缓冲树 |

与前轮 Ultra 相比，面积减少 0.168 library_area（约 0.0018%），最差 setup/hold 不变，原 9 条 max-capacitance 消失；先前 7 条零负载 min-capacitance 也未回归。本轮同时包含裕量和增量 pass，不将它拆成某一个 pass 的独立优化收益。

clock 的 `auto_disable_drc_nets` 回读为 UNAVAILABLE；采用实际网表连接验证，而不是宣称属性查询成功。TIM-134/135 中的 fanout=1000、聚合电容=1001 是高扇出近似，不是物理时钟树寄生。CTS 和时钟网络的物理 DRC 留到后续实现阶段。

依据：[area](reports/syn/area/area.rpt)、[高扇出及连接](reports/syn/checks/high_fanout.rpt)、[裕量](reports/syn/environment/max_capacitance_margin.rpt)、[DC 约束](reports/syn/checks/constraint_violations.rpt)、[PT 约束](reports/sta/checks/constraint_violations.rpt)。

## 3. 关键路径对应什么硬件

PT max/min 的 WNS、TNS、负 slack 端点数均为 0；下表保留实际正裕量，不能将 WNS=0 误读为恰好卡在零裕量。

| 路径分类 | 最差 setup/max slack（ns） | 最差 hold/min slack（ns） |
| --- | ---: | ---: |
| Reg2Reg | +2.554867 | +0.009693 |
| In2Reg | +2.444726 | +0.164472 |
| Reg2Out | +2.505592 | +0.236882 |
| In2Out | No constrained paths | No constrained paths |

- **全局 setup：**`io_master_rvalid` → router 响应接收/数据保持 mux → `subsystem/router/rdata_q_reg_24_/D`。到达 2.342228 ns，其中外部输入预算占 2 ns；要求 4.786954 ns。它反映当前 I/O 预算下的读响应捕获路径。
- **内部 Reg2Reg：**opbuf `data_q_reg_145_` → ALU/EXU → redirect 与 IFU/IFQ → decoder → opbuf `data_q_reg_125_`。按 `ysyx_opbuf.sv` 的 277-bit 拼接，起点是 `alu_rhs_imm`，终点是 `csr_wen`；到达 2.231622 ns。这是一条跨执行、取指控制和译码的组合反馈路径，不是已经退休指令的观察输出。后续时序优化可从这一控制链分析。
- **输出 setup：**router `state_q_reg_3_` → `io_master_awvalid`；到达 0.294408 ns，要求 2.8 ns，包含外部接收预算。
- **全局 hold：**IFQ `count_q_reg_0_` → 一层 MAOI22 → 自身 D；到达 0.084371 ns，要求 0.074677 ns。9.693 ps 的裕量仅说明当前 ideal-clock / ZeroWireload 模型通过，不能承诺 CTS 后仍然通过。

In2Out 无受约束路径与当前寄存式边界、常量字段及 reset 例外相符；PT `check_timing` 没有未约束功能端点或缺时钟诊断。本基线确认 200 MHz 目标通过，不把 `1/(5 ns−最差 slack)` 当成物理 Fmax。

原始路径：[全局 max](reports/sta/timing/timing_max.rpt)、[全局 min](reports/sta/timing/timing_min.rpt)、[Reg2Reg max](reports/sta/timing/Reg2Reg_max.rpt)、[In2Reg max](reports/sta/timing/In2Reg_max.rpt)、[Reg2Out max](reports/sta/timing/Reg2Out_max.rpt)；其余分类同目录保存。

## 4. 9120 项 untested 的逐类处置

Coverage 共 19076 项：9956 met、0 violated、9120 untested。setup/hold 各 1623 项均 100% met；逐条解析完整报告得到：

| 类型 / 原因 | 数量 | 对象及处置 |
| --- | ---: | --- |
| recovery / no_startpoint_clock | 1493 | 1422 个 CDN + 71 个 SDN；reset 释放时序 deferred |
| removal / no_startpoint_clock | 1493 | 同上 |
| min_pulse_width / no_clock | 5972 | CDN/SDN 的低有效脉宽检查；reset/set 脉宽 deferred，不是 FF 的 CP 缺时钟 |
| out_setup / no_paths | 81 | 常量输出，无活动数据路径 |
| out_hold / no_paths | 81 | 同一组常量输出 |

**8958 项 reset deferred + 162 项常量输出检查 = 9120。** 81 个常量输出与 `report_disable_timing` 的 81 个传播常量 `p` 对象完全一致，包括禁用 slave 输出、单拍 ID/LEN/BURST 等固定字段；其中三项为常量 1，其余为 0，完整位集合在 [review.json](review.json)。没有其他原因的 untested，也没有 loop-breaking 的 `l/L` 标记。

物理 reset 的来源、同步释放、分布延迟和脉宽仍需在真实实现时建立。本 scope 外已有 SoC reset 延长链，但功能仿真保持若干周期不证明这些模拟时序检查通过；继续关联 [reset TODO](../../../4-pre-soc-signoff/reset-timing-todo.md)。内部 mtime/mtimecmp/MTIP 逻辑并未被排除。

依据：[coverage](reports/sta/checks/coverage.rpt)、[完整 untested](reports/sta/checks/coverage_untested.rpt)、[禁用弧](reports/sta/checks/disable_timing.rpt)、[check_timing](reports/sta/checks/check_timing.rpt)。

## 5. 告警审查：对应对象、原因和接受依据

下表只处置本次冻结产物。出现相同编号的新告警时仍需查看对象，不能建立全项目按编号忽略的规则。所有 log/report 均未发现主流程 Error/Fatal；逐文件出现次数保存在 [review.json](review.json)，计数包含同一信息在不同报告重复出现。

| 告警 / 信息 | 本次证据与判断 |
| --- | --- |
| LINT-2，post 1228 条 | 逐条解析驱动层次，全部落在保留的 module 输出，未落在标准单元输出；主要为 commit/monitor、固定或未用字段。保留层次后端口名仍存在，与 leaf 零负载不是同一件事；本次库 min-capacitance 无违例。 |
| LINT-28，post 1838 条 | 未连接层次端口；顶层 141 bit 恰为已禁用的 19 个 IRQ/slave 输入字段。内部主要为被裁剪的观察字段、预测字段、立即数 opcode 位、对齐低位及受支持 CSR 位之外的端口。 |
| LINT-60，post 479 条 | 明确为无内外负载的 hierarchical input pin，集中在上述裁剪字段、opbuf payload 和 CSR dnxt。没有新增标准单元输入缺驱动类别；PT link/check_timing 成功。 |
| LINT-29 / LINT-31，post 85 / 187 条；UCN-1 195 条；VO-4 | EXU 的 pc/rs2/CSR 地址等直通，arbiter/router 读数据转发，以及多个常量端口共网。允许合法 assign/feedthrough，避免强制端口 buffer；PT 正常读入和连接此网表。UCN-1 的对象也来自这些连接。 |
| LINT-52，post 81 条 | 常量输出，位集合与 coverage/disable_timing 一致。 |
| LINT-1 / LINT-32 / LINT-33，pre 17 / 7 / 18 条 | 展开阶段的无用单元、常量或重复子模块输入；post 中这三类均消失。不得把 pre 工艺无关冗余当成最终网表问题。 |
| ELAB-311，两处 | LSU 和 IFU adapter 已覆盖全部二进制状态，default 分支在综合状态空间中不可达；不改变其正常状态机功能，也不构成非法状态自恢复验证。 |
| VER-318，一处 | ALU 的 `$signed(alu_src0) >>> shamt` 结果送到同宽 unsigned 输出；signed 保证算术右移，最终保存 32-bit 位模式。原表达式沿用已通过功能验证的 RTL。 |
| TIM-216，一处 | 仅顶层 reset 无 clock-relative input delay，符合暂缓 reset 时序的约定；正常数据 I/O 无该问题。 |
| TIM-134 / TIM-135 | 唯一高扇出网络是 ideal clock；真实 CP 集合已核对，见 §2。 |
| PTE-003 | 81 项常量传播禁用，详见 §4；没有组合环打断。 |
| UITE-502，两处 | 全局 timing report 只展示 20 条路径；另外的全部负 slack 端点枚举为 0，不能以“只打印 20 条”解释为“只分析 20 条”。 |
| NPC_CAP_NO_ENABLE_PINS，DC/PT 各一次 | 旧诊断查询 LSU E pin；本轮 68 个 req 状态寄存器均映射为无 E pin 的 DFCNQD1，使能由数据 mux 实现。该查询不适用，电容结论依据全设计约束报告。 |
| DDB-24，一次 | 日志显示重复 `read_db` 时发生；脚本没有 `write_lib`，原 runner 在 DC/PT 结束后核对输入 DB hash 成功。它不构成库文件被裕量设置写回的证据。 |
| UISN-40，两次 | Ultra 自动加入 DesignWare 合成库；最终叶级全为工艺单元，无 GTECH/未解析引用。 |
| UCN-4，一次 | 名称规范化中替代字符配置冲突提示；导出的网表已由 PT 成功解析/连接，名称可用于本次报告定位；不据此修改已冻结网表。 |
| PWR-24 / PWR-536（Information） | tie cells 缺 internal-power 表；本次未验收动态/总功耗，不影响本范围面积/时序结论。 |
| PWR-884 / PWR-850、max_leakage_power | Ultra 自动漏电优化不能关闭；单独处置见 §6。 |

原始证据：[DC log](logs/syn.log)、[PT log](logs/sta.log)、[pre check_design](reports/syn/checks/check_design_pre.rpt)、[post check_design](reports/syn/checks/check_design_post.rpt)、[DC check_timing](reports/syn/checks/check_timing.rpt)。

## 6. Leakage 例外与最终结论

`set_leakage_optimization false` 已被执行，但本版本明确给出 PWR-884：Ultra 的漏电优化自动启用且不能关闭。DC 报告 required=0、actual=7389.414551 nW（约 7.389 μW）。项目没有零漏电预算，这个优化目标未达到不等于面积/数据时序或电气规则不合格；该数字也不是运行 RT-Thread 的总功耗。

**2026-10-29 用户明确接受：只记录这一事实，无需为消除表面 constraint violation 重跑。** 因此保留运行脚本中未生效的关闭请求、原始约束报告及自动状态；本次人工验收只将这一已定位的自动零目标登记为已处置。没有放宽 capacitance/slew/timing，也没有忽略未来真实功耗预算的违例。

最终结论：**本范围的面积、数据时序和电气基线成立，S7 / M17 通过，无未处置阻塞。** 下一步 M5 S8 完成冻结版本干净复现、总验收和后续 GShare 对照条件交接。后续比较应保持本 top、观察边界、库、5 ns/接口预算及优化策略一致；改变任何一项都需明确记录，不能把 M4 与 M5 的不同边界直接当成优化前后。
