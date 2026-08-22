# PA3 - 穿越时空的旅程：批处理系统

> 本笔记对应原讲义 `PA3.md` 与 `3.1.md` 至 `3.5.md`，默认使用课程要求的 `riscv32` 主线。它按实验依赖重组任务，突出必做内容、验收现象和调试路径；ISA、ABI、系统调用及 SDL API 的精确定义仍以原讲义和相应手册为准。

[toc]

## 1. 实验目标与阶段边界

PA3 要在 PA2 的“单个 AM 程序独占机器”之上构建一个能够加载、运行并切换用户程序的批处理系统：

- 在 NEMU 中实现 RISC-V 异常响应和异常返回所需的指令及 CSR。
- 在 AM 的 CTE 中保存、解释并恢复 `Context`，把硬件异常封装为事件。
- 在 Nanos-lite 中加载 ELF 用户程序，分发系统调用并提供 TRM 运行时服务。
- 实现简易文件系统 SFS 与 VFS，把串口、键盘和 VGA 统一为文件接口。
- 在 Navy 中补齐 NDL、miniSDL 和定点运算，运行图形应用及 PAL。
- 实现 `execve()`，让一个程序结束后自动装入下一个程序，展示批处理系统。

课程原始阶段划分如下：

| 阶段 | 覆盖内容 | 明确结束位置 |
| --- | --- | --- |
| **PA3 一阶段（task PA3.1 / PA3 阶段 1）** | 自陷、异常响应、`Context`、事件分发、上下文恢复、`etrace` | 本文第 5.8 节末尾 |
| PA3 阶段 2 | ELF loader、系统调用、`write`、`brk`，支撑 TRM 程序 | 本文第 7.7 节末尾 |
| PA3 阶段 3 | SFS/VFS、设备文件、NDL/SDL、应用、批处理展示 | PA3 全部完成 |

整体调用和依赖关系：

```text
用户程序 / Navy 应用
  -> libc / libos / NDL / miniSDL
  -> syscall: ecall + 参数寄存器
  -> AM CTE: 保存 Context -> Event -> 恢复 Context
  -> Nanos-lite: irq / syscall / loader / VFS / device
  -> AM IOE
  -> NEMU: ISA + CSR + memory + device
```

推荐推进顺序：

```text
yield test
  -> 异常响应与 Context
  -> EVENT_YIELD + 上下文恢复 + etrace      [PA3 阶段 1]
  -> Nanos-lite + ELF loader
  -> SYS_yield / SYS_exit / write / brk     [PA3 阶段 2]
  -> SFS + 文件系统调用
  -> VFS + 串口 / 时钟 / 键盘 / VGA
  -> fixedpt + miniSDL + 应用
  -> execve + menu / NTerm                   [PA3 完成]
```

## 2. 开始前的必读原则

**[必读] 先整理 PA3 分支。** 原讲义要求在工程目录执行：

```bash
git commit --allow-empty -am "before starting pa3"
git checkout master
git merge pa2
git checkout -b pa3
```

这些命令会改变分支；执行前先确认 PA2 改动已经提交、工作区中没有不想纳入提交的文件。原讲义明确警告：不按要求整理分支会影响成绩。原讲义给出的 PA3 预计平均耗时是 40 小时。

**[必读] PA3 是复杂度分水岭。** 从这里开始，bug 会跨越 NEMU、AM、Nanos-lite、libos 和应用传播。不要靠随机修改、绕过测试或照抄代码推进；必须能说明状态在哪一层产生、如何跨层传递、最终在哪里被消费。

**[原则] 没有调不出的 bug，只有不理解的系统。** 遇到异常 PC、寄存器错位或系统调用参数错误时，从状态机视角逐项核对，不要只盯着最后的 panic。

**[原则] 抽象是契约。** `Context` 的内存布局、ISA 的异常语义、系统调用 ABI、VFS API 和 SDL API 都是层间契约。任何一侧“看似能跑”的偏差都可能在更高层才暴露。

**[必读] PA 必做内容不需要修改 Newlib。** 修改 C 库后“能跑”通常只是绕开了自己的 bug；问题会潜伏并在后续以更难理解的方式出现。

本笔记使用以下标签：

- `[必做]`：必须实现并达到给定验收现象。
- `[必读]` / `[原则]`：必须遵守的约束或可迁移的方法。
- `[提示]`：能避免返工、环境误判或常见错误的信息。
- `[选做·思考]` / `[选做·编程]`：不进入必做检查清单。

## 3. 批处理系统为什么需要异常（对应 3.1）

最早的批处理系统解决两个问题：

1. 用户程序结束后，把执行流交回后台的操作系统。
2. 操作系统加载下一个用户程序并把执行流交给它。

普通的 `jal`/函数调用不能限制用户程序进入内核的位置，也不能建立保护边界。现代 ISA 因此提供特权级和异常机制：低特权程序执行无权限操作时，硬件保存必要状态并跳到约定入口。PA 为遵循 KISS 原则，不实现完整权限保护，所有程序仍可运行在最高特权级；但保留“受控入口 + 保存状态 + 处理 + 返回”的核心机制。

对 RISC-V 主线，需要理解：

- `ecall`：主动触发环境调用异常。
- `mtvec`：M-mode 异常入口地址。
- `mepc`：发生异常时的 PC。
- `mcause`：异常原因。
- `mstatus`：处理器状态；本阶段可先当作保存 32 位数据的 CSR，不实现复杂状态位行为。
- `mret`：从异常返回，恢复 PC 等状态。

**[选做·思考] 什么是操作系统。** 完成 PA3 后再回看：操作系统首先是一个管理资源、承接受控执行流切换并为应用提供服务的程序，而不是由体积或 UI 定义的特殊存在。

## 4. 异常、Context 与 CTE 理论

### 4.1 RISC-V 异常响应

PA 中 RISC-V 的核心硬件路径可概括为：

```text
执行 ecall
  -> mepc <- 当前 PC
  -> mcause <- 异常号
  -> pc <- mtvec
  -> trap.S 软件入口
```

`isa_raise_intr(NO, epc)` 应完成 ISA 规定的状态更新并返回异常入口地址；自陷指令的执行语义再把 `dnpc` 指向该地址。实际字段和异常号必须查 RISC-V 手册及当前框架代码，不能凭印象填写。

异常响应与函数调用的关键区别是：函数调用遵守 calling convention，只需保存约定的调用者状态；异常可能在任意指令边界发生，处理程序必须能够恢复被打断程序的完整可见状态，所以需要保存更多寄存器和系统状态。

### 4.2 CTE 的抽象边界

CTE（Context Extension）把 ISA 相关异常抽象成架构无关事件：

```text
硬件异常号 + CPU 状态
  -> trap.S 构造 Context
  -> __am_irq_handle(Context *c)
  -> Event { event, cause, ref, msg }
  -> OS 注册的 handler(Event, Context *)
  -> 返回待恢复的 Context *
```

两个核心 API：

- `cte_init(handler)`：设置异常入口，并注册操作系统的事件回调。
- `yield()`：执行自陷，最终产生 `EVENT_YIELD`。

注意“异常”和“事件”不在同一层：异常是 ISA/硬件机制，事件是 AM 对异常原因和附加状态的封装。一条 `ecall` 可以承载 `yield` 或 syscall 等多个软件事件，因此仅看 `mcause` 未必足以完成事件分类，还要检查约定的通用寄存器。

### 4.3 Context 的形成与恢复

RISC-V 的异常入口通常由汇编完成以下工作：

1. 在当前栈上为 `Context` 分配空间。
2. 按固定顺序保存通用寄存器。
3. 读出并保存 `mcause`、`mstatus`、`mepc` 等 CSR。
4. 把栈上 `Context` 的地址作为参数调用 `__am_irq_handle()`。
5. 取回 handler 返回的 `Context *`。
6. 按相反约定恢复 CSR、通用寄存器和栈。
7. 执行 `mret` 返回。

`Context` 不是凭空创建的 C 对象，它就是 `trap.S` 在栈上按字节布局构造出的内存区域。C 结构体字段顺序和汇编保存顺序必须完全一致；地址空间字段即使 PA3 暂不使用，也必须处在正确位置，否则会把错误延迟到 PA4。

RISC-V 的 `ecall` 把当前指令 PC 写入 `mepc`，若希望 `yield()` 返回后继续执行下一条指令，软件要在适当位置把保存的 PC 加 4。不要把“所有异常都加 4”写成通用逻辑：缺页等故障类异常修复后需要重试原指令。

## 5. PA3 阶段 1：实现自陷与异常处理（对应 3.2）

### 5.1 以 `yield test` 为最小闭环

在 `am-tests` 中选择 `yield test`。调用路径应追到：

```text
hello_intr()
  -> yield()
  -> ecall
  -> NEMU isa_raise_intr()
  -> mtvec 指向的 __am_asm_trap
  -> trap.S 构造 Context
  -> __am_irq_handle()
  -> simple_trap(EVENT_YIELD, Context *)
  -> trap.S 恢复 Context
  -> mret
  -> yield() 返回
```

建议把断点依次放在 `ecall`、`isa_raise_intr()`、`__am_asm_trap`、`__am_irq_handle()` 和 `mret`，每到一处记录 PC、`mepc`、`mcause`、`mstatus`、`sp` 及关键通用寄存器。

### 5.2 设置异常入口

`cte_init()` 对 RISC-V 的第一项工作是把 `__am_asm_trap` 写入 `mtvec`，第二项工作是保存上层提供的事件 handler。先通过反汇编确认写 CSR 的真实指令，再补齐 NEMU 中缺失的 CSR 指令语义。

### 5.3 实现异常响应机制

**[必做] 实现自陷所需新指令与 `isa_raise_intr()`。**

- 根据手册实现 `ecall` 及访问 `mtvec/mepc/mcause/mstatus` 所需的 CSR 指令。
- 在 `nemu/src/isa/riscv32/system/intr.c` 实现异常状态保存和入口跳转。
- 阅读 `cte_init()`，确认真正的异常入口地址，不能硬编码猜测。
- 暂不需要实现完整的特权级切换和 `mstatus` 状态位语义。

验收：重新运行 `yield test`，NEMU 确实跳到 `mtvec` 指向的入口；此时若随后停在另一条未实现指令，仍说明异常入口这一小步正确。

**[选做·编程] 让 DiffTest 支持异常。** RISC-V 32 的参考状态通常要求把 `mstatus` 初始化为 `0x1800`（riscv64 为 `0xa00001800`），并正确同步异常相关状态。是否需要跳过/同步应以当前参考模型 API 为准。

### 5.4 重新组织 `Context`

**[必做] 让 C 结构体与 `trap.S` 完全一致。**

- 实现保存上下文路径中新遇到的指令。
- 逐条阅读 `abstract-machine/am/src/riscv/nemu/trap.S`。
- 重新组织 `abstract-machine/am/include/arch/riscv.h` 的 `Context` 成员。
- 正确保留地址空间信息所在槽位，即使本阶段还不用。
- 在 `__am_irq_handle()` 临时打印 `Context`，与 NEMU 简易调试器中的寄存器逐项核对；验证后移除侵入式打印。

**[必读] 不能靠乱改字段顺序直到测试通过。** 结构体每个成员都必须能对应到汇编的一次保存、硬件保存的状态或预留槽位。

### 5.5 识别自陷事件

**[必做] 在 `__am_irq_handle()` 中产生 `EVENT_YIELD`。** 根据 `yield()` 的实现检查 `mcause` 和约定寄存器，把这次自陷封装为 `EVENT_YIELD`。验收：`yield test` 的 `simple_trap()` 识别事件并输出字符 `y`。

### 5.6 恢复上下文

**[必做] 实现异常返回路径。**

- 实现恢复阶段遇到的新指令与 `mret`。
- 确认恢复使用的是 handler 返回的 `Context *`，而不一定假设永远是原指针。
- 对 `EVENT_YIELD` 正确推进保存的 PC，避免反复执行同一条 `ecall`。
- 逐项确认 CSR、通用寄存器、`sp` 和 PC 恢复正确。

验收：`yield test` 持续输出 `y`，每次均能从 `yield()` 返回并再次进入循环。

### 5.7 实现 `etrace`

**[必做] 在 NEMU 中实现 exception trace。** 至少记录异常号、触发异常的 PC 和异常入口；输出开关应可配置，关闭时不改变客户程序行为。`etrace` 位于 NEMU，不依赖客户程序成功进入 CTE，因此比在 handler 中插入 `printf()` 更适合诊断异常入口前的故障。

### 5.8 阶段验收点

> **[里程碑] PA3 一阶段（task PA3.1 / PA3 阶段 1）到此结束。**
>
> 通过条件：`yield test` 能反复完成 `ecall -> 异常响应 -> Context 保存 -> EVENT_YIELD -> Context 恢复 -> mret`，并已实现 `etrace`。这就是原讲义所说的“PA3 阶段 1”结束位置。

## 6. Nanos-lite 与 ELF loader（对应 3.3）

### 6.1 初始化 Nanos-lite 和 Navy

```bash
cd ics2025
bash init.sh nanos-lite
bash init.sh navy-apps
```

Nanos-lite 是运行在 AM 上的 C 程序，主要模块如下：

- `irq.c`：事件分发。
- `loader.c`：ELF 加载。
- `syscall.c`：系统调用分发。
- `fs.c` / `ramdisk.c`：文件系统和 ramdisk。
- `device.c`：设备文件。
- `proc.c`：进程初始化，PA3 暂以 `naive_uload()` 运行单个程序。

先在 `nanos-lite/include/common.h` 定义 `HAS_CTE`，再运行：

```bash
cd nanos-lite
make ARCH=riscv32-nemu run
```

**[必做] 为 Nanos-lite 分发 `EVENT_YIELD`。** 在 Nanos-lite 的事件 handler 中识别该事件并输出一句信息。验收：事件被识别后，程序仍执行到 `main()` 末尾预设的 `panic()`。

### 6.2 用户程序与 ramdisk

Navy-apps 为操作系统上的用户程序提供不同于 AM 的运行时环境。用户程序入口路径为：

```text
libos/crt0/start.S:_start
  -> call_main()
  -> main()
  -> exit()
  -> syscall
```

初次加载 `dummy` 时，可按原讲义先将它编译为 ELF，再复制成 Nanos-lite 的 `ramdisk.img`。RISC-V 用户程序链接在 `0x83000000` 附近；这不是 loader 决定的，而是 Navy 链接脚本/参数决定的。

### 6.3 ELF 的加载视角

Loader 应使用 ELF 的 program header table，而不是 section table。对每个 `PT_LOAD` segment：

```text
ELF [p_offset, p_offset + p_filesz)
  -> memory [p_vaddr, p_vaddr + p_filesz)

memory [p_vaddr + p_filesz, p_vaddr + p_memsz)
  -> 清零（典型地承载 .bss）
```

实现步骤：

1. 从 ramdisk 读 `Elf_Ehdr`。
2. 根据 `e_phoff`、`e_phnum`、`e_phentsize` 遍历 program header。
3. 仅处理 `PT_LOAD`。
4. 把 `p_filesz` 字节复制到 `p_vaddr`。
5. 把剩余 `p_memsz - p_filesz` 字节清零。
6. 返回 `e_entry`，由 `naive_uload()` 跳转执行。

**[必做] 实现 `loader()`。** 当前 `pcb`、`filename` 可暂时忽略；在 `init_proc()` 调用 `naive_uload(NULL, NULL)`。验收：成功进入 `dummy`，随后因尚未处理系统调用事件而报未处理事件。

**[选做·编程] 增强 ELF 检查。** 检查 ELF 魔数和 `e_machine` 是否与目标 ISA 匹配；可用 `Elf_Ehdr` / `Elf_Phdr` 同时兼容 32/64 位，并在 `am_native` 上隔离调试 loader。

## 7. 系统调用与 TRM（PA3 阶段 2）

### 7.1 系统调用链路

系统调用用寄存器描述服务号和参数，通过 `ecall` 进入内核：

```text
用户库函数
  -> libos::_syscall_(type, a0, a1, a2)
  -> 参数写入 ABI 约定寄存器 + ecall
  -> CTE 识别 EVENT_SYSCALL
  -> Nanos-lite handler
  -> do_syscall(Context *c)
  -> sys_xxx(...)
  -> 返回值写回 Context 的 ABI 返回值寄存器
  -> mret
  -> _syscall_() 取得返回值
```

RISC-V 的系统调用号不通过 `a0` 传递；必须阅读 `libos` 的宏和 ABI 约定，正确设置 `GPR1`–`GPR4` 及 `GPRx`，不要按参数名猜寄存器。

### 7.2 识别 syscall

**[必做] 让 CTE/Nanos-lite 识别 `EVENT_SYSCALL`。** `yield` 和 syscall 都可能使用同一条 `ecall`，需要用约定的额外状态区分。若识别错误，逐层检查 `_syscall_()` 输入寄存器、`Context` 布局、PC 推进、CTE 事件和 Nanos-lite handler。

### 7.3 `SYS_yield` 与 `SYS_exit`

**[必做] 实现 `SYS_yield`。**

1. 在架构头文件中定义正确的 `GPR?` 宏。
2. 在 `do_syscall()` 中按系统调用号分发。
3. 调用 CTE `yield()`，返回 `0`。
4. 把返回值写入 `GPRx`。

验收：`dummy` 从 `SYS_yield` 返回后继续触发编号为 0 的 `SYS_exit`。

**[必做] 实现 `SYS_exit`。** 本阶段直接以退出状态调用 `halt()`。验收：`dummy` 显示 `HIT GOOD TRAP`。

### 7.4 `strace`

**[必做] 在 Nanos-lite 实现 syscall trace。** 至少记录系统调用名/号、参数和返回值。它应位于能看到高层语义的 syscall 分发层，而不是只在 NEMU 中记录底层指令。

### 7.5 标准输出：`SYS_write`

**[必做] 在 Nanos-lite 上运行 Hello World。**

- 在 libos 的 `_write()` 调用系统调用入口。
- Nanos-lite 识别 `SYS_write`。
- 本阶段当 `fd` 为 1/2 时，用 `putch()` 输出 `buf` 的 `len` 字节。
- 按 `man 2 write` 返回实际成功写入的字节数，否则 libc 可能重试。
- 把 Nanos-lite 加载的程序切换为 `navy-apps/tests/hello`。

### 7.6 堆区：`SYS_brk` 与 `_sbrk()`

Newlib 的 `malloc()` 通过 `_sbrk()` 管理 program break。用户层 `_sbrk(increment)` 应：

1. 以链接器符号 `_end` 作为初始 break。
2. 计算新 break。
3. 调用 `SYS_brk(new_break)`。
4. 成功时更新记录并返回旧 break，失败时返回 `(void *)-1`。

**[必做] 实现堆区管理。** PA3 的单任务 Nanos-lite 可让 `SYS_brk` 总是返回成功；用户层仍需正确维护 break。调试 `_sbrk()` 时不得调用 `printf()`，否则 `printf -> malloc -> _sbrk -> printf` 会死递归；可用 `sprintf()` 加 `_write()`。

验收：开启 `strace` 后，`printf()` 通常不再逐字符调用 `write()`，而会批量输出缓冲区。

### 7.7 阶段验收点

> **[里程碑] PA3 阶段 2 到此结束。**
>
> `dummy` 能经 loader 启动并正常退出，`hello` 能使用 `write/printf` 输出，`brk/sbrk` 能为 libc 提供堆，`strace` 能展示调用过程。

## 8. SFS：简易文件系统（对应 3.4）

### 8.1 生成 ramdisk 与文件表

SFS 的限制是：文件数量和大小固定、不能创建文件、写入不能越过原大小、没有真正目录。文件在 ramdisk 中连续存放，`Finfo` 保存 `name`、`size`、`disk_offset` 和运行时 `open_offset`。

在 `nanos-lite/Makefile` 启用：

```make
HAS_NAVY = 1
RAMDISK_FILE = build/ramdisk.img
```

然后更新镜像：

```bash
make ARCH=riscv32-nemu update
```

**[提示] 修改 Navy 文件或应用列表后必须重新执行 `make ... update`。** 新应用还要加入 `navy-apps/Makefile` 的相应应用/测试列表，否则它不会进入 ramdisk。

### 8.2 文件描述符和偏移

Nanos-lite 可直接把 `file_table` 下标作为 fd；前三项保留给：

```c
#define FD_STDIN  0
#define FD_STDOUT 1
#define FD_STDERR 2
```

需要实现的 VFS 前身 API：

```c
int    fs_open(const char *pathname, int flags, int mode);
size_t fs_read(int fd, void *buf, size_t len);
size_t fs_write(int fd, const void *buf, size_t len);
size_t fs_lseek(int fd, size_t offset, int whence);
int    fs_close(int fd);
```

约束：

- 找不到文件属于异常，应 assertion 终止。
- SFS 可忽略 `open()` 的 `flags` 和 `mode`。
- 普通文件最终调用 `ramdisk_read/write()`。
- 读、写、定位都不能越过固定文件边界。
- 读写成功后按实际字节数推进 `open_offset`。
- `fs_close()` 可直接返回 0；除 stdout/stderr 写串口外，标准 fd 的其余特殊操作可先忽略。
- 根据 `man 2 lseek` 正确处理 `SEEK_SET/CUR/END` 和返回值。

### 8.3 必做推进

**[必做] 让 loader 使用文件。** 先实现 `fs_open/read/close`，把 loader 从直接访问 ramdisk 改成按文件名访问，例如 `/bin/hello`；以后更换程序只需改变 `naive_uload()` 的文件名。

**[必做] 实现完整 SFS。** 补齐 `fs_write/lseek`，在 Nanos-lite 和 libos 两端添加 `open/read/write/lseek/close` 系统调用，加入并运行 `navy-apps/tests/file-test`。验收输出为 `PASS!!!`。

**[必做] 让 `strace` 支持 SFS。** 利用 SFS 中 fd 与文件表项的固定映射，把 fd 翻译为可读文件名。

## 9. VFS 与“一切皆文件”

### 9.1 用函数指针统一普通文件和设备

VFS 通过 `Finfo` 中的读写函数指针把不同对象抽象为相同 API：

```c
typedef struct {
  char *name;
  size_t size;
  size_t disk_offset;
  ReadFn read;
  WriteFn write;
} Finfo;
```

普通文件的函数指针为 `NULL` 时走 ramdisk；特殊文件调用自己的 `read/write`。系统调用层只调用 `fs_*`，不应再按 fd 写一串设备特判。

**[原则] VFS 和 AM 使用同一种抽象思想。** 上层依赖统一接口，差异由下层实现封装；新增设备文件不应迫使 syscall 层同步改写。

### 9.2 串口

**[必做] 把串口抽象成文件。** 实现 `serial_write()` 并把 stdout/stderr 的写函数指向它；串口是字符设备，忽略 `offset`。stdin 可指向明确报错的读函数。

### 9.3 时钟

**[必做] 实现 `SYS_gettimeofday`。** RTFM 确认参数及返回值，通过 AM IOE 取得时间；新建 `timer-test`，每 0.5 秒输出一次。

**[必做] 用 `gettimeofday()` 实现 `NDL_GetTicks()`。** 返回毫秒数，再把 `timer-test` 改为使用 NDL。程序使用 NDL 前必须调用 `NDL_Init()`。

### 9.4 键盘事件

`/dev/events` 返回文本事件：按下如 `kd RETURN\n`，松开如 `ku A\n`；没有事件返回 0。

**[必做] 打通键盘链路。**

- `events_read()` 用 IOE 读键盘，最多向 `buf` 写 `len` 字节并返回实际长度。
- 在 VFS 注册 `/dev/events`。
- `NDL_PollEvent()` 从该文件读取；当前可假设一次最多一条事件。
- 运行 `event-test`，敲键时应打印正确事件。

**[提示] `/dev/events` 是无位置的字符流。** 根据 `fopen()` 的缓冲语义与 `open()` 的直接文件描述符语义选择合适接口，避免缓冲导致事件读取行为偏离预期。

### 9.5 屏幕与 frame buffer

Navy 约定：

- `/proc/dispinfo`：以 README 规定的文本格式提供屏幕宽高。
- `/dev/fb`：行优先的 32 位 `00RRGGBB` 像素序列，支持写和 `lseek`。

**[必做] 获取屏幕大小。** 实现 `dispinfo_read()`；NDL 解析它并实现 `NDL_OpenCanvas()`。画布不能大于屏幕。先运行 `bmp-test` 并打印解析结果。

**[必做] 把 VGA 显存抽象成文件。**

- 在 `init_fs()` 初始化 `/dev/fb` 大小。
- `fb_write()` 从字节 `offset` 换算像素坐标，通过 IOE 绘图，并按约定每次写后同步。
- `NDL_DrawRect()` 正确处理系统屏幕、画布和局部矩形三层坐标；逐行写入 `/dev/fb` 时正确设置偏移。
- 运行 `bmp-test`，应显示 Project-N logo。

**[选做·编程] 居中画布。** 根据屏幕和画布大小计算偏移，让 NDL 绘制在屏幕中央。

## 10. Navy 运行时、miniSDL 与应用（对应 3.5）

### 10.1 miniSDL 与 RTFM

miniSDL 用 NDL 支撑 timer、event、video、file、audio 和 general 模块。应给所有尚未实现且可能被应用调用的 API 设置清晰失败提示，避免复杂程序静默地产生错误状态。

**[必读] SDL API 必须 RTFM。** 讲义只描述用途，不足以替代 SDL 手册对边界、返回值、像素格式、裁剪和空指针行为的规定。

### 10.2 24.8 定点数

Navy 不提供 FPU 运行时，使用 32 位 `fixedpt` 的 24.8 格式：整数真值 `A` 表示实数 `a = A / 2^8`。

- 加减和比较可直接使用整数操作。
- 乘法需扩大到足够位宽后将结果除以 `2^8`。
- 除法需先把被除数扩大 `2^8` 再除。
- 负数、溢出、舍入及算术右移的行为要通过测试确认。

**[必做] 补齐 fixedptc API。** 尤其 `fixedpt_floor()` 与 `fixedpt_ceil()` 必须严格符合 `floor()` / `ceil()` 语义，正数用例不够，必须覆盖负数、整数边界、零、最小小数和可能溢出的乘除。

### 10.3 分层定位应用 bug

应用移植按以下环境逐层验证：

```text
Linux native
  -> Navy native（替换用户库）
  -> AM native（加入 Nanos-lite / libos / Newlib）
  -> NEMU（替换真实硬件）
```

在哪一层首次失败，bug 通常就位于这一层新引入的实现。前提是代码遵守接口且可移植，不能夹带只对某一环境有效的假设。

### 10.4 必做应用阶梯

**[必做] NSlider。**

- 按 README 把 4:3 PDF 转为 BMP 并加入 `fsimg`。
- 实现 `SDL_BlitSurface()` 和 `SDL_UpdateRect()`，先显示第一页。
- 实现 `SDL_WaitEvent()`，把 NDL 事件封装为 SDL 事件，实现翻页。
- **[提示] ramdisk 必须小于 48 MB**；否则其数据段可能与 RISC-V `0x83000000` 附近的用户程序加载区重叠。

**[必做] MENU。** 实现 `SDL_FillRect()`；验收为显示并可翻页的开机菜单。此时选择程序失败是预期现象，后面用 `execve` 打通。

**[必做] NTerm。** 按手册实现 `SDL_GetTicks()` 和非阻塞的 `SDL_PollEvent()`；验收为光标每秒闪烁且能键入字符。

**[必做] Flappy Bird。** 实现 `IMG_Load()`：读完整图片、调用 `STBIMG_LoadFromMemory()`、正确释放临时资源并返回 `SDL_Surface`。把 `SCREEN_HEIGHT` 改为 300；音频 API 暂时失败仍可无声运行。

**[必做] PAL。** 给 miniSDL 绘图 API 增加 8 位 palette surface 支持，并根据程序实际调用补齐其他 API。先在 Linux/Navy/AM native 分层验证，再在 NEMU 中运行；用不同存档覆盖迷宫、剧情、动画和敌人逻辑。

### 10.5 扩展与选做

- **[选做·思考]** 比较 `fixedpt` 与 `float` 的范围、精度和运算开销；解释常量形式的 `fixedpt_rconst()` 为何可能不生成浮点指令。
- **[选做·编程]** 为 NTerm 内建 Shell 添加 `echo`。
- **[选做·编程]** 让 ftrace 同时解析 Nanos-lite 与用户程序的多个 ELF。
- **[选做·编程]** 实现 Navy 上的 AM、microbench、FCEUX、NPlayer、音频支持及 C++ 全局对象初始化等原讲义扩展任务。
- **[选做·编程]** 给 NEMU 增加 `detach/attach` 动态 DiffTest，attach 前同步 DUT/REF 的内存、通用寄存器及特殊状态。
- **[选做·编程]** 增加 `save [path]` / `load [path]` 快照，保存和恢复完整机器状态；建议使用绝对路径。

### 10.6 原讲义扩展阅读索引

以下内容来自蓝色信息框，均不混入必做验收；需要深入时回到对应源章节阅读完整问题和上下文。

- **[扩展阅读·3.1]** 操作系统的定义；Meltdown/Spectre 如何突破特权边界，以及安全与性能的取舍。
- **[扩展阅读·3.2]** 不同 ISA 的异常设计原因；用软件模拟指令；AM 中浮点指令和未约定状态为何属于 UB；异常号由硬件或软件保存的取舍；异常与函数调用保存状态的差异；x86 `pushl %esp`；PC 加 4 所体现的 CISC/RISC 取舍；MIPS 延迟槽中的异常。
- **[扩展阅读·3.3]** 操作系统为何仍是 C 程序；堆和栈为何不存入 ELF；可执行格式和 ELF 魔数；`FileSiz`/`MemSiz` 的差异及 `.bss` 清零；ELF ISA 检查；系统调用是否是批处理系统的必要条件；RISC-V 系统调用号寄存器；Linux 的 `man syscall` / `man syscalls`；缓冲区对系统调用开销的影响；`printf` 遇换行刷新；多 ELF ftrace。
- **[扩展阅读·3.4]** 真实操作系统为何不能把 `open_offset` 简单放在全局文件表；用 C 结构体与函数指针模拟 OOP；居中画布。
- **[扩展阅读·3.5]** 运行时兼容、`LD_PRELOAD`、Wine 与 WSL；移植时逐层替换抽象；PAL 主循环、脚本引擎和游戏机制；在 Navy 上运行 AM/microbench/FCEUX/Nanos-lite；oslab0；NPlayer、音频、C++ 全局对象初始化、带声音的 PAL/Flappy Bird；动态 DiffTest、快照、终端启动程序的完整系统路径和开机音乐。

## 11. 展示批处理系统

### 11.1 `SYS_execve`

`execve(filename, argv, envp)` 成功后不返回原程序。PA3 可先只使用 `filename`，在 syscall handler 中调用 `naive_uload()`，暂时忽略参数和环境。

**[必做] 让 MENU 启动其他程序。** 实现用户层封装和 Nanos-lite 的 `SYS_execve`，从开机菜单选择并运行应用。

### 11.2 程序退出后自动装载

**[必做] 展示 MENU 版批处理系统。** 把 `SYS_exit` 从 `halt()` 改成重新执行 `/bin/menu`。应用退出后必须回到菜单，而不是终止 NEMU。

**[必做] 展示 NTerm 版批处理系统。**

- 在内建 Shell 解析输入，将命令路径交给 `execve()`。
- 让 `/bin/nterm` 成为首个用户程序。
- 应用退出后重新执行 `/bin/nterm`。
- 当前可忽略命令参数。

**[必做] 支持 `PATH`。** 用 `setenv("PATH", "/bin", 0)` 设置环境，按 `execvp()` 语义执行，使用户可以输入 `pal` 而不是 `/bin/pal`；`overwrite` 必须为 0，以维持 Navy native 的兼容行为。

验收序列建议：

```text
Nanos-lite 启动 NTerm
  -> 输入应用名
  -> execve 加载应用
  -> 应用运行
  -> exit
  -> Nanos-lite 再次加载 NTerm
```

## 12. Debug 方法

### 12.1 按故障所在边界检查

| 现象 | 首要检查 |
| --- | --- |
| `ecall` 后没有到 `trap.S` | `mtvec`、CSR 指令、`isa_raise_intr()`、`dnpc` |
| 进入 handler 后寄存器错乱 | `trap.S` 保存顺序、`Context` 布局、栈地址与对齐 |
| 一直重复同一条 `ecall` | `mepc` 是否对该事件正确推进、`mret` 语义 |
| `yield` 被识别为 syscall 或反之 | 事件区分寄存器、`GPR?` 宏、`Context` 字段 |
| loader 后跳飞 | ELF class/ISA、program header、`PT_LOAD`、入口、清零区间 |
| syscall 参数/返回值异常 | libos ABI、`GPR1`–`GPR4`、`GPRx`、符号/位宽 |
| 修改 Navy 后行为没变 | 应用列表与 `make ARCH=... update` |
| 文件尾读写错 | `open_offset`、截断长度、`lseek` 基准和返回值 |
| 图像错位或撕裂 | 字节/像素单位、pitch、画布偏移、逐行写、sync |
| 大应用才失败 | 用四层 native 路径定位；结合 `etrace/strace/ftrace` |

### 12.2 建议的证据链

- `readelf -h -l`：确认 ELF 类型、入口和 `PT_LOAD` 布局。
- 反汇编：确认 `ecall`、CSR 指令、`mret` 和 `_start` 的真实机器指令。
- NEMU debugger / GDB：对比异常前寄存器、栈上的 `Context` 和恢复后寄存器。
- `etrace`：定位异常号、异常 PC 与入口。
- `strace`：定位 syscall 号、参数、返回值和文件名。
- `ftrace`：串起 loader、libos、CTE、Nanos-lite 和库函数调用。
- `native` 分层运行：判断 bug 属于应用、Navy 库、Nanos-lite/AM 还是 NEMU。

## 13. 实验报告必答题

**[必做] 用自己的语言和实际代码路径回答，不要只画概念图。**

1. **理解上下文结构体的前世今生（PA3 阶段 1）**：`__am_irq_handle()` 的 `Context *c` 指向哪里；结构体如何在栈上形成；每个成员由硬件、哪条汇编或哪段 C 代码赋值；`riscv.h`、`trap.S`、讲义和 NEMU 新指令如何对应。
2. **理解穿越时空的旅程（PA3 阶段 1）**：从 `yield test` 调用 `yield()` 到返回，逐行解释 AM、测试程序与 NEMU 如何协作，包括关键指令、CSR、变量、事件分发和恢复过程。可合并上一题内容。
3. **hello 从何而来、到哪里去（PA3 阶段 2）**：从 C 源文件编译链接成 ELF、进入 ramdisk、被 loader 搬到链接地址、跳入第一条指令，到每个字符经 `write`、syscall、Nanos-lite、AM 和 NEMU 出现在终端的完整路径。无需展开 Newlib 内部 `printf -> write` 的全部实现。
4. **仙剑奇侠传究竟如何运行**：从 `PAL_SplashScreen()` 读取 `mgo.mkf` 中仙鹤像素，到库函数、libos、Nanos-lite、AM、NEMU 协作更新屏幕的完整路径。用 trace 证据说明文件读取、系统调用、VFS、设备访问和显示更新。

## 14. PA3 完成检查清单

### PA3 阶段 1

- [ ] 已按要求整理并创建 `pa3` 分支。
- [ ] 已实现 `ecall`、必要 CSR 指令、`isa_raise_intr()` 与 `mret`。
- [ ] `Context` 布局与 `trap.S` 完全一致，含地址空间槽位。
- [ ] `EVENT_YIELD` 被正确识别，`yield test` 持续输出 `y`。
- [ ] 异常返回 PC、寄存器和栈均正确恢复。
- [ ] `etrace` 可用。
- [ ] 已整理阶段 1 的两道必答题。

### PA3 阶段 2

- [ ] Nanos-lite 能分发 `EVENT_YIELD`。
- [ ] ELF loader 正确加载所有 `PT_LOAD`，复制文件内容并清零剩余内存。
- [ ] `dummy` 经 `SYS_yield` 和 `SYS_exit` 得到 `HIT GOOD TRAP`。
- [ ] `strace` 可记录调用名/号、参数和返回值。
- [ ] `SYS_write` 使 `hello` 正确输出。
- [ ] `SYS_brk` 与 `_sbrk()` 可供 Newlib 使用且无递归调试代码。
- [ ] 已整理 hello 完整运行路径的必答题。

### PA3 阶段 3 与最终展示

- [ ] loader 已改用文件名，SFS 的五个 API 和对应 syscall 完成。
- [ ] `file-test` 输出 `PASS!!!`，strace 能显示 SFS 文件名。
- [ ] VFS 通过函数指针统一普通文件和特殊文件。
- [ ] 串口、`gettimeofday`、NDL timer、`/dev/events` 均通过测试。
- [ ] `/proc/dispinfo`、`/dev/fb` 和 NDL 绘图通过 `bmp-test`。
- [ ] fixedptc 必做 API 通过含负数边界的自测。
- [ ] NSlider、MENU、NTerm、Flappy Bird 和 PAL 均达到原讲义验收现象。
- [ ] ramdisk 小于 48 MB，修改 Navy 后已更新镜像。
- [ ] `SYS_execve` 可由 MENU/NTerm 启动应用，应用退出后返回菜单或终端。
- [ ] NTerm 支持 `PATH=/bin` 和 `execvp()`。
- [ ] 四道实验报告必答题均已完成。

## 15. 源章节映射

| 原讲义 | 本笔记对应内容 |
| --- | --- |
| `PA3.md` PA3 总览 | 第 1、2 节：阶段划分、分支和总体要求 |
| `3.1.md` 批处理系统 | 第 3 节：操作系统需求、特权与异常动机 |
| `3.2.md` 异常响应机制 | 第 4、5 节：CTE、Context、自陷、恢复、etrace、阶段 1 标记 |
| `3.3.md` 用户程序和系统调用 | 第 6、7、13 节：Nanos-lite、ELF、syscall、TRM、阶段 2 |
| `3.4.md` 简易文件系统 | 第 8、9 节：SFS、VFS、设备文件和 NDL |
| `3.5.md` 精彩纷呈的应用程序 | 第 10、11、13 节：fixedpt、SDL、应用、批处理展示和报告 |
