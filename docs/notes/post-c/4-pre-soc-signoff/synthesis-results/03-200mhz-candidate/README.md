# 03：200 MHz DC/PT 基线候选

2026-10-18。**5 ns 下 DC/PT 均执行完成，PT 最差 setup/hold slack 为 +0.531597/+0.013534 ns，面积 9511.319905 library_area。仍有 66 条最小电容违例和复位脉宽覆盖审查项，尚不作为正式 S3 基线。** 原 run 虽命名为 `core-tt-5ns-baseline`，名称不代表验收通过。

## 1. 输入与比较边界

原 run：`npc/flow/build/core-tt-5ns-baseline/`。源版本 `344dde6ed4d73dc31947514973e9a13d888b7db5`；dirty patch 仅将 flow Makefile 的默认 SITE 改为 `site.local.tcl`。本次为服务器重新综合及 STA，不是只对旧网表改周期。

| 项目 | 实际值 |
| --- | --- |
| Top / scope | `ysyx_core_axi4lite`；Core + IFU/LSU adapters + Arbiter，保留 commit/monitor 输出；不含 Xbar、SRAM、外设 |
| ISA | S2.5 的 16 GPR、无 M/C、非法指令异常和限定 CSR 契约；不声明完整 ISA/特权合规 |
| 工具 | DC V-2023.12-SP5；PT T-2022.03-SP5 |
| 综合 | 普通 wire-load 模式，`compile -map_effort medium` |
| 库 / 条件 | `tcbn28hpcplusbwp12t40p140tt0p9v25c_ccs` / `tt0p9v25c`；TT、0.9 V、25°C；site 声明 RVT |
| 单位 | ns / pF；面积使用 library_area，未确认 μm² |
| 时钟 | 5 ns / 200 MHz；ideal clock，setup/hold uncertainty 0.2/0.05 ns |
| 接口 | input/output/reset min/max 0.2/2 ns；input/clock transition 0.1 ns；output load 0.01 pF |
| 互连 | DC/PT 实际均为 ZeroWireload；无布局、CTS、SPEF |
| 功耗 | 关闭，NOT_EVALUATED |

核验原 manifest 的 36 项输入、22 项 syn 产物、24 项 sta 产物 hash，全部一致；17 份 RTL 快照与本地及 02 实验一致。未在本地重跑 EDA，也未重新核验服务器工具或外部 DB。归档保留原始 [manifest](provenance/manifest.json)、[配置](provenance/design-config.tcl)、[site](provenance/site-config.tcl)、[dirty patch](provenance/dirty.patch)、输入 [SDC](provenance/core.sdc) 和导出 [SDC](provenance/dc.sdc)。

相比 [02](../02-rv32e-no-m/README.md)，RTL、scope、I/O 预算、库和综合策略不变，目标从 10 ns 收紧到 5 ns，并增加诊断报告。面积仍为 **9511.319905**，叶子单元 7656、时序单元 1509。本次未观察到收紧目标带来的面积增加，但两次网表并非字节相同，不能把相同面积当作网表等价证明；也不属于新增架构优化。与 01 相比的面积下降包含 ISA/GPR 范围变化。

依据：[area](reports/syn/area/area.rpt)、[QoR](reports/syn/summary/qor.rpt)、[互连模型](reports/sta/environment/wire_load.rpt)。

## 2. 时序与关键路径

PT 代表路径已包含正 slack，四类路径均有实际内容。max/min 指标的 WNS/TNS/负 slack 端点数均为 0；WNS 是截断到 0 的负裕量指标，不是下表的实际最小正裕量。

| PT 路径分类 | 最差 max slack（ns） | 最差 min slack（ns） |
| --- | ---: | ---: |
| [Reg2Reg](reports/sta/timing/Reg2Reg_max.rpt) | +1.600592 | +0.013534 |
| [In2Reg](reports/sta/timing/In2Reg_max.rpt) | +2.242464 | +0.162203 |
| [Reg2Out](reports/sta/timing/Reg2Out_max.rpt) | +0.531597 | +0.222797 |
| [In2Out](reports/sta/timing/In2Out_max.rpt) | +0.557764 | +0.447825 |

全局 setup 最差路径仍为：

```text
core/u_opbuf/u_context_reg/data_q_reg_145_（alu_rhs_imm）
  → EXU 操作数选择 → ALU → redirect
  → commit_redirect_reason[0]
```

PT 数据到达 2.268403 ns，要求时间 `5 − 0.2 − 2 = 2.8 ns`，slack **+0.531597 ns**；DC 对应为 +0.531889 ns。此前约 +0.53 ns 的预测得到实测支持。这是包含输出预算的路径，不能用 `1/2.268403 ns` 宣称 core Fmax。

内部 Reg2Reg 最差路径同样从 `data_q_reg_145_` 出发，经 ALU/redirect、IFU 的 IFQ 控制与 `add_83`，到 `data_q_reg_210_`。按 opbuf 的 277 位拼接，终点是 `pred_npc[31]`；IFU 的 `add_83` 对应 `if_ctx_pred_npc = if_ctx_pc + 32'd4`。数据到达 3.187134 ns，要求 4.787726 ns。这条反馈路径为后续优化提供了具体对象，不能仅凭 redirect/flush 命名认定为 false path。

全局 hold 最差是 arbiter 的 `owner_q_reg → prefer_lsu_q_reg`，到达 0.088077 ns、要求 0.074543 ns、slack **+0.013534 ns**。当前模型下满足，但约 13.5 ps 的裕量不能保证 CTS/布线后 hold 仍满足。

In2Reg 最差起点为 `rst_n`、终点为 LSU adapter 状态寄存器的 D pin；这是 reset 影响组合数据逻辑的路径，不是该分类中的 recovery 检查。In2Out 最差也是 `rst_n → monitor_bus[0]`，包括 2 ns 输入预算与 2 ns 输出预算。后续若提高频率，应同时审阅内部路径和实际接口预算，不能只去掉观察路径便宣称解决。

依据：[全局 max](reports/sta/timing/timing_max.rpt)、[全局 min](reports/sta/timing/timing_min.rpt) 和各分类报告。上述结论仅限本次 TT、ideal clock、ZeroWireload 模型，不外推 post-route 或全 PVT。

## 3. 高扇出与 PTE-003 已有明确对象

DC [high_fanout.rpt](reports/syn/checks/high_fanout.rpt) 记录阈值 1000，超阈值网络只有 **clk，1509 个负载**。这与时序单元数量一致，报告列出实际连接；时序报告仍使用 ideal clock、clock network delay 为 0。

报告同时提示 TIM-135 的高扇出估算，并打印聚合电容 1001；这个值处于工具的高扇出近似模型下，不能解释成实际时钟树有 1001 pF，也不能据此认定它导致数据路径失败。物理时钟驱动与分布需到 CTS 后评估；本次不通过调整阈值来掩盖告警。

PT [disable_timing.rpt](reports/sta/checks/disable_timing.rpt) 共 374 条打印记录（含重复条件弧，不等于独立路径数）：269 条 `p`（propagated constant），105 条 `C`（conditional arc），**没有 `l/L` loop-breaking 标记**。因此本次 PTE-003 不能解读为“发现组合环”；其已列出的禁用原因是常量传播/条件弧。这个结论不替代整体结构与常量裁剪审查。

PT 日志中的 UITE-502 表示代表路径报告达到了 `max_paths` 上限；纳入正 slack 后，未打印的其余端点不等于违例。WNS/TNS 的负 slack 端点查询独立执行，不能把 Top-N 报告当作全量覆盖率统计。

## 4. CONSTRAINT_FAIL 的原因与剩余审查

### 66 条最小电容违例

DC 无约束违例，评价为 REVIEW_REQUIRED；PT 执行 COMPLETE，但评价为 **CONSTRAINT_FAIL**。六位精度的 [constraint_violations.rpt](reports/sta/checks/constraint_violations.rpt) 显示 66 条均为 `min_capacitance`：required **0.000410 pF = 0.410 fF**，actual 打印为 0.000000 pF，slack −0.000410 pF。没有 setup/hold 负 slack，也不是 PTE-003 导致了这个评价。

结合原 run 的 `outputs/core.v`，全部为 EXU 内 `BUFFD1BWP12T40P140` 的输出 Z：

| 输出 | 数量 | 无负载的连接依据 |
| --- | ---: | --- |
| EXU `commit_pc[31:0]` | 32 | 父层实例连接 `SYNOPSYS_UNCONNECTED_40..71` |
| EXU `commit_mem_wdata[31:0]` | 32 | 父层实例连接 `SYNOPSYS_UNCONNECTED_72..103` |
| EXU `trap_epc[1:0]` | 2 | 送入 CSR，但 CSR 对 `mepc` 执行 `& 32'hfffffffc`，映射逻辑不使用这两位 |

这不是缺少顶层 output load：前两项是未使用的**子模块**输出，顶层同名观察输出另有驱动。下一步应检查层次优化及输出 buffer 插入后的无用逻辑清理，结合 RTL 接口确认能否消除这些无负载单元；具体在哪一步留下 buffer 尚未证明。不要给未连接网络虚构负载，也不要通过 timing exception 消掉电气违例。

DC [check_design_post](reports/syn/checks/check_design_post.rpt) 仍有 157 个未连接端口、129 个无负载网络和 26 个同单元多引脚共网检查项，需结合上述连接完成分类审查。未在本次文档审阅中修改网表或 flow。

### 复位/置位脉宽覆盖

[coverage](reports/sta/checks/coverage.rpt) 共 17852 项：12336 met、0 violated、5516 untested。setup/hold 各 1509、recovery/removal 各 1379、out_setup/out_hold 各 262，全部 met。min_pulse_width 共 11552，其中 6036 met、5516 untested。

[untested 明细](reports/sta/checks/coverage_untested.rpt) 全部为 `no_clock` 的 low-pulse 检查，对应 1374 个 CDN 和 5 个 SDN，每个引脚 4 项，与 02 一致。这不表示数据路径缺时钟，也不证明复位脉宽满足。正式基线前需明确外部 reset 最小有效脉宽、有效的验证证据和静态分析覆盖边界；recovery/removal 通过不能替代它，也不应给 reset 虚构时钟来消除未测试项。

## 5. 下一步与归档

1. 处理上述 66 个无负载 buffer，核对其他结构告警，改动后保留功能验证并重跑 DC/PT。
2. 给出 reset 脉宽的接口要求与验证/审查结论，形成具体覆盖边界；本记录没有自动豁免未测试项。
3. 冻结目标、scope、约束和源版本后再验收正式 S3；若目标继续为 200 MHz，本次时序结果已提供支持。暂不需要因 PTE-003 而假设存在组合环或重写仲裁器。

本次按原字节保留 48 份报告、日志和追溯文件，映射及 SHA-256 见 [archive.json](archive.json)。不复制 DB、完整工艺库报告、完整 RTL/网表/DDC；需要复查层次连接时应保留原 run 网表，原 manifest 已记录其 hash。本次仅审阅与归档，没有修改 RTL/SDC/执行脚本，也没有重新运行 EDA。
