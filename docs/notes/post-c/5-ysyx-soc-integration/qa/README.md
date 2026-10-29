# M5 面试 Q&A

> 2026-10-19：Q1–Q3记录规划依据；Q4–Q5来自 [S0审查](../0-upstream-contract.md)，尚无NPC接入功能结论。随有价值的设计/验证进展补充，不要求每次修改都记录。

## Q1：已有 AXI4-Lite，为什么不能只加 LEN、SIZE 等端口接入 SoC？

当前 LSU Lite adapter 已将地址按 word 对齐，Lite 读接口也没有携带访问 size。下游 wrapper 无法恢复原来的 byte address 和读宽度。UART 等 byte 寄存器可能有读取副作用，整字读后截取数据不一定等价于一次 byte 读。

因此直接升级现有 adapter，使 IFU/LSU local req/rsp 中的原始地址和宽度正确传到 AXI4 接口，固定 `LEN=0` 也能表达窄访问。按2026-10-20决定，不维护 B1 Lite 兼容路径；暂不实现 burst 或多 outstanding，并不意味着可以丢弃 size、ID/响应匹配和独立通道握手语义。

## Q2：Flash 启动和可写内存容量有什么关系？为什么不能直接搬用 B1 的 RT-Thread？

Flash 提供程序初始内容，但 `.data/.bss`、栈和 heap 仍需要可写存储。Flash 的映射窗口也不等于 SRAM 容量。讲义中 SRAM 只有 8 KiB，而本项目 B1 fixture 两个静态线程栈已占 16 KiB，还要求 heap 超过 32 KiB。

计划先用小程序完成 Flash → SRAM 的复制/清零/跳转，再按 ELF/map 与运行余量选择 RT-Thread 的存储方案，预期需要 PSRAM。验证启动时只加载 Flash/MROM，目标 RAM 预填图案，让 CPU 执行真实搬运，避免 harness 预加载 RAM 掩盖 bootloader 错误。

## Q3：能读 mtime、能运行 RT-Thread，是否代表支持中断？

都不代表。规划 M5 时 CLINT 只有计时器，B1 RT-Thread 通过主动 yield 协作切换；S5/S6 已补齐并验证 timer IRQ 和有限抢占。timer interrupt 还需要 mtimecmp/pending、CSR mask、精确接受边界、trap/MRET，以及 AM 与 RT-Thread 的 tick/中断开关和调度。

验收要让没有主动 yield 的线程也因 tick 得到运行机会，并检查 cause、EPC、上下文与访存副作用。上游 `io_interrupt` 是外部中断输入，与 CPU 内部 timer pending 分开；不能仅把 DUT 的 cause 注入 NEMU 后状态一致当成中断检测正确的证明。

## Q4：SoC 已生成 Verilog、模块也都能找到，为什么仍不能直接认为能运行？

生成只证明参数和结构能展开。本次61个CPU端口与spec一致，但CPU仍是BlackBox；PSRAM/SDRAM颗粒只有三态占位，GPIO/PS2/VGA没有驱动输出；普通SPI路径也没有Flash XIP转换。

因此要分别检查模块定义、端口合同和功能实现。S0的空CPU静态展开通过只证明源文件和ABI可连接；S2必须运行真实CPU取指和UART事务，S4再用真实SPI/颗粒协议证明外部启动。

## Q5：总线有 RESP 信号，非法地址就一定返回 DECERR 吗？

不一定。RESP如何产生取决于具体译码和slave。当前上游没有统一default responder，地址选择有简化；SRAM自身有范围检查，但不能替其他设备保证错误行为，MROM写甚至是断言而不是B通道错误响应。

CPU应正确传播收到的错误，同时SoC要保证未映射/禁用/只读写有确定应答，避免地址别名和无限等待。本工程将这项工作放到S2的SoC侧；S1先用可控responder验证adapter的错误传播。仿真timeout能发现挂死，却不是硬件access fault的实现。

## Q6：升级到 SoC 时，为什么不同时维护 B1 和 SoC 接口？

B1 是接入真实 SoC 前的系统测试阶段，没有持续使用旧硬件接口的需求。双路径会增加参数、源文件组合、地址兼容和回归的维护量。当前选择直接升级已有 adapter、仲裁和顶层，保留 local req/rsp 的语义边界；transport 只是这些总线传送逻辑的统称，不要求新增一套可替换后端。

保留的是验证积累：握手/owner、错误传播、commit/redirect、ISA/CSR 等检查需要迁移到新接口；不要求旧 B1 程序和旧地址仍可运行。需要复查 B1 或 M4 基线时，使用对应 Git revision 和归档证据。移除旧接口兼容与减少 CPU 行为验证是两回事。

## Q7：单拍、单 outstanding 的 AXI4 与 AXI4-Lite 有什么区别？

实现控制可以很接近，但接口语义不同。本工程通过 AxSIZE=0/1/2 表达窄访问，保留原始字节地址；外部接口还有固定的 ID/LEN/BURST/LAST。AXI4-Lite 没有 AxSIZE，且 Lite 本身也允许多个 outstanding，单 outstanding 是我们的实现选择。具体 S1 合同见 [实现记录](../1-axi4-interface.md#2-信号合同)。

“字节地址不按 word 对齐”也不等于支持 misaligned word：例如 byte@…05 是自然对齐的 byte 访问，word@…01 仍按 CPU 的异常策略处理。

## Q8：为什么 W-first 写不能立即按 AWADDR 路由？

AXI 写地址与写数据独立握手，W 没有地址；W 先到时，当前 AWADDR 可能尚无有效意义。S1 的仲裁器与 router 分别缓冲 AW/W，收齐后按锁存地址选 CLINT 或外部 SoC，响应完成前保持责任归属。测试覆盖 ingress/egress 的三种 AW/W 顺序组合和部分写复位。

## Q9：为什么 CLINT 在 CPU wrapper 内，ChipLink 却关闭？

当前 ysyxSoC 没有实例化 CLINT，CPU ABI 也没有独立 timer IRQ 输入；将独立计时模块放在 wrapper 内、流水线外，可以本地译码并在 S5 直连 MTIP。S1 只有 mtime，跟随 CPU 时钟/复位，不代表完整 CLINT 或独立常开计时域。

ChipLink 用于通过片间链路访问另一颗芯片的内存/设备；当前 M5 系统与 M6 cache/burst 不依赖它。关闭后 CPU slave 口没有访问源，保持 tie-off 并断言无请求；以后开启必须重新设计 slave、复位及跨时钟域合同，不能只切换开关。

## Q10：为什么 S2 在 SoC 入口检查地址，而不让 CPU 拒绝所有非法地址？

CPU 负责 ISA 异常和总线协议；具体 SRAM 容量、外设窗口及禁用设备属于 SoC 配置。把这些写成 CPU 白名单会把系统地址图固化进可复用 core，也无法验证真正的错误响应传播。

本次上游 crossbar 采用优化译码，洞地址可能别名到设备，MROM 写原本触发断言。S2 因此在 crossbar 前补完整范围检查，拒绝请求不送外设；未映射返回 DECERR，禁用/只读写/不支持访问形态返回 SLVERR，CPU 再将错误转为 access fault。测试同时验证 cause/EPC 和“错误写没有改变合法 SRAM、没有触发 UART 寄存器 strobe”。它只支持当前单拍合同，M6 burst 不能直接沿用。

## Q11：为什么仿真能打印 A，还要验证 TX 引脚和内部延迟事件？

UART `$write` 可能只表示数据进入发送队列，不能证明波特率、移位器与实际引脚正确。本次程序配置8N1/divisor1，轮询LSR后写THR，再等TEMT；harness从真实TX按位采样，独立得到一个A，才确认完整发送路径。

上游 UART 数据通路带 `#1`。只按时钟边沿推进仿真，可能让中间事件晚执行或被跳过。S2 在下一时钟边沿、Verilator内部事件、串行采样点三者中选择最早时间。它也解释了为什么 `--timing` 必须配合事件调度，不能只替换编译开关。

## Q12：错误响应的数量为什么不一定等于架构异常数量？

IFU 可能已发出后续预取。S2 的非法取指测试中，`0x20001000` 与下一字 `0x20001004` 都得到 DECERR，但第一条错误提交后跳到trap handler，后续响应应被丢弃，只产生一次cause1。验证要分别统计请求/响应和提交，确认未提交的预取既不产生额外trap，也不被误当成重复响应。

## Q13：程序在 ROM 执行，为什么还需要 data 的两套地址和 bss 清零？

已初始化的可写全局变量需要同时回答两个问题：初值保存在哪里，运行时写哪里。本轮 data 的 LMA 在 MROM，VMA 在 SRAM，启动代码从前者复制到后者；bss 只有运行空间，没有文件初值，由 CPU 清零。栈和 heap 也必须留在真实 SRAM 容量内。

例如S3 memory的32B data初值位于`0x200003fc`，运行于`0x0f000000`。只把binary装进ROM还没有完成C运行环境，必须先copy/clear再调用main。链接和启动过程见[S3第2节](../3-runtime-difftest.md#2-c-程序为什么需要新的链接与启动过程)。

## Q14：DUT 和 REF 都通过，为什么还要非零预填和故障检测负例？

两者可能执行同一个错误的启动程序；仿真RAM还可能初值恰好为零，遗漏清bss也不暴露。S3让CPU先把整个SRAM填成`0xa5`，再执行初始化，并用C程序检查已知初值/零值。把copy或clear的store替换成NOP后，两侧仍可能一致，但程序必须报错。

另一个负例只翻转普通addi结果的比较快照，验证差分链真的工作。这两种负例分别验证“程序预期能发现启动缺陷”和“比较器能发现两机分歧”，不能互相替代。

## Q15：为什么提交时的 GPR 看起来会差一条指令？设备读取必须跳过整条差分吗？

posedge callback可能先于非阻塞赋值生效。S3在该边沿只暂存commit元数据，等`eval()`返回再读取GPR、更新后的架构PC和CSR，与执行了一条指令的REF比较。

设备读值随时间变化，因此本轮仅同步UART/mtime该次读的输入，让REF仍执行load并比较其他寄存器、PC和CSR；ROM/SRAM全部正常差分。它比整状态skip保留更多检查，但仍不能独立证明设备返回的数据正确，必须结合真实TX、寄存器副作用和timer定向预期。详见[S3第4节](../3-runtime-difftest.md#4-difftest-为什么这样采样和同步)。

## Q16：Flash XIP 和 Flash 搬到 RAM 执行，有什么区别？

XIP 时，CPU 的取指地址就在 Flash 映射范围，每次读经过 APB→SPI 转换，串行取得指令。搬运启动先借助 XIP 执行小段 boot 代码，再将 `.text/.rodata` 与 `.data` 从 Flash LMA 复制到 RAM VMA，清 bss，跳到 RAM 中的入口。

因此 reset PC 指向 Flash，不代表整个应用都从 Flash 运行。当前 S4 的 Flash profile 在 `0x30000000` 起步，应用分别在 SRAM `0x0f000000` 或 PSRAM `0x80000000` 执行；应结合 ELF/map、复制 store 和跳转后的提交 PC 来证明。实现见 [S4 启动导读](../4-boot-memory.md#5-启动代码与-linker-怎样配合)。

## Q17：PSRAM 模型用了 DPI-C，是否就绕过了真实硬件路径？

关键是 DPI 所在的位置。本工程的 CPU 先发 AXI4，经 APB、PSRAM 控制器，最后由外部器件模型解码 `0xeb/0x38` 命令和串行地址/数据，再调用 DPI 访问 backing。这样仍会暴露命令、地址、字节顺序、strobe、等待周期和事务结束错误。

如果 harness 直接按 CPU 地址读写数组，或者启动时把应用塞进 RAM，才会绕过这些待验证环节。当前 Flash/PSRAM 在 NEMU 中是独立普通存储，复制指令和 RAM 取指都参与差分，最后比较整块 RAM；只有明确的 SPI **寄存器**读值采用设备输入同步。

## Q18：外部存储首尾地址测试为什么有价值？

除了发现地址截断/容量别名，还会暴露协议边界问题。本次 PSRAM 最后一个 word 读取最初触发越界：控制器 DONE 后仍多发一个 SCK 上升沿，颗粒模型尝试准备第五字节。正确修复是 DONE 时停止 SCK 并释放片选，而不是增大 backing 或屏蔽越界。

类似地，Flash 总线窗口虽然声明了 256 MiB，本轮器件只有 16 MiB；必须在截成 24-bit 串行地址之前拒绝超容量访问，否则 `0x31000000` 会悄悄访问 Flash 起点。详见 [S4 容量和错误策略](../4-boot-memory.md#4-容量权限与错误必须一致)。

## Q19：能读 mtime，为什么还需要 timer interrupt？如何关闭一次中断？

读 mtime 是软件主动查询；`mtime >= mtimecmp` 产生 MTIP 后，CPU 在 MTIE/MIE 都打开且到达可接受边界时主动进入 handler，软件才能在忙循环中被 tick 打断。MTIP 是电平，不是一闪而过的脉冲。设置未来的 mtimecmp 会清除 pending；清 MTIE/MIE 仅屏蔽交付，写 mip.MTIP 不会清除硬件源。

RV32 更新 64-bit compare 用“低半部全1 → 高半部 → 最终低半部”，避免临时更早的 deadline。MRET 后仍 pending 会立即再次进入；这不是 MRET 出错。见 [S5 timer/CSR 合同](../5-timer-interrupt.md#2-冻结的-timercsr-合同)。

## Q20：为什么有 IRQ 时不能直接 flush 所有东西？精确的 EPC 怎么决定？

已被设备接受的 store 不可撤回。若 flush 后保存 store PC，返回后重做就可能重复写设备。当前实现会保持已展示的 LSU 请求，等待已接受访存的成功或错误响应，先完成该指令再判断 IRQ；尚未执行的 ALU/branch 可以丢弃。

保存的是下一条未执行指令的 PC。branch 已提交就保存目标地址，未执行就保存 branch 自身。IRQ 入口不是一条正常提交，不做普通写回；返回不加4。同步 ECALL 已经执行，AM 才将其 EPC 加4。见 [S5 精确边界与优先级](../5-timer-interrupt.md#3-精确中断边界哪条指令算已经执行)。

## Q21：NEMU 没有 CPU 周期，怎么验证异步 timer IRQ？

不能让 NEMU 每执行一条指令就把 time 加1。S5 用独立的逐周期 timer 模型核对 RTL 的计数、compare 和 MTIP，再把边沿前/后的 MTIP 输入参考端。IRQ 到来时参考端用自己的 PC 和 CSR 检查条件、生成 cause/EPC，并比较全部状态。

参考端仍不知道流水线忙闲，所以 IRQ 的具体边沿由 DUT 事件告知。遗漏/过早交付、优先级和重复 store，需要固定 EPC 自检、EXU 定向、随机延迟下物理事务计数和超时补充。给 REF 注入 DUT 的 cause/EPC 再比较相同值不构成独立验证。见 [S5 验证分层](../5-timer-interrupt.md#6-如何验证而不是给参考端一个-cause-就算通过)。

## Q22：本轮最有价值的中断 bug 是什么？

手写程序故意不清第一次 IRQ 的 pending，MRET 后立即再次进入。IFU 原先只在 WAIT 上处理 redirect，已经进入 DROP 后再 redirect 会错误回到 REQ，遗留的旧取指响应无人接收，CPU 停止提交。

修复是“更新目标，但保留仍需排空旧响应的状态”。这个场景也说明，redirect 是改变未来执行流，不是消除已经发出的总线事务。现在保留连续 redirect 的 IFU+adapter 定向和 MRET-pending 系统自检。

## Q23：如何证明 RT-Thread 发生的是抢占，而不是程序主动切换？

S6 的两个同优先级线程在一段没有函数调用、ECALL、yield 或 sleep 的汇编中，分别推进自己的计数，再等另一个线程到达同一轮。若没有 timer 驱动的调度，第一线程无法让另一线程取得进展。测试还用 scheduler hook 检查忙等待阶段的切换发生在中断上下文，并检查不同线程的寄存器哨兵。

之后单独进入 sleep 阶段，检查 tick 到期恢复、idle 运行和资源正确性。把这两阶段分开，才能区分“被抢占”和“主动阻塞后换人运行”。实现见 [S6 第2–3节](../6-system-validation.md#2-如何证明真的发生了抢占)。

## Q24：多线程系统怎样统计栈使用，SP 和填充图案有什么区别？

每个线程有独立栈地址区间，主栈又在另一处。先从 ELF 或线程信息确定各区间，再分别记录最小 SP，按“栈顶减最小 SP”算本次最大使用；不能拿全局最低 SP 从主栈顶相减。

填充图案扫描统计被写过的范围，SP 则记录分配过的栈帧范围。函数可以先减 SP、稍后才写局部变量，所以两者可以相差几个字节。S6 同时检查各栈底部余量和 heap 归还，但这些观测不等于证明任意输入下的最坏资源需求。

## Q25：AXI 随机延迟能直接每周期随机开关 VALID 吗？

不能。VALID 已经展示且 READY 未接收时，VALID 和 payload 必须保持；每周期随机清 VALID 会让测试环境本身违反协议。S6 在展示 VALID 之前选取等待周期，展示后保持到握手完成，AW/W 分别处理，R/B 也独立延迟。

验证模型同样要检查：独立数据序列验证丢失/重复/乱序，计数验证缓冲占用，断言验证保持；再接真实 SoC 跑软件。`max=7` 是每道等待门的附加周期上限，不是整次 PSRAM 访问的延迟上限。

## Q26：SoC 集成后的 PPA 为什么不能只换 filelist，也不能直接与旧 core 面积相减？

filelist 只决定读取哪些源文件。综合范围还取决于 top、宏/参数、哪些观察输出对外可见，以及端口的时序/负载假设。M5 的实际 wrapper 改用 `clock/reset`，Flash PC 为 `0x30000000`，内部增加 router/CLINT/IRQ，commit/monitor 输出不再对外连接；驱动脚本的 top 校验、时钟 DRC 查询、reset 极性、LSU 层次诊断和 manifest 也必须同步。

因此新结果首先是新功能边界的基线。相对 M4 的变化混合了功能增加和观察逻辑裁剪，不能直接称为面积优化或接口升级开销。后续 GShare 使用相同 M5 scope、库和约束做前后比较，才便于归因。见 [S7](../7-synthesis-sta.md)。
