# M3 S3：SRAM、UART 与 CLINT

> 2026-10-14；状态：**S3 PASS，可进入 S4 系统集成**。
> 运行起点：`6fb1750`，初始工作区干净；本轮实现尚未提交，精确源码与日志见 [s3-manifest.json](s3-manifest.json)。

## 1. 实现与接口边界

新增三个 RTL slave 及公共 [ysyx_axi4lite_slave_frontend.sv](../../../../npc/vsrc/bus/ysyx_axi4lite_slave_frontend.sv)。AXI 位宽、地址图和 reset 约定沿用 [plan.md](plan.md)，未改变 Arbiter/Xbar 或 production Core 接口。

公共 frontend 负责先预留 read/write 类型、独立接收 AW/W、寄存响应和占槽；竞争时采用事务粒度 RR，reset 后 read 优先。后端设备只负责读数据、权限判断和写副作用。这样三个设备不会分别维护容易分歧的 AW/W 与反压逻辑。

```text
IDLE -> COLLECT_R -> RESP_R -> IDLE
     -> COLLECT_W -> EXEC_W -> RESP_W -> IDLE
```

- `rd_en` 在 AR 握手时有效；frontend 在该边沿采样设备的 `rd_data/rd_resp`。读响应从边沿后出现，并保持到 R 握手。
- AW/W 各自保存，收齐后进入 EXEC_W；下一个边沿执行写、采样 BRESP，然后进入 RESP_W。写执行与 BREADY 无关，每笔至多执行一次。
- 这是一种固定时序的内部后端接口，没有独立的后端 READY 或可变延迟 response。未来接入有不同延迟契约的 SRAM macro 时，需要重新核对读时序和缓冲，不能直接假设兼容。
- reset 关闭 AXI 控制和写执行信号，清空事务状态；内存内容不清零，mtime 清零，UART 不重放已输出字符。

本轮补充明确本项目的权限规则：**三个 mapped slave 对 `AWPROT[2]=1` 的写返回 SLVERR，包括零 strobe；`PROT[1:0]` 不构成权限隔离。** 这是本项目仅支持 data write 的策略，不是 AXI 通用要求。正常 LSU 的 AWPROT=001，IFU 无写端口，故不改变现有 Core 请求行为；独立 driver 会覆盖全部 PROT 值。

### SRAM

[ysyx_axi4lite_sram.sv](../../../../npc/vsrc/periph/ysyx_axi4lite_sram.sv) 使用 32-bit word array，默认 1 MiB。先检查完整地址范围、word alignment 和写权限，再使用相对 word 索引。结束地址用 33-bit 计算，拒绝零容量、未对齐容量、溢出及 MMIO 重叠；非法配置只 elaboration 一项占位 array，以便启动时明确报告参数错误。

SRAM 支持全部 16 个 WSTRB，每个 bit 独立更新一个 byte；稀疏 mask 合法，合法地址上的 `0000` 返回 OKAY 且不改内容。允许 instruction/data read，错误读返回 SLVERR/RDATA=0。frontend 的读响应寄存器形成同步 AXI 读行为，读写串行，无 read-after-write 歧义。

内存没有 reset 清零或隐式初始化。`mem` 的 Verilator `public_flat_rw` 注解提供仿真预装载/调试访问边界；本轮 TB 只在初次 reset 保持期间装入确定的字节模式，之后正常写全部经过 AXI，其他 reset 保留内容。读取 DUT array 仅用于最终内容比对。RTL 没有 DPI 调用，也没有依赖 Verilator 自动零初值来验证未初始化区。

该注解不是硬件端口、SRAM macro 或通用镜像 loader。S4 仍须实现受容量检查的镜像装载、reference 同步和 debugger 访问适配；在 reset 外通过 host 修改内存不属于正常运行契约。

### UART

[ysyx_axi4lite_uart.sv](../../../../npc/vsrc/periph/ysyx_axi4lite_uart.sv) 仅实现 `0xa00003f8` 的 TX data word：data write 的 WSTRB=1 发送 WDATA[7:0]，WSTRB=0 为 OKAY no-op。其他 strobe、保留地址、未对齐地址、取指标记写以及所有 read 返回 SLVERR，无输出事件。

执行写时寄存一个周期的 `tx_valid` 和 `tx_data[7:0]`。仿真 sink 必须每周期都能消费；本轮 TB 收集字节并检查完整 `I-love-ysyx\n` 输出流。B 长时间被回压不重复输出，reset 不撤销已观察到的事件，也不重放。生产 harness 的字符打印将在 S4 接入；这里不声称实现了 UART16550、RX 或串口电气时序。

### CLINT

[ysyx_axi4lite_clint.sv](../../../../npc/vsrc/periph/ysyx_axi4lite_clint.sv) 维护 64-bit mtime：每个非 reset 上升沿加 1，按 2^64 回绕。`0xa0000048/4c` 的 data read 分别返回低/高 word，在 AR 握手边沿采样 **更新前** 的值。R 被反压时只保持响应寄存器，mtime 继续增长。

所有 write、instruction read、非法偏移及未对齐访问返回 SLVERR，错误读数据为零；没有隐式 high/low 快照，也没有 mtimecmp/interrupt。TB 仅为 rollover 实验预置 `mtime_q`，生产 RTL 没有预置端口且 reset 值固定为 0。AM 的 high-low-high 重试和名义 MTIME_HZ 换算在 S4 迁移，本轮只验证等价的独立总线读序列。

## 2. 验证环境与结果

[axi4lite_slaves_test_top.sv](../../../../npc/tests/axi4lite_slaves_test_top.sv) 直接实例化三个设备；TB 仅在无在途事务时切换被测端口。[axi4lite_slaves_tb.cpp](../../../../npc/tests/axi4lite_slaves_tb.cpp) 使用独立 read/write 队列、实际握手记录、字节级参考内存和独立时钟计数参考，不读取 frontend 的 state/槽位作为预期。

输入握手后主动改变 payload，检测遗漏锁存。R/B 每周期与预期比较，UART 每周期检查事件是否应当发生。随机批次和 reset 后扫描全部 SRAM 内容，查找错误写、地址别名和未选 byte 被修改；reset 用例使用与旧内容不同的写数据，防止“错误写了相同值”掩盖问题。直接观察内部存储/counter 用于结果核对或受控初始化，不用 DUT 数据生成参考值。

| 检查 | 实测结果 |
| --- | --- |
| 配置 | 1 MiB、12 KiB、最小 4 B 均完整运行；包含非 2 的幂次容量及首/末 word 重合的边界 |
| SRAM byte mask | 全部 16 个 strobe × 首/末 word 共 32 个必测 bin；写后 AXI 取指读回，全部通过 |
| 地址与 PROT | 16 个设备地址场景 × read/write × 全部 8 个 PROT；写另外覆盖 strobe 0/1/15，共 512 笔；错误读数据为零、错误写无副作用 |
| AW/W 与反压 | 三设备分别覆盖 AW-first/same/W-first；gap/response hold 0/1/7/64，另测 257 周期长停顿；各自持续 read/write 竞争通过 |
| UART | 合法 lane0 每笔一个正确字节、zero strobe 无事件、其他操作 SLVERR；完整字符串、B hold、reset 前后无重复输出 |
| CLINT | 每个时钟与独立 64-bit 参考比较；AR 边沿采样、response holding、低位 rollover、64-bit wrap、reset 通过 |
| high-low-high | 预置低位接近溢出，实测 **1 次重试**，成功结果等于 low 采样时的完整 64-bit 值 |
| reset | 每个设备 8 个阶段，共 24 场景；每次之后执行新读写并核对 SRAM 保留与 mtime 新 epoch |
| 随机 | 每种容量 seeds 1–10 × 3 slaves × 每 slave 1000 笔，共 **30000 笔/容量**完成，所有 assertion/scoreboard 通过 |
| 总记账（每种容量） | **32125 accepted = 32107 completed + 18 reset-aborted**，无剩余 outstanding |
| 事件（每种容量） | 93 个已观察 UART 字节；2442 笔成功且非零 strobe 的 SRAM 写，包含 reset 前已执行但未消费响应的事务 |
| 功能覆盖 | 每种容量 436 个有命中的 bin；strobe、order、mask/boundary、reset、response hold 和竞争必测项自动检查 |
| 配置守卫 | 4 B、12 KiB 启动通过；0、6 B、MMIO 重叠、地址溢出四个负例以指定诊断拒绝 |
| 静态检查 | strict SVA lint PASS，仅沿用 `SYNCASYNCNET` 定向豁免；`-DSYNTHESIS` 分支 lint PASS，无告警 |
| S2 兼容 | `b1-xbar-test`（含 DECERR 独立测试）PASS，保留 S2 的 10488/10446/42 与 215 bins；default 为 328/317/11 与 65 bins |

8 个 reset 阶段：idle、read 已预留未握手、AW-only、W-only、AW/W 已收齐但尚未执行、写已执行/响应刚出现、读刚采样/响应已产生、B 已被回压 7 周期。由于 AR 接受边沿直接产生寄存 R，frontend 没有另一个“AR 已缓冲而未采样”的状态。前两项没有 accepted 事务，因此每设备中止 6 笔。

公共 SVA 的 A01/A03/A04/A07 对应响应 holding、写必须收齐、单类型/响应占槽、执行脉冲不连续重复；UART 的 A09 检查事件与成功写的等价关系及 byte payload。A06/A07/A08/A10 的设备错误、byte mask、reset epoch 和 timer 由外部参考 scoreboard 补充核对。436 个 bin 不是代码覆盖率，也不是完整 M3 master × route × device cross closure；没有运行 formal 或四值仿真。

## 3. 复现、问题与归档

```bash
make -C npc b1-slaves-test b1-slaves-config-test

make -C npc b1-slaves-test B1_TEST_SRAM_BYTES=12288 \
  OBJ_DIR=/home/cym/prj/ysyx-workbench/npc/build/s3-cap12k

make -C npc b1-slaves-test B1_TEST_SRAM_BYTES=4 \
  OBJ_DIR=/home/cym/prj/ysyx-workbench/npc/build/s3-min

make -C npc b1-xbar-test

verilator --lint-only --sv -Wall -DSYNTHESIS \
  --top-module axi4lite_slaves_test_top \
  npc/vsrc/bus/ysyx_axi4lite_slave_frontend.sv \
  npc/vsrc/periph/ysyx_axi4lite_sram.sv \
  npc/vsrc/periph/ysyx_axi4lite_uart.sv \
  npc/vsrc/periph/ysyx_axi4lite_clint.sv \
  npc/tests/axi4lite_slaves_test_top.sv
```

CSV 输出到 `OBJ_DIR/b1-slaves-test/coverage.csv`；[参数检查脚本](../../../../npc/tests/axi4lite_slaves_config_test.py) 输出 `OBJ_DIR/b1-slaves-config-test/results.csv`，只有指定参数错误的 abort 才算负例成功。工具为 Verilator 5.008、G++ 11.4.0、GNU Make 4.3。

首次编译因 ccache 沙箱写权限失败，获准沙箱外执行后通过。首轮功能测试即通过；后续补强非法地址零 strobe、reset 写数据区分和 4 B 容量边界覆盖。最终未观察到 RTL 功能 mismatch 或新增编译告警，不虚构 bug case。

源码副本、工具版本、命令、失败/最终日志、coverage CSV、参数报告和测试程序保存在 build 外的 `artifacts/m3-s3-20261014.tar.gz`。源码及压缩包 hash 见 [s3-manifest.json](s3-manifest.json)，目前只有本地归档。

## 4. 当前边界与下一步

S3 完成 T07/T09/T10 的设备模块子集及相关 T01/T03/T04/T06/T08 检查。SRAM byte mask 已验证，但 adapter 与真实设备组合的 lb/lbu/lh/lhu/lw/sb/sh/sw、AM uptime 单调/单位换算、系统异常与完整 fabric 仍待集成。CPU/DiffTest 未重跑：production filelist、Core、harness、AM 和 NEMU 均未改动，运行软件的 NPC 仍是 legacy 路径。

本轮没有实际综合/STA；RTL array 未映射 SRAM macro，仿真容量和名义 timer 频率不代表面积或 Fmax。S3 模块通过不等于完整 SoC 或 M3 sign-off。

**当前无未解决阻塞。下一步 S4：Core/Arbiter 与 B1 wrapper、独立 profile/filelist、loader/输出 sink、AM timer/容量适配及 DiffTest 系统回归。** 相关面试问答见 [qa/README.md](qa/README.md)。
