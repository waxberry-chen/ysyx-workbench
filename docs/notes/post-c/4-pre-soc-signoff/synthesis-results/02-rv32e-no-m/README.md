# 02：RV32E / 无 M 的 DC + PT 评估

2026-10-18。**DC 和 PT 均执行完成；10 ns 下未报告 setup/hold 违例，面积比首次综合下降 72.9%。PT 仍有 66 条 min-capacitance 违例、5516 项未测试的复位/置位脉宽检查，且缺少正 slack 关键路径报告。本次仍为基线准备实验，不作为正式 S3 基线。**

原 run：`npc/flow/build/core-tt-10ns-rv32e-nom/`。服务器运行时尚未采用报告分类；本归档保留 `reports/syn/`、`reports/sta/` 内原文件名及内容。当前 flow 的新目录组织不追溯修改历史 run。

## 1. 输入与可信边界

| 项目 | 实际值 |
| --- | --- |
| Top / scope | `ysyx_core_axi4lite`；Core + IFU/LSU adapters + Arbiter，保留 commit/monitor 输出；不含 Xbar、SRAM、外设 |
| ISA 实现 | S2.5：16 项 GPR、移除全部 M 指令、非法指令异常与限定 CSR 契约；不声明完整 ISA/特权合规 |
| 源版本 | `740c747f3859ce5c49afd7cd56b377354f3b9a10`，另有 Makefile 默认 SITE 改为 `site.local.tcl` 的未提交改动 |
| 工具 | DC V-2023.12-SP5；PT T-2022.03-SP5 |
| 综合 | 普通 wire-load 模式，`compile -map_effort medium` |
| 库 / 条件 | `tcbn28hpcplusbwp12t40p140tt0p9v25c_ccs` / `tt0p9v25c`；TT、0.9 V、25°C；site 声明 RVT |
| 单位 | ns / pF；面积仍记 `library_area`，不擅自换成 μm² |
| 时钟 | 10 ns，ideal clock；setup/hold uncertainty 0.2/0.05 ns |
| I/O | input/output/reset min/max 0.2/2 ns；输出负载 0.01 pF，含观察端口 |
| 互连 | DC/PT 均为 `ZeroWireload`；无布局、CTS、SPEF |
| 功耗 | 关闭，`NOT_EVALUATED` |

核验了原 manifest 的 36 项输入、21 项 syn 产物、23 项 sta 产物 SHA-256，全部一致；17 份 RTL 快照与审阅时本地源码一致。未重新运行 EDA，也未重新核验服务器上的工具或外部 DB。原 [manifest](provenance/manifest.json)、[dirty patch](provenance/dirty.patch)、[配置](provenance/design-config.tcl)、[site](provenance/site-config.tcl)、[SDC](provenance/core.sdc) 均保留；阶段评价都是 `REVIEW_REQUIRED`。

## 2. 与首次综合比较

| 指标 | 01：32 GPR / 含 M | 02：16 GPR / 无 M |
| --- | ---: | ---: |
| DC cell area（library_area） | 35080.415848 | 9511.319905 |
| 组合 / 时序面积 | 28749.335966 / 6331.079882 | 4991.784007 / 4519.535898 |
| 叶子 / 时序单元 | 23835 / 2021 | 7656 / 1509 |
| ALU 层次面积 | 22706.208 | 969.864 |
| DC setup critical slack | −7.29 ns | +5.53 ns |
| DC setup TNS / 违例数 | −9958.09 ns / 1807 | 0 / 0 |
| DC hold 违例数 | 19 | 0 |
| PT | 未运行 | max/min WNS=0、TNS=0、违例端点=0 |

依据：[area](reports/syn/area.rpt)、[QoR](reports/syn/qor.rpt)、[PT max 指标](reports/sta/metrics_max.tsv)、[PT min 指标](reports/sta/metrics_min.tsv)。PT 的 WNS 是截断到 0 的最坏负 slack，不表示实际最小 slack 恰好为零，也不能代替正裕量报告。

减少 M 运算和一半 GPR 同时改变了实现/功能范围，因此 72.9% 的面积下降不能宣传成相同 ISA 下的优化。剩余面积中 GPR 约 28.3%、opbuf 约 12.3%、ALU 约 10.2%；不再由组合乘除法主导。功耗未评估，不能由面积下降推导程序能耗下降。

## 3. 关键路径与报告缺口

DC [max 报告](reports/syn/timing_max.rpt) 的最差路径为：

```text
opbuf data_q_reg_145_（out_alu_rhs_imm）
  → EXU 操作数选择 → ALU 组合逻辑 → redirect_valid
  → commit_redirect_reason[0]
```

数据到达约 2.27 ns，要求时间 `10 − 0.2 − 2 = 7.8 ns`，slack +5.53 ns，QoR 记录 57 级逻辑。组合 M 的异常长路径已消失，但最差端点仍是观察输出；不能直接将 `1/2.27 ns` 当成 core Fmax。正式基线还需分别审阅内部 Reg2Reg 和接口路径，且不能从 ideal-clock、ZeroWireload 的单角结果外推 post-route 频率。

DC [min 报告](reports/syn/timing_min.rpt) 的首条路径为 arbiter 的 `owner_q_reg → prefer_lsu_q_reg`，打印 slack 为 +0.01 ns；只说明当前模型下通过，不能据此认定布局后 hold 无风险。

**PT 全局及四类路径报告实际全部带 `-slack_lesser_than 0.00`，显示 `No paths with slack less than 0.00`。** 原 [PT 脚本](provenance/sta.tcl) 没有显式给代表路径加该筛选；原因是 `report_timing -max_paths > 1` 的默认行为。PT L-2016.06 User Guide 正文 17-5 / PDF 637 明确说明这一点，并以 `-slack_lesser_than 100 -max_paths 40` 示范如何包含正 slack 路径。实际 PT T-2022.03-SP5 报告与该行为一致。

因此目前不能用 PT 报告确认四类路径的最小正裕量。后续修正代表路径查询，使其包含正 slack；用于 WNS/TNS 的负 slack 端点查询应继续保留原筛选。报告分类本身没有修复这个行为；本次审阅没有修改执行脚本或重跑 PT。

## 4. 约束、电气与覆盖率问题

### constraints.rpt 不只是 timing path 违例

DC [constraints.rpt](reports/syn/constraints.rpt) 无违例；PT [同名报告](reports/sta/constraints.rpt) 有 **66 条 `min_capacitance`**，全部在 `core/u_exu` 的 `BUFFD1BWP12T40P140` 输出 Z 上。它们属于电气约束，不是 setup/hold path：

- 32 个驱动 EXU 的 `commit_pc[31:0]`，32 个驱动 `commit_mem_wdata[31:0]`。原网表的父层实例将这些子模块输出接到 `SYNOPSYS_UNCONNECTED_*`；DC [结构报告](reports/syn/check_design_post.rpt) 同样记录这些输出无负载。顶层观察输出保留不等于同名子模块输出一定被使用。
- 另外 2 个驱动 `trap_epc[1:0]`。需要结合 CSR 对齐位处理、完整负载连接和库约束继续核对。
- 报告所有数值都打印为 `0.00`，并明确标记 `VIOLATED: increase significant digits`。这是显示精度不足，不能解释为零违例；应提高报告精度，并检查这些 pin 的实际负载、库最小电容和未使用 buffer 的产生原因。

当前新 flow 的 **`checks/constraint_violations.rpt`** 命名应保留。把完整报告改成 `timing/timing_violations.rpt` 会掩盖上述电气问题；若以后需要该文件名，应让它只承载明确筛选的 timing 违例，同时保留完整约束报告。

### 未测试项都属于异步控制引脚的脉宽检查

[coverage](reports/sta/coverage.rpt) 中 setup/hold 各 1509、recovery/removal 各 1379、out_setup/out_hold 各 262，全部 met；没有 violated。min_pulse_width 共 11552，其中 6036 met、5516 untested。

逐项统计 [untested 明细](reports/sta/coverage_untested.rpt)：5516 项全部为 `no_clock`，对应 1379 个异步控制引脚，每个 4 个 SDF 条件检查；1374 个 CDN 和 5 个 SDN，均为 low pulse。它不表示 5516 条数据路径没有时钟，也不能直接计作通过。`check_timing succeeded` 与这些 coverage 未测试项可以同时出现。

正式基线需明确外部 reset 的最小有效脉宽和本次静态模型的覆盖边界，形成验证证据及逐类审查结论；不要仅为消掉 `no_clock` 给 reset 虚构周期时钟。recovery/removal 已被测试，并不证明复位有效脉宽足够。

### 其他告警

PT [日志](logs/sta.log) 有 PTE-003：为打断 timing loop 或常量传播而禁用 timing arcs。现有报告不能区分两种原因，需补 `report_disable_timing` 定位后审阅，不能直接断言存在组合环，也不能直接豁免。

DC 综合后仍有 157 个未连接端口、129 个无负载网络、26 个同单元多引脚共网检查项；另有 signed→unsigned、不可达 default、命名规则、重复读库和 TIM-134 高扇出告警。详见 [结构报告](reports/syn/check_design_post.rpt) 与 [日志](logs/syn.log)。TIM-134 本身未列出网络名称，不在本记录中将其未经定位地归因于 clk。

## 5. 下一步与归档

1. 补足包含正 slack 的 PT 全局/四类关键路径报告，提高约束报告精度，补禁用 timing arc 明细；使用新 run 留下证据。
2. 审查 66 个 min-capacitance 对象及未使用 buffer，核对复位脉宽契约与 PTE-003，关闭或有依据地豁免各类检查。
3. 确认观察端口/功能端口预算与评估范围，固定最终输入后建立正式 S3 基线。当前已有真实 DC/PT 执行证据，但上述审查项尚未关闭。

46 份原始报告、日志、manifest、配置/约束及执行脚本按字节保存，映射和 SHA-256 见 [archive.json](archive.json)。保留完整 coverage 明细和空路径报告作为证据；不复制 DB/完整库报告、网表/DDC 或完整 RTL 快照。网表层次定位来自原 run 的 `outputs/core.v`，其 hash 留在 manifest；需要进一步追踪负载时仍需保留原 run。此次没有修改 RTL、SDC 或历史产物。
