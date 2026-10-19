# M5：ysyxSoC 集成与系统启动

> 2026-10-19：计划已建立，S0 尚未执行。前置 [M4 本轮验收](../4-pre-soc-signoff/signoff.md)已通过；本目录尚无 SoC 集成或综合实测结果。

目标是让当前 RV32E NPC 接入上游 ysyxSoC，完成 MROM/SRAM/UART、Flash 启动、DiffTest、machine timer interrupt 与有限 RT-Thread workload，再对新增的可综合 CPU 边界建立面积/时序基线。以 [2607 C5 原版讲义](https://ysyx.oscc.cc/docs/2607/c/5.html)为主要学习入口，按本工程 roadmap 裁剪范围；不等同于完成整章外设练习或官方流片考核。

- [设计与分步计划](plan.md)：范围、现状缺口、接口和启动方案、S0–S8 出口、实施依赖。
- [验收矩阵](test-plan.md)：协议、启动、DiffTest、中断、系统与综合检查；当前均未执行。
- [开发日志](dev-log.md)：记录实际推进、决定和阻塞。
- [阶段 Q&A](qa/README.md)：先记录本次规划中有价值的架构选择，随有效进展更新，不要求每次修改都新增问答。

执行顺序：**S0 上游契约 → S1 原生 AXI4 单拍接口 → S2 最小 SoC → S3 AM/SRAM/DiffTest → S4 Flash 启动及容量闭环 → S5 timer interrupt → S6 RT-Thread → S7 综合/STA → S8 验收归档**。

下一步 S0：固定上游与子模块 revision、生成方式、实际接口及地址表，核查 reset/中断和内存预算。当前仓库没有 ysyxSoC checkout，不能把在线分支的接口表当成已冻结的实现契约。现有 B1 RT-Thread 仅两个线程的静态栈就有 16 KiB，另要求超过 32 KiB 的 heap，无法直接放入讲义中的 8 KiB SRAM；S0 必须决定专用小 workload 的预算，或在 S4 接通 PSRAM。
