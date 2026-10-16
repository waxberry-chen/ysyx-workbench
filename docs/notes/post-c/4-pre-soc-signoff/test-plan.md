# M4 验收矩阵

2026-10-16：**S1 本地出口通过**，证据见 [综合范围与回归](1-synthesis-scope.md)。I02 的 filelist/预处理与 I03 的 lint 部分通过，DC analyze/elaborate/link/check_design 仍待 S3；I04 的静态/reset 定向和 I05 的本轮功能回归通过。I01/I06–I08/I12 待验，I09/I10 延后，I11 未评估。S2 的配置/失败注入、SDC 对象检查及实际 Tcl 的 mock 编排共 28 项测试通过，见 [S2](2-flow.md)；I01 仅本地路径/失败机制部分已验，真实工具启动、库属性与 license 仍待服务器。DC/PT 入口已实现，PDK 路径保留服务器配置。

| ID | 验证内容 | 通过条件 / 证据 | 阶段 |
| --- | --- | --- | --- |
| I01 | 工具、库与输入 preflight | explicit 文件清单存在且 hash/版本可定位；空库/错误 top/缺 SDC/旧 manifest 确实失败；服务器实际工具启动与 feature 可用 | S2/服务器执行前 |
| I02 | synthesizable source closure | SV analyze/elaborate/link，无 DPI/未解析 reference；参数/宏与目标匹配；无意外 black box | S1/S3 |
| I03 | RTL 结构 | lint + DC check_design：无非预期 latch/组合环/多驱动/未驱动；位宽和 constant pruning 有解释；禁止全局关闭 warning | S1/S3 |
| I04 | 上电和 reset | x0 恒零；GPR 初始化策略已落实；valid/owner/控制 reset 可知；无功能性 CDC 的层次审查及 reset release 假设记录；本轮静态审查与功能回归，不声称四值 X 检查通过 | S1 |
| I05 | 变更后的功能基线 | 先最小定向，后受影响 M2/M3 回归；最终保留 `make -C npc b1-signoff` 结果及明确的 legacy 影响检查；参考实现/软件初始化一致 | S1/S6 |
| I06 | SDC coverage | clk/全部功能 I/O 的 max/min/drive/load 有值和单位；例外有精确对象与原因；无未解释 unconstrained endpoint；check_timing 和 coverage 报告可定位 | S3 |
| I07 | 综合 area/QoR | 映射 cell/hierarchy area、units、资源、网表/DDC/SDC；无未解析宏/意外裁空；零面积/仅剩常量必须失败 | S3 |
| I08 | pre-layout STA | 同一网表/库/SDC；max/min、WNS/TNS/违例端点、关键路径与约束检查齐全；目标 PASS 要求对应 setup/hold/DRV 无未豁免违例；单角通过不推广至全 PVT | S3 |
| I09（延后） | 四值 RTL smoke | 不依赖全局 zero-init；reset 后取指、x0、load/store、redirect、错误/异常、背压；X 控制不能被 if/case 静默当作合法值；记录测试通过条件与 watchdog | 延后，非本轮出口 |
| I10（延后） | 功能网表 smoke | 匹配 stdcell 模型；相同 AXI 环境/有限程序下 RTL/网表 commit PC/inst、异常、内存副作用结果一致；不得访问已经优化掉的内部 regfile 层次来“证明通过” | 延后，非本轮出口 |
| I11（附带） | DC report_power 粗估 | PVT/频率/load/互连模型、活动假设/单位/来源可追溯；记录 internal/switching/leakage/total 与 warning；无 workload 数据，不声称实际程序功耗；不可用时记未评估，不阻塞 I07/I08 | S3 |
| I12 | 可复现归档 | 干净 run 复现；失败退出码 + 工具错误/报告检查；版本/配置/输入输出 hash 和原始报告归档；Q&A 与结果边界一致 | S6 |

本轮不搭建四值、GLS、FM 或 PTPX 流程；I09/I10 保留后续验证需求，不纳入本轮通过率。DC/PT 的面积/时序报告不能代替等价验证、X 检查或网表 smoke。

指标表至少包含：top/配置、corner/Vt、库单位、cell area、target period、WNS/TNS/violations、关键路径、互连模型、clock/IO assumptions、相关 RTL 回归结果。附带功耗列出假设活动下的 internal/switching/leakage/total 或未评估原因；无 workload 功耗、activity coverage 或能量/指令结果。`cycles / target_frequency` 只有在频率条件和环境模型相符时才能作为有条件的执行时间估算。
