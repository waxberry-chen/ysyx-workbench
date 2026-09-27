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

- master 驱动: arvalid, araddr, arprot, rready; slave 驱动: arready, rvalid, rdata, rresp. 
- arvalid 不允许 等 arready, arready 可以等 arvalid 拉高再进行状态跳转. 同样 rvalid 不能等 rready, rready 可以等 rvalid. “A信号等待B信号” 按照我的理解是指B信号可以作为输入控制A信号的产生/A信号一侧的状态跳转? 
- 地址握手成功后, 不需要保持 valid 和 payload. 
- 应该以 AR channel 的 arvalid && arready 发生作为读请求发起的边界, R channel 的 rvalid && rready 握手成功作为读事物完成的边界. 读事务发起但未完成, 处于 Outstanding. 
- RRESP[1:0] 的可用结果: 2‘b00: OKAY, 正常访问成功; 2’b01: EXOKAY, 独占访问, AXI4-Lite 里没有; 2'b10: SLVERR, 请求成功到达 slave, 但是 slave 出现了错误; 2'b11: DECERR, 通常由互联生成, 告知在 AR 地址没有有效的 slave. rresp 与 rdata 作为同一 R channel payload 一同传输. 

Q: 关于读/写事务, 包含完整的 AR -> R 或者 AW -> W -> B, 用 transaction 描述? 单个通道传输用 transfer 来描述. 这样对吗? 

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

- AR 在 T2 完成 tranfer, R 在 T6 完成 transfer. 
- 在 T3 上升沿记录 outstanding read, 在 T7 清除. 
- T1~T2 应该由 master 保持 arvalid 和 araddr. T4~T6 应该由 slave 保持 rvalid, rdata, rresp. 
- 没问题. 不行, 因为 valid 不能依赖 ready 信号. 
- 协议允许, AXI4-Lite 没有 ID, 因此响应应该是顺序提交/退休 in-order commit 的. 

判断: 1 合法, 2 不合法. 组合在一起造成死锁 (deadlock), 总是互相等待, 无法正常握手. 

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

- IFU 的 REQ 对应 AR, WAIT 对应 R, DROP 本质上也属于 R, 只是 返回的 data 不进入 ifq, 没有被用到. req_fire 相当于地址握手成功, 一次读事务产生后专门等待 rsp_fire 而不能进行更多的 req_fire, 同时进行的读事务只能有一个, 所以 single-outstanding. 
- imem_rsp_ready = (state_q == DROP) | ((state_q == WAIT) & (redirect_valid | ifq_in_ready));, WAIT 状态下没有 redirect 和 ifq 没有 flush、没有满的情况下默认为 1. ready 默认为高, 一周期接受 response. 关系如上述表达式, WAIT 时候没有 redirect 的话, 需要 ifq 队列空间有空. 
- 目前看来, 如果要支持 redirect 发生在地址请求已被接受、但读响应尚未返回时取消 AXI 读事务, 那么 RAM 侧需要加入抛弃已成功的地址握手的逻辑. IFU 应该正常接受旧 `RDATA/RRESP`, 但是不放入 ifq. 在 R/rep channel 握手返回后立即发出新 PC 的读地址. 
- dmem_req_valid -> dmem_arvalid, dmem_req_ready -> dmem_arready, dmem_req_addr -> dmem_araddr, dmem_rsp_valid -> dmem_rvalid, dmem_rsp_ready -> dmem_rready, dmem_rsp_data -> dmem_rdata, dmem_rsp_error -> dmem_rresp. 同时加入 dmem_arprot. rresp 应该在 RAM 一侧撰写新的逻辑产生. 不过由于目前没有 exclude 访问也没有 interconnect, 所以实际上也可以把 dmem_rsp_error 直接作为 dmem_rresp[1]. 
- LSU 有 2 个界面, 一个是 EXU <-> LSU, 一个是 LSU <-> memory. AXI 读仅在 LSU <-> memory. IDLE 和 RESP 是用于 EXU <-> LSU 之间握手传输. 
- C++ RAM 中 RESP 阶段也是判断 rsp_fire_ 再进行状态跳转, backpressure 情况下只是等待. prepare_response() 产生 rsp_data 以及 rsp_error. 同时 state_ = RESP , 在下个周期 ram tick 的时候应该是同时到来的, 没有状态跳转应该也不会变, 符合保持义务. 

新增 AXI4-Lite adapter, 这个问题我不太理解是什么意思, CPU 一侧 RREADY 应该不会故意 stall? 如果要新增, 这个 adapter 应该与 LSU 、IFU 握手, 内部维护一个状态来生成 valid, ready. 同时保存所有的 payload? 并且理论上应该直接将 IFU, LSU 的 mem 侧接口改成 AXI4-Lite 吧? 为什么新增一层 Adapter?  

我现在的直觉是, 一次握手时间上最小需要一周期 (ready 默认为高则下周期采样直接握手成功). 因此一次 AXI 读事务最少要 2 周期分别进行 AR、R 握手? 新增一个 adapter, 一次读事务 lsu -> adapter, adapter -> mem, mem -> adapter, adapter -> lsu, 多了 2 次握手至少多2周期? 

<!-- ANSWER Q3 END -->

## 回答方式

请按题号直接在对应的 `ANSWER Qn BEGIN/END` 标记之间作答。可以画简短时序图或引用具体 RTL/C++ 表达式；不确定的判断请明确标出。

---

## Review（2026-09-27）

### 总体评价

本轮对 AXI4-Lite 读事务本身的理解已经比较扎实：两个通道的驱动关系、必要依赖、response 编码、backpressure 和无 ID 时的顺序要求都回答正确。第二题唯一实质性偏差是把 outstanding 状态的置位和清除各推迟了一个标号。

第三题对当前 IFU 状态机和 C++ RAM model 的理解基本正确，但接口转换方向、adapter 的职责以及“是否必然增加两周期”还没有形成稳定模型。这正是本轮最有价值的暴露点。

### 对问题 1 的 review

五组信号的驱动方、依赖关系、地址握手后的保持义务以及 `RRESP` 编码均回答正确。AXI4-Lite 合法使用 `OKAY`、`SLVERR`、`DECERR`，不使用 `EXOKAY`；`RDATA` 与 `RRESP` 是同一个 R channel transfer 的 payload，必须随 `RVALID` 一起保持并通过同一次 `RVALID && RREADY` 握手被接收。

“A 信号等待 B 信号”可以更准确地理解为：**A 的产生被实现为必须先观察到 B 才会发生**。这种依赖既可能被错误地写成组合逻辑，也可能是先在时钟沿采样 B、之后再通过状态机产生 A。协议依赖规则讨论的是这种逻辑前提，不只是在讨论组合赋值；而“接口输入输出之间不能有组合路径”是另一条额外的实现约束。

例如：

- master 无论通过组合逻辑还是状态机，都不能把“已经看到 `ARREADY`”作为产生 `ARVALID` 的前提；
- slave 可以先采样到 `ARVALID`，之后再通过时序逻辑产生 `ARREADY`；
- slave 不能把“已经看到 `RREADY`”作为产生 `RVALID` 的前提。

#### transaction 与 transfer

你的区分基本正确：

- **transaction** 表示一笔完整的端到端访问。AXI4-Lite read transaction 包含一次 AR transfer 和一次 R transfer；write transaction 包含一次 AW transfer、一次 W transfer 和一次 B transfer。
- **transfer** 通常表示某个通道在一个上升沿通过 `VALID && READY` 交付一次 payload；在数据通道语境中也常指一个 data beat。

需要避免把 write transaction 写成具有固定时序含义的 `AW -> W -> B`：`B` 必须在 `AW` 和 `W` 都完成之后，但 `AW` 与 `W` 彼此独立，可以任意一个先完成或同拍完成。

### 对问题 2 的 review

`AR` 在 T2、`R` 在 T6 完成 transfer，stall 期间的保持方和保持内容也判断正确。T3 的 `RREADY=0` 合法；slave 不能等待 `RREADY` 才产生 `RVALID`。两个给定设计分别是“master 合法、slave 非法”，组合后会死锁，这部分完全正确。

outstanding 的记账边界需要改成：

- T2 上升沿发生 `ARVALID && ARREADY`，因此就在 **T2 这次握手后**产生一笔 outstanding read；
- T6 上升沿发生 `RVALID && RREADY`，因此就在 **T6 这次握手后**清除它。

如果用时序寄存器实现，`outstanding_q` 会在 T2 边沿执行置位，并在 T6 边沿执行清零；在波形的周期间隔上表现为 T2 之后到 T6 之后有效。你写 T3/T7，表达的是“下一个周期看到状态变化”，但协议边界应绑定在实际发生握手的 T2/T6，而不是再推迟一个上升沿。

去掉 single-outstanding 限制后，T3 可以继续发出下一笔 AR。AXI4-Lite 没有 ID，因此同方向的返回必须保持请求顺序：先被接受的 AR 所对应的 R 必须先返回。这里更适合说“按 AR 接受顺序返回”，而不是 CPU 语境下的 commit/retire，因为总线响应完成不等同于处理器指令提交。

### 对问题 3 的 review

#### IFU 状态与队列 credit

对状态的总体映射正确，但应把它描述成协议阶段而不是直接等同通道：

- `REQ`：尚未完成外部读请求握手，正在尝试交付地址；
- `WAIT`：请求已经被接受，存在一笔正常的 outstanding read，等待 response；
- `DROP`：仍存在一笔 outstanding read，但它已因 redirect 变成 stale，返回结果只能被消费并丢弃。

它是 single-outstanding，因为 `REQ` 发生 `req_fire` 后立即进入 `WAIT`，在 `rsp_fire` 之前没有任何路径回到可发出下一请求的 `REQ`。

对 `imem_rsp_ready` 表达式的观察正确，但“队列没有满就可以收”还少了关键的 credit 推理：IFU 只有在 `ifq_in_ready=1` 时才允许 `req_fire`，相当于在接受请求时为将来的 response 预留一个 IFQ entry。此后因为只有一笔 outstanding，不会有另一笔 response 抢占该空间，所以正常 `WAIT` 中 response 到达时应仍有 credit。`p_fresh_response_has_credit` 正是在检查这个不变量。redirect 则 flush IFQ，并通过 `DROP` 或 `redirect_valid` 路径保证 stale response 也能被接收。

#### redirect 后不能要求 RAM 取消请求

你的后半段处理方式正确：IFU 应接收旧 response，但不把它写入 IFQ，之后再请求 redirect target。

前半句“RAM 侧需要加入抛弃已成功地址握手的逻辑”需要删除。AR 握手后，slave 已经接受并拥有这笔事务，master 不能再取消它，也不应要求 slave 猜测该 response 是否仍有用。应由 master/IFU 记录 stale 状态并消费、丢弃返回的 `RDATA/RRESP`：

- redirect 与旧 response 同拍完成时，当前 IFU flush 旧结果并回到 `REQ`，下一周期可请求新 PC；
- response 尚未到达时，IFU 进入 `DROP`，等旧 R transfer 完成后再回到 `REQ`。

#### LSU load 与 `AR/R` 的转换方向

这里的主要问题是把内部接口和 AXI 接口按同名信号直接连线，并且把部分 response 方向写反了。正确的数据流应是：

- LSU 向 adapter 提交 `dmem_req_valid/addr/size`；
- adapter 作为 AXI master，向 slave 驱动 `ARVALID/ARADDR/ARPROT`，并从 slave 接收 `ARREADY`；
- slave 向 adapter 驱动 `RVALID/RDATA/RRESP`，adapter 驱动 `RREADY`；
- adapter 再向 LSU 产生 `dmem_rsp_valid/data/error`，由 LSU 的 `dmem_rsp_ready` 接收。

因此应当是 `RRESP -> dmem_rsp_error`，不是 `dmem_rsp_error -> RRESP`。对于 AXI4-Lite 的合法响应，`RRESP[1]` 恰好能区分 `OKAY` 与 `SLVERR/DECERR`；更显式的写法是判断 `RRESP != 2'b00`。这与当前有没有 exclusive access 或 interconnect 无关：即使直连 slave，也仍可能用 `SLVERR` 报告访问错误；存在地址译码层时则通常由它产生 `DECERR`。

还有一个尚未处理的差异：当前 `dmem_req_size` 在 AXI4-Lite 上没有对应的 `ARSIZE`，因为读数据宽度固定为整条总线。当前 C++ RAM model 会按请求 size 从精确地址读取并把结果放在返回值低位，而原 LSU 也固定从 `dmem_rsp_data[7:0]` 或 `[15:0]` 取窄数据。将来转换到 32-bit AXI4-Lite 时，需要明确由 adapter 还是 LSU 根据地址低位选择 `RDATA` byte lane；不能仅删除 `dmem_req_size` 后直接连接。

#### AXI response 与 EXU response 是两个完成边界

你已经看出 LSU 有两层接口，但还需要把状态迁移说完整：

1. LSU 在 `WAIT` 中通过 `dmem_rsp_valid && dmem_rsp_ready` 接受外部 response。若该外部接口换成 AXI，这一边界对应 R transfer 完成，AXI read transaction 到此结束。
2. 同一个上升沿，LSU 把 data/error 保存到 `response_data/response_error` 并进入 `RESP`。
3. LSU 随后保持 `rsp_valid/rsp_rdata/rsp_error`，直到 EXU 通过 `rsp_valid && rsp_ready` 接受。此时才离开 `RESP`，回到 `IDLE`。

因此 AXI read transaction 可以已经完成，而处理器内部的 load response 仍因 EXU backpressure 停留在 LSU 的 buffer 中。

#### C++ RAM model

你的判断正确。`prepare_response()` 只在进入 `RESP` 前生成一次 `response_data_` 和 `response_error_`；`drive()` 在整个 `RESP` 状态持续驱动它们并保持 `rsp_valid=1`；只有 `rsp_fire_` 后状态才回到 `IDLE`。因此 response 遭遇 backpressure 时，valid 和 payload 都保持稳定，符合 R channel source 的义务。

### 关于 adapter 的疑问

#### 为什么要增加 adapter，而不是直接修改 IFU/LSU？

adapter 不是协议强制要求，而是一种架构选择，两种方案都可以：

- **直接修改 IFU/LSU**：让 IFU 自己实现 AXI read master，让 LSU 自己实现 AXI read/write master。模块数少，但协议状态分散在两个单元中；如果芯片外部只有一个 AXI master port，后面仍需要仲裁和响应路由。
- **保留当前内部接口并增加 adapter/bridge**：IFU/LSU 继续使用简单 request/response，adapter 集中处理 AXI 的通道保持、response 解码和协议断言。若共享一个 AXI port，还可在 bridge 附近加入仲裁。

第二种方式的意义是隔离协议复杂度，并不是因为当前接口不能被改。最终选哪种，需要结合计划中的顶层端口数量和仲裁位置决定。

#### 当前 CPU 侧是否会主动制造 R backpressure？

你的直觉对当前实现基本成立：

- LSU 在 `WAIT` 时令 `dmem_rsp_ready=1`，并有自己的 `RESP` buffer；
- IFU 在发请求前预留 IFQ credit，正常 `WAIT` 时也应能令 `imem_rsp_ready=1`；
- redirect 时 IFU 仍会消费 stale response。

所以在不增加共享仲裁等新约束时，adapter 可以设计成只要存在 outstanding read 就持续令 AXI `RREADY=1`，当前 CPU 通常不会故意 stall R channel。但这是一项由内部 buffer/credit 保证支撑的设计结论，不是 AXI master 天然永远不会 backpressure。若未来改变队列、共享端口或允许更多 outstanding，就需要重新证明该结论。

#### single-outstanding read adapter 至少保存什么？

一种清晰的最小模型是维护类似以下阶段：

- `IDLE`：没有请求；
- `SEND_AR`：已经接收内部请求，保持 `ARVALID/ARADDR/ARPROT`，等待 `ARREADY`；
- `WAIT_R`：AR 已握手，等待 `RVALID`；
- 可选的 `HOLD_RSP`：AXI R 已握手，但内部 response 尚未被 IFU/LSU 接受。

相应需要保存的内容取决于职责划分，但通常包括：

- AR stall 期间必须保持的地址和属性；
- 共享端口时，请求来自 IFU 还是 LSU 的 owner 信息；
- IFU redirect 后是否应丢弃 response 的 stale/drop 信息；
- 如果 adapter 负责窄 load 的 lane 处理，还需要地址低位和 load size/type；
- 如果 adapter 在内部 consumer 之前先接受了 AXI R，还需要保存 `RDATA/RRESP`。

如果 adapter 选择等到内部 `dmem_rsp_ready/imem_rsp_ready` 为 1 才拉高 `RREADY`，则 R payload 可以由 AXI slave 按协议保持，adapter 不一定需要 `HOLD_RSP` buffer；如果它先完成 R 握手，就必须自己保存 response。

#### adapter 是否必然多两周期？

不必然。一次 handshake 是在一个上升沿发生的事件，不是协议规定必须额外占用一个完整状态周期：只要 `VALID` 和 `READY` 在该上升沿之前已经稳定为 1，就在该边沿完成 transfer。

对于刚被接受的读地址，在禁止输入到输出组合路径的前提下，slave 通常最早在后续周期给出 `RVALID`，所以最理想的 AR transfer 和 R transfer 会发生在相邻上升沿。这可以理解为读事务至少跨越两个握手边沿，但不要把它推导成每个握手都固定消耗一个额外周期。

adapter 是否增加 latency 取决于实现：

- 全寄存的请求 buffer 通常会在内部 request handshake 后，下一周期才驱动 `ARVALID`，可能增加一拍；response 再寄存一次也可能增加一拍。
- 若内部 source 已经满足 AXI 的稳定性，部分信号可以直接驱动或采用 skid/elastic buffer，使内部 handshake 与 AXI handshake 同拍，或者让 R transfer 直接进入现有 IFU/LSU buffer。
- IFU 当前允许 redirect 撤销 stalled request，不能无条件直接接到 AR，因此至少要修改 IFU 语义或由 adapter 接管并保持这笔请求。

因此“加 adapter 必然多两次握手、至少多两周期”并不成立。adapter 两侧确实有两个接口，但它们可以同拍协同，实际延迟由是否寄存、是否直通和 buffer 放置决定。

### 本轮结论

本轮读协议部分可以视为通过。进入写事务前应固定下面三个边界：

1. AR handshake 产生 outstanding read，R handshake 消除它。
2. AXI R response 从 slave 流向 master，再由 adapter 转换成 LSU/IFU 的内部 response。
3. 总线 transaction 完成与处理器内部消费 response 是两个不同事件，中间可以有 buffer 和 backpressure。
