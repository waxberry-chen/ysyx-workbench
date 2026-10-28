# M5 S6 精选验证证据

> 2026-10-28：M14–M16 通过。68 个真实 SoC 正向运行共 1,824,069 条提交、30 次 IRQ，全部分别差分；每次完成后比较全部 SRAM/PSRAM。另有独立协议/错误回归、3 组延迟通道单元测试和 10 个预期失败检查。

本轮按四组增量运行，具体命令见各组 manifest；没有将编译命令计作 workload，也未提前计入 S8 的干净重建。实现和阅读路线见 [S6](../6-system-validation.md)。后续统一入口为 `make -C npc s6-test`。

**阅读分工**：本页回答“实际跑了什么、结果如何”；[S6 实施文档](../6-system-validation.md)回答“新增了什么、测试怎样工作”；[RT-Thread 基础教程](../../../knowledge-notes/rtthread-scheduling-sleep-and-preemption-basics.md)解释线程、抢占、睡眠唤醒和资源检查。`regression` 是选择复用的既有测试集合，不表示完整依次重跑全部 S1–S5 入口。

## 1. 系统验收

| 组 | 真实 SoC 正向运行数 | 通过内容 |
| --- | ---: | --- |
| RT-Thread | 2 | 正常时序，以及 seed 29 / 最大附加等待 7；非主动 yield 抢占、sleep 唤醒、idle、Context/内存、栈和 heap |
| UART | 3 | 正常、固定等待 3、seed 19 随机等待 7；每次实际 TX 精确输出 528 字节 |
| 随机系统 | 22 | hello/memory 各固定等待一组及 seed 1–10；逐指令与最终内存比较 |
| 系统回归 | 41 | 34 个 CPU tests、sieve/fib、SPI、PSRAM、XIP、正常/延迟下的存储错误路径 |

CPU tests 共 35 个源文件，其中 `unalign` 因本核采用未对齐异常策略而明确排除，其他 34 个通过，见 [分类表](cpu-tests.json)。独立 responder 的 cause 1/4/5/6/7、SLVERR/DECERR、ID/LAST 故障检查不计入上表真实 SoC 运行数。

### RT-Thread 的实际结果

| 条目 | 正常系统 | 随机等待系统 |
| --- | ---: | ---: |
| 指令提交 / DiffTest steps | 361,495 | 336,421 |
| IRQ / IRQ 比较 | 15 | 15 |
| CPU 周期，含真实 Flash 启动 | 71,767,432 | 78,872,523 |
| 两线程忙等待阶段进度 | 6 / 6 | 6 / 6 |
| 最终两个方向的线程切入次数 | 5 / 5 | 5 / 5 |
| IRQ 内调度次数 | 10 | 10 |
| 请求 sleep 4 / 6 tick 后实际经过 | 4 / 7 | 4 / 7 |
| idle hook 次数 | 933 | 711 |
| heap 总量 / 峰值 / 最终使用，B | 4,080,416 / 544 / 0 | 同左 |

两种时序下忙等待/idle 循环次数不同，因此指令数不同；这不是固定指令序列的性能对比。最终调度计数含睡眠/唤醒阶段；忙等待阶段的三次/方向最低要求由程序单独检查。

四个栈的 SP 观测结果在两次运行中一致：

| 栈 | 预留 B | 最大使用 B | 剩余 B |
| --- | ---: | ---: | ---: |
| main | 65,536 | 224 | 65,312 |
| worker0 | 8,192 | 448 | 7,744 |
| worker1 | 8,192 | 372 | 7,820 |
| idle | 4,096 | 268 | 3,828 |

线程填充图案扫描另给出 worker0/worker1/idle 未改写字节 7,744 / 7,824 / 3,832。SP 可以分配但尚未写入部分栈空间，两种测量不必逐字节相等。它们只覆盖当前有限 workload。

### UART 与延迟通道

- UART divisor=8，每 bit=128 个 CPU 周期。正常/固定/随机等待分别观察到 9,009 / 3,151 / 2,634 次 THRE=0 的忙轮询，最终各输出 528 字节；每帧按实际 TX 采样验证。
- 延迟通道的零附加等待、seed 7 随机等待 7、固定等待 3，各传送 1,000 笔，输入输出计数相等，无丢失、重复、乱序或 VALID/payload 保持违例。
- 真实 SoC 的 8 个存储错误案例在正常和随机等待下均精确完成；没有产生 Flash/PSRAM backing 访问副作用。
- 10 个预期失败检查包括：arbiter/fabric 错误 ID/LAST 六项、非法外部 IRQ/CPU slave 请求两项、错误 UART 接收波特率、故意缩小声明栈区间。每项都检查非零退出及预期诊断。

## 2. 证据入口与复现边界

| 文件 | 含义 |
| --- | --- |
| [manifest.json](manifest.json) | 汇总结论、最终源码状态/hash、补充负例、源码 patch 与分组 manifest hash |
| `manifest-{rtthread,uart,random,regression}.json` | 各增量运行当时的源码状态、工具、实际命令/返回码；不是仅一个 base HEAD |
| [npc-source.patch](npc-source.patch) | 主仓库本轮 NPC 修改及新增源码；可对应基准 revision 重放，不包含生成 RTL/二进制 |
| [workloads.json](workloads.json) | 68 次系统运行的原始 summary、延迟通道统计、分栈观测；无整状态 skip |
| [images.json](images.json)、[artifacts.json](artifacts.json) | ELF 符号/布局与镜像预算、归档时的 ELF/bin/参考库 hash |
| `rtthread-{normal,delayed}.log/.tx/.irq.csv` | 实际串口、自检与中断入口序列；IRQ CSV 的时间为十进制 ps，其余字段为十六进制 |
| [uart-normal.serial.csv](uart-normal.serial.csv) | 每行 start_ps、stop_sample_ps、byte，均为十进制；528 个实际串行帧 |
| `arbiter/fabric/redirect/guard/isa-contract.log` | 独立协议、复位、错误、CPU 语义验证的原始摘要；coverage CSV 配套保留 |
| [delay-unit-summary.txt](delay-unit-summary.txt) | 三种等待配置的独立通道计数与通过结果 |
| `uart-wrong-baud.log`、`stack-bound-negative.log` | 两个新增观察器的有效失败证据 |

完整构建日志、ELF/bin/map、UART 寄存器 CSV 和独立测试 FST 留在 `npc/build/m5-s6/`。最终整理仅补了命令帮助、provenance 记录和已单独执行的栈边界负例；原始分组输入保持历史语境，S8 再进行冻结版本的干净构建复现。S6 没有修改 CPU/SoC 功能 RTL、AM、NEMU 或 RT-Thread BSP；保留了原有嵌套 Rocket Chip 工作区修改。

这是有限系统功能验收，不宣称完整 RT-Thread API/交互 shell、形式证明、四值/X 安全或新 SoC 子系统 PPA 已通过。下一步 S7，服务器 DC/PT 仍由用户运行并回传结果。
