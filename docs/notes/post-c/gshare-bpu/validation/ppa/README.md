# S4：OFF / GSHARE DC/PT 回传审查

2026-11-01。**两组结果在约定的 CPU 子系统 pre-layout 面积、数据时序及电气检查范围内通过，无新增阻塞错误。** GSHARE 相对同批 OFF 的 cell area 增加 **21.076%**，两者均满足 **5 ns / 200 MHz** 目标。S4 完成；最终版本冻结与交接属于 S5。

原始自动状态仍为 DC `CONSTRAINT_FAIL`、PT `REVIEW_REQUIRED`：DC 仅有已接受的 Ultra leakage 零目标违例；PT 无约束违例，但 reset/set 的物理时序暂缓，常量输出也有 untested。这里记录人工审查结论，未改写原 manifest 或报告。

**library_area** 是工艺库的单元面积计量值，本项目尚未独立确认它与 μm² 的换算。**CP / CDN / SDN / E** 分别为触发器的时钟、低有效异步清零、低有效异步置位、同步使能引脚。**coverage** 统计库时序检查项，一个引脚或触发器可以对应多项条件检查，不能直接当成寄存器数量。

## 1. 输入一致性与归档

| 项目 | 核对结果 |
| --- | --- |
| 原始 run | `npc/flow/build/soc-cpu-tt-5ns-bpu-off`、`npc/flow/build/soc-cpu-tt-5ns-bpu-gshare` |
| 源版本 | 两者均为 `9d7c63d562c2298e7f00451eab37c946205733e8`；服务器记录的 git-status / dirty.patch 为空 |
| 源码与脚本 | 两组 49 个冻结输入仅 `design-config.tcl`、`run.tcl` 不同；RTL、公共配置、SDC、filelist、综合/STA 脚本相同，快照与当前本地对应文件一致 |
| 唯一有效配置差异 | `NPC_BPU_MODE=0` / `NPC_BPU_MODE=2`；索引宽度均为 7 |
| 工具 | DC V-2023.12-SP5；PT T-2022.03-SP5；两组记录的工具入口、DC setup 和 DB hash 一致 |
| 库与单位 | `tcbn28hpcplusbwp12t40p140tt0p9v25c_ccs`、`tt0p9v25c`；TT / 0.9 V / 25°C；ns、pF、library_area |
| Scope | `ysyx_25030087`：core、AXI adapters/arbiter/router、CLINT；不含上游完整 SoC、存储颗粒或仿真 monitor |
| 时序条件 | 5 ns、ideal clock、ZeroWireload/top；setup/hold uncertainty 0.2/0.05 ns，输入/输出 delay 0.2/2 ns，输入 slew 0.1 ns，输出 load 0.01 pF |
| 综合策略 | Ultra `-no_autoungroup` + incremental design-rule fixing；max fanout 32；DC 库引脚 max capacitance 使用 90% 上限，PT 按原库验收 |
| 例外 | 仅 reset 发起路径 false path；19 个禁用外部 IRQ/slave 输入字段 case analysis=0；内部 CLINT timer IRQ 正常分析 |
| 功耗 | 可选 report_power 关闭；Ultra 自动 leakage 优化实际仍启用，不等于有功耗预算或功耗验收 |

逐文件核对两组 run 各 **98 个冻结输入及阶段产物**，均与 manifest SHA-256 一致；按当前同版本 runner 的 `inspect_stage` 重新解析得到的结果也与原记录一致。这是本地文件审查，没有重新运行 DC/PT，也没有重新访问服务器工具和 DB；外部依赖保留服务器记录的 hash。

本目录逐字节归档 **194 份原文件**，包括 manifest、49 个登记输入、日志、报告和 DC 导出 SDC；不复制后来生成在 inputs 工作目录中的 alib/cache、DB、DDC 或生成网表。生成网表、DDC 的原 hash 已核对并保留在 manifest 中。复制映射与 hash 见 [archive.json](archive.json)，派生统计见 [review.json](review.json)。

入口：[OFF manifest](off/manifest.json)、[GSHARE manifest](gshare/manifest.json)、[OFF 配置](off/inputs/design-config.tcl)、[GSHARE 配置](gshare/inputs/design-config.tcl)、[公共 SDC](gshare/inputs/npc/flow/00_indata/constraints/soc_cpu.sdc)、[综合脚本](gshare/inputs/npc/flow/02_syn/run.tcl)、[STA 脚本](gshare/inputs/npc/flow/03_sta/run.tcl)。归档保留服务器绝对路径，用于审阅，不能把本目录作为原 run 直接续跑。

## 2. 面积与硬件保留情况

| 指标 | OFF | GSHARE | 增量 |
| --- | ---: | ---: | ---: |
| 总 cell area | 9583.727856 | 11603.591918 | +2019.864062（+21.076%） |
| 组合 cell area | 4741.295964 | 5097.791949 | +356.495985 |
| 时序 cell area | 4842.431892 | 6505.799968 | +1663.368076 |
| 叶级标准单元 | 7345 | 8461 | +1116 |
| 触发器 | 1623 | 2006 | +383 |
| IFU 层次总面积 | 974.7360 | 2996.2800 | +2021.5440 |
| IFQ 层次面积 | 577.4160 | 916.4400 | +339.0240 |
| GShare 模块面积 | 已裁剪 | 1518.2160 | 含 PHT/GHR、查询和训练逻辑 |
| predecode 面积 | 已裁剪 | 123.9840 | 组合预译码与目标偏移生成 |

网表展开后，GSHARE 的预测器保留 **256 个 PHT 存储位 + 7 个 GHR 位**；OFF 中该模块被裁剪。两组均无 macro/blackbox、GTECH 或未解析叶级引用，叶级均为当前库标准单元。新增 383 个触发器中，263 个位于预测器，其余为前端/上下文等状态的净增量。

面积增量是完整预测方案的成本，包含 JAL 提前处理、目标计算、metadata、恢复比较及全设计重新映射。它不是“256 bit PHT 的面积”，也不能从该对照单独推导纯 GShare 相对 JAL_ONLY 的面积；本轮没有 JAL_ONLY 的 DC/PT 对照。局部映射也发生变化，IFU 增量不要求恰好等于顶层增量。

GSHARE 映射出 649 个 `EDFCNQD1`（带 E 引脚）触发器，OFF 为 0；其余均为常规 DFF。两组唯一高扇出网络均为 `clock`，其直接负载 CP 集合与全部 **1623 / 2006** 个触发器逐项一致，没有为 max_fanout=32 插入时钟缓冲树。

本批 OFF 与历史 M5 的 9530.135856 相比略有变化，因此正式面积增量使用本批 **OFF→GSHARE**，不混用历史数字。依据：[OFF area](off/reports/syn/area/area.rpt)、[GSHARE area](gshare/reports/syn/area/area.rpt)、[GSHARE high_fanout](gshare/reports/syn/checks/high_fanout.rpt)。

## 3. 时序结果与关键路径

| 路径分类 | OFF setup/max slack（ns） | GSHARE setup/max slack（ns） | OFF hold/min slack（ns） | GSHARE hold/min slack（ns） |
| --- | ---: | ---: | ---: | ---: |
| Reg2Reg | +2.591039 | +1.801808 | +0.009693 | +0.008700 |
| In2Reg | +2.444726 | +2.444726 | +0.164472 | +0.164472 |
| Reg2Out | +2.505592 | +2.505592 | +0.236882 | +0.239585 |
| In2Out | 无受约束路径 | 无受约束路径 | 无受约束路径 | 无受约束路径 |

两组 max/min 的 WNS、TNS 和 violating endpoints 均为 0。这里的 WNS 只统计负裕量；实际正裕量见上表，不能把 WNS=0 解读成卡在零裕量。

- **OFF 全局 setup**：`io_master_rvalid` → router → `rdata_q_reg_24_/D`，+2.444726 ns。
- **GSHARE 全局 setup**：opbuf `data_q_reg_140_` → ALU 进位链 → EXU/恢复控制 → IFU/IFQ → 主译码 → opbuf `data_q_reg_125_/D`，到达时间 2.967990 ns，slack +1.801808 ns。按当前 285-bit payload，起点对应 `alu_ctrl[0]`，终点对应 `csr_wen`。这是功能控制反馈路径；所报告的最差路径没有经过 PHT 查询。OFF 最差 Reg2Reg 从 `data_q_reg_145_`（`alu_rhs_imm`）到同一终点，slack +2.591039 ns；开启预测后该类组合链的时序代价已经体现在报告中。
- **GSHARE 全局 hold**：IFU `fetch_pc_q_reg_28_` → IFU AXI adapter `request_addr_q_reg_28_/D`，到达 0.070713 ns，slack +0.008700 ns。

In2Out 无路径与当前寄存式边界、常量输出及 reset 例外相符；PT `check_timing` 没有未约束功能端点、缺时钟或组合环诊断。8.7 ps 的 hold 裕量只在本次 ideal-clock/ZeroWireload 模型下成立；没有 CTS、布线寄生或多 PVT 验证，不从这些正裕量反推物理 Fmax。

原始路径：[OFF Reg2Reg max](off/reports/sta/timing/Reg2Reg_max.rpt)、[GSHARE Reg2Reg max](gshare/reports/sta/timing/Reg2Reg_max.rpt)、[GSHARE Reg2Reg min](gshare/reports/sta/timing/Reg2Reg_min.rpt)；其余分类及全局前 20 条路径分别保留在两组 timing 目录。

## 4. Coverage：未测试项均已解释

| 检查 / 原因 | OFF | GSHARE | 审查结论 |
| --- | ---: | ---: | --- |
| setup：全部 met | 1623 | 3304 | 无 violated / untested |
| hold：全部 met | 1623 | 3304 | 无 violated / untested |
| recovery / no_startpoint_clock | 1493 | 1796 | CDN/SDN 释放时序，继续 deferred |
| removal / no_startpoint_clock | 1493 | 1796 | 同上 |
| min_pulse_width / no_clock | 5972 | 9780 | 全部为 CDN(low)/SDN(low)，reset/set 脉宽继续 deferred |
| out_setup / no_paths | 81 | 81 | 固定输出 |
| out_hold / no_paths | 81 | 81 | 同一组固定输出 |
| 总 untested | 9120 | 13534 | 无其他类型或原因 |

GSHARE 的 9780 项脉宽未测由 **5192 项 EDFCNQD1 CDN + 3788 项 DFCNQD1 CDN + 4 项 DFCND1 CDN + 796 项 DFSNQD1 SDN** 构成。带使能的 EDFCNQD1 在报告中每实例对应 8 项 reset 脉宽条件，其余上述单元每实例为 4 项；因此未测数量增长既来自更多触发器，也来自不同库单元的条件数，不能只按寄存器增量估算。**这些 no_clock 都在异步控制脚，不是 CP 没有时钟。**

每组的 81 个常量输出与 `report_disable_timing` 的 81 个 `p`（propagated constant）对象逐项一致；无 `l/L`（loop breaking）或其他未解释禁用弧。PT `PTE-003` 因此来自常量传播，不是组合环打断。reset 待办继续关联 [reset-timing-todo.md](../../../4-pre-soc-signoff/reset-timing-todo.md)。

原始证据：[OFF coverage](off/reports/sta/checks/coverage.rpt)、[GSHARE coverage](gshare/reports/sta/checks/coverage.rpt)、[GSHARE 完整 untested](gshare/reports/sta/checks/coverage_untested.rpt)、[disable_timing](gshare/reports/sta/checks/disable_timing.rpt)。

## 5. 电气规则、leakage 与告警

两组 PT `report_constraint -all_violators` 均无违例；DC 只有 `max_leakage_power` 一行，没有新增 min/max capacitance、transition、fanout 或数据时序违例。DC 所用的 90% 电容裕量在两组一致，PT 仍使用原库上限。

Ultra 报出 PWR-884，说明 leakage 优化自动启用且不能关闭；required=0，OFF/GSHARE actual 分别为 **7412.663086 / 8735.994141 nW**。沿用用户在 M5 的决定：保留原始违例与自动状态，只对这一不存在真实预算的零目标作例外处置，不为清空报告重综合。这些数字不表示程序运行时的总功耗。

| 告警类别 | 本次对象与处置 |
| --- | --- |
| Error / Fatal / NPC_FLOW_ERROR | 两组主日志和报告均未发现 |
| post LINT-2 | OFF 1291、GSHARE 1134 条；逐条定位，驱动均为层次 module 输出，无标准单元无负载输出类别；库 min-capacitance 无违例 |
| post LINT-28 / LINT-60 | 未连接层次端口、无内部负载的层次输入；顶层均为 141 bit 禁用外部 IRQ/slave 输入。LINT-60 均明确为 hierarchical cell，未出现新叶级缺驱动告警 |
| post LINT-29 / LINT-31 / LINT-52 | 两组各 85 / 187 / 81 条；合法直通、常量共网、常量输出，与允许 assign/feedthrough 的策略相符 |
| GSHARE post LINT-33 | 1 条，IFU 的 `u_ifq` 多个输入位共网；实际 `.in_data` 中 `request_pc_q[0]` 同时用于地址低位及复用位，不是多驱动 |
| pre LINT-1 / LINT-32 等 | 展开阶段冗余；LINT-1/32 在最终 post 中消失，不能把尚未优化的常量/未使用单元当成最终功能丢失 |
| VER-318 | 原 ALU 算术右移的同宽 unsigned 赋值；GSHARE 新增 `INDEX_BITS'(entry)` 的 signed→unsigned 比较转换。entry 为 0～127，转换后 7-bit 位模式与 train_index 比较正确，单元模型已覆盖全部索引 |
| ELAB-311 | IFU adapter、LSU 的二进制状态空间已穷尽，default 不可达；未改变正常状态语义 |
| TIM-216 | 仅 reset 无 clock-relative input delay，符合 reset 时序 deferred 合同 |
| TIM-134 / TIM-135 | 仅 ideal clock 高扇出，实际 CP 连接已核对；报告中的 1000/1001 为工具近似，不作为物理时钟网络结论 |
| PTE-003 / UITE-502 | 前者仅为 81 个常量传播对象；后者为 report_timing 的打印数量限制。全部负 slack 端点枚举为 0，分析不只覆盖打印的 20 条 |
| OFF NPC_CAP_NO_ENABLE_PINS | OFF 的 LSU FF 无 E pin，旧定点诊断不适用；GSHARE 使用带 E 的 FF，该报告正常给出数据。全设计电气结论来自约束报告 |
| DDB-24 / UISN-40 / UCN-1 / UCN-4 / VO-4 | 沿用 M5 的库重读、DesignWare 自动加入、命名及合法 assign 提示；最终网表全映射，PT 读入/连接完成，登记输入和产物 hash 一致 |

原始证据：[OFF DC 约束](off/reports/syn/checks/constraint_violations.rpt)、[GSHARE DC 约束](gshare/reports/syn/checks/constraint_violations.rpt)、[GSHARE PT 约束](gshare/reports/sta/checks/constraint_violations.rpt)、[GSHARE post check_design](gshare/reports/syn/checks/check_design_post.rpt)、[DC log](gshare/logs/syn.log)、[PT log](gshare/logs/sta.log)。

## 6. 可对外表达的结论

在相同 CPU 子系统 scope、库和 5 ns 约束下，完整 GShare + predecode 方案以 **21.076% 单元面积增量**，获得六个固定镜像 **1.114～1.201× 的周期加速比**，并保持 200 MHz pre-layout 数据时序与电气检查通过。功能/性能比较与 EDA 使用同一实现；仿真 harness 的时钟仍为 100 MHz，这里的周期比和 200 MHz STA 目标分别来自两套测量，不声称已重跑 200 MHz 整机仿真。

这说明实现了可量化的性能/面积取舍。若按同频 throughput/area 衡量，本轮六项速度提升均小于面积增长，不应声称面积效率也提高；未测动态功耗，不给能效结论。当前没有新增阻塞，下一步按 [signoff](../../signoff.md) 完成 S5 冻结与 JOB-PREP-01 交接。
