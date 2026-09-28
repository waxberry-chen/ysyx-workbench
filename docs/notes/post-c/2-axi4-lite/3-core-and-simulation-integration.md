# AXI4-Lite 阶段 3：Core 与仿真环境集成

> 完成日期：2026-09-28  
> 基线提交：`52e36ac`（Stage 2）  
> 状态：Stage 3 complete；无阻塞项。

## 1. 阶段结果

本阶段将前两阶段独立验证的 IFU/LSU adapter 接入实际 NPC 执行路径，并把 C++ RAM
model 从自定义 local req/rsp slave 改为 AXI4-Lite slave model：

```text
                         ysyx_core
  +-------------------------------------------------------+
  | IFU -- imem req/rsp -- IFU adapter -- IFU AXI master  | ---> C++ I-AXI slave
  | LSU -- dmem req/rsp -- LSU adapter -- LSU AXI master  | ---> C++ D-AXI slave
  +-------------------------------------------------------+
```

IFU、LSU 的内部职责和 local transaction contract 未改变。AXI channel 状态被限制在
adapter 与外部 slave 中，因此执行单元不需要感知 AW/W 分离、response code 或总线
backpressure 的具体形式。

主要修改文件：

| File | Change |
| --- | --- |
| `npc/vsrc/core/ysyx_core.sv` | 实例化两个 adapter，对外暴露两套 AXI4-Lite master |
| `npc/csrc/memory/ram_model.cpp` | 实现可随机 stall/延迟的 I/D AXI slave model |
| `npc/csrc/sim.cpp` | 仿真周期改为采样 AXI channels |
| `npc/csrc/utils/sim_stats.cpp` | stall 统计从 local channel 迁移到 AXI channel |
| `npc/csrc/include/sim_stats.h` | 更新 cycle observation 输入接口 |

## 2. Core 顶层集成

### 2.1 IFU master

`ysyx_core` 不再向 harness 暴露 `imem_req/imem_rsp`，而是暴露：

```text
ifu_axi_arvalid/arready/araddr/arprot
ifu_axi_rvalid/rready/rdata/rresp
```

local interface 仍是 core 内部 wire：IFU 负责 fetch、redirect 和 stale response；IFU
adapter 负责保持 AXI payload、保存 response 和 single-outstanding 约束。

### 2.2 LSU master

LSU 顶层接口迁移为完整的 AXI4-Lite read/write channels：

```text
lsu_axi_ar* / r*
lsu_axi_aw* / w* / b*
```

LSU 仍只看到一笔 `dmem_req` 和一笔 `dmem_rsp`。adapter 保存完整 local request，将
store 拆成独立 AW/W handshakes，并在收到 B response 后才向 LSU 返回完成。

当前 core 因而有两个外部 master。将它们仲裁为一个 external master 属于后续
`3-axi4-lite-interconnect` milestone，不在本阶段内完成。

## 3. C++ AXI Slave Model

### 3.1 Instruction read slave

instruction slave 使用单 outstanding 状态机：

```text
IDLE --AR fire--> WAIT --latency expires--> RESP --R fire--> IDLE
```

- `ARREADY` 每周期按配置概率独立决定；
- AR handshake 后保存地址并生成 `0..max_latency` 的响应延迟；
- `RVALID/RDATA/RRESP` 在 response handshake 前保持稳定；
- 非 PMEM 取指返回 `SLVERR`，随后由 RTL 转换成 instruction access fault。

### 3.2 Data read slave

data read path同样独立处理 AR 和 R。AXI4-Lite 没有 `ARSIZE`，因此 slave 对对齐地址
读取完整 32-bit bus word；LSU adapter 根据原 effective address 将目标 byte/halfword
右移到低位，最终符号/零扩展仍由 LSU 完成。

### 3.3 Data write slave

AW 和 W 分别保存，不能假设它们同周期或固定顺序到达：

```text
WRITE_COLLECT -- both AW/W captured --> WRITE_WAIT --> WRITE_RESP
```

- `AWREADY` 与 `WREADY` 使用相互独立的随机结果；
- AW-first、W-first 和同周期完成均可工作；
- 只有 AW/W 都完成后，才根据 `WSTRB` 解码 effective address、size 和 write data；
- backend write 只执行一次，B response stall 不会重复 MMIO/PMEM side effect；
- 合法 strobe 为单 byte、自然对齐 halfword 或完整 word；非法 lane pattern 返回
  `SLVERR`；
- `BVALID/BRESP` 在 handshake 前保持稳定。

这一步保留了原 `paddr_try_read/write()` 入口，所以 PMEM、UART、RTC 和 access-fault
处理仍复用现有地址空间实现。UART byte store 由 `WSTRB` 还原为一次精确的 1-byte
MMIO write，而不是对整个 32-bit word 逐 byte 重复调用设备 callback。

### 3.4 随机时序和配置

命令行选项保持兼容：

```text
--ram-seed
--ram-max-latency
--ram-ready-percent
```

同一 seed 可以复现一次运行；IFU 与 LSU 使用不同 seed，AR/AW/W 每周期分别抽取 ready，
R/B 则分别使用 transaction latency。当前参数名称仍沿用 `ram-*`，因为它同时控制 PMEM
和设备背后的仿真 memory system。

## 4. 统计语义迁移

原 stall categories 被保留，但观察点改为外部 AXI channel：

| Existing category | AXI observation |
| --- | --- |
| IF request stall | `ifu ARVALID && !ARREADY` |
| IF response wait/stall | IFU `RREADY&&!RVALID` / `RVALID&&!RREADY` |
| D request stall | LSU AR/AW/W 中任一 valid 被 backpressure |
| D response wait/stall | LSU R/B response wait 或 backpressure |

RAM report 继续输出 instruction/data transaction 数和 error 数，并额外分别输出 LSU
AR/R/AW/W/B stall cycles。由于观察边界已经改变，这些 cycle-level 数值不能与 Stage 0
逐项直接比较；architectural commit trace 才是功能等价依据。

## 5. 验证结果

### 5.1 功能与协议

| Verification | Result |
| --- | --- |
| core lint | PASS；仅有既存 `ysyx_gen_imm.inst[6:0]` warning |
| primitive / IFU / LSU / EXU directed tests | PASS |
| IFU/LSU adapter directed tests | PASS，assertions ON |
| instruction/load/store access fault | PASS，cause 1/5/7 |
| load/store address misaligned | PASS，cause 4/6，零 AXI data request |
| RV32E CPU tests | 排除旧 `unalign` 后 34/34 PASS，DiffTest ON |
| random timing | seeds 1～10，max latency 7，ready 50%，全部 PASS |
| UART hello | 参数与字符输出正确，GOOD TRAP |
| RTC am-test | 连续输出正确日期、时间和秒数 |
| yield-os | 持续交替输出 `AB`，无 DiffTest mismatch/assertion |

### 5.2 Architectural trace

固定 workload 为 `cpu-tests/add`，seed 42、max latency 3、ready 75%。commit 数仍为
1095，architectural fields hash 与 Stage 0 完全一致：

```text
bbf8496edf2329d695eb4437641ced89bba9cf0b6006f1a0b5955c32941e9284
```

这说明 adapter 和 AXI slave 改变了 transaction timing，但没有改变 PC、instruction、
next-PC 或 architectural state sequence。

### 5.3 当前性能样本

| Metric | Stage 0 local interface | Stage 3 registered AXI adapter |
| --- | ---: | ---: |
| committed instructions | 1095 | 1095 |
| cycles | 5121 | 7801 |
| CPI | 4.677 | 7.124 |
| IF request stall cycles | 431 | 467 |
| IF response wait cycles | 1889 | 1952 |
| D request stall cycles | 76 | 105 |
| D response wait cycles | 426 | 444 |

cycles/CPI 增长主要来自全寄存 adapter 在 local request、AXI request、AXI response 和
local response 之间增加的固定转发阶段，而不是 architectural retry 或 transaction
丢失。该结果符合本 milestone “先保证协议正确”的选择；是否实现 fall-through/skid
fast path，应在后续结合综合关键路径再决定。

## 6. 阶段结论与下一步

Stage 3 已完成：实际 NPC 已通过两套 AXI4-Lite master 访问仿真 memory system，旧的
core-top local memory ports 已移除，功能、异常、MMIO 与 DiffTest 均保持正确。

下一步 Stage 4 只需进行正式 sign-off：固化完整回归命令和结果，复核 transaction
计数/trace，并冻结这两套 master interface，作为后续 Arbiter/Xbar 的输入。
