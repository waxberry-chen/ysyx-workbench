# 缺失 flow 脚本核查说明

2026-10-15：按用户澄清修订。[missing-files.csv](missing-files.csv) **只核查本地参考快照中未拷贝的 flow 脚本及编排配置**，服务于本地 flow 蒸馏，不是原工程复现所需的全部输入清单。文件路径均相对 `npc/ref-flow/`；`not_copied` 不表示服务器文件丢失；`copied` 表示已补齐并保留原编号供核查，不表示已运行验证。

## 范围

纳入：根 Makefile 和已读阶段脚本/README 明确引用的 launcher、Tcl/Python/shell 驱动、仿真编译配置和 Kconfig。当前检查范围为配置、综合、FM、PnR、QRC、STA、GLS、功耗及 dataset 主链；未穷举所有历史 SG/ECO 分支。

不纳入：

- PDK/标准单元/SRAM 的 DB、LIB、LEF、TF、RC tech、仿真模型等：用户确认在服务器，保留现有脚本中的路径，本地无需补拷。
- 工具安装文件、license 与本地工具可用性：本地不执行 EDA，不作为脚本缺口。
- C906 RTL、原始 design SDC、程序、网表、DEF、SPEF、波形和报告：它们的角色记录在[逐级输入输出](0-flow-map.md)，不是漏拷的 flow 脚本。
- 将来需要新建的 NPC 脚本、RTL 修复和生成物：属于 [plan](plan.md) 的实施任务，不放进 missing-files。

`11_sim/syn/filelists/syn_base.fl` 纳入是因为它描述仿真编译编排；不据此要求补齐它引用的所有 design 源码。`cts.spec` 在 CTS 脚本中生成后 source，属于运行产物，已排除，避免把所有 source 目标都当成缺失脚本。

本轮 NPC 已收敛为 DC/PT 面积时序基线，功耗只附带 DC `report_power`。清单中的 PX/GLS/FM/dataset 缺口继续作为参考 flow 的历史核查项，均不构成本轮搭建阻塞。

## 如何使用清单

本批补拷后共 16 项：7 项已标记 `copied`，9 项为 `not_copied`（原有 7 项，加新发现的回归汇总脚本和条件 PnR 仿真 runner）。均有调用者或文档中的确切文件名。保留已有 R 编号，删除了原先混入的库、工具、设计数据和 NPC 待建项；新增 QRC 与 dataset 的入口缺口。CSV 记录缺少哪部分 flow 知识、是否值得补拷及现有替代依据，不将它们一概标成 PPA 运行阻塞。

本批已补齐 `run.sta`、`run.qrc`、Kconfig 和 GLS 编译/runner/回归入口。剩余缺口中优先关注 `time_based_power.tcl` 与 `report_gen.pl`；FM/dataset 和条件 PnR runner 的范围见 CSV。现有脚本足够继续蒸馏 NPC 基本结构，**当前没有必须等待补拷才能继续的本地蒸馏阻塞**。

FM/QRC/dataset 缺失处只记录已知契约和推断，详见流程图；暂不为理解它们而重建完整旧工程。确需保留某项旧功能且无法从现有内容确定其语义时，再针对具体脚本报告阻塞。
