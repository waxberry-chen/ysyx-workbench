# NPC AXI4-Lite Adapter 改造计划

## 1. 文档用途

本文记录 `1-memory-request` 完成后，NPC 从自定义 instruction/data memory request/response 接口迁移到 AXI4-Lite master 接口的架构决策和任务划分。

本阶段只处理：

- IFU 的 AXI4-Lite read master adapter；
- LSU 的 AXI4-Lite read/write master adapter；
- 两个 adapter 接入 `ysyx_core`；
- 仿真 memory model 和现有回归迁移到 AXI4-Lite。

Arbiter、Xbar、RTL AXI slave/device 和 ysyxSoC 接入属于后续阶段，不在本文范围内。

## 2. 相关文档

- 前序重构计划：[`3-core-microarch-refactor-plan.md`](../1-memory-request/3-core-microarch-refactor-plan.md)
- 当前微架构说明：[`4-current-npc-architecture.md`](../1-memory-request/4-current-npc-architecture.md)
- Post-C 总体路线：[`roadmap.md`](../roadmap.md)
- AXI4-Lite 协议摘录：[`b-amba-axi4-lite-extract.pdf`](../../../ref-spec/b-amba-axi4-lite-extract.pdf)
- AXI 信号与默认值资料：[`docs/ref-spec/`](../../../ref-spec/)
- 重组后的 ysyx B 阶段讲义：[`ysyx2306-b-stage.md`](../../../lectures/ysyx/ysyx2306-b-stage.md)
- 原始 B1 总线讲义：[`basic/1.7.md`](../../../misc/ysyx/docs/2306/basic/1.7.md)
- AXI4-Lite 学习问答：[`docs/notes/learn-axi4-lite/`](../../learn-axi4-lite/)

协议行为以 AXI 手册为准；讲义用于确定工程任务和验收范围。

## 3. 架构决策

### 3.1 保留 IFU/LSU 的 local req/rsp 接口

不把 AXI channel 状态直接写入 IFU 和 LSU，而是在 memory-side 增加两个 adapter：

```text
ysyx_ifu ── imem req/rsp ── ysyx_ifu_axi4lite_adapter ── AR/R

ysyx_lsu ── dmem req/rsp ── ysyx_lsu_axi4lite_adapter ── AR/R/AW/W/B
```

这样可以保持现有职责不变：

- IFU 继续处理 fetch PC、IFQ credit、redirect 和 stale response；
- LSU 继续处理 operation holding、load extension 和 backend response；
- adapter 只负责 local transaction 与 AXI channel 之间的转换。

### 3.2 采用全寄存、single-outstanding 实现

第一版 adapter 以协议正确和易验证为目标：

- IFU、LSU 各最多保留一笔 transaction；
- local request、AXI request 和 local response 均可独立 backpressure；
- AXI payload 在 `VALID && !READY` 时保持不变；
- AXI response 先进入 adapter buffer，再交给 IFU/LSU；
- 接受 adapter 引入的固定周期，暂不实现 fall-through/skid fast path。

### 3.3 IFU adapter

IFU adapter 只实现 `AR/R`：

```text
IDLE -> SEND_AR -> WAIT_R -> HOLD_RSP -> IDLE
```

- 接受 `imem_req` 后保存地址；
- 保持 `ARVALID/ARADDR/ARPROT` 直到 AR handshake；
- 接收并保存 `RDATA/RRESP`；
- 将 `RRESP != OKAY` 转换为 `imem_rsp_error`；
- redirect 不取消已经接受的 AXI transaction，旧 response 仍由 IFU 的 `DROP` 语义丢弃。

### 3.4 LSU adapter

LSU read path 与 IFU 类似。write path 必须独立处理 AW 和 W：

- 接受 `dmem_req` 后保存 direction、address、size 和 write data；
- 用独立的 `aw_pending`、`w_pending` 记录 AW/W 完成情况；
- 正确处理 AW 先完成、W 先完成和同周期完成；
- AW/W 都完成后等待 B response；
- 将 `RRESP/BRESP != OKAY` 转换为 `dmem_rsp_error`；
- 一笔 accepted store 只产生一笔 AXI write transaction 和一次 local response。

### 3.5 窄访问和错误

第一版只接受自然对齐访问，不拆分跨边界 transaction。byte 任意对齐，halfword
要求 `addr[0] == 0`，word 要求 `addr[1:0] == 0`。不满足时由 EXU 在
发出 local/AXI request 前产生精确异常：

```text
load address misaligned  -> mcause = 4
store address misaligned -> mcause = 6
```

异常指令不产生正常 architectural side effect，也不得发出 AXI transaction。
对合法窄访问，adapter 使用对齐后的总线地址和 byte lane：

```text
bus_addr = {req_addr[31:2], 2'b00}
WSTRB    = base_strobe << req_addr[1:0]
WDATA    = req_wdata << (8 * req_addr[1:0])
rsp_data = RDATA >> (8 * req_addr[1:0])
```

load 的 sign/zero extension 仍由 LSU 完成。adapter 中的 alignment assertion 用于检查
core-side contract，不负责替代 architectural exception。

AXI response 统一映射为：

```text
OKAY                  -> rsp_error = 0
EXOKAY/SLVERR/DECERR  -> rsp_error = 1
```

随后沿用现有精确 instruction/load/store access fault 路径。

### 3.6 接口属性和阶段边界

接口使用 32-bit address、32-bit data：

```text
IFU  ARPROT = 3'b101  // privileged, secure, instruction
LSU  ARPROT = 3'b001  // privileged, secure, data
LSU  AWPROT = 3'b001  // privileged, secure, data
```

Milestone 2 完成后，`ysyx_core` 暂时暴露 IFU、LSU 两套 AXI4-Lite master。后续 `3-axi4-lite-interconnect` 再将它们合并为一套 external master。

adapter 模块内部的 AXI 端统一命名为 `m_axi_*`，`ysyx_core` 顶层分别使用
`ifu_axi_*`、`lsu_axi_*`。完整信号、位宽、reset 和 local transaction 契约冻结在
[`0-freeze-baseline.md`](0-freeze-baseline.md)。

本阶段不实现 burst、AXI ID、多 outstanding、cache、Arbiter 或 Xbar。

## 4. 阶段划分

### 阶段 0：冻结基线和接口

- 保存 Phase 3 的功能回归、commit trace 和 cycles/CPI 基线；
- 冻结 adapter local side、AXI side 的信号、位宽和命名；
- 明确自然对齐、byte lane、response error 和 reset 约定。

完成状态（2026-09-28）：已复现 Phase 3 功能、trace 和 CPI 基线，并冻结 local/AXI
接口契约；详见 [`0-freeze-baseline.md`](0-freeze-baseline.md)。

### 阶段 1：IFU AXI4-Lite adapter

- 实现 `ysyx_ifu_axi4lite_adapter`；
- 增加 adapter standalone directed test，覆盖 AR stall、延迟 R、response backpressure 和错误 response；
- 增加 `IFU + adapter + scripted AXI read slave` 的小型 SystemVerilog integration test；
- 覆盖 redirect 发生在 AR handshake 前、AR handshake 后等待 R，以及 R response 同拍到达三种情况；
- 检查旧 AXI transaction 仍正常完成、旧 response 不进入 IFQ，随后从 redirect target 重新取指；

完成状态（2026-09-28）：全寄存 single-outstanding adapter、standalone directed test
和 `IFU + adapter` integration test 均已完成；协议 corner cases、既有回归和 Phase 3
architectural baseline 均通过，详见
[`1-ifu-axi4-lite-adapter.md`](1-ifu-axi4-lite-adapter.md)。adapter 尚未接入
`ysyx_core` 顶层，这是阶段 3 的集成任务。

### 阶段 2：LSU AXI4-Lite adapter

- 先在 EXU 完成 load/store address-misaligned 精确异常及定向测试，确保非法访问不进入 LSU/AXI；
- 实现 read path 和 AW/W independent write path；
- 实现 `WSTRB/WDATA` packing 和 `RDATA` normalization；
- 增加 standalone directed test；
- 覆盖 AW-first、W-first、窄访问、错误 response 和重复副作用检查。

完成状态（2026-09-28）：EXU 已实现 load/store address-misaligned 精确异常，端到端
测试确认 `mcause=4/6`、`mepc`、DiffTest 和零 D-RAM request；全寄存 LSU adapter
及 standalone directed test 已完成，覆盖 read、AW/W independence、B response、byte
lane、错误传播、backpressure、reset 和 transaction 去重。验证记录见
[`2-lsu-axi4-lite-adapter.md`](2-lsu-axi4-lite-adapter.md)。adapter 尚未接入
`ysyx_core`，留待阶段 3 统一集成。

### 阶段 3：Core 与仿真环境集成

- 在 `ysyx_core` 内连接 IFU/LSU local 接口和两个 adapter；
- 顶层改为暴露两套 AXI4-Lite master；
- 将现有 C++ instruction/data memory model 改为 AXI4-Lite slave model；
- 分别随机化 AR、R、AW、W、B channel timing；
- 保持现有 memory model 初始化、统计和错误注入入口。

### 阶段 4：回归与阶段验收

- adapter directed tests 和 protocol assertions 通过；
- lint、现有 IFU/LSU/EXU tests 通过；
- fetch/load/store access-fault tests 通过；
- 除旧 `unalign` 成功访问 case 外的 34 项 CPU tests、固定 seed 随机 stall、hello 和 yield-os/DiffTest 通过；
- load/store address-misaligned 定向测试通过，检查 `mcause=4/6`、`mepc`、无 AXI request 和无正常写回；
- commit trace architectural fields 与 Phase 3 一致；
- 记录 adapter 引入的 cycles/CPI/stall 变化；
- 冻结两套 master 接口，作为后续 Arbiter 的输入。

## 5. Optional：降低 adapter 固定延迟

全寄存 adapter 的无 stall 路径预计为：

```text
local request -> AXI request -> AXI response -> local response
```

request 和 response 两侧各增加一次寄存转发，预计相对直接连接固定增加约 2 cycles。基础版本验收后，可在接口和 single-outstanding 语义不变的前提下分步优化。

### 5.1 Request fall-through/skid

- adapter 空闲时，由 local request 直接驱动 AXI request；
- AXI ready 时，local 与 AXI request 可同周期 handshake；
- AXI stall 时，在 skid entry 中保存 local payload，并继续保持 AXI `VALID`；
- LSU write 需要分别记录 AW、W 是否已经完成，只保存尚未完成的 channel 状态。

完成后可消除 request 方向的 1 cycle 固定转发延迟。

### 5.2 Response fall-through/skid

- response buffer 为空时，AXI response 可直接传给 IFU/LSU；
- local ready 时，AXI response 和 local response 可同周期 handshake；
- local stall 时，adapter 接收并保存 AXI response，随后保持 local response payload。

完成后可消除 response 方向的 1 cycle 固定转发延迟。

### 5.3 优化约束与验收

- 可以只优化 request 或 response，将固定额外延迟从约 2 cycles 降到约 1 cycle；两侧都优化后目标为 0 cycle；
- 不允许 `VALID` 依赖对端 `READY`，也不能在 adapter、Arbiter 和 slave 之间形成组合环；
- stall 时的 payload holding、AW/W independence、错误传播和 single-outstanding 规则保持不变；
- 全寄存版本的 directed tests、随机 backpressure 和系统回归必须继续通过；
- 比较优化前后的 cycles/CPI、关键组合路径和综合频率，再决定是否保留 fast path。

## 6. 预计文件

新增：

```text
npc/vsrc/bus/ysyx_ifu_axi4lite_adapter.sv
npc/vsrc/bus/ysyx_lsu_axi4lite_adapter.sv
npc/tests/ysyx_ifu_axi4lite_adapter_tb.sv
npc/tests/ysyx_ifu_axi4lite_adapter_integ_tb.sv
npc/tests/ysyx_lsu_axi4lite_adapter_tb.sv
```

主要修改：

```text
npc/vsrc/core/ysyx_core.sv
npc/filelist.f
npc/scripts/tests.mk
npc/csrc/memory/ram_model.cpp
npc/csrc/sim.cpp
npc/csrc/utils/sim_stats.cpp
```
