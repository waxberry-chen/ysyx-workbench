# M5：ysyxSoC 集成与系统启动

> 2026-10-20：S0、[S1 AXI4 单拍接口](1-axi4-interface.md)完成，下一步 S2。
> 独立 CPU/协议回归与实际 NPC wrapper 的真实 SoC 静态展开通过；尚未完成真实 SoC 启动、AM/DiffTest 或新 scope 综合。

S1 已直接升级当前 adapter/仲裁/顶层，不维护 B1/SoC 双接口。B1 仅作为历史系统测试，其有效协议与 CPU 检查已迁移；[原始结果摘要](s1-validation/README.md)。

目标是让当前 RV32E NPC 接入上游 ysyxSoC，完成 MROM/SRAM/UART、Flash 启动、DiffTest、machine timer interrupt 与有限 RT-Thread workload，再对新增的可综合 CPU 边界建立面积/时序基线。以 [2607 C5 原版讲义](https://ysyx.oscc.cc/docs/2607/c/5.html)为主要学习入口，按本工程 roadmap 裁剪范围；不等同于完成整章外设练习或官方流片考核。

- [设计与分步计划](plan.md)：范围、现状缺口、接口和启动方案、S0–S8 出口、实施依赖。
- [S0 上游与平台契约](0-upstream-contract.md)：固定 revision、61-port ABI、实际地址/容量、reset/IRQ、模型缺口及 S1 交接；[检查 manifest](s0-validation/manifest.json)。
- [S1 接口实现与迁移](1-axi4-interface.md)：事务合同、CLINT、wrapper、源闭包、测试及旧入口处置。
- [验收矩阵](test-plan.md)：M01/M02 的 S0 范围、M03–M05 与 M16 的 S1 范围通过。
- [开发日志](dev-log.md)：记录实际推进、决定和阻塞。
- [阶段 Q&A](qa/README.md)：先记录本次规划中有价值的架构选择，随有效进展更新，不要求每次修改都新增问答。

执行顺序：**S0 上游契约 → S1 原生 AXI4 单拍接口 → S2 最小 SoC → S3 AM/SRAM/DiffTest → S4 Flash 启动及容量闭环 → S5 timer interrupt → S6 RT-Thread → S7 综合/STA → S8 验收归档**。

下一步 S2：接入真实 SoC harness，完成 MROM ebreak 与 UART A，并处理默认错误响应、空外设、DPI backing、仿真延时与复位。当前无阻止 S2 开始的外部依赖。S0 已确定 SRAM 8 KiB、PSRAM 4 MiB，约42 KiB的既有 RT-Thread 静态段需要 S4 的 PSRAM 路线；Flash XIP 与颗粒模型仍待完成。
