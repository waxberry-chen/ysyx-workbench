# PA4 - 虚实交错的魔法：分时多任务

> 本笔记对应原讲义 `PA4.md` 与 `4.1.md` 至 `4.5.md`，默认使用课程要求的 `riscv32` 主线。它按依赖关系整理多道程序、虚拟内存、抢占调度和内核栈切换；ISA、ABI、分页和中断的精确定义仍以原讲义、RISC-V 手册及相关 ABI 为准。

[toc]

## 1. 实验目标与阶段边界

PA4 要把 PA3 的单任务批处理系统扩展为具有地址空间隔离和时钟抢占能力的分时多任务系统：

- 用 `Context`、独立栈和 PCB 创建、保存及调度多个执行流。
- 创建内核线程和用户进程，并向它们传递参数与环境。
- 理解程序位置、虚拟地址与物理地址的解耦。
- 在 NEMU 实现 RISC-V Sv32 地址转换，在 AM 实现 VME，在 Nanos-lite 管理物理页和进程地址空间。
- 实现时钟中断与抢占式调度，使不主动 `yield()` 的程序也会被切换。
- 在进入内核时从用户栈切换到内核栈，支持多个用户进程安全切换。
- 并发运行多个应用并展示完整计算机系统。

课程原始阶段划分：

| 阶段 | 覆盖内容 | 明确结束位置 |
| --- | --- | --- |
| **PA4 1阶段（task PA4.1 / PA4 阶段 1）** | 内核线程、协作式上下文切换、用户进程、参数化 `execve()`、BusyBox | 本文第 4 节 |
| PA4 阶段 2（task PA4.2） | Sv32、VME、分页上的用户进程与多道程序 | 本文第 7.7 节末尾 |
| PA4 阶段 3（task PA4.3） | 时钟中断、抢占、内核栈/用户栈切换、最终展示和报告 | PA4 全部完成 |

整体依赖关系：

```text
多个 Navy 用户进程 / Nanos-lite 内核线程
  -> syscall / timer interrupt
  -> CTE: 保存 Context + 切换栈
  -> Nanos-lite scheduler: 保存 current->cp + 选择 next
  -> VME: 切换 next 的 AddrSpace
  -> CTE: 恢复 next Context
  -> NEMU: interrupt + Sv32 MMU + device
```

推荐推进顺序：

```text
yield-os + kcontext
  -> Nanos-lite 内核线程切换
  -> ucontext + 用户栈
  -> 参数 / execve / BusyBox             [PA4 1 阶段]
  -> 分页原理 + Sv32 MMU
  -> VME + loader + 用户栈映射 + brk
  -> 分页上的多道程序                    [PA4 阶段 2]
  -> timer interrupt + 抢占调度
  -> 内核栈 / 用户栈切换
  -> 多用户进程 + 前台应用切换             [PA4 阶段 3 / PA4 完成]
```

## 2. 开始前的必读原则

**[必读] 先整理 PA4 分支。** 原讲义要求在工程目录执行：

```bash
git commit --allow-empty -am "before starting pa4"
git checkout master
git merge pa3
git checkout -b pa4
```

执行前确认 PA3 已提交且工作区干净。原讲义明确警告：不按要求整理分支会影响成绩。PA4 预计平均耗时为 40 小时。

**[必读] PA4 不再提供滴水不漏的代码指导。** 讲义刻意省略部分实现细节；先理解状态和接口，再通过 RTFSC、RTFM、反汇编和实验补全代码。靠猜测字段、照抄别人的布局或反复改到“能跑”无法支撑后续组合场景。

**[原则] 上下文切换的本质是状态切换。** 要能回答：旧状态保存在哪里、谁持有它的地址、新状态从哪里来、何时切换地址空间和栈、恢复后第一条指令是什么。

**[原则] 机制与策略解耦。** CTE 提供“能够切换 Context”的机制；Nanos-lite 的 `schedule()` 决定“切换到谁”。VME 提供地址映射机制；操作系统决定每个进程映射哪些页面。

**[原则] 生命周期决定存放位置。** 只属于某个进程/上下文并且跨切换存活的状态必须放在 PCB、内核栈或 `Context` 中；共享全局变量可能被其他线程、中断或 CTE 重入覆盖。

本笔记使用：

- `[必做]`：必须实现并达到给定验收现象。
- `[必读]` / `[原则]`：不可弱化的约束和方法。
- `[提示]`：影响实验推进或避免误判的内容。
- `[扩展阅读]` / `[选做·编程]` / `[选做·思考]`：不进入必做清单。

## 3. 多道程序与上下文切换（对应 4.1）

### 3.1 为什么需要多道程序

PA3 一次只运行一个用户程序。若该程序等待慢速 I/O，CPU 也随之空转。多道程序要求：

1. 内存中同时存在多个进程。
2. 在某些条件下切换进程执行流。

本阶段先用 `yield()` 模拟程序在 I/O 时主动让出 CPU。每个执行流必须有自己的栈；共享栈会使不同执行流的栈帧和已保存 `Context` 相互覆盖。

### 3.2 Context、PCB 与栈切换

进程 A 自陷时，`trap.S` 把 A 的 `Context` 保存到 A 的栈。若 handler 返回的不是 A 的 `Context *`，而是 B 栈上的 `Context *`，`trap.S` 就会恢复 B：

```text
A 运行
  -> A 栈保存 Context A
  -> schedule(Context A)
       current->cp = Context A
       current = PCB B
       return B->cp
  -> trap.S 以 Context B 恢复
  -> B 运行
```

因此当前模型下“上下文切换就是切换到另一份可恢复的栈上状态”。PCB 至少维护内核栈和 `Context *cp`：

```c
typedef union {
  uint8_t stack[STACK_SIZE];
  struct {
    Context *cp;
  };
} PCB;
```

`current` 指向当前 PCB。调度时必须先保存 `prev`，再选择目标并返回其 `cp`；否则当前进程下次无从恢复。

### 3.3 `kcontext()`：人工创建第一个状态

新内核线程尚未运行过，栈上没有自然产生的 Context。`kcontext(Area kstack, entry, arg)` 要在给定栈中人工构造一个可恢复状态，使 `trap.S` 恢复后从 `entry(arg)` 开始执行。

必须确认：

- `Context` 位于栈顶方向的正确位置并满足 ABI 对齐。
- PC/异常返回地址指向入口或必要的包裹函数。
- `sp` 指向合法的内核栈。
- 状态寄存器允许正确返回；RISC-V 配合 DiffTest 时通常把 `mstatus` 初始化为 `0x1800`。
- `arg` 按 RISC-V calling convention 放入入口参数寄存器。
- AM 规定入口函数不得返回；若需要返回行为，必须用不会返回的包裹函数处理。

### 3.4 在 `yield-os` 实现最小切换

**[必做] 实现上下文切换。**

- 实现 CTE 的 `kcontext()`。
- 修改 `__am_asm_trap()`：使用 `__am_irq_handle()` 返回的 `Context *` 作为恢复来源，先切换到新上下文，再恢复寄存器。
- 运行 `am-kernels` 的 `yield-os`。

第一步验收：不断输出 `?`，说明已经从 `main()` 切到至少一个内核线程。

**[必做] 实现内核线程参数。** 按 RISC-V ABI 把 `arg` 放入正确寄存器。验收：两个线程分别得到正确参数，`yield-os` 交替输出 `A` 和 `B`。

**[提示] 若恢复后立即跑飞，先反推“能正确开始执行 `entry` 的最小 CPU 状态”，再逐项检查人工 Context；不要只改单个 PC。**

### 3.5 迁移到 Nanos-lite

**[必做] 在 Nanos-lite 实现上下文切换。**

- 实现 `context_kload(PCB *, entry, arg)`：调用 `kcontext()` 并保存返回的 `cp`。
- 实现 `schedule(Context *prev)`：保存当前 `cp`、选择下一个 PCB、返回目标 `cp`。
- 处理 `EVENT_YIELD` 时调用 `schedule()` 并把结果返回 CTE。
- 在 `init_proc()` 创建两个 `hello_fun` 内核线程，并调用 `switch_boot_pcb()` 初始化 `current`。

验收：两个 `hello_fun` 按各自参数轮流输出。

**[提示] AM native 创建的上下文默认开中断。** 在 native 上测试时先识别 `EVENT_IRQ_TIMER` 并原样返回 Context；本阶段无需据此调度。

### 3.6 创建用户进程

内核线程的代码、数据和栈都在内核空间。用户进程应拥有用户区代码、数据和用户栈，同时在 PCB 中保留内核栈。`ucontext(AddrSpace *as, Area kstack, entry)` 在 PCB 内核栈上创建用户 Context；阶段 1 暂时忽略 `as`。

Nanos-lite 与 Navy 的初始约定：

```text
Nanos-lite context_uload
  -> loader 得到 entry
  -> ucontext(NULL, pcb.kstack, entry)
  -> 把用户栈顶放入 Context.GPRx
  -> 调度并恢复用户 Context
  -> Navy _start 从 GPRx 取栈顶并设置 sp
  -> call_main
```

本阶段可先以 `heap.end` 为用户栈顶；稍后参数化 `execve()` 时改为 `new_page()` 分配独立的 32 KB 用户栈。

**[必做] 实现多道程序系统。**

- 实现 VME 的 `ucontext()`。
- 实现 Nanos-lite 的 `context_uload()`。
- 在 Navy `_start` 设置正确用户栈；AM native 也必须工作。
- 以一个 `hello_fun` 内核线程和一个 `/bin/pal` 用户进程测试。
- 暂在 `serial_write()`、`events_read()`、`fb_write()` 开头调用 `yield()` 模拟慢设备；阶段 3 使用时钟抢占后删除这些人工 `yield()`。

验收：PAL 正常运行，同时 hello 信息仍持续输出；还应通过修改/观察栈区证明 PAL 使用用户栈而非 PCB 内核栈。

### 3.7 用户栈上的 `argc/argv/envp`

操作系统需按简化 ABI 在用户栈构造：

```text
高地址
  字符串区域: argv/envp 指向的 \0 结尾字符串
  可选对齐空隙
  NULL
  envp[]
  NULL
  argv[]
  argc             <- Context.GPRx 指向这里
低地址
```

所有指针必须是用户进程将来可见的地址，数组和字符串不能互相覆盖，栈需满足 ABI 对齐。Navy `_start` 把 `GPRx` 传给 `call_main()`；后者解析 `argc/argv/envp`，设置 `environ`，再调用 `main()`。

**[必做] 给用户进程传递参数。**

- 把 `context_uload()` 扩展为接收 `filename, argv, envp`。
- 用可移植的指针和 `uintptr_t` 逻辑构造用户栈。
- 修改 Navy CRT 正确解析参数。
- 让 PAL 接收 `--skip` 并跳过片头商标动画。

验收：`init_proc()` 给 PAL 传入 `--skip` 后确实跳过动画。

### 3.8 带参数的 `execve()` 与 BusyBox

执行 A 的 `SYS_execve` 时，内核处理代码仍在使用 A 的栈和 Context，不能直接覆盖它。`context_uload()` 应用 `new_page()` 给 B 分配新的 32 KB 用户栈；PA4 暂不实现 `free_page()`。创建 B 后，通过 `switch_boot_pcb()` 使 A 不再被调度，再 `yield()` 切入 B。

**[必做] 实现带参数的 `execve()`。**

- 用户层传递 `filename/argv/envp`。
- Nanos-lite 创建新用户 Context 并结束旧执行流。
- `exec-test` 应能递增参数并正确自执行一段时间；因不回收页面，最终覆盖固定加载区是本阶段已知限制。
- MENU 能启动程序。
- NTerm 能解析命令参数，例如 `pal --skip`。

**[必做] 运行 BusyBox。** 从 NTerm 运行 `cat`、`printenv` 等简单命令，适当降低 `hello_fun()` 输出频率，避免淹没命令输出。

**[必做] 支持 BusyBox 的 `PATH` 遍历。**

- 把 `/usr/bin` 加入 `PATH`，使用 `:` 分隔路径。
- `fs_open()` 找不到文件时不再 assertion，而要返回失败。
- `SYS_execve` 对不存在文件返回 `-2`。
- libos 的 `execve()` 在系统调用返回负值时设置 `errno = -ret` 并返回 `-1`。
- 让 `execvp()` 继续搜索其他路径。

验收：在 NTerm 执行位于 `/usr/bin` 的命令，例如：

```bash
wc /share/games/bird/atlas.txt
```

结果应与 Linux 上相同。

## 4. PA4 1阶段验收点

> **[里程碑] PA4 1阶段（task PA4.1 / PA4 阶段 1）到此结束。**
>
> `yield-os`、Nanos-lite 内核线程、PAL + hello 多道程序、用户参数、带参数 `execve()`、NTerm 和 BusyBox/`PATH` 均达到验收现象。这里就是原讲义明确标出的 PA4 阶段 1 结束位置。

## 5. 程序位置与虚拟内存（对应 4.2）

### 5.1 两个用户程序为什么互相覆盖

PA4 阶段 1 的 Navy 程序都链接到 RISC-V `0x83000000` 附近。同时加载两个绝对代码程序，后者会覆盖前者。仅把 ELF 搬到另一个物理地址也不行，因为程序中的地址已在链接时确定。

三种传统处理方式：

- **绝对代码**：只能在链接时确定的位置运行。
- **加载时/运行时重定位**：修改重定位项，使程序适配实际位置；需要额外处理和元数据。
- **PIC/PIE**：主要使用相对寻址，可装入不同位置；仍涉及 GOT 等机制和空间/性能取舍。

### 5.2 虚拟内存的核心解耦

虚拟内存让每个进程继续看到相同虚拟地址，操作系统却把它们映射到不同物理页：

```text
进程 A VA 0x40000000 -> PA page A
进程 B VA 0x40000000 -> PA page B
```

操作系统决定映射并建立页表，硬件 MMU 在每次取指、读和写之前完成地址转换。因此虚存是软硬协同机制：软件维护映射，硬件执行映射。

状态机视角下，把每次 `M[addr]` 扩展为 `M[fvm(addr)]`；`fvm` 由页表和地址空间寄存器决定，是可由软件修改的机器状态。

### 5.3 分段、分页与 TLB

分段近似 `pa = base + va`，灵活性有限。分页把虚拟/物理内存切成定长页，用页表枚举虚拟页到物理页的映射；多级页表避免为未使用虚拟空间分配完整一级大表。

TLB 缓存页级转换结果。切换进程时必须维持 TLB 与当前地址空间一致：可使用 ASID 标识进程，或在切换页表根时冲刷相关 TLB。PA 的 RISC-V/x86 路线不要求在 NEMU 模拟 TLB，直接做 page table walk。

**[选做·编程] PIE loader。** 若二周目尝试，需要理解 ELF relocation、GOT 和 ABI；它不是 PA4 虚存主线的替代品。

## 6. Sv32 与 VME 理论（对应 4.3）

### 6.1 RISC-V Sv32 page table walk

Sv32 使用 4 KB 页面和二级页表。32 位虚拟地址通常拆成：

```text
31             22 21             12 11              0
+----------------+-----------------+------------------+
|    VPN[1]      |    VPN[0]       | page offset      |
+----------------+-----------------+------------------+
      10 bits          10 bits           12 bits
```

`satp` 保存分页模式与根页表物理页号。转换过程：根页表经 `VPN[1]` 找二级页表，二级页表经 `VPN[0]` 找叶 PTE，叶 PTE 的 PPN 与页内偏移组成物理地址。PTE 的 `V/R/W/X/U/A/D` 等位必须按手册解释；PA 即使不完整实现保护，也应 assertion 检查无效/非法表项，避免错误地址继续传播。

**[必做] 理解分页机制。** 必须结合 RISC-V privileged spec 明确：`satp` 格式、两级索引、PTE 位、叶/非叶判断、页对齐、访问类型，以及一次取指/读/写如何完成转换。

### 6.2 VME API

AM 用 VME 抽象架构差异：

```c
bool vme_init(void *(*pgalloc_f)(int), void (*pgfree_f)(void *));
void protect(AddrSpace *as);
void unprotect(AddrSpace *as);
void map(AddrSpace *as, void *va, void *pa, int prot);
Context *ucontext(AddrSpace *as, Area kstack, void *entry);
```

`AddrSpace` 中：

- `pgsize`：页面大小。
- `area`：用户虚拟地址范围。
- `ptr`：ISA 相关页表根/地址空间描述符。

`vme_init()` 注册页分配回调并建立内核地址空间 `kas`；`protect()` 为进程创建包含内核映射的新地址空间；`map()` 维护单页映射；`ucontext()` 把地址空间信息放入 Context。

### 6.3 NEMU MMU 边界

所有虚拟访存先调用：

```c
int isa_mmu_check(vaddr_t vaddr, int len, int type);
paddr_t isa_mmu_translate(vaddr_t vaddr, int len, int type);
```

- `MMU_DIRECT`：直接 `paddr_read/write`。
- `MMU_TRANSLATE`：先 page table walk，再访问转换后的物理地址。
- `MMU_FAIL`：理论上触发异常；PA 用例通常不走此分支。

RISC-V 主线由 `satp` 判断是否启用地址转换。原讲义对 NEMU 做了简化：允许 M-mode 访存也经过地址转换，从而暂不引入完整 S/U-mode 细节。

## 7. PA4 阶段 2：实现分页上的多道程序

### 7.1 让 Nanos-lite 在分页机制上运行

启用 `HAS_VME` 后，Nanos-lite 的 `init_mm()` 初始化空闲物理页并调用 `vme_init()`。内核虚拟地址使用恒等映射，因此开启分页前后看到的地址不变。

**[必做] 在分页机制上运行 Nanos-lite。**

- 实现 `pg_alloc(n)`：用 `new_page()` 分配整数页并全部清零。
- 实现 VME `map()`：必要时经 `pgalloc_usr()` 分配并清零下级页表，填写正确 PTE。
- 在 NEMU 实现 `isa_mmu_check()`、`isa_mmu_translate()` 和 `satp` 相关 CSR 行为。
- 对无效 PTE 使用 assertion；内核恒等映射阶段可断言转换后 `pa == va`。

验收：开启分页后 Nanos-lite 和 PAL 仍能运行。RISC-V/x86 不需要实现 TLB。

### 7.2 为用户进程创建地址空间

用 `VME=1` 编译 Navy，使程序链接到 `0x40000000`；该虚拟地址超出 NEMU 128 MB 物理内存并不构成问题。

`context_uload()` 应先 `protect(&pcb->as)`。Loader 不能直接写用户虚拟地址，而应按页：

1. 为 segment 覆盖的虚拟页分配物理页。
2. 用 `map(&pcb->as, va_page, pa_page, prot)` 建立映射；为兼容 AM native 的权限检查，加载程序页面时把 `prot` 设置为可读、可写、可执行。
3. 把 ELF 文件内容读入物理页的正确页内区间。
4. 正确处理非页对齐 segment、跨页内容和 `p_memsz > p_filesz` 的清零区域。

用户栈同样分配物理页，映射到：

```text
[as.area.end - 32 KB, as.area.end)
```

`argc/argv/envp` 中保存的必须是用户虚拟地址，而不是 loader 可见的物理指针。

### 7.3 切换地址空间

地址空间描述符随 Context 恢复：

- `ucontext()` 设置用户 Context 的 `pdir`（x86 为 `cr3`）。
- `__am_get_cur_as()` 在进入 handler 时保存当前地址空间描述符。
- `__am_switch()` 在 handler 返回前把目标 Context 的地址空间落实到 MMU。
- `kcontext()` 用 `NULL` 标记内核线程；所有用户地址空间都复制内核映射，因此内核线程可以沿用当前地址空间，无需切换。

**[必做] 在分页机制上运行用户进程。** 先只调度 `/bin/dummy`，暂让 `exit` 调用 `halt()`。验收：dummy 输出 `GOOD TRAP`。

### 7.4 实现分页堆

每个 PCB 用 `max_brk` 记录该进程历史最大 program break。`mm_brk(new_brk)` 只为超过 `max_brk` 的新页分配物理页并映射；PA 不要求缩小时回收页面。

**[必做] 在分页机制上运行 PAL。** 实现 `mm_brk()`，明确 `map()` 是否要求 `va/pa` 页对齐，正确处理首尾页和重复映射。验收：PAL 在自己的地址空间中正常运行。

### 7.5 恢复多道程序

**[必做] 支持虚存管理的多道程序。** 同时加载 PAL 用户进程和 hello 内核线程。效果与阶段 1 相似，但取指、用户数据、用户栈和堆都运行在分页机制上。

### 7.6 架构条件任务

**[必做·仅 mips32] 实现软件管理 TLB。** 包括 TLB refill 异常、`__am_tlb_refill()` 的 page table walk/填充，以及切换地址空间时 `__am_tlb_clear()`。RISC-V 主线忽略此项。

### 7.7 阶段验收点

> **[里程碑] PA4 阶段 2（task PA4.2）到此结束。**
>
> NEMU 已实现 Sv32 转换，VME 能维护地址空间，dummy/PAL 和用户堆能在分页机制上运行，PAL 用户进程可与 hello 内核线程协作式并发。

## 8. 时钟中断与抢占多任务（对应 4.4）

### 8.1 为什么 `yield()` 不够

协同多任务依赖程序主动让出 CPU。死循环或恶意程序可以永远不调用 `yield()`，使其他进程饿死。抢占多任务用程序无法控制的时钟中断强制进入内核并调度。

NEMU 的时钟设备约每 10 ms 调用 `dev_raise_intr()`。CPU 在每条指令完成后查询中断；只有中断待决且 `mstatus.MIE` 允许时，才响应时钟中断。

### 8.2 NEMU 的中断路径

RISC-V 主线需完成：

```text
timer_intr()
  -> dev_raise_intr(): cpu.INTR = true
  -> 每条指令结束 isa_query_intr()
  -> IRQ_TIMER = 0x80000007
  -> isa_raise_intr(IRQ_TIMER, cpu.pc)
       MPIE <- MIE
       MIE  <- 0
       mcause / mepc <- ...
       pc <- mtvec
  -> CTE EVENT_IRQ_TIMER
  -> schedule()
  -> mret: MIE <- MPIE; MPIE <- 1
```

中断响应与同步异常的区别在于到来时机不由当前程序决定；保存的 `mepc` 应使被打断指令流从正确位置继续，不能套用 `ecall` 的 PC + 4 逻辑。

### 8.3 实现抢占

**[必做] 实现抢占式分时多任务。**

- 在 CPU 状态增加 `bool INTR`。
- `dev_raise_intr()` 拉高中断请求；`isa_query_intr()` 在允许时消费请求并返回时钟中断号。
- 每条指令执行后查询并响应中断。
- 正确实现 `mstatus.MIE/MPIE` 在 `isa_raise_intr()` 与 `mret` 中的转换。
- CTE 把时钟中断封装为 `EVENT_IRQ_TIMER`。
- Nanos-lite 收到该事件后调用 `schedule()`。
- `kcontext()` / `ucontext()` 构造出恢复后处于开中断状态的 Context。
- 删除设备访问函数中为阶段 1 人工插入的 `yield()`。

验收：即使进程不主动 `yield()`，仍会被时钟中断抢占。可临时在 Nanos-lite 收到 `EVENT_IRQ_TIMER` 时 `Log()`，确认后删除或受调试开关控制。

**[提示] 时钟中断无法与 QEMU DiffTest 保持同一到达时刻。** 进入这一部分后不能依赖逐指令 DiffTest；先关闭中断验证确定性路径，再打开中断，用 trace 和不变量诊断。

### 8.4 时间片与并发

固定频率时钟把执行时间划分为时间片。简单 round-robin 已能展示分时；也可让 PAL 获得多个时间片、hello 偶尔运行，以改善交互性能。

中断使状态转移具有外部不确定性，共享状态可能出现 Heisenbug。不要通过增加打印认定问题消失；记录中断序列、Context、`current`、地址空间和栈边界，尽量构造可复现条件。

## 9. 内核栈与用户栈切换

### 9.1 为什么 Context 不能留在用户栈

若进程 A 的地址空间中访问不到进程 B 的用户栈，就无法读取 B 用户栈上的 Context 以切换到 B 的页表；但不切页表又访问不到 B 的 Context，形成循环依赖。

更严重的是，内核不能信任用户给出的 `sp`：恶意用户程序可让 `sp` 指向内核数据后执行 `ecall`，若 CTE 直接在此压 Context，就会破坏内核。

解决办法：从用户态进入 CTE 时，在任何压栈前切到当前进程的内核栈；Context 始终位于所有地址空间可见的内核区域。返回用户态时再恢复用户栈。

### 9.2 四个概念状态

- `pp`：进入 CTE 前的 privilege。
- `ksp`：当前进程内核栈位置。
- `np`：目标 Context 将返回的 privilege。
- `usp`：目标 Context 的用户栈指针。

`np` 和 `usp` 会跨上下文切换，因此必须属于 Context；若做成全局变量，它们可能描述旧进程。`ksp/pp` 描述当前 CPU 进入 CTE 前后的瞬时状态，可由 ISA 机制维护，但必须考虑 CTE 重入。

PA 为避免中断嵌套，在进入 CTE 后保持关中断；系统调用内部主动 `yield()` 仍可能导致 CTE 重入，因此进入后要及时把“当前位于内核态”的状态落实。

### 9.3 RISC-V 的 `mscratch` 方案

RISC-V ABI 没有保留内核 GPR，使用 `mscratch` 保存概念上的 `ksp`。入口可用原子 CSR 交换：

```asm
__am_asm_trap:
  csrrw sp, mscratch, sp
  bnez  sp, save_context
  csrr  sp, mscratch

save_context:
  # 此时 sp 指向正确的内核栈，再保存 Context
```

- 从用户态进入时，旧 `mscratch` 是内核栈，交换后 `sp` 已切到内核栈，旧用户 `sp` 暂存于 `mscratch`。
- 从内核态进入时，旧 `mscratch` 为 0；交换后通过第三条指令取回原内核 `sp`。
- Context 添加 `np`，原用户 `sp` 保存到 `c->gpr[sp]` 的正确位置。
- 返回时根据目标 Context 的 `np` 决定是否恢复用户栈，并为下一次用户陷入准备好 `mscratch`。

### 9.4 实现与验收

**[必做] 实现内核栈和用户栈之间的切换。**

- 修改 RISC-V CTE 入口/出口、`Context` 和必要 CSR 指令支持。
- 在 `cte_init()`、`kcontext()`、`ucontext()` 初始化 `mscratch/np` 等状态。
- 确保从内核态进入 CTE 不会把 `sp` 重置到栈底并覆盖现有栈帧。
- 确保上下文切换后使用的是目标 Context 的 `np/usp/pdir`。
- 先关闭时钟中断测试确定性切换，再打开抢占。

验收：同时加载 NTerm 和 hello 两个用户进程，从 NTerm 启动 PAL；hello 与 NTerm/PAL 分时运行。这次是两个真正拥有独立地址空间、用户栈和内核栈的用户进程。

**[提示] 当前最多允许一个需要更新画面的前台进程参与调度。** 多个图形进程会覆盖同一 frame buffer；真正的解决方案需要窗口管理和 IPC，不属于 Nanos-lite 必做范围。

## 10. PA4 阶段 3：最终展示（对应 4.5）

### 10.1 展示计算机系统

Nanos-lite 最多维护 4 个进程。可加载 PAL、Flappy Bird、NSlider 和 hello，用 `fg_pcb` 表示当前前台程序；在 `events_read()` 将 `F1/F2/F3` 绑定到不同前台 PCB，调度器只让所选前台与 hello 运行。

**[必做] 添加前台程序切换并展示系统。**

- 启动多个应用并保证各自状态在切走后保留。
- 用功能键切换前台应用。
- hello 后台线程/进程继续获得时间片。
- 切换过程中不破坏地址空间、用户栈、内核栈和 Context。

也可以加载多份 MENU 或 NTerm，用不同地址空间验证同一虚拟地址可并存。

### 10.2 阶段与 PA 完成点

> **[里程碑] PA4 阶段 3（task PA4.3）与 PA4 到此完成。**
>
> 时钟中断能稳定抢占，多个用户进程通过独立地址空间和双栈正确切换，前台应用可交互切换；完成第 12 节必答题和实验报告后，才算完成整个 PA4。

## 11. Debug 方法

### 11.1 分阶段保持确定性

1. 先用 `yield-os` 验证 Context 人工创建和协作式切换。
2. 再迁移 Nanos-lite 内核线程。
3. 单独验证一个用户进程和用户栈。
4. 开分页后先只运行 dummy，再运行 PAL，再恢复内核线程。
5. 时钟中断关闭时验证内核栈/用户栈切换。
6. 最后打开中断和多个用户进程。

每一步都记录可回归的最小验收现象；不要把 Context、MMU、抢占和双栈同时打开后再找第一处错误。

### 11.2 故障定位表

| 现象 | 首要检查 |
| --- | --- |
| `yield-os` 第一次切换即跑飞 | 人工 Context 的 PC、sp、`mstatus`、对齐、恢复顺序 |
| 只能运行一个线程 | `current->cp = prev`、目标选择、handler 返回值 |
| 参数显示为 `?`/乱码 | RISC-V ABI 参数寄存器、Context 字段、指针生命周期 |
| 用户程序入口即崩溃 | `_start` 的 sp、GPRx、用户栈地址和对齐 |
| 第二个用户程序覆盖第一个 | 阶段 1 固定链接地址限制；进入 VME 主线 |
| 开分页后 Nanos-lite 立即崩溃 | `satp`、根页表物理地址、内核恒等映射、PTE `V` 位 |
| 页表 walk 地址离谱 | VPN/PPN 位抽取、物理地址/页号混淆、左移位数 |
| dummy 可跑、PAL 堆崩溃 | `mm_brk/max_brk`、页对齐、漏映射或重复映射 |
| 切换后进入别人的代码/数据 | Context 的 `pdir`、`__am_get_cur_as()`、`__am_switch()` |
| 时钟中断只来一次 | `INTR` 清除、`MIE/MPIE`、`mret` 恢复 |
| 开中断后偶发崩溃 | 先关中断复现；检查共享全局状态、重入和栈边界 |
| 两用户进程切换失败 | Context 是否在内核栈、`mscratch`、`np/usp` 的归属 |
| `execvp` 不继续搜索 | `fs_open` 失败语义、`SYS_execve=-2`、`errno` 和返回值 |

### 11.3 建议观察的不变量

- `current->cp` 始终落在 `current` 的内核栈范围。
- 用户态运行时 `sp` 落在该进程用户栈虚拟区间。
- 内核 C 代码运行时 `sp` 落在当前 PCB 内核栈。
- 根页表和所有下级页表物理地址页对齐。
- 用户 VA 映射到分配器返回的合法物理页；不同进程同一 VA 可映射不同 PA。
- 内核映射出现在每个用户地址空间中。
- `satp`、Context 地址空间字段与被调度 PCB 一致。
- `EVENT_IRQ_TIMER` 的返回 PC 不跳过被打断指令，也不重复已完成指令。

## 12. 实验报告必答题

**[必做] 必须结合自己的代码、运行轨迹和工具证据回答。**

1. **分时多任务的具体过程**：解释分页机制和硬件时钟中断如何支撑 PAL 与 hello 在 Nanos-lite、AM、NEMU 中分时运行。至少覆盖中断产生/响应、Context 保存、调度、地址空间和栈切换、恢复及继续执行。
2. **理解计算机系统：字符串写保护**。在 Linux 运行：

   ```c
   int main() {
     char *p = "abc";
     p[0] = 'A';
     return 0;
   }
   ```

   从程序、编译器、链接器、ELF、loader、操作系统页表、MMU 和异常/信号处理解释 `p[0] = 'A'` 为什么产生段错误，以及系统如何保证写保护生效。建议用 `readelf`、`objdump`、`gdb`、`/proc/<pid>/maps` 等证据验证字符串所在 segment/页面权限和故障指令。

## 13. PA4 完成检查清单

### PA4 1阶段

- [ ] 已按要求整理并创建 `pa4` 分支。
- [ ] `kcontext()` 和 CTE 恢复逻辑使 `yield-os` 正确交替输出。
- [ ] `kcontext()` 按 ABI 正确传递 `arg`。
- [ ] Nanos-lite 两个 `hello_fun` 内核线程可切换。
- [ ] `ucontext()`、`context_uload()` 和 Navy `_start` 使用正确用户栈。
- [ ] PAL 与 hello 内核线程能够协作式多道运行。
- [ ] 用户栈正确构造 `argc/argv/envp`，PAL 的 `--skip` 生效。
- [ ] 带参数 `execve()`、`exec-test`、MENU 和 NTerm 参数解析可用。
- [ ] BusyBox 简单命令可运行，`PATH` 能搜索 `/bin:/usr/bin`。
- [ ] 不存在文件时 `fs_open/execve/errno` 返回语义正确。

### PA4 阶段 2

- [ ] 已按手册理解并实现 RISC-V Sv32 page table walk。
- [ ] `pg_alloc()` 分配页并清零，`map()` 正确建立二级页表。
- [ ] NEMU 的 MMU check/translate 与 `satp` 行为正确。
- [ ] Nanos-lite 在内核恒等映射上运行。
- [ ] Navy 以 `VME=1` 链接，loader 按页建立用户映射。
- [ ] 用户栈映射在地址空间末尾，参数指针使用用户 VA。
- [ ] Context 与调度正确切换地址空间。
- [ ] dummy 在分页上得到 `GOOD TRAP`。
- [ ] `mm_brk()` 为新堆页建立映射，PAL 在分页上运行。
- [ ] PAL 用户进程与 hello 内核线程在分页上多道运行。

### PA4 阶段 3

- [ ] NEMU 能产生、查询并响应 RISC-V 时钟中断。
- [ ] `mstatus.MIE/MPIE` 和 `mret` 语义正确。
- [ ] CTE 产生 `EVENT_IRQ_TIMER`，Nanos-lite 据此抢占调度。
- [ ] 已删除设备访问中的人工 `yield()`。
- [ ] RISC-V CTE 使用 `mscratch` 正确切换用户栈/内核栈。
- [ ] `np/usp` 随 Context 切换，不被错误的全局状态覆盖。
- [ ] NTerm + hello 两个用户进程以及从 NTerm 启动的 PAL 可稳定分时。
- [ ] 前台应用可通过功能键切换，后台 hello 仍运行。
- [ ] 两道实验报告必答题已完成并有工具证据。

## 14. 扩展与选做索引

以下主题来自原讲义蓝色框或明确选做章节，不进入必做验收：

- **[扩展阅读·4.1]** 多进程为何需要不同栈；内核线程与进程的区别；机制/策略解耦；ABI 与 `argc/argv/envp`；`const` 差异；操作系统为何自管页对齐内存；`errno`；全局变量在多线程和中断下的危险。
- **[选做·编程·4.1]** 用 CTE 移植 RT-Thread 的 Context 创建/切换，在 RT-Thread 中集成 AM 应用，并分析脚本如何解决多个 AM 程序的符号/数据冲突。
- **[扩展阅读·4.2/4.3]** PIE/GOT loader；PIC 与共享页面；多级页表、空指针本质、TLB/ASID；内核映射作用；native VME；用户 Context 为什么放在内核栈；RISC-V 完整 M/U 特权和 DiffTest；mips32 TLB 一致性。
- **[选做·思考·4.3]** 在完成双栈方案前独立分析“两个用户进程为何不能并发”；这是原讲义的一周目高难度问题。
- **[扩展阅读·4.4]** 中断嵌套的灾难与软硬件协同；优先级调度；CTE 重入；Linux 上下文切换；RISC-V `mscratch` 与 MIPS 内核寄存器方案比较；Nanos-lite 的并发 `brk` 风险。
- **[选做·编程·4.5]** 必须在新分支尝试 ONScripter、SDL_ttf/image/mixer、BGM/音效、磁盘、NWM、按键缓冲、绘图并发和崩溃一致性；这些改动可能与必做主线不兼容。
- **[扩展阅读·4.5]** 缓存与字体光栅化、内存文件、DMA 与 cache、`fork()`、窗口管理、持久化、操作系统定义，以及交互/互联/融合时代的系统演进。

**[必读] 二周目与方法复盘。** 原讲义强调：一周目顺利掌握的程度会在二周目暴露；若无法解释程序如何执行及本课程反复使用的原则，应独立重做关键链路，而不是只保留“测试通过”的结果。

## 15. 源章节映射

| 原讲义 | 本笔记对应内容 |
| --- | --- |
| `PA4.md` PA4 总览 | 第 1、2 节：阶段划分、分支和总体要求 |
| `4.1.md` 多道程序 | 第 3、4 节：Context、线程/进程、参数、exec、BusyBox、阶段 1 标记 |
| `4.2.md` 程序和内存位置 | 第 5 节：重定位、PIC/PIE 与虚存动机 |
| `4.3.md` 超越容量的界限 | 第 6、7 节：分页、VME、用户地址空间、阶段 2 |
| `4.4.md` 分时多任务 | 第 8、9 节：中断、抢占、内核栈与用户栈 |
| `4.5.md` 编写不朽的传奇 | 第 10、12、14 节：展示、报告、扩展方向与 PA4 完成 |
