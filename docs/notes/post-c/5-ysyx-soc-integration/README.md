# M5：ysyxSoC 集成与系统启动

> 2026-10-28：S0–[S6 系统回归](6-system-validation.md)完成，下一步 S7。
> CLINT/CSR、精确 IRQ/MRET、AM 上下文、RTT 抢占/阻塞唤醒与栈/heap 验收通过；新 CPU 子系统范围 DC/PT 待 S7。

S1 已直接升级当前 adapter/仲裁/顶层，不维护 B1/SoC 双接口。B1 仅作为历史系统测试，其有效协议与 CPU 检查已迁移；[原始结果摘要](s1-validation/README.md)。

目标是让当前 RV32E NPC 接入上游 ysyxSoC，完成 MROM/SRAM/UART、Flash 启动、DiffTest、machine timer interrupt 与有限 RT-Thread workload，再对新增的可综合 CPU 边界建立面积/时序基线。以 [2607 C5 原版讲义](https://ysyx.oscc.cc/docs/2607/c/5.html)为主要学习入口，按本工程 roadmap 裁剪范围；不等同于完成整章外设练习或官方流片考核。

- [设计与分步计划](plan.md)：范围、现状缺口、接口和启动方案、S0–S8 出口、实施依赖。
- [S0 上游与平台契约](0-upstream-contract.md)：固定 revision、61-port ABI、实际地址/容量、reset/IRQ、模型缺口及 S1 交接；[检查 manifest](s0-validation/manifest.json)。
- [S1 接口实现与迁移](1-axi4-interface.md)：事务合同、CLINT、wrapper、源闭包、测试及旧入口处置。
- [S2 最小启动与源码导读](2-bringup.md)：功能/改动位置索引、MROM与PC初始化、guard接线和状态机、UART完整路径、monitor/退出、逐项测试及[证据](s2-validation/README.md)。建议按文内阅读顺序对照源码。
- [S3 AM/SRAM/DiffTest 与源码导读](3-runtime-difftest.md)：VMA/LMA、CPU 初始化、提交后采样、设备读值同步、独立参考配置；[证据与分类](s3-validation/README.md)。
- [S4 Flash/PSRAM 启动与源码导读](4-boot-memory.md)：各层改动、XIP FSM、串行颗粒模型、VMA/LMA、逐条差分与容量；[精选证据](s4-validation/README.md)。
- [S5 定时器中断与源码导读](5-timer-interrupt.md)：timer/CSR 合同、精确接受边界、AM/RTT tick、独立时间模型、IRQ 差分及连续 redirect 修复；[精选证据](s5-validation/README.md)。
- [S6 系统验证与源码导读](6-system-validation.md)：双线程抢占/睡眠唤醒、分栈水位、AXI 等待注入与实际 UART；[精选证据](s6-validation/README.md)。
- [验收矩阵](test-plan.md)：M01/M02 的 S0 范围、M03–M05 与 M16 的 S1 范围、M06–M08 的 S2/S3 范围、M09/M10 的 S4 范围与 M11–M13 的 S5 范围通过，S6 关闭 M14–M16。
- [开发日志](dev-log.md)：记录实际推进、决定和阻塞。
- [阶段 Q&A](qa/README.md)：先记录本次规划中有价值的架构选择，随有效进展更新，不要求每次修改都新增问答。

执行顺序：**S0 上游契约 → S1 原生 AXI4 单拍接口 → S2 最小 SoC → S3 AM/SRAM/DiffTest → S4 Flash 启动及容量闭环 → S5 timer interrupt → S6 RT-Thread → S7 综合/STA → S8 验收归档**。

下一步 S7：冻结 CPU 子系统的综合 scope、filelist 和 SDC，沿用 DC/PT flow 建立新面积/时序基线，由用户在服务器运行并回传。S6 已完成 68 个真实 SoC 正向运行、34 个适用 CPU tests、30 次 IRQ 差分，当前无未处置功能阻塞；完整 SoC 物理实现与交互 shell 不在本轮范围。
