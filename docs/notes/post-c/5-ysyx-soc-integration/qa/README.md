# M5 面试 Q&A

> 2026-10-19：Q1–Q3记录规划依据；Q4–Q5来自 [S0审查](../0-upstream-contract.md)，尚无NPC接入功能结论。随有价值的设计/验证进展补充，不要求每次修改都记录。

## Q1：已有 AXI4-Lite，为什么不能只加 LEN、SIZE 等端口接入 SoC？

当前 LSU Lite adapter 已将地址按 word 对齐，Lite 读接口也没有携带访问 size。下游 wrapper 无法恢复原来的 byte address 和读宽度。UART 等 byte 寄存器可能有读取副作用，整字读后截取数据不一定等价于一次 byte 读。

因此直接升级现有 adapter，使 IFU/LSU local req/rsp 中的原始地址和宽度正确传到 AXI4 接口，固定 `LEN=0` 也能表达窄访问。按2026-10-20决定，不维护 B1 Lite 兼容路径；暂不实现 burst 或多 outstanding，并不意味着可以丢弃 size、ID/响应匹配和独立通道握手语义。

## Q2：Flash 启动和可写内存容量有什么关系？为什么不能直接搬用 B1 的 RT-Thread？

Flash 提供程序初始内容，但 `.data/.bss`、栈和 heap 仍需要可写存储。Flash 的映射窗口也不等于 SRAM 容量。讲义中 SRAM 只有 8 KiB，而本项目 B1 fixture 两个静态线程栈已占 16 KiB，还要求 heap 超过 32 KiB。

计划先用小程序完成 Flash → SRAM 的复制/清零/跳转，再按 ELF/map 与运行余量选择 RT-Thread 的存储方案，预期需要 PSRAM。验证启动时只加载 Flash/MROM，目标 RAM 预填图案，让 CPU 执行真实搬运，避免 harness 预加载 RAM 掩盖 bootloader 错误。

## Q3：能读 mtime、能运行 RT-Thread，是否代表支持中断？

都不代表。当前 CLINT 只有计时器，B1 RT-Thread 通过主动 yield 协作切换。timer interrupt 还需要 mtimecmp/pending、CSR mask、精确接受边界、trap/MRET，以及 AM 与 RT-Thread 的 tick/中断开关和调度。

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
