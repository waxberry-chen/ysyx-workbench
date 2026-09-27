# AXI4-Lite 学习：第 4 轮问题

## 本轮主题

理解一笔完整 AXI4-Lite 写事务：`AW` 和 `W` 为什么必须独立握手，slave 何时可以产生 `B` response，以及当前 LSU 的一笔 store 应如何拆分、跟踪并完成。

## 建议阅读范围

- `docs/ref-spec/AMBA AXI and ACE Protocol Specification.pdf`
  - A2.2 Write address channel signals
  - A2.3 Write data channel signals
  - A2.4 Write response channel signals
  - A3.2 Basic read and write transactions
  - A3.3 Relationships between the channels，重点阅读 write transaction dependencies
  - A3.4 Transaction structure，重点阅读 write strobes 和 response structure
- `docs/ref-spec/b-amba-axi4-lite-extract.pdf`
  - B1.1.1 Signal list
  - B1.1.3 Write strobes
  - B1.1.4 Optional signaling
- 当前工程：
  - `npc/vsrc/core/ysyx_lsu.sv`
  - `npc/csrc/memory/ram_model.cpp` 中 `DataRamModel`
  - `docs/notes/post-c/2-axi4-lite/plan.md` 中 LSU adapter 的架构决策

## 问题

### 1. 一笔 AXI4-Lite 写事务由哪些独立 transfer 组成？

请围绕 `AW`、`W` 和 `B` 三个通道回答：

- master 和 slave 分别驱动哪些 `VALID/READY` 与 payload？
- `AWVALID` 和 `WVALID` 是否存在协议规定的先后关系？master 能否等待其中一个通道 ready 后，才在另一个通道发出 valid？
- slave 是否可以分别 backpressure `AW` 和 `W`？它最早在满足什么条件后才能 assert `BVALID`？
- `AW` 已完成而 `W` 尚未完成，或者相反时，master 和 slave 分别需要记住什么？
- `BRESP` 与 `BVALID` 是什么关系？`BVALID && BREADY` 完成后，整笔写事务处于什么状态？
- 对 single-outstanding master，应以哪些事件设置、更新和清除一笔写事务的状态？

#### 我的回答

<!-- ANSWER Q1 BEGIN -->



<!-- ANSWER Q1 END -->

### 2. 分析一笔 W 先完成、AW 后完成且 B 遭遇 backpressure 的写事务

下表表示每个 ACLK 上升沿采样到的值。`A` 是写地址，`D/S` 分别是写数据和 byte strobe。

| 上升沿 | `AWVALID` | `AWREADY` | `AWADDR` | `WVALID` | `WREADY` | `WDATA/WSTRB` | `BVALID` | `BREADY` | `BRESP` |
| --- | ---: | ---: | --- | ---: | ---: | --- | ---: | ---: | --- |
| T0 | 0 | 0 | - | 0 | 0 | - | 0 | 1 | - |
| T1 | 1 | 0 | A | 1 | 1 | D/S | 0 | 1 | - |
| T2 | 1 | 0 | A | 0 | 0 | - | 0 | 1 | - |
| T3 | 1 | 1 | A | 0 | 0 | - | 0 | 1 | - |
| T4 | 0 | 0 | - | 0 | 0 | - | 1 | 0 | `OKAY` |
| T5 | 0 | 0 | - | 0 | 0 | - | 1 | 0 | `OKAY` |
| T6 | 0 | 0 | - | 0 | 0 | - | 1 | 1 | `OKAY` |
| T7 | 0 | 0 | - | 0 | 0 | - | 0 | 1 | - |

请回答：

- `AW`、`W`、`B` 分别在哪个上升沿完成 transfer？
- T1 之后 master 为什么可以撤销 `WVALID`，却必须继续保持 `AWVALID/AWADDR`？
- 从 T1 到 T3，slave 需要保存哪些已经接收的信息？T3 之后它为什么已经具备产生写响应的条件？
- T4～T6 期间由谁保持哪些信号？在 T6 之前，master 能否把这笔 transaction 当作成功完成？
- 如果 T1 的 `WREADY` 也为 0，master 必须保持哪些 payload？
- 将轨迹改成 AW 在 T1 完成、W 在 T3 完成是否合法？状态记录需要怎样对称变化？

最后判断下面两个实现是否合法，并说明原因：

1. master 固定先完成 AW，之后才开始 assert `WVALID`；
2. slave 在 AW 和 W 都完成 transfer 之前就 assert `BVALID`，但保证 `BREADY=0` 时不撤销它。

#### 我的回答

<!-- ANSWER Q2 BEGIN -->



<!-- ANSWER Q2 END -->

### 3. 将一笔 LSU store 映射为 AXI4-Lite 写事务

请结合当前 `ysyx_lsu.sv`、`DataRamModel` 和 adapter 计划回答：

- 当前一次 `dmem_req_valid && dmem_req_ready` 同时交付了哪些 store 信息？adapter 为什么需要在这个边界保存完整 request？
- adapter 接受一笔 store 后，如何用独立状态记录 AW 和 W 的进度？什么条件下可以从发送阶段转入等待 B response？
- 对下面的自然对齐访问，应产生什么 `AWADDR[1:0]`、`WSTRB[3:0]` 和 `WDATA[31:0]` byte-lane 布局？
  - `SB 0xAA -> address 0x8000_0003`
  - `SH 0xBEEF -> address 0x8000_0002`
  - `SW 0x1234_5678 -> address 0x8000_0000`
- C++ AXI slave 分别接收到 AW 和 W 时，为什么不能立即各执行一次写副作用？它应在什么条件下调用一次现有 memory/MMIO write backend？
- `BRESP` 应如何转换成 `dmem_rsp_error`？为什么当前 LSU/store 仍需要等待 local response，不能在 AW/W 完成后直接 commit？
- 如果 `BVALID` 到达时 LSU 暂时不能接受 local response，adapter 可以采用哪些方式处理 `BREADY` 和 response buffer？两种方式各由谁承担 payload holding？

最后用状态名或伪代码描述一个 single-outstanding LSU write adapter 的最小控制流程，不要求写 RTL。

#### 我的回答

<!-- ANSWER Q3 BEGIN -->



<!-- ANSWER Q3 END -->

## 回答方式

请按题号直接在对应的 `ANSWER Qn BEGIN/END` 标记之间作答。可以画简短时序图或引用具体 RTL/C++ 表达式；不确定的判断请明确标出。
