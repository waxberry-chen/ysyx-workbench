# M5：ysyxSoC 集成与系统启动

> 2026-10-19：[S0 上游与平台契约](0-upstream-contract.md)已完成，下一步 S1。前置 [M4 本轮验收](../4-pre-soc-signoff/signoff.md)已通过；已有 SoC 生成/静态展开证据，尚未接入 NPC 或进行新 scope 综合。

目标是让当前 RV32E NPC 接入上游 ysyxSoC，完成 MROM/SRAM/UART、Flash 启动、DiffTest、machine timer interrupt 与有限 RT-Thread workload，再对新增的可综合 CPU 边界建立面积/时序基线。以 [2607 C5 原版讲义](https://ysyx.oscc.cc/docs/2607/c/5.html)为主要学习入口，按本工程 roadmap 裁剪范围；不等同于完成整章外设练习或官方流片考核。

- [设计与分步计划](plan.md)：范围、现状缺口、接口和启动方案、S0–S8 出口、实施依赖。
- [S0 上游与平台契约](0-upstream-contract.md)：固定 revision、61-port ABI、实际地址/容量、reset/IRQ、模型缺口及 S1 交接；[检查 manifest](s0-validation/manifest.json)。
- [验收矩阵](test-plan.md)：M01/M02 的 S0 范围通过，其余待实施。
- [开发日志](dev-log.md)：记录实际推进、决定和阻塞。
- [阶段 Q&A](qa/README.md)：先记录本次规划中有价值的架构选择，随有效进展更新，不要求每次修改都新增问答。

执行顺序：**S0 上游契约 → S1 原生 AXI4 单拍接口 → S2 最小 SoC → S3 AM/SRAM/DiffTest → S4 Flash 启动及容量闭环 → S5 timer interrupt → S6 RT-Thread → S7 综合/STA → S8 验收归档**。

下一步 S1：按冻结的上游 `df38a4d...` ABI，从 local req/rsp 边界接出原生 AXI4 单拍 transport/wrapper，保留 B1。S0 确认 SRAM 8 KiB、PSRAM 4 MiB，已有 RT-Thread 静态段约42 KiB，已决定 S4 纳入 PSRAM。当前无阻止 S1 的外部依赖；SoC 默认错误响应、空外设处理、Flash XIP 与 PSRAM 颗粒等缺口已分配到 S2/S4，不代表这些功能已通过验收。
