# M4 验收：core 综合面积与 pre-layout 时序基线

2026-10-19：**M4 在约定范围内验收通过，S0/S1/S2/S2.5/S3/S6 完成。** 已形成可复现的 DC/PT flow、通过功能回归的实现版本、正式基线 04 和独立复现 05。无当前范围内阻塞；下一阶段为 M5 ysyxSoC 接口/启动集成。

## 1. 交付内容与结果

| 项目 | 结论与入口 |
| --- | --- |
| 可综合实现 | RV32E 16 GPR、无 M/C，非法编码精确异常及限定四 CSR 契约；[S2.5](2.5-isa-contract.md) |
| 实现边界 | `ysyx_core_axi4lite`：Core + IFU/LSU adapters + Arbiter；保留 commit/monitor 输出；无 Xbar/SRAM/UART/CLINT/IO pad |
| flow | 普通 DC 映射 → PT pre-layout；[入口与使用说明](../../../../npc/flow/README.md)、[S2](2-flow.md) |
| 固定条件 | TT / 0.9 V / 25°C / RVT；5 ns / 200 MHz；ideal clock；ZeroWireload；既有 I/O delay/slew/load 与 uncertainty |
| 面积 | **9242.855942 library_area**；6909 leaf cells，其中 1509 sequential；未确认 μm² |
| PT setup / hold | **+0.596843 / +0.008754 ns**；max/min WNS/TNS/违例端点数均为 0 |
| 内部关键路径 | Reg2Reg max slack **+1.678541 ns**；经 ALU/redirect/IFU next-PC 回到 opbuf |
| 电气规则 | DC/PT 无约束违例；LSU enable 负载分支 25/25/18，最大 0.0405621 pF < 驱动库上限 0.045377 pF |
| 正式基线与复现 | [04 基线](synthesis-results/04-200mhz-baseline/README.md)、[05 独立复现](synthesis-results/05-s6-reproduction/README.md)，面积/时序/覆盖/映射一致 |
| 功能与 flow 验证 | [S6 本地最终回归](s6-validation/manifest.json)及[复现交接记录](6-reproduction.md) |

全局 setup 最差到 `commit_redirect_reason[0]`，包含观察接口输出预算；内部路径单独保留。200 MHz 是当前假设下通过的约束点，不是实测硅频率或通过搜索得到的 Fmax。最差 hold 8.754 ps 也不构成 CTS/布线后的裕量承诺。

## 2. 验收矩阵的最终处置

| 验收项 | 最终状态 | 证据与限制 |
| --- | --- | --- |
| I01 工具/库/输入；I02 可综合闭包 | 通过 | 04/05 DC/PT 均 COMPLETE；37 输入、23 DC/25 PT 产物 hash 自洽；无未解析/未映射逻辑 |
| I03 结构 | 通过当前范围审查 | 同一 RTL 的 scope/lint 与 DC/PT 结构报告；连接/常量告警已分类，无非预期 latch、环、未驱动或多驱动 |
| I04 上电/reset 功能 | 功能/静态部分通过 | 两值仿真与结构审查；不包含真实 reset 脉宽、释放、RDC 或四值 X 安全 |
| I05 功能；I13 ISA/异常契约 | 通过项目契约 | S6 本日重新执行 ISA 定向、B1 完整验收、legacy 34 CPU/trace/10 seeds；不声明完整 ISA/特权规范合规 |
| I06 SDC coverage | 通过当前范围审查 | 10730 met、0 violated；9426 reset deferred + 24 mtvec 常量条件禁用，逐类/对象有依据 |
| I07 面积；I08 pre-layout STA | 通过 | 两次结果一致、无约束违例；单 TT、ideal clock、ZeroWireload |
| I12 可复现归档 | **通过** | 05 新 run 重新执行 DC/PT；输入、报告、映射、告警与 04 对照通过；本地验证与交接文档齐全 |
| I09 四值；I10 网表 smoke | 延后 | 本轮明确不实施，不计入通过项 |
| I11 DC 功耗粗估 | 未评估 | power_enable=0；附带项，不阻塞面积/时序验收 |

具体通过标准见[验收矩阵](test-plan.md)。DC/PT 工具返回的 `REVIEW_REQUIRED` 保留；本页是按既定范围、例外和证据作出的人工验收，不改写原始 manifest。

## 3. 版本、复现与归档

- 04/05 的实际测量 HEAD 都为 `9e449fac5b8abe863c6bd5c90f79a1c4230607a1`，包含同一份已记录的 Makefile 默认 SITE 修改。两次设计/site 求值及外部依赖 hash 相同；37 输入仅新 run 路径不同。
- 本地最终回归 HEAD 为 `415c87b`；与测量版本之间只有文档提交。当前 17 份 RTL、实际执行脚本与约束均与测量快照一致。
- 05 与 04 的 core.v、dc.sdc 去掉日期注释后相同；43 份报告仅日期及 QoR 的四行耗时不同。DDC 不要求字节相同，也未声称完成其语义比对。
- 04/05 分别归档 51/52 份原始报告、日志和追溯文件；S6 本地归档 14 份验证证据。各自 manifest/archive 保存 hash，原始文件不改写。
- 服务器阶段内已验证外部 DB、工具入口与已记录 startup 文件 hash；本地回传审阅不能重新读取这些外部依赖。无需把工艺 DB、完整网表/DDC 提交到 Git。

后续复现使用[服务器命令与条件](6-reproduction.md#3-服务器独立复现已完成及后续操作入口)，显式指定私有 SITE 与新 RUN_ID。04/05 作为长期参照保留，不清理或覆盖；改频率、端口 scope、库或 reset 模型时另立实验。

## 4. 保留的范围限制与后续工作

1. **真实 reset**：恢复 recovery/removal、脉宽及分发/释放验证的条件见 [reset TODO](reset-timing-todo.md)；当前 defer 不等于 reset sign-off。
2. **物理与多角**：没有 placement/CTS/route/SPEF、全 PVT/OCV 及真实 IO；本结果属于 pre-layout core 评估。
3. **功耗与等价**：未做功耗、GLS/FM、四值验证；综合/STA 通过不证明 RTL 与网表形式等价。
4. **ISA 与系统边界**：EBREAK harness 约定、cause 0 等限制沿用 S2.5；SoC 中断、完整 CSR、SRAM macro 等依据后续集成需求另行规划。
5. **非阻塞告警**：UITE-416 的具体端点对应仍为交叉证据推断；UCN-4、DDB-24 等已有明确处置，可在后续 flow 整理时改进，不声称本轮消除了所有 warning。

后续进入 M5 前固定 ysyxSoC revision 与接口契约，优先核对 AXI 窄 MMIO 访问地址/size 语义、启动/reset/中断要求及功能回归入口。不得把本 core 基线直接称为集成后完整 SoC 的面积/时序结果。
