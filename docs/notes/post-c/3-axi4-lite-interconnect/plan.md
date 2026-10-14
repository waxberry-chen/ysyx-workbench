# M3：AXI4-Lite Interconnect 设计与验收计划

> 日期：2026-10-14；状态：S0–S2 已完成，SRAM/UART/CLINT 与系统集成待实施。
> 阅读时 HEAD：`c6dd719`；M2 实现基线：`5b6f29c`。本文不代表重新执行了 M2 验收。  
> 配套：[测试矩阵](test-plan.md)、[开发日志](dev-log.md)、[总路线](../roadmap.md)。

2026-10-14：S0/S1 已完成，基线见 [0-baseline.md](0-baseline.md)，Arbiter 实现与验证见 [1-arbiter.md](1-arbiter.md)，M3 测试状态见 [test-status.csv](test-status.csv)。S2 的 Xbar/default 实现与验证见 [2-xbar.md](2-xbar.md)，当前可进入 S3 SRAM/UART/CLINT；尚未集成 Core。

## 1. 目标、依据与边界

把已验收的 IFU/LSU 两套 AXI4-Lite master 接成最小 B1 系统：

```text
ysyx_core（现有弹性 Core，含 IFU/LSU adapters）
    IFU AR/R ──┐
                ├─ 2-to-1 Arbiter ── 一套 AXI4-Lite master
    LSU 五通道 ┘                         │
                           ysyx_core_axi4lite 边界
                                         │
                                       Xbar
                           ┌─────────┬────┴────┬──────────┐
                          SRAM      UART     CLINT     DECERR
                           └─────────┴─────────┴──────────┘
                                      ysyx_b1_top
```

本阶段保持 local req/rsp、IFQ/opbuf、commit/redirect、精确异常语义；增加总线 RTL、验证及必要的 harness/AM 适配。采用全局 single-outstanding、寄存缓冲和确定性可复现测试。允许吞吐率下降，必须记录代价；不以性能提升作为验收条件。

本阶段不实现 AXI4 burst/ID、多 outstanding、cache、完整 UART16550、串口电气发送器、`mtimecmp`/timer interrupt、ysyxSoC 接入或 PnR。UART 是带字符输出事件的最小 MMIO slave；CLINT 是只读 `mtime` 子集。

依据与优先级：

- 协议依据为仓库内 ARM IHI 0022H，参见 [AXI4-Lite 摘录](../../../ref-spec/b-amba-axi4-lite-extract.pdf)，尤其 B1.1.3 write strobes、B1.1.4 outstanding 限制；完整手册 A3 用于握手依赖关系。
- 2026-10-14 核对了[官方 B1 总线讲义](https://ysyx.oscc.cc/docs/2407/b/1.html)：本阶段覆盖其仲裁、多设备路由、错误返回及最小 UART/CLINT 练习。讲义示意地址不直接作为本工程地址表。
- 输入契约继承 [M2 冻结文档](../2-axi4-lite/0-freeze-baseline.md)与 [M2 sign-off](../2-axi4-lite/4-signoff.md)。下文的仲裁策略、容量和寄存器语义是本项目的 M3 设计选择，并非声称是完整 AXI/CLINT 标准要求。

## 2. 已核对的现状与迁移影响

| 现状与源码 | 对 M3 的约束 |
| --- | --- |
| `npc/vsrc/core/ysyx_core.sv` 对外为 IFU read-only、LSU read/write 两套接口 | 保留该模块作为内部 Core 与 M2 验证对象，新增含 Arbiter 的 `ysyx_core_axi4lite` 作为单 master 对外边界 |
| `npc/vsrc/bus/ysyx_*_axi4lite_adapter.sv` 全寄存、各一笔事务 | 不改 adapter 语义；不能只用真实 adapter 测试覆盖 W-first 请求，因为它通常同时拉起 AWVALID/WVALID |
| LSU adapter 将地址按 4 字节对齐，用 WSTRB/WDATA 表示窄写，读后再移位 | slave 读返回完整 32-bit word；不得在下游推断读 size 或原始 byte offset |
| `npc/csrc/memory/ram_model.cpp` 是两套 C++ AXI slave | M3 系统运行时由 RTL slaves 唯一响应，禁止 C++ 同时驱动或重复执行 MMIO |
| `npc/csrc/include/config.h` 与 AM `riscv/npc/trm.c` 均采用 128 MiB PMEM | 新系统缩小容量时必须同时约束 loader、heap、地址检查与测试，不能只改 RTL decode |
| AM `riscv/npc/timer.c` 先读高位再读低位，C++ timer 在读高位时快照；另有日历寄存器 | RTL mtime 采用实时计数，AM 改为 high-low-high 重试；日历不纳入新硬件 |
| EXU 以地址高 nibble `0xa` 标记 MMIO；DiffTest 先处理异常，再处理 MMIO skip | 保留当前 MMIO 地址可减少无关改动；异常必须仍比较 trap 状态，不得被 MMIO skip 掩盖 |
| `npc/scripts/tests.mk` 固定检查 add 的 IF transaction 数和旧 RAM 日志 | M3 新增统计与验收目标，不能照搬旧事务数；架构 trace 比较与周期/事务计数分开 |
| `rt-thread-am/bsp/abstract-machine/Makefile` 和 AM BSP 已存在 | RT-Thread 有本地接入入口，但未在本次计划工作中验证构建或启动 |

## 3. 信号、事务与 reset 契约

### 3.1 基本接口

- 单时钟 `clk`，低有效 `rst_n`；沿用异步置位复位状态、时钟边沿释放的使用约定。系统所有参与者一起 reset，M3 不支持单独 reset 某个 slave 或时钟域。
- address/data 为 32 bit，`WSTRB[3:0]`，`ARPROT/AWPROT[2:0]`，`RRESP/BRESP[1:0]`；无 ID、LEN、SIZE、LAST。
- IFU 只读，`ARPROT=3'b101`；LSU 数据访问 `ARPROT/AWPROT=3'b001`。Arbiter/Xbar 保留 PROT，不把它重写为常量。
- master 在 VALID 等待 READY 时保持 payload；不得等待 READY 才产生 VALID。内部先收请求、后寄存驱动下游，第一版无 fall-through 组合通路。
- 仲裁器的两个输入分别是 IFU read-only 和 LSU read/write，不承诺通用双 read/write master。LSU 在一笔事务结束前不发起另一笔，也不同时发 read 与 write；独立 TB driver 遵守这个输入契约。

### 3.2 “全局一笔”的精确定义

`ysyx_core_axi4lite` 的总线服务槽从选定 owner/type 开始占用，直到对应 **上游 adapter 的 R/B 握手** 才释放。占用期间不接受任何 master 的另一笔 read/write；read 与 write 不并行。

两个 adapter 可以分别持有一个尚未进入 Arbiter 的请求；adapter 也可能在接收 AXI response 后继续等待 local response 消费。这些不算第二笔 fabric transaction。Arbiter 内部缓存 response 后，下游 Xbar 可以结束其局部事务，但 Arbiter 仍保持服务槽至 adapter 接收。

### 3.3 Arbiter：先预留 owner，再独立接收请求

采用两 master round-robin，reset 后同时竞争时 IFU 优先。每完成一笔上游响应，将下一次竞争优先权交给另一个 master；只有一个请求者时立即服务它。第一版就保证有条件的无饥饿，不采用可能饿死 LSU 的固定 IFU 优先策略。

1. IDLE 根据 `IFU.ARVALID`、`LSU.ARVALID`、`LSU.AWVALID || LSU.WVALID` 选定并寄存 `owner` 与 read/write 类型。本周期不开放输入 READY；下一周期只向选定 owner/type 开放空请求槽的 READY。
2. 预留 owner 后即使尚无握手，也不能重新仲裁。该规则避免请求通道停顿期间切换 master。上游 VALID 保持义务保证请求不会凭空消失。
3. read 独立保存一次 AR payload；write 用独立 AW、W 一项寄存槽，任何一个可先握手，已满槽不再 READY。W-first 时即使还不知道地址，也接受并保存 W。
4. read 收齐 AR 后向下游发送。write 收齐 AW 与 W 后，向下游**分别**驱动 AWVALID/WVALID，各自保持到握手，各自记录 sent 状态。等待收齐不会阻止上游 AW/W 独立握手。
5. R 或 B 进入一项 response buffer，再只向 owner 返回。read 未发送 AR、write 未发送完整 AW/W 时不得接受正常响应；B 必须在下游 AW/W 都握手之后出现。
6. 上游 response 握手后清空 owner/type/槽位并返回 IDLE，下一周期再选请求。无同拍释放并接收下一笔的快路径。

无饥饿保证以 master 最终补齐 AW/W、slave 最终响应、response receiver 最终 READY 为前提。持续请求的 master 在已获服务事务结束后，最多再被另一个 master 服务一笔；无限停顿的外部参与者不在保证范围内，RTL 不靠超时取消 AXI 事务。

### 3.4 Xbar：地址到 target 的归属

- 单输入、四输出（SRAM/UART/CLINT/default）。第一版局部同样只接受一笔 read 或 write。
- 独立模块允许上游同时提出 read/write，但一次只选一种；类型竞争使用轮转，reset 后 read 优先。实际 Arbiter 输出不会同时发两种事务。
- 与 Arbiter 一样先预留类型，再开放请求槽。AR 握手时译码并锁存 read target；AW 握手时译码并锁存 write target。W-first 时只保存 W，`target_valid=0`，不得按旧地址或实时输入转发。
- write 收齐 AW/W 且 target 已知后才向选定 slave 独立发送 AW、W。target 保持到上游 B 握手；read target 保持到上游 R 握手。
- 只允许目标 slave 接收请求，只接收目标 slave 的 response；未选中端口的请求 VALID 与 response READY 为 0。数据/错误码经 response buffer 原样返回。
- 对未映射地址选择 DECERR slave。对已映射但禁止执行的 MMIO、非法寄存器操作，由对应 slave 返回 SLVERR；两者必须在覆盖与日志中区分。

### 3.5 reset 与副作用

reset 清除 owner/type/target valid、AW/W/AR 槽 valid、sent 位和 response valid；reset 期间不握手、不执行设备写事件。数据槽不要求为功能而清零，必须由 valid 屏蔽。

reset 会中止未完成事务，不跨 reset 补发旧响应。已经执行的 SRAM 写或输出字符不能回滚，也不得在 reset 后重放。计数器按 reset epoch 统计中止项，不能把跨 reset 的 request/response 差额直接判成丢事务。SRAM 内容不由 reset 清零；CLINT mtime 清零。testbench 在非采样沿释放 reset，并禁止送回上一个 epoch 的响应。

## 4. B1 地址表与 slave 行为

### 4.1 地址与容量

以下范围均为 **左闭右开**，仅用于本工程 B1 profile，与 ysyxSoC 的最终映射分开。

| Route | 地址范围 | 权限与处理 |
| --- | --- | --- |
| SRAM | `[0x8000_0000, 0x8000_0000 + SRAM_BYTES)` | instruction/data read、data write；默认 `SRAM_BYTES=0x0010_0000`（1 MiB），默认 end 为 `0x8010_0000` |
| CLINT | `[0xa000_0048, 0xa000_0050)` | `+0` mtime low、`+4` mtime high，只读数据访问 |
| UART | `[0xa000_03f8, 0xa000_0400)` | `+0` TX data word；`+4` 保留，访问返回 SLVERR |
| Default | 其余地址 | read/write DECERR，RDATA=0，无副作用 |

约束：SRAM_BYTES 必须为正、4 字节对齐，地址加法不回绕且不重叠 MMIO。decode 用范围比较，不用会产生镜像地址的截断索引。第一版总线侧地址要求 word aligned；对 mapped slave 的非 word-aligned 请求返回 SLVERR，不静默修正。正常窄访问已在 adapter 中对齐，CPU 的自然对齐异常仍由 EXU 处理。

1 MiB 是初始仿真配置，不是已经测得可容纳所有 workload 的结论。集成时检查 ELF 段、stack、heap 与 RT-Thread 实际需求；若不足，显式扩大参数并更新 manifest。禁止越界地址取模。M4 不把 1 MiB RTL array 当作免费 SRAM macro，更不直接综合旧 128 MiB C++ PMEM。

### 4.2 公共 slave 事务规则

slaves 分别保存 AW/W；即使 W 先到也不能丢失或重复使用。第一版一次仅服务一个 read 或 write，输入同时出现时预留一种，已占用后屏蔽另一种。request 完整且合法时仅执行一次 read sample/write effect，生成寄存 response，保持到 response 握手。不以 RREADY/BREADY 决定是否生成响应。

所有错误在副作用前判定：失败 write 不改变内存/设备，失败 read 的 RDATA 固定为 0。不得先写成功，再由注入器把 B 改成错误以模拟“精确 store fault”。协议/scoreboard 错误可以使测试失败；正常软件访问非法地址必须通过 AXI error 返回，不能由 harness abort 代替。

### 4.3 SRAM

- 32-bit word array，同步读，AR 被接受后最早下一周期产生 RVALID。写执行点在 AW/W 都已捕获之后的时钟边沿，执行一次后保持 B。
- 支持全部 16 种 WSTRB：每个置位 bit 独立更新对应 byte，稀疏 strobe 合法；`0000` 在合法地址返回 OKAY、不改数据。不要继承当前 C++ model 只接受连续 lane 的限制。
- 读/写串行；响应未被上游接收时不接受下一笔，因此同一地址 read-after-write 无歧义。
- RTL 存储与 AXI 控制均不调用 DPI。仿真镜像通过仿真层初始化 hook/hex 预装载；初始化是 host 行为，不计入总线 transaction。正常运行只有 AXI 写改变 DUT 内存。
- 对未初始化区不承诺读零；测试读取前先初始化。四值验证不能依赖 Verilator 自动零初值。BSS 的软件初始化/镜像装载责任需在集成时检查。

### 4.4 UART

- TX data word 只写；合法 WSTRB 为 `0001`（发送 WDATA[7:0]）或 `0000`（OKAY no-op）。其他 strobe、读访问、保留 word 访问返回 SLVERR，无字符输出。
- `ARPROT[2]=1` 的取指访问返回 SLVERR，不产生外设副作用。CLINT 同样拒绝 instruction read。SRAM 正常允许取指。
- 写执行时产生一次 `tx_valid` 单周期事件与 `tx_data[7:0]`；M3 sink 约定每周期都能消费，字符打印在仿真层完成。B 回压不得重复触发 tx 事件。
- 这是最小 TX MMIO 功能，不声称具备 UART16550 寄存器、RX、波特率、FIFO 或串行引脚。

### 4.5 CLINT、AM 时间语义

- `mtime[63:0]` 在每个非 reset 上升沿加 1（模 2^64）。AR 握手时采样该边沿更新前的对应半字，随后 RDATA 保持；低、高 word 之间没有隐式快照关联。
- RV32 软件使用 `high1 -> low -> high2`，高位不等则重试，保证跨低位溢出时不会拼出撕裂值。定向测试用 TB 预置计数器到低位将溢出的值，不等待数十亿周期。
- 所有 write 返回 SLVERR，包括 WSTRB=0；这是只读设备权限策略。读无清零等副作用，非法取指返回 SLVERR。
- B1 回归采用固定的名义 `MTIME_HZ=1_000_000`（每周期 1 tick），AM 以该频率换算微秒。这个值是仿真时间配置，**不是综合 Fmax 或 host 仿真速率**。其他频率须在硬件/AM/实验配置中一致记录，采用避免乘法中间值溢出的换算。
- 官方讲义另要求估计仿真速率，使 uptime 接近 host 经过时间；将其作为独立校准实验记录测量窗口和 ticks/s，再通过 AM 时间参数换算。该校准受主机与 tracing 配置影响，不用于确定性性能对比，也不允许改回 host gettimeofday 作为 RTL mtime 数据源。
- B1 AM profile 设 `AM_TIMER_CONFIG.has_rtc=false`；`AM_TIMER_RTC` 返回确定的未提供日历值（字段零、year=1900），不访问原 `RTC_ADDR+8..28`。旧 `am-tests t` 若仍打印 GMT，必须标明是占位值；新增有限次 uptime 检查才是 timer 正确性验收。

## 5. 集成、构建与软件契约

### 5.1 顶层和 profile

计划新增 `ysyx_core_axi4lite`（现有 Core + Arbiter，单 master）和 `ysyx_b1_top`（前者 + Xbar + slaves）。所有 commit/debug 观察端口向仿真层转接。`ysyx_core` 的双 master 作为内部模块和旧 standalone 验证接口保留；roadmap 所说“core 对外只剩一套 master”以新集成边界验收。S1 Arbiter 目前仅 standalone 验证，尚未加入上述 wrapper。

计划增加显式构建参数 `NPC_PLATFORM=legacy|b1`，初期默认 legacy；M3 sign-off 的所有系统入口明确指定 b1。两个 profile 使用不同的 Verilator 输出目录、filelist/top 选择及 AM 编译配置，避免复用旧对象。M2 的 `axi4lite-signoff` 留在 legacy；新 M3 targets 见 [测试计划](test-plan.md)。这些参数/targets 当前尚未实现。

现有 `npc/Makefile` 固定 TOP_MODULE，且 `Vysyx_core` 类型散布在 C++ 中；集成需用小型统一 DUT 类型/访问适配层处理 profile，不逐处堆复制逻辑。若层次变化影响 GPR/CSR DPI scope、monitor 或统计，必须一起迁移并验证。

### 5.2 内存、loader 与 DiffTest

- B1 的 SRAM_BYTES 从同一构建配置传给 RTL、harness 和 AM；AM `PMEM_SIZE/heap.end` 不再固定 128 MiB。link/build 检查 image、BSS、stack 与 heap 起点在容量内，loader 拒绝超大镜像并报告范围。
- AM 参数必须传播到 RT-Thread BSP；profile/容量变化时重编 AM，不能复用旧 `trm.o`。从 `riscv32e-npc` 构建目标进入，不另改 ISA 能力声明。
- loader 向 RTL SRAM 与 NEMU reference 装载同一镜像。C++ pmem 可以留作初始镜像或显式 reference shadow，但不能继续作为 DUT 的实际读写源。调试器读内存应读 DUT SRAM 或经验证一致的 shadow；若暂不支持，应明确报不支持，不能悄悄展示旧 pmem。
- 保留 commit GPR/CSR DiffTest。MMIO 普通提交按既有约定同步 reference；异常优先走 `difftest_raise_intr` 并比较状态。总线 scoreboard 单独验证设备值和副作用，MMIO skip 不证明设备正确。
- 未映射内存、MMIO 取指、只读设备写均补端到端异常测试；软件不会执行成功的 faulting instruction。M3 SRAM 缩小而 reference 仍有更大 PMEM 时，不能靠 reference 自然访存报错验证 DUT 边界，必须检查 DUT bus error 与 trap。
- access-fault 脚本应检查 AXI response/commit cause，不再要求出现 C++ “RAM access error” 文本。无副作用属性由 TB 参考内存/设备事件计数交叉检查。

### 5.3 随机化与统计

模块验证以独立 AXI driver/scoreboard 测试；真实系统以协议正确的仿真 delay shim 在模块边界注入延迟。shim 持有已发布的 VALID/payload，不允许每周期随机门控 VALID 造成撤销；若两侧握手不同步，必须有独立缓冲。随机控制不进入生产 RTL。

统计分层记录 master 接收、route、下游响应、上游完成、reset abort、UART effect。无 reset 且 drain 完成时请求与响应一一对应；软件在 ebreak 立即停机时可能留下 speculative fetch，单独列出 outstanding，不硬套“全部相等”。性能统计截止 commit 停机点，drain 周期不混入执行周期。

保留现有 cycle/commit/stall，新增 IFU/LSU 等待仲裁周期和各 route transaction/error 数。stall 可重叠，不直接相加解释 CPI。选 add、bubble-sort、hello 做确定性时序比较，再做多 seed；同 seed 在旧 C++ 与新 RTL 模型中不是相同延迟序列。

## 6. 实施顺序与每步出口

| 步骤 | 实现内容 | 进入下一步的条件 |
| --- | --- | --- |
| S0 基线（已完成） | 保存 M2 版本、配置、镜像/hash；检查当前接口与本计划；为测试 ID 建立结果清单 | 已明确 legacy/b1 隔离约定并完成 legacy 独立 NPC 构建；最小相关回归通过，profile selector/AM 隔离在 S4 实施 |
| S1 Arbiter（已完成） | owner/type、RR、独立 AW/W 槽、响应返回；独立 driver + scripted slave | T01–T04/T08 的 Arbiter 部分通过；10 seeds × 1000 笔随机事务与 13 个 reset 场景通过，详见 S1 报告 |
| S2 Xbar（已完成） | 地址范围、target holding、default error slave | T05/T06/T08 的 Xbar/default 子集通过；两种容量、10 seeds × 1000 笔及 reset 恢复通过，见 S2 报告；mapped slave 错误待 S3 |
| S3 Slaves | SRAM、UART、CLINT 及仿真输出/初始化边界 | T07/T09/T10 通过，包括全部 WSTRB、计时器 rollover 和 exactly-once |
| S4 系统集成 | 两个 wrapper、filelist、harness、loader、AM profile、DiffTest | 有限 CPU 程序、hello、uptime、yield-os 与异常回归通过 |
| S5 RT-Thread 与 closure | 固定 BSP/workload、随机回归、coverage、波形与性能结果 | 测试矩阵所有必测项有证据，未完成项如实列出，不假称 sign-off |

建议文件落点（开始实现时再创建）：

```text
npc/vsrc/bus/ysyx_axi4lite_arbiter.sv
npc/vsrc/bus/ysyx_axi4lite_xbar.sv
npc/vsrc/bus/ysyx_axi4lite_decerr.sv
npc/vsrc/periph/ysyx_axi4lite_{sram,uart,clint}.sv
npc/vsrc/top/ysyx_core_axi4lite.sv
npc/vsrc/top/ysyx_b1_top.sv
npc/tests/                 # standalone/integration TB、scoreboard、监视器
npc/scripts/tests.mk       # 聚合入口；过长时拆独立 b1 测试 include
```

修改范围还包括 `npc/Makefile`、filelists、`csrc` 的 DUT/内存/统计适配、`abstract-machine/scripts/platform/npc.mk` 与 `am/src/riscv/npc/`；RT-Thread 仅在 BSP/workload 需要时修改，NEMU 原则上沿用现有 reference ABI。

## 7. 验收交付与 M4 衔接

详细需求到 test/assertion/coverage 的映射见 [test-plan.md](test-plan.md)。M3 交付至少包括：

1. 单 master Core 边界及 RTL B1 system，可从干净的源码/明确的上游 BSP 配置复现。
2. directed、random、CPU tests、hello、uptime、yield-os、RT-Thread 和精确异常结果；所有 PASS 附实际命令、版本和范围。
3. lint/SVA 结果、机器可读功能覆盖矩阵、剩余 hole 与 formal 状态；无工具不能写成 proof PASS。
4. IFU/LSU 竞争、W-first write、DECERR 三段代表波形，架构/地址图及至少一个有实际证据的 bug case；没有发现 bug 时不编造案例。
5. 确定性功能/性能基线、原始报告定位与 hash，M3 `signoff.md` 在实际验收时创建；展示入口只链接摘要。

M3 期间可准备 DC/PT 最小 flow；M3 稳定后进入 M4 正式面积/时序基线。优先测 `ysyx_core_axi4lite`，另报告 fabric/slave control；如包含 SRAM 必须说明是触发器阵列还是实际 macro、容量及库模型，禁止漏掉存储后宣称完整 SoC 面积。无 PnR 为 pre-layout；无活动与功耗工具则只报告面积/时序，不声称完整 PPA。

本次发现工作区有未跟踪的 `npc/ref-flow/`，尚未审计其入口、工艺输入与可复用范围。存在目录不等于 flow 已可运行；后续专门处理。M3 不等待服务器 EDA 结果。

## 8. 风险、待验证项与阻塞判定

**目前没有阻塞进入 S3 SRAM/UART/CLINT 的事项。** 下列项目须在对应步骤解决：

| 项目 | 当前状态 | 何时构成阻塞 / 处理方式 |
| --- | --- | --- |
| 1 MiB 容量与 RT-Thread 需求 | 尚未量测，参数可调整 | S4/S5 检查 ELF、stack、heap；不足则显式扩大并重建，不能越界继续运行 |
| RT-Thread BSP 源码与构建配置 | 本地存在，未复测 | S5 若构建输入缺失或 workload 依赖尚未实现的 RX/interrupt，记录具体缺口；先选择本地可实现的无 RX、协作调度 workload，不能以启动 banner 代替验证 |
| timer AM 兼容 | 旧快照/日历契约已识别 | S4 必须迁移 high-low-high、has_rtc 和 profile；不能让旧 AM 成功读到不存在的寄存器 |
| RV32E x16–x31 合规收尾 | 既有遗留，不属互联协议改动 | 保留准确能力声明；不要顺带扩大 ISA 重构范围 |
| formal / 四值 / DC/PT | 本次未探测工具与库 | 属性与仿真先行；M4 相关项标待验，不阻塞无依赖的 RTL 工作 |
| ysyxSoC 窄 MMIO 地址/size | Lite 无法还原原始 read size | M5 单独核对契约；不把 B1 地址图/对齐读语义当成通用 SoC wrapper |

遇到真实阻塞时，开发日志应写明：阻塞哪一步、复现命令和错误、已尝试的处理、需要的最小输入；其他无依赖工作继续推进。
