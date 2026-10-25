# SoC 仿真与验证入门：谁在执行，谁在观察，谁来判断对错

2026-10-25。以 M5 S3 为例，先建立整体认识，再阅读 [S3 实现记录](../post-c/5-ysyx-soc-integration/3-runtime-difftest.md)。本文可以离线阅读；代码位置用于之后对照，不要求一边读一边打开所有源码。

阅读目标：能画出一次测试的执行关系，解释正常程序如何通过，以及故意破坏启动后为什么应该失败。

## 1. 先分清宿主机与被模拟的 CPU

**宿主机**是运行 Linux、Python、编译器和仿真可执行文件的电脑。**目标机**是仿真中的 RISC-V CPU 与 SoC。下面虽然都写着“执行”，执行者却不同。

| 内容 | 谁执行 | 做什么 |
| --- | --- | --- |
| `m5_s3_test.py` | 宿主机上的 Python 解释器 | 构建程序，启动仿真进程，读取结果并判定测试 |
| C++ harness（仿真驱动程序） | 宿主机 | 加载镜像，驱动时钟/复位，推进仿真，采集状态、输出日志 |
| Verilator 生成的 C++ 模型 | 宿主机 | 计算 RTL 描述的信号与状态变化，包括 CPU、总线、外设 |
| `start.S`、AM 和测试 C 程序对应的机器码 | 仿真中的 RISC-V CPU | 取指、访存、初始化 SRAM、运行程序 |
| NEMU 参考模型 | 宿主机 | 按 ISA 语义执行目标指令，提供参考状态 |

这里的 C/C++ 有两种用途：`npc/csrc/soc/main.cpp` 编译成宿主机程序；`npc/tests/soc-runtime/memory.c` 交叉编译成 RISC-V 程序。**源语言相近，不代表运行在同一台“机器”上。**

CPU 不执行 Python，也不把 `main.cpp` 当成自己的软件。Python 通常以一次测试为单位启动 EXE；每个时钟和内部延迟事件由 EXE 内的 harness 推进。

## 2. 构建得到三类不同产物

```text
CPU/SoC/外设 RTL + 仿真 monitor
        │ Verilator 转换为 C++ 模型
        └─ 加上手写 C++ harness，编译链接
              → VysyxSoCFull：宿主机可执行文件（EXE）

NEMU 的 C 源码 + SoC 参考端配置
        └─ 宿主机编译器编译链接
              → nemu-ref.so：参考模型共享库

start.S + AM + 测试程序 + 链接脚本
        └─ RISC-V 交叉编译、链接 → ELF → objcopy
              → 程序.bin：目标 CPU 要执行的镜像
```

当前 REF 单独构建为 `.so`，harness 根据 `--diff` 参数用 `dlopen` 加载到仿真进程。它没有直接编入 EXE，也不需要为这次比较单独启动一个 NEMU 进程。NEMU 本身还有独立运行等用途，这里只描述它在 S3 中的参考端角色。

构建入口在 `npc/scripts/soc.mk`：`soc-build` 生成 EXE，`soc-ref` 生成参考库，`s3-test` 准备这两者后运行 Python。Python 再为各测试构建目标程序。修改某个 C 测试通常只需要更新程序镜像；修改 RTL/harness 才需要更新仿真 EXE。

## 3. 一次测试如何流动

```text
Python 选择镜像、参考库、周期上限及结果文件路径
  → 启动 VysyxSoCFull --mrom ... --diff ...
      → harness 将 BIN 装入 MROM backing（仿真中保存 ROM 字节的容器）
      → 驱动复位、时钟和仿真事件
      → CPU 从复位 PC 取指，执行启动代码和测试程序
      → monitor 观察提交/总线；harness 调用 REF 作比较
      → harness 解码 UART TX，并写 JSON / CSV / 日志
      → 仿真进程退出，向宿主机返回退出码
  → Python 检查退出码、文件内容及该测试的预期
```

**monitor** 是观察器。当前 `npc/sim/soc_monitor.sv` 通过仿真绑定访问内部状态，并借助 DPI（SystemVerilog 与 C/C++ 的调用接口）传递信息。它提供观察通道；它不是 CPU 在真实芯片上运行所必需的功能模块。

当前 SRAM 的启动写入由 CPU 发出，经过 LSU、AXI 和 SoC 中的 SRAM 实现。harness 装载 MROM 不等于已经替 CPU 初始化了 SRAM。

`.log` 是进程诊断文本；`.json` 保存结构化统计；`.commit.csv` 保存提交记录；`.bus.csv` 保存总线事件；`.tx` 是从 UART TX 引脚解码得到的字节。终端上出现文字，并不能单独证明 UART 引脚发送正确。

## 4. CPU 从哪里开始，怎样进入 C 程序

当前 MROM 是 `0x20000000` 起的 4 KiB，SRAM 是 `0x0f000000` 起的 8 KiB。代码在 MROM 执行；可写数据、栈和堆在 SRAM。

下面三个条件配合，才能执行 `_start`：RTL 的复位 PC 为 `0x20000000`；链接器把入口代码放在该地址；harness 把 BIN 起始字节装入对应的 ROM 位置。修改链接脚本中的 `ENTRY`，不会自动改变硬件复位 PC。

启动顺序为：

```text
_start
  → 设置 sp（栈指针）
  → S3 验证用：向整块 SRAM 写入 0xa5a5a5a5
  → 复制 .data：MROM 中的初值 → SRAM 中的变量
  → 清零 .bss：建立零初始化的全局/静态变量
  → _trm_init：配置 UART
  → main：执行测试程序
  → halt：等待 UART 发完，传出退出码，再执行 ebreak
```

这里 `.text` 是代码节，`.data` 是有初值的可写数据节，`.bss` 为零初始化数据预留空间。链接器安排布局；CPU 执行启动指令来完成实际复制和清零。

`_stack_top` 是链接器定义的边界符号，当前数值为 `0x0f002000`。它不是保存栈顶数值的内存变量。`la sp, _stack_top` 使 CPU 把这个边界值放入 `sp`。

`__am_data_copy:` 是汇编标签，给后面的指令位置起名字。双下划线是项目命名约定，不会自动创建函数或代码区域。测试脚本用相邻标签的地址划定一段启动代码。完整解释见 [裸机启动教程](bare-metal-linker-script-and-startup.md) 和 [符号教程](symbols-elf-and-relocation-basics.md)。

## 5. 从需求推导检查：不要只问“是否跑完”

做一个测试，先填写四个问题：**要证明什么？施加什么输入？从哪里观察？与什么预期比较？** 预期有时称为 oracle；实现比较的代码称为 checker。二者可以很简单，不必先搭一个复杂框架。

| 要验证的性质 | 输入或操作 | 观察点 | 预期与局限 |
| --- | --- | --- | --- |
| 指令产生正确的架构状态 | 运行目标程序 | 每条提交后的 PC/GPR/CSR | 与 REF 比较；只覆盖实际执行到的行为 |
| 启动正确建立 C 数据环境 | 先填非零，再执行初始化 | C 程序读取全局变量 | 已知初值或零；不能只靠两机相等 |
| UART 真正发送字节 | `putch` 写 UART | TX 引脚解码得到的 `.tx` | 与 Python 保存的预期字节比较 |
| 非法访存产生预期异常 | 指定异常测试指令 | 提交记录的 PC/cause | 在正确指令位置出现正确原因码 |
| 测试能结束 | 启动 EXE，设置周期上限 | 退出原因和返回码 | 超时算失败；正常结束还须通过其他检查 |

读报告时，必须能把一个 `PASS` 还原成对应的观察值和预期。某一程序退出成功，只说明这些已执行的检查成立，不能自动推广为全部指令、总线时序或中断都已验证。

## 6. poison 与两个负例：具体追一次失败

**poison** 在这里指“先用容易辨认的非零图案填内存”。这样即使仿真的 RAM 原先恰好为零，遗漏初始化也不会被掩盖。当前由 `start.S` 的 CPU store 完成，不是 Python 直接写 SRAM；它是 S3 的验证手段，不是所有裸机启动的必需步骤。

**负例**指故意制造一个已知错误，检查测试是否能发现它。S3 的 `negatives()` 复制正常 BIN，再将指定启动区间内的一条 store 替换为 NOP，生成两个独立镜像；原始源码和正常镜像保持原样。

| 情况 | 初始化后的值 | `memory.c` 的检查 | 结果 |
| --- | --- | --- | --- |
| 正常启动 | `initialized[0] = 0x01234567`，`zeros[0] = 0` | 两者符合预期 | 继续完成测试，最终正常退出 |
| 漏掉 data-copy store | `initialized[0]` 仍为 `0xa5a5a5a5` | 初值不等于 `0x01234567` | 调用 `halt(1)` |
| 漏掉 bss-clear store | data 正常，`zeros[0]` 仍为 `0xa5` | 零初始化检查失败 | 调用 `halt(1)` |

关键的 C 检查来自 `npc/tests/soc-runtime/memory.c`，下列摘录省略了其他变量和测试：

```c
static volatile uint32_t initialized[] = {0x01234567, 0x89abcdef, 0x87654321};
static volatile uint8_t zeros[31];
static void check(int ok) { if (!ok) halt(1); }
/* main 中： */
check(initialized[0] == 0x01234567 /* 还会检查后两个元素 */);
for (unsigned i = 0; i < sizeof zeros; i++) check(zeros[i] == 0);
```

失败如何传到 Python：

```text
C 条件不满足 → check(0) → halt(1)
  → trm.c 将 1 写入 a0（x10），执行 ebreak
  → harness 观察到结束指令及非零 a0
  → 输出 "ebreak with nonzero a0"，仿真进程返回 1
  → Python 核对“非零退出码 + 预期错误文本”
  → 该负例标记 PASS：成功检测到了故意制造的错误
```

这是当前 AM/harness 的退出约定，不是 RISC-V 规定所有 `ebreak` 都必须退出仿真。正常路径也会通过 `halt(main(...))` 结束；上述失败则是自检直接调用 `halt(1)`，没有等到 `main` 返回。

`a0` 是目标 CPU 的寄存器；进程返回码是宿主机操作系统接收的数值；Python 的测试结论是第三层判断。它们通过代码联系起来，不能当成同一个东西。负例只接受预定原因，任意崩溃或超时都不能算通过。

## 7. DiffTest 为什么必要，又为什么不够

**DUT** 是被测设计；**REF** 是参考模型；**commit** 表示一条指令的架构结果提交。CPU 可能用多个周期执行一条指令，REF 不需要模拟相同的流水级和等待周期，只要在比较点给出相同的架构行为。

当前 harness 在提交回调时记录元信息，待 `eval()` 返回后读取更新后的寄存器状态，再让 REF 执行对应步骤并比较。若在寄存器更新之前取样，就可能把 DUT 的旧状态与 REF 的新状态比较，产生假的不一致。

但 DUT 和 REF 也可能**一致地执行了错误的软件**。例如它们都执行“漏掉 bss 清零”的 BIN，并且都读到同样的 `0xa5`。因此还需要 C 程序中独立的“应当为零”预期。

另一个 `diff-negative` 会翻转比较快照中的 x5，预期出现 `DiffTest mismatch GPR[5]`。它验证比较链能发现分歧；两个启动负例验证程序自检能发现初始化错误。这是两类不同检查。

UART/mtime 读值与时刻有关，当前实现会将该次设备读输入同步给 REF。这样仍能检查 load 的架构效果，但不能依靠同一个被同步的值证明外设本身正确；UART TX 和 timer 的定向检查仍然需要保留。

## 8. 读完后对照哪些源码

按问题查位置，不需要从仓库第一行读到最后一行。

| 你要回答的问题 | 文件与定位词 |
| --- | --- |
| 三类产物怎样构建？ | `npc/scripts/soc.mk`：`soc-build`、`soc-ref`、`s3-test` |
| 谁设置参数、检查输出、制造负例？ | `npc/tests/m5_s3_test.py`：`simulate`、`startup_evidence`、`negatives` |
| 谁推进仿真、判断结束、输出 JSON？ | `npc/csrc/soc/main.cpp`：`dut->eval()`、`last_a0`、`summary_path` |
| 谁观察提交、导出内部状态？ | `npc/sim/soc_monitor.sv`：`npc_soc_commit`、`npc_soc_state` |
| 谁装载 REF、比较状态？ | `npc/csrc/soc/difftest.cpp`：`SocDiff::init/step/memory` |
| 谁填充/复制/清零 SRAM？ | `abstract-machine/am/src/riscv/ysyxsoc/start.S`：三个 `__am_` 标签 |
| 哪一条条件判定数据错误？ | `npc/tests/soc-runtime/memory.c`：`check`、`initialized`、`zeros` |
| 退出码怎样进入 a0？ | `abstract-machine/am/src/riscv/ysyxsoc/trm.c`：`halt` |

合上文档后尝试画出第 2、3 节的关系，并口述第 6 节的一次失败。如果能说明“输入是什么、谁执行、哪里观察、预期从哪里来”，就可以回到 S3 实现记录查更细的改动。
