# 05：S6 独立复现

2026-10-19。**独立新 run 成功复现 04，S6 的服务器复现出口通过。** 当前范围的 DC/PT 面积、数据时序、电气规则、coverage 和告警均与 [04](../04-200mhz-baseline/README.md)一致，M4 总验收见 [signoff](../../signoff.md)。本次不是新的优化实验。

## 1. 输入与独立执行证据

| 项目 | 实际结果 |
| --- | --- |
| run | `npc/flow/build/core-tt-5ns-s6-repro` |
| 创建时间 | 2026-10-19 19:13:05 北京时间；DC 导出约 19:13:59，PT 报告约 19:14:17 |
| HEAD | `9e449fac5b8abe863c6bd5c90f79a1c4230607a1`，与 04 相同 |
| dirty | 与 04 相同，仅 Makefile 默认 SITE 从 example 改为 local；[原始 patch](provenance/dirty.patch) |
| config / 外部依赖 | 求值后的 design/site 完全相同；DB、DC/PT 入口和已记录 DC startup 文件的 hash 与 04 相同 |
| 输入快照 | 37 项中 36 项原字节相同；只有绑定新运行目录的 `inputs/run.tcl` 改变，替换 run 路径后也相同 |
| 阶段执行 | DC/PT 均 COMPLETE、exit 0；各自 argv 指向新 run 的脚本，日志与报告记录本次时间 |
| 完整性 | 两个 run 的输入及产物 hash 均自洽；新 run 为 37 输入、23 DC 产物、25 PT 产物 |
| 当前本地源码 | 与新快照比对，32 份 NPC 输入中除 Makefile 默认 SITE 外均一致，含 17 份 RTL；后续两个提交仅文档 |

“干净 run 复现”指 driver 在新的、不存在的运行目录重新执行 synth/STA；本次服务器 Git 工作区**不是完全干净**。保留已知且相同的 SITE 默认值修改，实际求值配置与快照均已核对，未将它伪装为 clean checkout。显式传 SITE 可在未修改的 Makefile 上选择同样配置；其他未解释的实现 dirty 修改不能按此例外接受。

外部依赖的证据来自原 manifest 与已冻结 driver：每个阶段成功前后均调用 `verify(run)`，检查外部及输入 hash，之后才标 COMPLETE。本地没有这些服务器文件，未声称重新读取过 DB/工具，也没有收到独立 `make inspect` 的终端记录。本次离线重新执行的是只读的 `inspect_stage` 报告解析，结果与 manifest 一致；结合阶段内已执行的完整检查，满足本轮出口。

依据：[manifest](provenance/manifest.json)、[绑定新目录的 run.tcl](provenance/run.tcl)、[DC 日志](logs/syn.log)、[PT 日志](logs/sta.log)、[机器可读对照](comparison.json)。

## 2. 结果对照

| 指标 | 04 | 05 | 结论 |
| --- | ---: | ---: | --- |
| cell area（library_area） | 9242.855942 | 9242.855942 | 一致 |
| leaf / sequential cells | 6909 / 1509 | 6909 / 1509 | 一致 |
| 全局 setup slack（ns） | +0.596843 | +0.596843 | 一致 |
| 全局 hold slack（ns） | +0.008754 | +0.008754 | 一致 |
| Reg2Reg max slack（ns） | +1.678541 | +1.678541 | 一致 |
| DC / PT constraint violations | 0 / 0 | 0 / 0 | 一致 |
| max/min WNS、TNS、违例端点 | 全部 0 | 全部 0 | 一致 |
| coverage total / met / violated / untested | 20180 / 10730 / 0 / 9450 | 20180 / 10730 / 0 / 9450 | 一致 |
| LSU E pin 分支 | 25 / 25 / 18 | 25 / 25 / 18 | 一致 |
| 最大分支电容（pF） | 0.0405621 | 0.0405621 | 一致，库上限 0.045377 |
| clk 直接 CP 负载 | 1509 | 1509 | 一致，无普通 fanout 目标产生的 clock tree |

通过逐文件对照，而不只是比较 summary 总数：

- **43 份报告**在去掉 `Date:` 行后相同；其中 QoR 还需去掉四行综合 CPU/wall time 统计。没有忽略 timing、capacitance、area、coverage 或 warning 内容。
- **core.v** 只差文件头生成日期；移除该行后逐字节相同。
- **dc.sdc** 只差 `write_sdc` 日期注释；移除该行后逐字节相同。
- **core.ddc** 原 hash 不同，本地未做二进制语义比对；不宣称 DDC 一致。映射 Verilog、SDC 与报告已经独立比较。
- PT 日志替换 run 路径后相同；DC 日志其余差异仅时间、运行耗时和主机资源统计。DC/PT 告警集合均无新增或消失。

归一化只用于内存中的比较，规则与 hash 保存在 [comparison.json](comparison.json)，原文件原字节保留。

## 3. coverage、告警与范围判定

完整 untested、禁用弧、check_design/check_timing 和负载明细与 04 相同，因此延续其逐对象处置：9426 项 reset 脉宽/释放检查 deferred，24 项 mtvec[1:0] 常量条件禁用。没有新增未解释的功能端点、loop-breaking 弧或电气违例。

UITE-416 两个端点与常量 D 端的对应仍保留 04 的“交叉证据推断”边界，不升级为工具逐名证明；其余结构连接、clock high-fanout、PTE-003、UITE-502 等处置见 [04 告警审查](../04-200mhz-baseline/README.md#5-结构与其他告警审查)。

接受范围保持 TT / 200 MHz、ideal clock、ZeroWireload、Core + adapters + Arbiter、观察端口保留；不是完整 SoC、真实 reset、功耗或物理 sign-off。工具 `REVIEW_REQUIRED` 原样保留，人工验收与工具状态分开记录。

## 4. 归档与交接

保存 **52 份原始文件**：沿用 04 的 51 项选择，增加 `provenance/run.tcl` 以显示新目录绑定；来源、大小和 SHA-256 见 [archive.json](archive.json)。`comparison.json` 为派生核验结果，不冒充工具原始报告。网表/DDC、完整工艺库报告仍在完整 run 中，不复制进长期 Git 文档归档。

本次无 RTL、SDC 或执行脚本变更，功能证据使用本日已重新执行的 [S6 本地最终回归](../../s6-validation/manifest.json)，没有为了相同实现重复跑一轮功能测试。04 及新 run 均未修改。

I12 独立复现出口关闭；S6 与本轮 M4 完成，无当前范围内阻塞。后续按 [M4 signoff](../../signoff.md)交接至 M5。
