# PA2 - 简单复杂的机器：冯诺依曼计算机系统

> 本笔记对应原讲义 `2.1.md` 至 `2.5.md`，默认使用课程要求的 `riscv32` 主线。它用于组织实验路径、实现重点和验收方法；具体指令语义、API 约定和最终要求仍以 ISA 手册、C 标准库手册及原讲义为准。

[toc]

## 1. 实验目标

PA2 要把 PA1 中只能运行内置程序的 NEMU 扩展成能执行 C 程序、提供运行时环境和输入输出的冯诺依曼计算机系统：

- 理解并实现指令的取指、译码、执行和更新 PC。
- 通过交叉编译和 AM 在 NEMU 上运行 C 程序。
- 实现 `klib` 的字符串与格式化输出函数。
- 建立 `iringbuf`、`mtrace`、`ftrace`、`dtrace` 等调试基础设施。
- 实现串口、时钟、键盘和 VGA 对应的 IOE 功能。
- 用 `cpu-tests`、`alu-tests`、`am-tests`、benchmark 和应用程序逐层验证系统。
- 同时从“程序是状态机”和“计算机是抽象层”两个视角理解程序运行。

整体依赖关系：

```text
C 程序
  -> klib: string / sprintf / printf
  -> AM: TRM + IOE
  -> ISA: 计算、访存、控制流、设备访问
  -> NEMU: CPU + memory + device + monitor
  -> 宿主 GNU/Linux / SDL
```

推荐推进顺序：

```text
YEMU与指令周期
  -> dummy
  -> cpu-tests
  -> AM构建与批处理
  -> string / hello-str
  -> trace基础设施
  -> Hello World / printf / alu-tests
  -> timer / benchmark
  -> keyboard / VGA
  -> 应用展示与报告
```

## 2. 开始前的必读原则

**[必读] PA2 是正式的系统实现阶段。** 讲义不会指出每一处需要修改的位置；测试失败、反汇编和调用路径共同决定下一步工作。不要把 `TODO` 当作任务边界，也不要以“测试能过”为唯一完成标准。

**[原则] 驾驭项目，而不是被项目驾驭。** 每实现一条指令或一个 API，都要知道它位于哪一层、输入输出是什么、修改了哪些状态、由什么用例验证。遇到宏或抽象层时，通过预处理结果、GDB 和调用关系拆解，不要复制粘贴出一组似懂非懂的实现。

**[原则] 遵守约定。** ISA、ABI、C 标准库、ELF 和 AM API 都是层间契约。实现前 RTFM，尤其确认输入、输出、符号扩展、溢出、对齐、重叠区间和未定义行为。通过测试不代表代码符合规范。

**[原则] 先完成，后完美。** 先得到功能正确、完整、可测试的系统，再考虑性能优化。实现尽可能少的功能进入下一个测试，每次新增功能后立即回归。

本笔记继续使用：

- `[必做]`：黄色信息框任务，必须纳入主流程和完成清单。
- `[必读]` / `[原则]`：红色信息框中的约束与方法，不得弱化。
- `[提示]`：影响推进或避免误判的信息。
- `[选做]`：蓝色或明确声明为选做的内容，与必做验收分开。

## 3. 指令周期与 YEMU（对应 2.1）

一条指令经历四个阶段：

1. **IF，取指**：用 PC 指出的地址从内存取出指令。
2. **ID，译码**：从比特串识别操作码、寄存器编号、立即数等操作数。
3. **EX，执行**：完成计算、访存、跳转或状态更新并写回结果。
4. **更新 PC**：顺序指令指向下一条静态指令，控制流指令指向下一条动态指令。

YEMU 用 4 个 8 位寄存器、4 位 PC、16 字节内存和 4 条指令演示了这一循环。核心代码与 NEMU 同构：`exec_once()` 取出 `M[pc]`，按 opcode 分派，执行后更新 `pc`。

**[必做] 理解 YEMU 如何执行程序**

- 用包含 PC、寄存器和相关内存的状态表示 YEMU 加法程序。
- 画出程序从初始状态到把 `16 + 33` 写入 `M[7]`，再遇到非法指令停止的状态转移。
- 逐行说明 `inst_t`、`DECODE_R/M`、`switch` 和 `pc++` 分别对应取指、译码、执行和更新 PC 的哪一步。
- 解释“画状态机”和“阅读 `exec_once()`”的关系：前者描述动态行为，后者是生成这些状态转移的静态规则。

该内容也是实验报告必答题。

## 4. 阶段 1：实现指令并运行 C 程序（对应 2.2）

### 4.1 NEMU 中的一条指令

应能完整追踪以下路径：

```text
cpu_exec
  -> execute
    -> exec_once(Decode *s)
      -> isa_exec_once
        -> inst_fetch(&s->snpc, len)
          -> vaddr_ifetch
            -> paddr_read
        -> decode_exec
          -> INSTPAT 模式匹配
          -> decode_operand
          -> 指令语义
      -> cpu.pc = s->dnpc
    -> trace_and_difftest
```

关键状态：

- `s->pc`：当前指令 PC。
- `s->snpc`：static next PC，取指后指向下一条静态指令。
- `s->dnpc`：dynamic next PC，实际将执行的下一条指令；跳转时与 `snpc` 不同。
- `s->isa.inst`：取出的 ISA 指令。
- `rd`、`src1`、`src2`、`imm`：操作数译码结果。

`INSTPAT(pattern, name, type, body)` 用模式字符串匹配 opcode，再通过 `decode_operand()` 按指令类型抽取操作数，最后执行 `body`。`BITS` 用于位抽取，`SEXT` 用于符号扩展。

**[必做] 整理一条指令在 NEMU 中的执行过程**

选择一条实际指令，用源码路径、关键函数、`Decode` 字段和状态变化说明 IF/ID/EX/更新 PC。建议用 GDB 单步并同时查看反汇编、寄存器与内存。该整理也是实验报告必答题。

**[必读] Copy-Paste 是糟糕的编程习惯。** 相似指令应复用操作数译码、算术或访存辅助逻辑；复制后局部修改很容易留下寄存器、位宽、符号扩展或 PC 更新错误。

### 4.2 准备交叉编译环境

**[必做] 非 x86 主线安装对应 GCC 与 binutils**

课程默认 `riscv32` 使用：

```bash
apt-get install g++-riscv64-linux-gnu binutils-riscv64-linux-gnu
```

工具名包含 `riscv64`，仍可根据编译参数生成 `riscv32` 程序。若安装需要管理员权限，按本机环境执行。mips32 主线使用 `g++-mips-linux-gnu binutils-mips-linux-gnu`；x86 不需要额外交叉工具链。

### 4.3 从 `dummy` 开始

初始化 am-kernels: 

```shell
bash init.sh am-kernels
```

然后: 

```bash
cd am-kernels/tests/cpu-tests
make ARCH=riscv32-nemu ALL=dummy run
```

首次运行通常会遇到未实现指令。不要猜指令语义：

1. 查看 `build/dummy-riscv32-nemu.txt` 的反汇编和机器码。
2. 找到第一条未实现或错误的动态指令。
3. 在 RISC-V 手册中确认编码、操作数、立即数和行为。
4. 在 `nemu/src/isa/riscv32/inst.c` 增加模式与语义。
5. 用 `si`、`info r`、`x`、itrace 或 GDB 验证这一条指令。
6. 重新运行 `dummy`，重复直到成功。

**[必做] 运行第一个客户程序**

完成 `dummy` 所需指令后，必须看到 `HIT GOOD TRAP`。没有看到就说明指令或运行时路径仍有错误，不能把 `ABORT`、`HIT BAD TRAP` 或超时当作通过。

### 4.4 逐个通过 `cpu-tests`

单个测试与 GDB：

```bash
make ARCH=riscv32-nemu ALL=add run
make ARCH=riscv32-nemu ALL=add gdb
```

全量回归：

```bash
make ARCH=riscv32-nemu run
```

**[必做] 实现更多指令**

- 以测试反汇编中的实际动态指令为驱动，按计算、访存、控制流逐步补齐。
- 每次只实现足够让测试继续前进的最少指令，立刻测试并回归已通过用例。
- 框架可能已有语义但缺模式，也可能辅助函数仍不完整；不要只搜索 `TODO`。
- `string` 和 `hello-str` 还依赖 klib，暂时跳过，留到阶段 2。
- RISC-V 的 `x0` 必须始终为 0；分支与 `jal/jalr` 必须正确维护 `dnpc`；访存要遵守宽度、符号/零扩展及地址语义。

**[提示] 伪指令不一定出现在 ISA 编码表中。** 反汇编器可能把真实指令显示为伪指令；根据机器码或让反汇编器显示基础指令，找到手册中的真实编码。

## 5. 阶段 2：运行时环境、AM 与 klib（对应 2.3）

### 5.1 为什么需要 AM

同一个 C 程序依赖它所处的运行时环境。GNU/Linux 程序不能直接放进当前 NEMU 运行，因为 NEMU 尚未提供 GNU/Linux 的系统服务。AM（Abstract Machine）为裸机程序提供统一的架构抽象：

- TRM：堆区 `heap`、字符输出 `putch()`、结束运行 `halt()`、入口 `_trm_init()`。
- IOE：设备输入输出，稍后实现。
- klib：架构无关的字符串、内存和格式化输出等基础库。

AM 程序的启动路径：

```text
linker.ld 把 entry 放到镜像起始处
  -> abstract-machine/am/src/riscv/nemu/start.S
  -> 设置栈顶
  -> _trm_init()
  -> main(mainargs)
  -> halt(return_code)
  -> nemu_trap
  -> NEMU set_nemu_state()
```

### 5.2 理解 AM 构建

AM 构建过程大致为：编译 ISA/平台相关的 AM 并打包成库；编译应用；编译所需 klib；最后按 `abstract-machine/scripts/linker.ld` 组织 `.text/.rodata/.data/.bss` 并生成 ELF、binary 和反汇编文件。

**[必做] 阅读 AM Makefile**

- 从应用目录的 `Makefile` 开始，跟踪变量、`include`、隐式规则和被重写的规则。
- 阅读 `abstract-machine/Makefile`、`abstract-machine/scripts/*.mk` 和当前 `riscv32-nemu` 相关脚本。
- 用 `make -n` 查看命令而不执行，用 `make -nB` 强制展示完整构建链。
- 能解释源文件如何形成目标文件、静态库、ELF、binary 和反汇编文件。

**[必做] 让 AM 默认以批处理模式启动 NEMU**

阅读 NEMU 的 batch 选项解析和 AM 的运行规则，修改合适的 Makefile 参数，使 `make ARCH=riscv32-nemu ... run` 启动 NEMU 后直接执行客户程序，不再手动输入 `c`。保留 `gdb` / 交互调试路径的可用性。

### 5.3 实现 klib

**[必做] 实现字符串与内存处理函数**

在 `abstract-machine/klib/src/string.c` 中按需实现函数，使 `cpu-tests` 的 `string` 通过。逐个 RTFM 并测试：返回值、末尾 `\0`、长度为 0、空字符串、符号比较、内存区间与重叠约束不能凭印象决定。

```bash
man 3 strlen
man 3 strcpy
man 3 memcpy
man 3 memmove
man 3 memset
man 3 strcmp
```

**[必做] 实现 `sprintf()`**

在 `abstract-machine/klib/src/stdio.c` 实现 `sprintf()`；阶段要求至少支持 `%s` 和 `%d`，使 `hello-str` 通过。阅读 `man 3 printf` 与 `man stdarg`，正确处理负数、十进制转换、返回字符数和末尾 `\0`。

避免分别复制一份数字转换逻辑；为后续 `printf()` 提取可复用的格式化核心。

**[原则] 计算机是抽象层。** 程序需求经 klib、AM、ISA 和硬件/NEMU 层层实现：例如 `printf -> putch -> MMIO -> serial_io_handler`。调试时先判断错误位于哪一层，再选择观察点。

## 6. 基础设施：trace 与回归（对应 2.4）

### 6.1 已有 itrace

itrace 记录 PC、指令字节和反汇编，默认可写入 `nemu/build/nemu-log.txt`。复杂程序不要无限输出；通过配置与条件限定地址区间或执行阶段，再用 `rg`、`awk`、`sed` 等筛选。

### 6.2 最近指令环形缓冲区

**[必做] 实现 `iringbuf`**

- 每执行一条客户指令，把 itrace 风格的信息写入固定大小环形缓冲区。
- 缓冲区满后覆盖最旧项，保持正确的时间顺序。
- 客户程序异常结束时打印最近若干条指令，并清楚标记导致异常的当前指令。
- 分别测试未填满、恰好填满、回绕多次和异常位置在回绕边界的情况。

### 6.3 内存访问踪迹

**[必做] 实现 `mtrace`**

- 在 `paddr_read()` / `paddr_write()` 的统一路径记录读写类型、地址、长度和值。
- 在 Kconfig 和构建/源码中加入开关，通过 `make menuconfig` 启停。
- 建议支持地址区间过滤，避免海量输出。
- 注意设备 MMIO 是否走相同路径；输出应能区分普通内存与后续的设备访问。

### 6.4 函数调用踪迹

**[必做] 实现 `ftrace`**

1. 为 NEMU 增加 ELF 文件参数，并在 `parse_args()` 中解析。
2. 直接按 `man 5 elf` 读取 ELF header、section headers、`.symtab` 和关联字符串表。
3. 只收集 `STT_FUNC` 符号，用 `[st_value, st_value + st_size)` 建立地址到函数名的映射。
4. 在指令执行中识别调用和返回，输出 PC、目标函数和缩进后的调用层次。
5. `riscv32` 需要根据 `jal` / `jalr` 的寄存器约定和实际语义区分普通跳转、函数调用与返回。

不得调用或解析 `readelf` 的文本输出来代替 ELF 解析；`readelf` 只能用于人工交叉验证。用 `recursion` 等测试结合反汇编核对调用目标和层次。

### 6.5 测试 klib 与一键回归

先在 `native` 上测试 klib，可以更快区分“库函数错误”和“NEMU 指令错误”；再在 `riscv32-nemu` 上运行同一测试验证完整路径。每增加指令、库函数、trace 或设备功能后都重新运行：

```bash
cd am-kernels/tests/cpu-tests
make ARCH=riscv32-nemu run
```

不要因为库函数短小就省略边界用例。特别检查 `memcpy` 与 `memmove` 的重叠语义、字符串终止符、`sprintf` 返回值和目标缓冲区内容。

### 6.6 Differential Testing

**[选做·编程] 实现 DiffTest**

原讲义将其标为蓝色选做题，但它是非常有价值的指令调试基础设施：DUT（NEMU）与 REF（`riscv32` 使用 Spike）从相同内存和寄存器状态出发，每执行一条指令就比较通用寄存器和 PC。

- 确认 REF API 所要求的寄存器排列顺序。
- 实现 `isa_difftest_checkregs()`，逐项比较并报告导致差异的指令 PC。
- 在 menuconfig 中启用 `Testing and Debugging -> Enable differential testing`。
- RISC-V/Spike 不支持不对齐访存；若 DiffTest 因此跳到 PC 0，优先检查 klib 或客户程序的访存错误。
- 设备访问状态不可直接对齐时，框架会使用 `difftest_skip_ref()` 校准。
- DiffTest 有性能开销，跑 benchmark 前关闭。

**[扩展阅读] 自动捕捉死循环**：可研究基于状态重复、控制流周期或超时/指令预算的检测方法，但需区分“合法长期循环”和“程序失去进展”。

## 7. 输入输出与 IOE（对应 2.5）

### 7.1 I/O 模型

设备把数据、状态和命令寄存器暴露给 CPU：

- 端口映射 I/O：使用专门 `in/out` 指令和端口号，x86 使用这种方式访问部分设备。
- 内存映射 I/O（MMIO）：普通访存地址被映射到设备空间，`riscv32` 使用这种方式。

NEMU 用 `IOMap` 统一两类映射。`paddr_read/write()` 判断地址落在 `pmem` 还是设备映射，设备访问再经过 `map_read/write()` 及回调函数。

加入设备后，输入使状态转移不再只由 CPU 当前状态决定：读键盘、时钟等设备时，结果取决于物理世界或宿主时间。`volatile` 用于告诉编译器每次设备寄存器访问都具有可观察意义，不能随意合并、删除或缓存。

### 7.2 启用设备与串口

在 NEMU 的 menuconfig 中启用：

```text
[*] Devices  --->
```

**[必做] 运行 Hello World**

- `riscv32` 的 MMIO 框架已具备，不需额外 I/O 指令；x86 需要实现 `in/out` 并调用 `pio_read/write()`。
- 在 `am-kernels/kernels/hello/` 运行：

```bash
make ARCH=riscv32-nemu run
```

终端必须看到 hello 输出。避免 itrace 等调试信息淹没程序输出。

**[扩展阅读] 理解 `mainargs`**

```bash
make ARCH=riscv32-nemu run mainargs=I-love-PA
```

通过 RTFSC 追踪字符串如何从 Make 变量进入镜像，再由 `$ISA-nemu` 的启动代码传给 `main()`；对比 `native` 平台采用的不同传递方式。

**[必做] 实现 `printf()`**

在 klib 中复用 `sprintf()` 的格式解析/数字转换逻辑，通过 `putch()` 输出，避免复制两份格式化实现。确认返回值与格式行为符合 `printf` 约定；根据后续程序实际使用的格式逐步补齐，不能假设 `%s` / `%d` 足以支撑所有 PA2 程序。

**[必做] 运行 `alu-tests`**

在 `am-kernels/tests/alu-tests/` 根据 README 编译并运行  ，验证各种 C 运算生成的指令。编译可能需要约一分钟；失败时从第一个错误用例及其反汇编定位指令语义。

```bash
cd am-kernels/tests/alu-tests
make ARCH=riscv32-nemu run
```

### 7.3 时钟

NEMU 用两个 32 位设备寄存器提供 64 位微秒时间。AM 用 `AM_TIMER_UPTIME` 抽象开机后经过的微秒数。

**[必做] 实现时钟 IOE**

- 在 `abstract-machine/am/src/platform/nemu/ioe/timer.c` 实现 `AM_TIMER_UPTIME`。
- 使用 NEMU 平台头文件与 ISA 访问接口读取设备寄存器，正确组合为 64 位值。
- 阅读设备回调，确定读取次序如何保证高低 32 位来自同一次时间采样，不要凭地址顺序猜测。
- 在 `riscv32-nemu` 运行 `am-tests` 的 `real-time clock test`；应每隔 1 秒输出一行。
- `AM_TIMER_RTC` 未实现导致日期恒为 1900 年 0 月 0 日，这是预期行为，不是 bug。

```bash
make ARCH=riscv32-nemu run mainargs=t
```

**[必做] 测量 NEMU 性能**

依次运行 `am-kernels/benchmarks/` 下的：

1. `dhrystone`
2. `coremark`
3. `microbench`

先用 microbench `test` 规模检查正确性，再用 `ref` 测量性能；不要求运行耗时极长的 `huge`。跑分前关闭监视点、所有 trace、DiffTest 和 debug information，清理并重编译，记录配置、宿主环境和分数，避免把调试开销当作模拟器性能。

**[必读] 跑分异常首先检查正确性。** 时钟读取链路中有需要通过 RTFSC 发现的细节；错误高分、低分或不稳定都可能来自时钟实现，而非 NEMU 真正速度。

### 7.4 设备访问踪迹

**[必做] 实现 `dtrace`**

- 在统一设备映射访问处记录读写、设备名、地址/偏移、长度和值。
- 使用 `map->name` 提升可读性。
- 加入配置开关和可选设备/地址过滤，避免持续产生大量日志。
- 用串口、时钟和后续键盘/VGA 测试验证 dtrace。

### 7.5 键盘

`AM_INPUT_KEYBRD` 返回 `keydown` 与 `keycode`；无事件时为 `AM_KEY_NONE`。按下产生 make code，释放产生 break code。

**[必做] 实现键盘 IOE**

- 在 `abstract-machine/am/src/platform/nemu/ioe/input.c` 实现 `AM_INPUT_KEYBRD`。
- 从 NEMU 键盘数据寄存器读取编码，正确拆分按下/释放标志与键码。
- 运行 `am-tests` 的 `readkey test`；窗口中按下和释放按键时，终端应显示正确的名称、键码和状态。

### 7.6 VGA / GPU

AM 使用两个核心抽象寄存器：

- `AM_GPU_CONFIG`：返回固定屏幕宽高。
- `AM_GPU_FBDRAW`：把 `pixels` 中的 `w*h` 矩形绘制到 `(x,y)`，像素为 `00RRGGBB`；`sync` 为真时刷新屏幕。

**[必做] 实现 GPU 配置与同步（IOE 3）**

- NEMU 已实现屏幕大小寄存器，AM 端需要读取并填充 `AM_GPU_CONFIG`。
- AM 已发出同步写操作，NEMU 端需要为同步寄存器添加硬件支持并触发屏幕更新。
- 按原讲义在 `__am_gpu_init()` 临时写满 framebuffer 并同步；从 `display test` 的用法取得正确宽高。
- 运行 `display test`，应看到全屏颜色信息。

**[必做] 实现 `AM_GPU_FBDRAW`（IOE 4）**

- 按行把源矩形复制到 framebuffer 的正确位置，目标步长使用屏幕宽度而非矩形宽度。
- 正确处理坐标、`w/h`、逐行源指针和 `sync`。
- 重新运行 `display test`，应看到预期动画。
- 验收后删除 `__am_gpu_init()` 中临时填屏代码。

### 7.7 声卡

**[选做·编程] 实现声卡**

声卡部分在原讲义中明确为选做。需要同时实现 NEMU 设备寄存器、环形音频缓冲区与 AM 的音频 IOE，并通过 `audio test`；完成后可运行带音频的应用和 FCEUX。

**[必读·仅在测试声卡时] 将系统音量调低。** 错误实现可能输出高强度白噪声，必须先保护听力，再调试数据格式、缓冲区和并发访问。

## 8. 展示冯诺依曼计算机系统

**[必做] 展示你的计算机系统**

完整实现 IOE 后，逐项尝试原讲义列出的应用并记录运行情况；其中至少要运行后续分析所需的打字小游戏：

- `am-kernels/kernels/slider/`
- `am-kernels/kernels/typing-game/`
- `am-kernels/kernels/demo/`
- `am-kernels/kernels/bad-apple/`
- `am-kernels/kernels/snake/`
- `am-kernels/kernels/litenes/`
- FCEUX on AM

不要只以“窗口出现”为通过：检查时钟节奏、键盘按下/释放、画面刷新、程序退出和终端错误。应用暴露的新指令仍需回到 ISA 手册补齐并运行全部回归。

**[必做] 分析打字小游戏如何运行**

以一次“按下字母并命中”为事件，串起完整路径：

```text
物理按键
  -> SDL event / NEMU keyboard device
  -> 键盘设备寄存器
  -> MMIO load 指令
  -> AM_INPUT_KEYBRD
  -> typing-game 更新游戏状态
  -> AM_GPU_FBDRAW
  -> framebuffer MMIO store
  -> sync register
  -> NEMU VGA / SDL 刷新窗口
```

同时说明：

- 微观视角：每条指令如何改变 PC、寄存器、内存或设备状态。
- 宏观视角：程序、klib、AM、ISA、NEMU 与宿主设备如何通过抽象协作。
- `AM_TIMER_UPTIME` 如何决定帧更新时机，TRM 如何完成游戏逻辑计算。

用 ftrace 和 dtrace 观察真实调用与设备访问，结合源码和反汇编验证分析。该内容也是实验报告必答题。

## 9. Debug 方法

### 9.1 按错误类型选择工具

| 现象 | 首选工具与检查点 |
| --- | --- |
| 第一条未实现指令 | `iringbuf`、itrace、反汇编、ISA 手册 |
| 指令执行后寄存器错误 | `si` / `info r`、GDB、可选 DiffTest |
| 分支后跑飞 | `snpc/dnpc`、立即数符号扩展、目标地址与链接寄存器 |
| 访存越界或值错误 | mtrace、地址/长度、符号扩展、对齐、端序 |
| 进入错误函数或返回错误 | ftrace、调用约定、栈、`jal/jalr` 语义 |
| klib 仅在 NEMU 失败 | 先在 native 测试，再检查指令、对齐和 UB |
| Hello World 无输出 | `putch -> MMIO -> map_write -> serial`，配合 dtrace |
| 时钟不递增或跳变 | RTC 高低位读取次序、设备回调、64 位组合 |
| 键盘无事件/状态反了 | `device_update`、设备寄存器、break/make 标志解析 |
| VGA 花屏 | 坐标、矩形行步长、像素格式、framebuffer 地址、sync |
| 复杂程序莫名失败 | 最小失败用例、全部 trace、ASan、GDB、回归测试 |

### 9.2 指令调试闭环

1. 保存第一个 failure 的 PC、指令字和最近指令。
2. 从反汇编确认真实指令，而不是只看伪指令名。
3. RTFM 写出预期输入、输出、PC 和异常/UB 条件。
4. 用 `si` 或 GDB 记录执行前状态。
5. 单步后比较实际状态，只修复产生第一个 error 的 fault。
6. 重跑当前用例，再跑所有已通过用例。

**[必读] 复杂程序的调试依赖对正确行为的认识。** 如果完全不知道从哪里查，通常说明没有读懂相关源码或没有掌握合适工具。不要在最终崩溃点附近试探式修改。

### 9.3 RTFSC 范围自检

PA2 结束时应阅读并基本理解：

- NEMU 除 `fixdep`、kconfig 和未选 ISA 外的已有代码及 Makefile。
- `abstract-machine/am/` 中与 `riscv32-nemu` 相关且除 CTE/VME 外的代码。
- `abstract-machine/klib/`、AM Makefile 与 scripts。
- `cpu-tests` 全部代码及运行过的 `am-tests`。
- microbench 的入口与运行框架。
- `hello`、`slider`、`typing-game` 源码。

## 10. 实验报告必答题（对应 2.5）

**[必做] 用自己的语言详细回答以下问题。** 实验性改动应在回答后删除，并用版本控制确认没有残留。

1. **程序是个状态机**：画出并解释 YEMU 加法程序，关联其 `exec_once()` 实现。
2. **RTFSC**：整理一条指令在 NEMU 中从 `cpu_exec()` 到状态更新和 trace 的完整过程。
3. **程序如何运行**：从微观状态机与宏观抽象层两个视角解释打字小游戏的一次命中。
4. **`static inline` 与编译链接**：对 `nemu/include/cpu/ifetch.h` 的 `inst_fetch()` 分别去掉 `static`、去掉 `inline`、同时去掉两者，记录每种构建结果并用 C 的 inline/linkage 规则、预处理结果和符号表证明解释。
5. **头文件中的 `static` 实体**：
   - 在 `common.h` 添加 `volatile static int dummy;`，统计最终 NEMU 中实体数量并说明方法。
   - 再在 `debug.h` 添加同名定义，比较实体数量并解释头文件包含关系。
   - 把两处改成 `volatile static int dummy = 0;`，解释新问题及 tentative definition 与显式初始化的差异。
   - 完成后删除这些实验代码。
6. **了解 Makefile**：说明在 `am-kernels/kernels/hello/` 执行 `make ARCH=riscv32-nemu` 后，变量、包含文件和隐式规则如何组织 `.c/.h`，经预处理、编译、汇编、归档和链接生成 `build/hello-riscv32-nemu.elf`。使用 `make -nB`、链接 map/命令和 `readelf` / `nm` 等证据支持说明。

## 11. PA2 完成检查清单

### 指令与运行时

- [ ] 已画出 YEMU 加法程序状态机并理解 `exec_once()`。
- [ ] 已整理一条 NEMU 指令的 IF/ID/EX/更新 PC 全路径。
- [ ] 已准备 `riscv32` 交叉编译工具链。
- [ ] `dummy` 得到 `HIT GOOD TRAP`。
- [ ] 已逐步实现所需指令并通过 `cpu-tests` 全量回归。
- [ ] 若选择 x86，已按指令手册处理 `in/out`、`push` 符号扩展、字符串指令和 `endbr32` 等差异；若选择 mips32，已明确 NEMU 使用 `-fno-delayed-branch` 简化分支延迟槽。
- [ ] 已阅读 AM Makefile 和构建脚本。
- [ ] AM 启动 NEMU 时默认使用 batch mode。
- [ ] `string` 通过，字符串/内存函数符合手册约定。
- [ ] `hello-str` 通过，`sprintf()` 至少正确支持 `%s` / `%d`。

### 基础设施

- [ ] `iringbuf` 能在异常时按顺序打印最近指令并标出当前指令。
- [ ] `mtrace` 可配置，能正确记录内存读写。
- [ ] `ftrace` 直接解析 ELF，能显示函数调用与返回。
- [ ] 每次改动后可一键运行 `cpu-tests` 回归。
- [ ] `dtrace` 能显示设备名、读写、地址、长度和值。
- [ ] 可选：DiffTest 能比较 `riscv32` 通用寄存器和 PC。

### IOE 与系统

- [ ] Hello World 能通过串口输出。
- [ ] `printf()` 复用格式化核心并可用于 AM 输出调试。
- [ ] `alu-tests` 通过。
- [ ] `AM_TIMER_UPTIME` 正确，RTC test 每秒输出一次。
- [ ] 已运行 dhrystone、coremark、microbench 并记录合规配置下的结果。
- [ ] `AM_INPUT_KEYBRD` 通过 readkey test。
- [ ] `AM_GPU_CONFIG`、VGA sync 与 `AM_GPU_FBDRAW` 通过 display test。
- [ ] 已运行并检查至少若干展示程序。
- [ ] 已从两种视角分析打字小游戏的一次命中。
- [ ] 可选：已追踪 `$ISA-nemu` 与 `native` 的 `mainargs` 传递路径。
- [ ] 可选：声卡通过 audio test，且全程低音量测试。
- [ ] 实验报告六组必答题均已完成并清理临时代码。

## 12. 源章节映射

| 原讲义 | 本笔记对应内容 |
| --- | --- |
| `2.1.md` 不停计算的机器 | 第 3 节：指令周期与 YEMU |
| `2.2.md` RTFM / RTFSC(2) | 第 4 节：NEMU 指令实现与 cpu-tests |
| `2.3.md` 程序、运行时环境与 AM | 第 5 节：AM、构建、klib 与抽象层 |
| `2.4.md` 基础设施(2) | 第 6、9 节：trace、DiffTest、回归和 Debug |
| `2.5.md` 输入输出 | 第 7、8、10 节：IOE、设备、应用与报告 |

## 13. 遇到问题:

### 1. `capstone` 有版本更新. 会导致一些参数定义不兼容.

- 具体的: `nemu/src/utils/disasm.c` 中的 `CS_MODE_RISCVC` 在 capstone 6.0.0 的 某个 Alpha 版本后 `nemu/tools/capstone/repo/include/capstone/capstone.h` 中变成了`CS_MODE_RISCV_C`. 

- 解决方法: 

	```Makefile
	REPO_PATH = repo
	# fix version for NEMU
	CAPSTONE_VERSION = 6.0.0-Alpha4
	
	ifeq ($(wildcard repo/include/capstone/capstone.h),)
	  $(shell git clone --depth=1 --branch $(CAPSTONE_VERSION) git@github.com:capstone-engine/capstone.git $(REPO_PATH))
	endif
	
	```

	Makefile 中固定 capstone 版本, 重新 clone 并编译. 问题解决. 

### 2. 新环境执行 NEMU 的回归测试的时候环境缺失

```bash
# init am-kernels
bash init.sh  am-kernels
# install cross-compile
sudo apt-get install g++-riscv64-linux-gnu binutils-riscv64-linux-gnu
# ERROR: /usr/riscv64-linux-gnu/include/gnu/stubs.h:8:11: fatal error: gnu/stubs-ilp32.h: No such file or directory
# then you should: 
# sudo vim /usr/riscv64-linux-gnu/include/gnu/stubs.h

# -# include <gnu/stubs-ilp32.h>
# +//# include <gnu/stubs-ilp32.h>
```

- 同时 make 在执行 shell 命令时不会加载你的 `~/.bashrc`, 对于 alias python=python3, 可以: 

	```bash
	sudo ln -s /usr/bin/python3 /usr/bin/python
	# or
	sudo apt install python-is-python3
	```

	
