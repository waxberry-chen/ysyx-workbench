# 一生一芯 2306 B 阶段加速讲义

> 对应原讲义 `basic/1.7.md`--`basic/1.11.md`（B1--B5）。本文面向已经完成 C 阶段的学习者，按“可流片系统 -> 量化优化 -> 流水线 -> 代码调试考核”重排内容。总线协议、SoC 地址映射、ISA 语义和 CI 的最终约定，必须以原讲义、官方手册和当前上游仓库为准。

## 1. 阶段目标

B 阶段不是简单地把 C 阶段的单周期 NPC 加速，而是把一个依赖仿真环境的处理器逐步变成可接入真实 SoC、可综合、可验证、可评估的 RISC-V 计算机系统：

```text
C6 单周期 NPC
  -> B1：AXI4-Lite、仲裁、Xbar、RTL 外设
  -> B2：ysyxSoC、MROM/SRAM、Flash/PSRAM/SDRAM、NVBoard
  -> B3：性能模型、计数器、icache、形式化验证、设计空间探索
  -> B4：流水线、冒险、推测执行、转发、分支预测、fence.i
  -> B5：32 位流片接口、静态检查、四值/网表仿真、CI 与代码考核
```

### 阶段出口

- [ ] NPC 通过 AXI4-Lite 访问统一存储器和多个设备，能在随机延迟下运行 RT-Thread。
- [ ] NPC 接入 `ysyxSoC`，能在 MROM/SRAM 及外部存储器上运行程序，并通过 UART/NVBoard 交互。
- [ ] 有可复现的性能基线、性能计数器、瓶颈分析和优化前后数据；至少完成简易 I-cache 与形式化验证。
- [ ] 流水线能处理结构、数据、控制冒险，支持异常和 `fence.i`，并用 microbench、DiffTest、形式化或随机测试验证。
- [ ] 通过 B5 的代码规范、四值仿真、网表仿真和 CI 检查，提交代码调试考核申请。

**[原则] 先完成，后完美。** 先把处理器改造成接口真实、功能完整、可接 SoC 的系统，再用数据决定微结构优化。每一次优化都要先估算收益和代价，再实现、验证和复测。

## 2. 通用工作流

1. **建立基线**：固定程序、输入、时钟/延迟模型、编译选项，记录动态指令数、周期数、IPC、频率和运行时间。
2. **拆接口**：为每个模块写清 request/response、`valid/ready`、地址、数据、掩码、错误响应和状态机。
3. **先功能后性能**：先用 DiffTest、trace、断言和小程序保证功能，再引入随机延迟、cache 或流水化。
4. **从高层到低层调试**：程序输出 -> 指令/函数 trace -> 访存/总线 trace -> 波形 -> 网表波形。
5. **每次变更可回退**：小提交、保持 `tracer-ysyx` 记录、不要提交构建产物；记录假设、证据和结论。

**[必读] AXI 和器件行为必须 RTFM。** 不要依赖未经核验的博客或示例代码推测握手、同时读写 SRAM、UART 初始化和存储器延迟；协议细节错误会在接入 SoC 后变成难以定位的死锁或数据错误。

## 3. B1：总线

对应原讲义：`basic/1.7.md`。

### 3.1 目标与理论

把 C 阶段“通过 DPI-C 直接读写内存”的隐式接口，重构成具有请求、响应、延迟和错误处理的显式总线。重点理解：

- 同步/异步请求、状态机和握手；请求者（master）与响应者（slave）的职责。
- 只读存储器、可读写 SRAM、可变延迟存储器的接口差异。
- `valid/ready` 解耦：只有双方在同一周期有效且就绪时才完成传输。
- Arbiter 负责多个 master 的调度、阻塞和响应归属；Xbar 依据地址译码并转发到不同 slave。
- AXI4-Lite 五通道：读地址 `AR`、读数据 `R`、写地址 `AW`、写数据 `W`、写响应 `B`。每个通道独立握手，不能假设地址和数据同周期到达。

### 3.2 [必做] 从简单总线到 AXI4-Lite

1. 画出 IFU、IDU、LSU、SRAM 的请求和响应状态转移图；用状态机实现一个带延迟的最小总线。
2. 把 IFU 访问的 ROM 改造成 SRAM 接口，评估单周期 NPC 的综合主频和 microbench 执行时间。
3. 把 LSU 访问的存储器改造成可读写 SRAM；明确 load 可能需要读请求、等待响应、写回三个周期或更多周期。
4. 在 RTL 中实现 AXI4-Lite master/slave；IFU 只使用读通道，LSU 使用读写通道。即使当前 SRAM 延迟固定为 1 周期，也必须在两端正确使用握手。
5. 给 SRAM 加固定延迟（5、10、20 周期），再用 LFSR 随机化 slave 响应和 master `valid/ready` 延迟；随机延迟下仍能启动 RT-Thread 才算总线基本可靠。
6. 为 IFU 与 LSU 实现 AXI4-Lite 仲裁器，使两个 master 共享同一个 SRAM。仲裁器要记录当前请求来自哪个 master，并把响应转回原请求者。
7. 实现 Xbar：根据地址把请求路由到 UART、SRAM、CLINT 等 slave；未命中地址返回 `decerr`，不要静默吞掉非法访问。
8. 用 AXI4-Lite 接口实现仿真 UART（写寄存器低 8 位输出字符）和 CLINT（至少提供递增的 `mtime`），再运行 `hello` 与时钟测试。

### 3.3 设计重点

**请求与响应必须解耦。** master 不能假设 slave 立即响应，slave 也不能假设 `AR` 与 `R`、`AW` 与 `W` 同周期发生。握手信号的依赖方向要符合官方规范，避免 `valid` 等待 `ready`、`ready` 又等待 `valid` 造成死锁；也要避免双方周期性撤销信号造成活锁。

**仲裁要保留上下文。** 一次请求被转发后，必须记住 master 编号、读写类型和必要的地址/掩码，直到对应 `R`/`B` 响应完成。当前 IFU/LSU 不会同时发请求时可以使用简单优先级，但接口要为后续并发保留清晰边界。

**不要过早拦截地址。** 可流片 NPC 应尽量把地址请求送到 SoC；不存在的设备由 SoC 通过 AXI `resp` 报错。过早在 CPU 内部过滤地址会阻断未来接入的设备。

### B1 出口

- [ ] AXI4-Lite master/slave、仲裁器、Xbar 均能在随机延迟下工作，无死锁/活锁。
- [ ] 非法地址返回可观察错误；UART、CLINT 至少可被程序访问。
- [ ] 评估了总线改造前后的频率、周期数和运行时间，并保留报告。

## 4. B2：SoC 计算机系统

对应原讲义：`basic/1.8.md`。

### 4.1 目标与拓扑

将 NPC 接入 `ysyxSoC`，把存储器也视为一种设备，通过 Xbar 连接 MROM、SRAM、UART、CLINT、SPI/Flash、PSRAM/SDRAM、GPIO、PS/2、VGA 等。2306 版本后续环境已经转向 32 位数据总线；接入前必须核对当前仓库的地址和位宽定义。

```text
NPC (AXI master)
      |
   Arbiter/Xbar
  |    |     |      |
 MROM SRAM  UART  CLINT/SPI/GPIO/...
```

### 4.2 [必做] 接入与最小 SoC

1. 获取并阅读 `ysyxSoC` README、顶层模块和地址映射；设备地址可能变化，不要把旧讲义数字当作永久规范。
2. 生成 SoC Verilog，接入 NPC，先测试 MROM 取指和输出单个字符 `A`。
3. 为 ysyxSoC 添加 AM 运行时，恢复 DiffTest：将 MROM 内容同步给 NEMU，并检查在 MROM 执行的指令；必要时实现 Access Fault，帮助暴露跑飞访问。
4. 编写 `mem-test`：对所有可写内存区域分别进行 8/16/32/64 位写入和读回校验，避开栈区；不要依赖 `printf()`，防止程序过大或引入额外访存。
5. 通过 bootloader 将数据段从 MROM 的 LMA 复制到 SRAM 的 VMA，使全局变量可写。链接脚本用 `MEMORY`、`>` 和 `AT>` 明确代码/数据的运行地址与加载地址。
6. 实现 UART16550 初始化、发送队列状态轮询和 `putch()`；运行 `hello`，确认长字符串不会丢字符。

### 4.3 [必做] 外部存储器路径

- **Flash/SPI**：理解 Flash 的命令、状态和 SPI 串并转换；实现 bit-reverse 练习、`flash_read(addr)`，把程序从 Flash 加载到 SRAM 后跳转执行；再实现 XIP，用 Flash 直接取指并替代 MROM。
- **PSRAM/QPI**：实现仿真颗粒、SPI/QPI 控制器和访问测试；运行 `microbench`，用 bootloader 将程序加载到 PSRAM，并在 PSRAM 上运行 RT-Thread。
- **SDRAM**：理解行/列/Bank、预充电和刷新；实现仿真模型和控制器，完成完整访问测试，把程序加载到 SDRAM 执行；再将控制器数据位宽扩展到 32 位并完成字扩展。

这些任务的共同验收不是“能读几个字节”，而是：随机地址、不同访问宽度、长延迟、跨边界和连续突发访问均保持数据正确，且程序能从该存储器启动。

### 4.4 [必做] 外设与系统软件

- 更新 NVBoard，在程序中实现流水灯、读取拨码开关和七段数码管显示学号。
- 将 UART TX/RX 接入 NVBoard，运行 RT-Thread 串口命令；处理标准输入输出可能导致的重复字符。
- 接入 PS/2 键盘，验证 RT-Thread 中的按键输入。
- 复习 VGA 时序和帧缓冲，将像素输出到 NVBoard，运行图形程序/游戏。
- 更新 RT-Thread 并运行其他 AM 程序；ChipLink 属于可扩展主题，可在主线完成后学习。

### B2 出口

- [ ] NPC 在 ysyxSoC 中取指、访存和输出正常，DiffTest 可重新工作。
- [ ] `mem-test`、全局变量写入、`hello` 和 RT-Thread 均通过。
- [ ] 至少一条 Flash/PSRAM/SDRAM 路径完成从存储器启动程序的闭环。
- [ ] NVBoard 的 GPIO、UART、键盘或 VGA 外设有可复现测试。

## 5. B3：性能优化和简易缓存

对应原讲义：`basic/1.9.md`。

### 5.1 性能方法

性能不是“感觉更快”，而是：

```text
运行时间 = 动态指令数 × CPI × 每周期时间
         = 动态指令数 × (1 / IPC) × (1 / 频率)
```

优化方向对应减少指令数、提高 IPC、提高频率；三者可能互相牵制，必须记录面积、频率、周期数、IPC 和运行时间。

2306 主线默认使用 `am-kernels` 的 `microbench` `train` 规模：可裸机运行、规模适中，覆盖排序、位操作、解释器、矩阵、素数、A*、网络流、压缩和 MD5 等场景。CoreMark/Dhrystone 是合成程序，不应作为唯一性能依据；红白机则可用 FPS 评价。

### 5.2 [必做] 性能计数器与瓶颈

1. 为 NPC 添加总周期数、提交指令数、IPC，以及 IFU 取指、LSU 返回数据、EXU 完成计算、各类 stall、cache hit/miss 等事件计数器。
2. 通过 trace 或 CSR 读取计数器，固定 benchmark 和配置，记录优化前基线。
3. 用 Amdahl 定律估算局部优化对整体运行时间的上限；没有量化收益的优化不要直接写入 RTL。
4. 用综合后的关键路径估算频率，用 `time = cycles / frequency` 估算硬件执行时间，同时区分 RTL 仿真耗时和实际芯片执行时间。
5. 通过 `yosys-sta` 校准存储器延迟，寻找最高综合频率；每次优化后重新记录性能数据。

**[原则] 先测量再优化。** 性能计数器必须能回答“程序慢在哪里”，而不是只提供一个总时间。对单个 benchmark 有益但会损害其他程序、面积或频率的方案，必须明确其适用范围。

### 5.3 [必做] 简易 I-cache

实现直接映射、块大小 4B、共 16 个 cache block 的 I-cache（首版可用触发器阵列，参数应可配置）：

1. 将地址拆成 `tag/index/offset`；保存 `valid`、`tag` 和数据。
2. 命中时直接返回指令；缺失时通过总线读回块、填入 cache、更新元数据，再响应 IFU。
3. 只缓存适合缓存的存储器地址空间；SRAM 一周期访问通常不值得缓存，设备空间不可盲目缓存。
4. 用 DiffTest 和 microbench 验证功能，统计命中率、缺失代价和 AMAT；至少比较容量、块大小和关联度的收益。

### 5.4 [必做] 形式化验证与设计空间探索

- 用 BMC/SMT 工具描述 cache 的参考行为或不变量，检查任意有限长度访问序列，而不只依赖 Utest。
- 先用较小 bound 快速找反例，再逐步增加 bound；保存反例序列和修复后的回归用例。
- 实现 `cachesim`，对压缩后的访存 trace 做离线 cache 设计空间探索，先估算收益再选择 RTL 参数。
- 评估块大���、容量、缺失处理、突发传输、内存布局和面积限制；不要细抠综合器选项来掩盖架构问题。
- 处理 `fence.i`/自修改代码导致的指令缓存一致性：写入代码后必须使相关 I-cache 行失效或采取等价措施。

### B3 出口

- [ ] 有 microbench 基线、性能事件、IPC/CPI、频率和运行时间记录。
- [ ] I-cache 功能正确，并通过形式化/随机/差分中的至少两类验证。
- [ ] 至少完成一次参数设计空间探索，并能用数据解释最终配置。

## 6. B4：流水线处理器

对应原讲义：`basic/1.10.md`。

### 6.1 理论与基本实现

流水线把 IF、ID、EX、MEM、WB 等阶段重叠执行，目标是提高吞吐而不是降低单条指令延迟。先实现最简单的流水线，再逐个处理：

- **结构冒险**：同一硬件资源被多个阶段争用；复制资源、分时访问或停顿。
- **数据冒险**：RAW/WAR/WAW 等依赖；顺序流水线的核心是 RAW，先用 stall 保证正确，再用 forwarding 减少停顿。
- **控制冒险**：分支/跳转改变 PC；冲刷错误路径、等待解析或进行预测。

### 6.2 [必做] 流水线与异常

1. 为每个流水段定义 `valid` 和数据/控制寄存器；无效指令不应更新架构状态。
2. 用最保守的 stall/flush 实现基本流水线，运行 microbench 验证。
3. 让异常信息和对应 PC 随流水段传递；实现精确异常：`mepc` 必须是发生异常的指令 PC，而不是当前 IFU PC。
4. 推测执行中的异常只有在确认该指令不会被冲刷后才更新 `mepc`、`mcause`、CSR、寄存器或内存。
5. 运行异常测试；传统 `riscv-tests` 只覆盖单条指令，不能证明所有指令序列和冒险组合正确。
6. 使用随机指令序列、DiffTest、断言和形式化验证遍历依赖、分支、访存和异常组合。

### 6.3 [必做] 性能优化顺序

先在性能计数器上量化，再决定是否实现。C 阶段/讲义要求的重点是减少数据冒险停顿；其他方案可根据面积和瓶颈选择：

1. **提升指令供给**：若 I-cache 命中需要多周期，可对 I-cache 访问流水化；先估算其对 IPC 的收益。
2. **数据转发**：从后续流水段把结果旁路到 EX 输入，消除大部分 RAW；load-use 仍可能需要一个 stall。实现前后对比理论收益和实测收益。
3. **控制冒险**：统计分支占比和错误预测代价；实现 `branchsim` 评估静态/动态预测准确率，再选择简单分支预测器、BTB、`jal` 目标预测或返回地址预测。
4. **综合权衡**：把面积资源投入到收益最高的瓶颈；记录频率、IPC、面积和功耗趋势，不以单一 benchmark 取胜为目标。

### 6.4 `fence.i`

设计一个反例：程序修改将要执行的指令，流水线中可能仍有旧指令或旧 I-cache 数据。确认多周期处理器能通过而流水线失败后，实现 `fence.i` 的必要冲刷、等待和 cache 失效逻辑，再用反例回归。

### B4 出口

- [ ] 基本流水线能运行 microbench 和 RT-Thread。
- [ ] 结构/数据/控制冒险均有明确策略；至少实现数据转发并验证 load-use 等边界。
- [ ] 异常为精确异常，推测错误不会污染架构状态。
- [ ] `fence.i` 反例通过；性能计数器显示优化收益与估算基本一致。

## 7. B5：流片准备与代码调试考核

对应原讲义：`basic/1.11.md`。B5 的重点是把“本地能跑”变成“第三方 CI 可拉取、可综合、可复现”。具体流程可能变化，提交前应重新阅读最新版原讲义。

### 7.1 [必做] 流片前 RTL 检查

1. **切换 32 位 ysyxSoC**：更新上游代码；NPC 顶层 AXI 数据位宽改为 32 位并移除旧位宽转换；用新 SoC 重新仿真。
2. **开放地址空间**：NPC 不要提前拦截未来设备地址，所有请求通过 AXI；不存在设备由 SoC 返回错误。
3. **去除下降沿时钟**：统一同步时序，避免后端时序收敛困难；检查所有 `negedge`。
4. **去除锁存器**：综合后检查 `synth_stat.txt`，不得出现 `DLL_X1`、`DLL_X2`、`DLH_X1`、`DLH_X2`。修复不完整组合赋值或不当行为建模。
5. **命名与合并**：生成单个 `ysyx_XXXXXXXX.v`/`.sv`，顶层模块为 `ysyx_XXXXXXXX`；所有模块和 Verilog 宏添加学号前缀。Chisel 可使用 module prefixing，Verilog 需手动处理。
6. **静态检查**：运行 `verilator --lint-only -Wall -Werror`；`DECLFILENAME` 可按讲义抑制，`UNUSED` 必须逐项确认原因后再决定是否忽略。

### 7.2 [必做] 四值仿真与网表仿真

四值仿真用 `X` 检查复位后未初始化状态的传播；不要为了让 Verilator 的二值仿真“看起来正常”而盲目复位所有寄存器。优先复位会影响控制的最小寄存器集合，数据寄存器可由软件或 `valid` 控制初始化。

由于 Icarus 不支持 DPI-C/C++ 驱动，需要提供条件编译仿真环境：去掉 DiffTest/DPI-C、用 Verilog/Chisel 行为模型实现内存、用 `$readmemh()` 装载镜像，并使用 `-g2012`。建议先用 Verilator + DiffTest 排除功能错误，再用 Icarus 找 X 传播问题。

用 Yosys 综合网表和 `yosys-sta/nangate45/sim/cells.v` 标准单元模型，通过 Icarus 仿真 microbench、RT-Thread 等程序；修改 RTL 后重新执行全部检查。

### 7.3 [必做] CI 约定与申请

目录结构至少保持：

```text
ysyx-workbench/
├── abstract-machine/  nemu/  npc/  Makefile
└── patch/
    ├── rt-thread-am/
    └── ysyxSoC/
```

- `abstract-machine`、`nemu`、`npc`、`Makefile` 名称不得改变；`Makefile` 中 `STUID`/`STUNAME` 必须正确。
- 对 `rt-thread-am`、`ysyxSoC` 的修改用 `git format-patch origin/master` 生成补丁，放入对应 `patch/` 目录；不要提交构建产物，补丁总大小不应超过 1MB。
- 公开仓库至少包含通过 CI 的工作分支和 `tracer-ysyx` 分支。
- `make -C npc verilog` 生成 `npc/build/ysyx_XXXXXXXX.v` 或 `.sv`，顶层模块名、PC 复位地址、CLINT 地址符合 CI 约定。
- 常用 CI 目标包括：

  ```bash
  make -C npc verilog
  make -C ysyxSoC dev-init
  make -C ysyxSoC verilog
  make -C npc sim-iverilog IMG=xxx
  make -C npc sim-iverilog-netlist IMG=xxx NETLIST=yyy CELLS=zzz
  ```

- `riscv32e-npc` 程序首地址为 `0x80000000`；接入 SoC 的 `riscv32e-ysyxsoc` 程序首地址为 `0x30000000`。CI 的 Verilator 使用 `stable` 分支，需适配其最新版本。
- CI 不会替你调试波形，也通常不测试 DiffTest；提交前必须在本地充分验证，CI 只作为最终检查，不是调试平台。

通过 CI 后按考核流程创建申请，填写学号、仓库 URL、分支名和提交备注；CI 成功通常会关闭 issue 并生成 `ysyx_学号` 分支，已通过的分支不可随意覆盖。流程或时间要求变化时，以最新版考核指引为准。

## 8. B 阶段调试决策表

| 现象 | 首选检查 | 重点证据 |
| --- | --- | --- |
| AXI 卡死 | `valid/ready` 依赖、通道状态机、响应归属 | 握手时序、最后一个持有请求的模块 |
| 随机延迟下数据错 | 地址/掩码/上下文保存 | 请求 ID、返回数据与 master 映射 |
| SoC 输出乱码/丢字 | UART 初始化、发送队列状态轮询 | UART 寄存器写入和状态位 |
| 全局变量写错 | LMA/VMA、bootloader、链接脚本 | `objdump -h/-t`、复制范围和目标地址 |
| cache 偶发错指令 | valid/tag/index、缺失填充、`fence.i` | cache trace 与内存 trace |
| 流水线结果不一致 | stall/flush/forward、提交顺序 | DiffTest 首个差异指令和流水段 valid |
| 复位后随机失败 | 未复位寄存器、X 传播 | Icarus 四值波形与控制信号 |
| CI 失败 | 目录、目标、生成文件、补丁 | CI 日志、本地复现命令和版本 |

## 9. B 阶段完成清单

- [ ] B1 的 AXI4-Lite、仲裁、Xbar、随机延迟和设备接口均有测试。
- [ ] B2 的 ysyxSoC、内存测试、bootloader、UART 和至少一条外部存储器路径可运行。
- [ ] B3 有性能基线、性能计数器、I-cache、形式化验证和设计空间探索记录。
- [ ] B4 的流水线、冒险处理、转发、异常、预测评估和 `fence.i` 反例均通过。
- [ ] B5 的 32 位 SoC、地址空间、时钟、锁存器、命名、lint、四值仿真和网表仿真均完成。
- [ ] 本地构建可复现，补丁干净，公开仓库和 `tracer-ysyx` 分支准备完毕，CI 申请材料齐全。
