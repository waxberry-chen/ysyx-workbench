# AXI4-Lite 学习：第 3 轮问题

## 本轮主题

理解一笔完整 AXI4-Lite 读事务：读地址如何被接受、读数据和响应何时返回、两个通道如何分别 backpressure，以及 single-outstanding 的当前 IFU/LSU 应如何与 `AR/R` 对接。

## 建议阅读范围

- `docs/ref-spec/AMBA AXI and ACE Protocol Specification.pdf`
  - A3.2.2 Channel signaling requirements 中的 Read address channel 和 Read data channel
  - A3.3 Relationships between the channels
  - A3.3.1 Read transaction dependencies
  - A3.4.5 Read and write response structure
- `docs/ref-spec/b-amba-axi4-lite-extract.pdf`
  - B1.1.1 Signal list
  - B1.1.4 Optional signaling
- 当前工程：
  - `npc/vsrc/core/ysyx_ifu.sv`
  - `npc/vsrc/core/ysyx_lsu.sv`
  - `npc/csrc/memory/ram_model.cpp` 中 `InstructionRamModel` 和 `DataRamModel` 的 request/response 状态迁移

## 问题

### 1. 一笔 AXI4-Lite 读事务从何时开始，到何时完成？

请围绕 `AR` 和 `R` 两个通道回答：

- master 和 slave 在两个通道上分别驱动哪些 `VALID/READY` 和 payload？
- `ARVALID`、`ARREADY`、`RVALID`、`RREADY` 之间有哪些必须遵守的依赖关系？哪些信号允许等待另一个信号，哪些不允许？
- `ARVALID && ARREADY` 发生后，master 是否还需要保持 `ARVALID/ARADDR`，直到读数据返回？
- 应当以哪个握手作为“读请求已经被接受”的边界，以哪个握手作为“整笔读事务已经完成”的边界？在这两个边界之间，这笔事务处于什么状态？
- AXI4-Lite 的 `RRESP[1:0]` 有哪些可用结果？`RRESP` 与 `RDATA` 是分别握手，还是作为同一 `R` channel payload 一起传输？

#### 我的回答

<!-- ANSWER Q1 BEGIN -->

在这里作答。

<!-- ANSWER Q1 END -->

### 2. 分析一笔带有地址 stall 和数据 backpressure 的读事务

下表表示每个 ACLK 上升沿采样到的值。假设当前 master 采用 single-outstanding 策略，`A` 是读地址，`D` 是该地址的返回数据。

| 上升沿 | `ARVALID` | `ARREADY` | `ARADDR` | `RVALID` | `RREADY` | `RDATA` | `RRESP` |
| --- | ---: | ---: | --- | ---: | ---: | --- | --- |
| T0 | 0 | 0 | - | 0 | 0 | - | - |
| T1 | 1 | 0 | A | 0 | 1 | - | - |
| T2 | 1 | 1 | A | 0 | 1 | - | - |
| T3 | 0 | 0 | - | 0 | 0 | - | - |
| T4 | 0 | 0 | - | 1 | 0 | D | `OKAY` |
| T5 | 0 | 0 | - | 1 | 0 | D | `OKAY` |
| T6 | 0 | 0 | - | 1 | 1 | D | `OKAY` |
| T7 | 0 | 0 | - | 0 | 1 | - | - |

请回答：

- `AR` 和 `R` 分别在哪个上升沿完成 transfer？
- master 应当从哪个上升沿开始记录存在 outstanding read，又能在哪个上升沿清除它？
- T1～T2 和 T4～T6 期间分别由哪一方保持哪些信号？
- T3 时 `RREADY=0` 是否有问题？T4 时 slave 能否因为看到 `RREADY=0` 而不拉高 `RVALID`？
- 如果去掉“当前 master 为 single-outstanding”这一实现限制，协议是否允许 master 在 T3 再发出另一个 `AR` 请求？如果允许，AXI4-Lite 没有 ID 会对响应顺序提出什么要求？

再判断下面两个设计是否合法，并说明它们组合在一起可能产生什么结果：

1. master 只有观察到 `RVALID=1` 后，才在后续周期拉高 `RREADY`；
2. slave 只有观察到 `RREADY=1` 后，才在后续周期拉高 `RVALID`。

#### 我的回答

<!-- ANSWER Q2 BEGIN -->

在这里作答。

<!-- ANSWER Q2 END -->

### 3. 将 `AR/R` 事务映射到当前 IFU 和 LSU

请结合 RTL 和 C++ RAM model 回答：

- IFU 的 `REQ/WAIT/DROP` 分别对应读事务的什么阶段？从 `req_fire` 到 `rsp_fire` 之间，为什么它属于 single-outstanding？
- IFU 在正常 `WAIT` 状态下为什么通常能立即接受 response？`ifq_in_ready`、请求时预留的队列空间和 `imem_rsp_ready` 之间是什么关系？
- 如果 redirect 发生在地址请求已被接受、但读响应尚未返回时，为什么不能取消这笔 AXI 读事务？IFU 应如何处理旧 `RDATA/RRESP`，又应在什么时候发出新 PC 的读地址？
- 对一次 LSU load，当前 `dmem_req_*` 和 `dmem_rsp_*` 应分别转换为哪些 `AR/R` 信号？`RRESP` 应如何转换成当前单 bit 的 `dmem_rsp_error`？
- AXI slave 已经完成 `RVALID && RREADY` 后，为什么 LSU 仍可能处于 `RESP` 状态？请区分 AXI 读事务完成与 EXU 接受 `lsu_rsp_*` 结果这两个边界。
- 当前 C++ RAM model 在进入 `RESP` 后如何处理 response backpressure？它的行为是否符合 AXI 对 R channel source 的保持义务？

最后给出你的初步设计选择：如果保留当前 IFU/LSU 接口并在外面增加一个 single-outstanding AXI4-Lite adapter，这个 adapter 至少需要保存哪些状态或 payload，才能分别承受 `ARREADY` 和 `RREADY` 带来的 stall？此处不要求写 RTL。

#### 我的回答

<!-- ANSWER Q3 BEGIN -->

在这里作答。

<!-- ANSWER Q3 END -->

## 回答方式

请按题号直接在对应的 `ANSWER Qn BEGIN/END` 标记之间作答。可以画简短时序图或引用具体 RTL/C++ 表达式；不确定的判断请明确标出。
