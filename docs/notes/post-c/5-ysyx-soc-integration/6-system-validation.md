# M5 S6：RT-Thread 抢占与系统回归

> 2026-10-28；M14–M16 通过。68 个真实 SoC 正向运行、1,824,069 条提交、30 次 IRQ 全部差分，下一步 S7。原始结果及范围见 [精选证据](s6-validation/README.md)。

S5 已接通 timer IRQ、AM 上下文和 RT-Thread tick。S6 要验证这些机制在一个完整、有限的工作负载中一起工作：两个线程不主动让出 CPU 仍能交替运行，睡眠后能由 timer 唤醒，寄存器、栈和 heap 保持正确；加入总线等待后，系统仍能完成。

本步沿用 Flash → PSRAM 的真实启动过程，最终检查实际 UART TX，以及 DUT/REF 的全部 SRAM/PSRAM。没有增加 CPU ISA、外设或 RTOS shell 功能；新范围的面积/时序评估仍由 S7 完成。

若还不熟悉线程、抢占或睡眠，先读 [RT-Thread 系统测试入门](../../knowledge-notes/rtthread-scheduling-sleep-and-preemption-basics.md)。本文解释实现和测试原理，[s6-validation/README.md](s6-validation/README.md)汇总实际测试结果和证据；两者配合阅读。

## 相关术语

### 线程怎样交替执行

| 术语 | 含义与本步对应 |
| --- | --- |
| RTOS / thread / scheduler | RTOS 是实时操作系统，RT-Thread 是本步使用的内核；thread 是线程，每个线程有自己的执行位置、寄存器状态和栈；scheduler 是调度器，决定接下来运行哪个就绪线程。当前只有一个 CPU 核，两个工作线程轮流执行。 |
| Preempt / preemption（抢占） | `preempt` 是动词，`preemption` 是名词：当前线程没有主动让出 CPU，调度器仍能暂停它，让另一线程运行。本步由 timer 中断推进内核时间，在时间片到期时切换线程。`preempt.S` 因此命名，它是验证抢占的汇编程序，不是名为 preempt 的 CPU 指令。 |
| Yield（主动让出）/ 协作式调度 | yield 指当前线程主动请求重新调度；协作式调度依赖线程主动让出或阻塞。本步用于证明抢占的循环不调用 yield，也不 sleep，让另一个线程推进只能依靠中断驱动的切换。 |
| OS tick（内核节拍）/ 时间片 | OS tick 是内核推进时间的基本单位，本测试配置为 100 Hz，即目标每 10 ms 一次；时间片是同优先级线程轮流使用 CPU 的时间配额，本步为 1 tick。这里的 tick 不是 CPU 的一个时钟周期，也不是 CLINT 计数器每加 1。 |
| Ready / running / blocked；sleep / wakeup | 分别是就绪（可以运行但等待调度）、运行中、阻塞（暂时不能被选中）。sleep 让线程阻塞一段时间；wakeup 使它重新就绪，仍要等待调度器选中才实际执行。第 3 节检查睡眠没有提前结束。 |
| Context / context switch（上下文 / 上下文切换） | Context 保存 PC、寄存器等恢复执行所需状态；切换线程时保存 A 的状态，恢复 B 的状态，之后还能恢复 A 从原处继续。S5 已实现保存/恢复通路，本步检查反复切换后数据仍属于各自线程。 |
| Hook（钩子、回调）/ idle（空闲线程） | hook 是注册给内核的函数，在指定事件发生时由内核调用。本步 `switched()` 观察调度切换，`idle()` 统计空闲线程的执行；idle 线程在其他线程都不可运行时获得 CPU。hook 在这里负责观察和检查，切换仍由调度器决定。 |
| IRQ nest（中断嵌套计数） | RT-Thread 记录的软件中断处理层数：0 表示不在中断处理期间，1 表示正在处理一层中断。本步以它判断切换是否由中断处理触发；读到 1 不代表实现了多层硬件中断嵌套。 |
| Barrier / rendezvous（屏障 / 会合） | 一种同步约定：线程先报告自己到达某一轮，再等待同伴也到达。本步用 `progress[0/1]` 做六轮会合，等待时仍在执行循环；若不能切到另一线程，进度就会卡住。这里不是内存屏障指令 `FENCE`。 |
| Sentinel（哨兵值） | 预先放入、稍后核对的已知值，用来发现内容被意外修改。本步给两个线程的寄存器放入不同值，检查切换后是否恢复了当前线程自己的寄存器。 |
| Stack / SP / heap；watermark（水位） | stack 是栈，保存函数调用现场、局部变量和中断现场；SP 是栈指针，即 x2；heap 是通过 `rt_malloc/rt_free` 动态分配/释放的堆。水位指本次运行观察到的最大使用量；向低地址增长的栈用最低 SP 估计，堆记录分配峰值。第 3 节解释另一种栈填充扫描方法。 |

例如 A 正在循环等待 B 更新变量，A 没有调用任何调度函数；timer 到期后，内核选择 B 并恢复 B 的上下文，B 才有机会更新变量。以后再切回 A，A 从被打断的位置继续。这就是本步要证明的 **抢占式线程切换**，具体实现见第 2 节。

### 仿真和验证怎样制造、观察等待

| 术语 | 含义与本步对应 |
| --- | --- |
| Payload / handshake / backpressure | payload 是一个总线通道携带的地址、数据、控制字段；handshake 是时钟边沿上 VALID 与 READY 同时为 1，完成一次传递；backpressure（背压）是接收端暂时不拉高 READY，使发送端等待。等待期间发送端必须保持已拉高的 VALID 和对应 payload。 |
| Delay injection / seed | 延迟注入是在仿真通道中增加等待周期；seed 是产生伪随机等待序列的初始值。本步五个 AXI 通道各有一个缓冲项和独立序列，不修改传输内容；固定输入、配置和 seed 便于复现。 |
| Harness / DUT / REF / DiffTest | harness 是驱动和观察 RTL 的 C++ 仿真程序；DUT 是被测 RTL CPU，REF 是 NEMU 参考模型；DiffTest 比较两者的执行状态。本步还在程序结束时比较 SRAM/PSRAM 的全部内容。 |
| Workload / fixture / regression | workload 是一次运行的测试负载；fixture 是为运行测试准备的程序、配置和环境；regression（回归）是重新运行已有测试，确认新增工作没有破坏既有功能。下文 responder 指按协议回应请求的测试模型，guard 指拦截不支持请求并报错的检查模块，smoke 指快速验证基本功能的小测试。 |
| 正例 / 负例 | 正例要求有效程序完成并自检通过；负例故意制造错误，要求检查器报告指定失败。例如 UART 接收采样速度设置错误时必须报错，证明检查器确实能发现问题。负例通过表示“成功检出预期错误”。 |
| Provenance / manifest / hash | provenance 是结果的来源记录；manifest 是保存这些记录的清单文件；hash 是根据文件内容计算的摘要，用于核对输入和产物是否相同。本步记录源码版本、命令、镜像、seed 和结果，使一次测试能追溯到具体输入。 |

### UART 发送涉及哪些状态

| 术语 | 含义与本步对应 |
| --- | --- |
| TX / baud rate / divisor / 8N1 | TX 是串行发送引脚；baud rate 是波特率，此处二进制 UART 等于每秒传送的 bit 数；divisor 是配置发送速度的分频值；8N1 表示 8 个数据位、无校验位、1 个停止位，另有 1 个起始位。第 5 节用真实 TX 电平解码每个字符。 |
| THR / THRE / TEMT | THR（Transmit Holding Register）是软件写待发字节的发送保持寄存器；THRE（THR Empty）表示保持寄存器空、可继续写；TEMT（Transmitter Empty）表示保持寄存器和发送移位寄存器均空，最后一帧也已发完。`putch()` 等 THRE，`halt()` 等 TEMT，两者用途不同。 |
| Framing error（帧格式错误） | 接收端按预定 bit 时间采样，若停止位不是应有的高电平，就报帧格式错误。本步故意设置错误的 harness 采样速度来触发它，检查的是仿真接收解码器的检错能力。 |

CLINT、trap、MIE、ECALL、MRET、AM/BSP 的基础含义见 [S5 开头的术语说明](5-timer-interrupt.md#相关术语)；下文沿用同一条中断处理通路。

## 1. 各层做了什么

| 层次 | S6 的工作 | 源码入口 |
| --- | --- | --- |
| CPU / SoC 功能 RTL | 复用 S1–S5 的接口、存储和中断实现；运行更完整的系统验收 | `npc/vsrc/`、`ysyxSoC/` 的现有实现 |
| 仿真总线环境 | 增加独立的 AXI 五通道延迟配置，检查 VALID/payload 保持和事务守恒 | [soc_delay.py](../../../../npc/scripts/soc_delay.py)、[soc_delay_channel.sv](../../../../npc/sim/soc_delay_channel.sv) |
| C++ harness | 按 ELF 地址分别统计各栈 SP；记录 UART 起始位至停止位采样的时间；继续逐指令/IRQ 差分 | [main.cpp](../../../../npc/csrc/soc/main.cpp)，`StackRegion`、`--stack-region`、`--uart-serial-trace` |
| AM / NEMU / RT-Thread BSP | 复用 S5 的 trap/恢复、timer 输入和 BSP 调度接口 | [S5 的分层导读](5-timer-interrupt.md#1-先把各层的改动对上) |
| 系统测试程序 | 增加无主动 yield 的双线程程序、睡眠唤醒、寄存器/内存与资源检查；增加慢波特率长字符串 | [soc-system/](../../../../npc/tests/soc-system/README.md) |
| 测试与构建脚本 | 组织四组测试、固定 seed/超时、记录命令与输入输出 hash，复用原有协议和错误检查 | [m5_s6_test.py](../../../../npc/tests/m5_s6_test.py)、[soc.mk](../../../../npc/scripts/soc.mk) |

## 2. 如何证明真的发生了抢占

### 2.1 测试程序不能偷偷主动让出 CPU

[rtthread-system.c](../../../../npc/tests/soc-system/rtthread-system.c) 创建两个同优先级线程，时间片为 1 tick。每个线程先准备自己的栈上局部数组和 heap 数据，然后调用 [preempt.S](../../../../npc/tests/soc-system/preempt.S) 中的 `preempt_registers(id)`。这个函数负责在被反复抢占的过程中核对寄存器，没有主动切换线程的指令。

汇编循环让两个线程分别更新 `progress[id]`，再等待另一个线程达到相同轮次，总计六轮。这段代码没有函数调用、ECALL、yield 或 sleep。若 timer 不产生 IRQ，或者 IRQ 没有真正切换线程，第一个线程就会一直等另一个线程，测试最终超时。这样不依赖“打印了两种线程名”来猜测发生了抢占。

每个线程还把不同的约定值放入 ra/gp/tp/s0/s1/a1–a4，轮次之间检查这些值、id 和自身计数。例如 a1 的哨兵值为 `0x12300b00 + id`：线程 A 的 id 为 0，线程 B 的 id 为 1，切回来后必须仍是自己的值。timer handler 会执行 C，调度又可能恢复另一线程的 Context；因此哨兵可以检查保存/恢复后的状态是否确实属于当前线程。

`rt_scheduler_sethook(switched)` 将 `switched` 函数注册为调度钩子；发生切换时内核调用它，记录线程切换方向和是否处于中断处理中。在忙等待阶段，工作线程之间的切换必须发生在 IRQ nest=1 时。六轮屏障并不要求每方向六次切换：一次运行可以完成上一轮、再发布下一轮；本程序至少需要每方向三次切入。打印的最终切换计数还包括后续睡眠/唤醒阶段。

### 2.2 从 timer IRQ 到另一线程恢复

```mermaid
flowchart LR
    A[线程 A 忙等待] --> IRQ[CLINT 到期 / CPU trap]
    IRQ --> SAVE[AM 保存 A 的 Context]
    SAVE --> TICK[RT-Thread tick / 时间片到期]
    TICK --> SWITCH[BSP 记录待恢复线程 B]
    SWITCH --> RESTORE[AM 从 B 的 Context 恢复 / MRET]
    RESTORE --> B[线程 B 推进 progress]
```

复用的关键实现位于 BSP `context.c`：中断内切换请求先记录 `pending_from/pending_to`，退出 AM handler 时保存原 Context 并返回目标 Context。这里不在 IRQ handler 内另发 ECALL。机制来自 S5，S6 增加的是两个真实线程跨多次切换的验证。

## 3. 阻塞唤醒与资源检查

### 3.1 睡眠意味着线程暂时不可运行

忙等待阶段结束后，两线程分别调用 `rt_thread_delay(4)` 和 `rt_thread_delay(6)`。RT-Thread 将线程从可运行集合移除，为它注册内核 timer；这里的内核 timer 是按 OS tick 判断是否到期的软件计时对象，由 S5 的硬件 timer IRQ 推进。到期后线程恢复为可运行。测试没有在 harness 中直接恢复线程，也没有用另一个线程手动调用 resume。

检查包括：

- 返回时内核 tick 差分别至少为 4、6，不能过早唤醒；就绪后仍可能等待调度，因此不要求差值恰好相等。
- 两线程都阻塞时 idle hook 确实执行，证明睡眠期间 CPU 可以运行其他线程。
- 返回时 MIE 开启、IRQ nest 回到 0，寄存器、局部数组和各自 heap 数据未被破坏。
- 两块 heap 内存释放后，使用量回到创建线程后的初始值；峰值大于最终使用量，且小于总容量。

### 3.2 为什么不能用一个全局最低 SP 报栈使用量

主栈在 PSRAM 顶端，工作线程和 idle 栈在 `.bss` 中。它们不是同一块栈；把最低线程 SP 从主栈顶减去，会把中间的整个地址间隔误报成栈消耗。

脚本读取 ELF 的 `_stack_bottom/_stack_top`、`worker_stacks`、`idle_thread_stack`，向 harness 传入四个不重叠区间。harness 在每次指令提交/IRQ 后观察 x2：分别记录最小 SP、样本数、最大使用量与余量；建立栈后若 SP 落到全部声明区间之外则失败。

线程还复用 RT-Thread 初始化时填入的 `'#'` 图案，从栈底扫描连续未改写字节。它与 SP 测量互补：一次函数调用可以先减小 SP 分配栈帧，却没有写到帧的每个字节，因此两种数字可以差几个字节。两者都只描述本 workload 的运行，不能据此宣称所有程序的最坏栈深度已经证明。

## 4. 系统延迟注入如何工作

`SOC_DELAY=1` 在单独构建目录生成 wrapper 副本。生成器读取维护中的 `ysyx_25030087.sv`，保留端口与 `subsystem` 层次，只将对外 AXI 连接改接到五个仿真通道；原功能 RTL、上游生成的 SoC 和正常源清单不改动。端口集合或连接形态变化时，生成器直接报错，要求人工审查。

每个通道有一个缓冲项，顺序为：

```text
发现 VALID → 等待 N 周期 → 接受并保存 payload
           → 等待 M 周期 → 展示 VALID → 等待下游 READY → 释放
```

AR/AW/W 沿请求方向，R/B 沿响应方向。N、M 可固定，也可由 seed 驱动的独立伪随机序列在有界区间内选取。VALID 一旦展示就保持，不能下一周期因为重新随机而撤回。payload 包含地址、数据、size、ID、RESP、LAST 等该通道字段，逐项传递。

通道模块中的 `s_*` 接上游发送端，`m_*` 接下游接收端：`s_valid && s_ready` 时锁存输入，`m_valid && m_ready` 时交付输出。在 AR/AW/W 上，上游是 CPU；在 R/B 上，上游是 SoC。这里“上游/下游”按该通道的数据流方向定义。计数检查要求“接受数 − 交付数”始终等于当前缓冲占用（0 或 1），这就是本测试所说的事务守恒。

`+npc_delay_max=7` 表示每道等待门最多附加 7 周期，**不表示完整访存最多 7 周期**：通道自身有状态转换，下游还可能进行较慢的 SPI/PSRAM 事务。最大值为 0 的延迟配置仍有缓冲状态；真正的正常时序是 `SOC_DELAY=0`。

CPU 与 CLINT 始终正常计时，等待期间可能发生 timer 到期。测试由此覆盖“外部访存拖长时仍然正确接受中断和恢复执行”。单通道先用独立计数/数据预期验收；系统运行再检查五通道输入输出计数、CPU 事务、逐指令/IRQ DiffTest 和最终 RAM。

## 5. UART：检查真实串行输出和忙等待

[uart-long.c](../../../../npc/tests/soc-system/uart-long.c) 在 AM 初始化之后，将 UART divisor 从 1 改为 8，发送固定的 66 字节行八次，共 528 字节。100 MHz UART 时钟下每 bit 为 `16 × 8 = 128` 个周期；接收器按同样的 bit 时间在实际 TX 引脚采样 8N1 帧。

配置寄存器时还会看到三个缩写：LCR（Line Control Register，线路控制寄存器）选择数据位数、校验、停止位等；其中 DLAB（Divisor Latch Access Bit）置 1 时，低地址寄存器切换为分频值的低/高字节 DLL/DLM，写完后清除 DLAB，恢复正常收发寄存器访问；LSR（Line Status Register，线路状态寄存器）包含 THRE、TEMT 等状态位。因此测试既检查最终字符，也检查软件是否按正确顺序配置和轮询这些寄存器。

降低波特率是为了让程序实际遇到 THRE=0，验证 `putch()` 的轮询，而不是因为 CPU 足够慢而从未碰到发送忙。harness 同时记录寄存器访问与串行帧：

- DLAB、DLL/DLM、8N1 配置顺序正确，THR 写数与完整串行字节数均为 528。
- 所有字符逐字节等于固定预期，至少一次读到 THRE=0。
- 从起始位下降沿到停止位中心采样相差 9.5 bit，帧顺序无重叠；AM `halt()` 等待 TEMT 后才退出。
- 正常、固定等待、随机等待三种配置均验收；错误波特率负例保持 DUT 每 bit 128 周期，故意将 C++ 接收解码器设置为每 bit 16 周期，必须报 `UART framing error`。这验证 harness 能检出采样配置错误；本步没有测试 UART 硬件的 RX 接收或接收错误处理。

## 6. 回归分工、命令与证据

| 组 | 验证对象 |
| --- | --- |
| `rtthread` | 正常系统、seed 29 / 最大等待 7 的完整抢占/唤醒与资源测试 |
| `uart` | 528 字节实际 TX；正常、固定等待 3、seed 19 随机等待 7；错误波特率负例 |
| `random` | hello 与 SRAM memory，各一组固定等待及 seed 1–10 随机等待；全部指令差分、最终 RAM 比较 |
| `regression` | S1 协议/CPU/错误检查、SoC guard、适用 CPU tests、sieve/fib smoke、SPI/PSRAM/XIP 与实际 SoC 错误路径 |

协议 responder 可以主动返回 SLVERR/DECERR、错误 ID 或 LAST；这些是独立测试环境的错误注入。真实 SoC 则通过未映射、越界、只读写等访问触发自身错误响应，再核对 cause/EPC 和副作用。两类证据分别记录，不把 responder 测试称为真实外设错误注入。

统一入口为 `make -C npc s6-test`；按组复验与产物说明见 [fixture README](../../../../npc/tests/soc-system/README.md)。每条命令有返回码、日志和宿主超时；仿真另有周期上限。manifest 记录仓库 revision/改动摘要、源文件 hash、工具与参考端版本；workload 记录实际镜像、配置、seed 与执行结果。编译命令不计作通过的 workload。

完成本步后，S7 对 core + adapter/仲裁/router + CLINT + wrapper 建立新的 DC/PT 评估。S6 的功能结果不代替时序验证，也不扩展为完整 RT-Thread API、交互 shell 或 whole-SoC 物理实现验收。
