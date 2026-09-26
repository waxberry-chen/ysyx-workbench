# AXI4-Lite 学习：第 2 轮问题

## 本轮主题

理解所有 AXI 通道共用的 `VALID/READY` 握手机制，包括传输发生的时刻、stall 期间的信号义务，以及避免死锁所需的依赖规则。

本轮先讨论单个通道的通用规则。读事务和写事务跨通道的完整时序将在后续轮次展开。

## 建议阅读范围

- `docs/ref-spec/AMBA AXI and ACE Protocol Specification.pdf`
  - A3.1 Clock and reset
  - A3.2 Basic read and write transactions
  - A3.3 Relationships between the channels
  - A3.3.1 Dependencies between channel handshake signals 中的通用规则；读写事务的具体依赖图暂不要求展开
- 当前工程：
  - `npc/vsrc/core/ysyx_ifu.sv` 中 `req_fire`、`rsp_fire` 和两个 stall stability assertion
  - `npc/vsrc/core/ysyx_lsu.sv` 中四个 `*_fire` 以及 request/response stability assertion
  - `npc/vsrc/gnrl/ysyx_gnrl_primitive.sv` 中 `ysyx_gnrl_fifo` 的 `in_valid/in_ready`、`out_valid/out_ready` 实现

## 问题

### 1. 对任意一个 AXI 通道，`VALID/READY` 握手到底规定了什么？

请分别从 source 和 destination 的角度说明：

- 一次 transfer 在什么条件、什么时刻发生？
- source 何时可以拉高 `VALID`？它能否等待 `READY` 后再拉高？
- `VALID=1 && READY=0` 时，source 对 `VALID` 和 payload 分别有什么义务？
- destination 能否等待 `VALID` 后再拉高 `READY`？已经拉高的 `READY` 能否在尚未看到 `VALID` 时撤回？
- 如果 `VALID` 和 `READY` 连续多个周期同时为 1，会发生一次 transfer，还是每个采样边沿各发生一次 transfer？

#### 我的回答

<!-- ANSWER Q1 BEGIN -->

- 一次 transfer 在采样到 valid & ready == 1 的时候发生. 
- source 在要发送的 addr、data、control info 有效的时候就可以拉高了, valid 和 ready 的拉高逻辑不应相互依赖, 不应该 valid 等 ready 或者 ready 等 valid. 
- valid=1 && ready=0 时, backpressure. source 应该保持 valid=1 并且 payload 保持不变. 
- destination 的 ready 不应该依赖 valid 拉高. 已拉高的 ready 在没等到 valid 的时候可以撤回. 但是 valid 一旦拉高必须等到 ready=1 发生 transfer, 不可撤回. 
- 每个采样边沿各发生一次 transfer. 

Q: 协议里面经常说 assert, 怎么准确理解这个词? 比如这句话中: This specification does not recommend a default AWREADY state of LOW, because it forces the transfer to take at least two cycles, one to assert AWVALID and another to assert AWREADY. 为什么 一个 cycle assert valid 一个cycle assert ready? assert 可以理解为拉高吗? 还是理解为判断拉高? 

<!-- ANSWER Q1 END -->

### 2. 分析下面两段握手轨迹

表中的值表示每个 ACLK 上升沿采样到的信号值。假设 payload 用字母表示。

轨迹 A：

| 上升沿 | `VALID` | `READY` | payload |
| --- | ---: | ---: | --- |
| T0 | 0 | 0 | - |
| T1 | 1 | 0 | A |
| T2 | 1 | 0 | A |
| T3 | 1 | 1 | A |
| T4 | 1 | 1 | B |
| T5 | 0 | 1 | - |

轨迹 B：

| 上升沿 | `VALID` | `READY` | payload |
| --- | ---: | ---: | --- |
| T0 | 0 | 0 | - |
| T1 | 1 | 0 | A |
| T2 | 1 | 0 | B |
| T3 | 0 | 1 | - |

请回答：

- 每段轨迹在哪些上升沿发生了 transfer，一共传输了哪些 payload？
- 哪段轨迹符合协议，哪段不符合？若不符合，具体违反了什么义务？
- 轨迹 A 中 source 在 T3 之后没有先把 `VALID` 拉低，而是在 T4 直接给出 B，这种行为是否合法？为什么？

#### 我的回答

<!-- ANSWER Q2 BEGIN -->

- Trace A: T3 传输了 A, T4 传输了 B. Trace B: 无 trasfer. 
- Trace A 符合, Trace B 不符合. valid 在没等到 ready 时就撤销了. 
- 合法? 只要 valid & ready == 1, 即视作一次有效 transfer? 

<!-- ANSWER Q2 END -->

### 3. 将通用握手规则放回当前 NPC RTL 中检查

请阅读 IFU、LSU 和通用 FIFO 中相关的 `fire` 表达式与 stability assertion，然后回答：

- 这些模块如何表示一次 transfer？它与 AXI 的握手判定是否一致？
- LSU 的 `p_request_stable_when_stalled` 和 `p_response_stable_when_stalled` 分别约束谁扮演的 source？它们检查了 `VALID` 和哪些 payload？
- IFU 的 `p_request_stable_when_stalled` 为什么允许下一拍出现 `redirect_valid`，而不再强制保持原请求？如果将 `imem_req_*` 直接替换成 AXI `AR*`，这种例外是否仍然符合 AXI？请说明理由和可能需要的处理方式。
- AXI 对 reset 期间各类 `VALID` 有什么要求？当前 IFU/LSU 状态机在复位期间对外部 `*_valid` 的行为是否满足相同方向上的要求？
- AXI 禁止接口输入与输出之间存在组合路径。检查当前接口时，你认为应该重点追踪哪些 `READY -> VALID` 或 `VALID -> READY` 的组合依赖链？

#### 我的回答

<!-- ANSWER Q3 BEGIN -->

- 一致, 都是 valid & ready == 1 时发生 trasfer. 
- LSU 的 `p_request_stable_when_stalled` 约束 LSU 扮演的 source, 检查了 dem_req_valid == 1 但是 dmem_req_ready == 0 的 backpressure (RAM 对 LSU) 时刻, 下一拍 valid 不变并且 dmem_req_write, dmem_req_addr, dmem_req_size, dmem_req_wdata 组成的payload稳定. `p_response_stable_when_stalled` 约束了 RAM 一侧的 source (笔误了, LSU 作为 source), 检查了 EXU 对 LSU 施加 backpressure 时候的 valid 和 rsp_rdata, rsp_error 组成的 payload 稳定. 
- 因为 redirect_valid 的时候需要重新 fetch redirect_target 位置的指令, 虽然状态会保持 REQ 阶段, 但是 imem_req_valid == 0, payload imem_req_addr 会变成 redirect_target. 这种情况不符合 AXI 规定的 valid 在没有收到 ready 时保持 valid + payload 的约定. 目前似乎没有想到什么好的方法, 如果继续保持不动等 ready, 握手成功后再进行一次地址握手, 覆盖地址的话, 多了冗余操作的同时又复杂化了, 并且只是单纯为了满足协议...
- AXI 要求 reset 期间所有的 valid 信号全部为 0 (master: arvalid + awvalid + wvalid; slave: rvalid + bvalid), 剩余任意值. 当前 rtl reset 期间 imem_req_valid 会是 1, dmem 界面 dmem_req_valid = 0. 
- 查找 imem_req_*, imem_rsp_*, dmem_req_*, dmem_rsp_* 中间 valid 是否依赖 ready 赋值, ready 是否依赖 valid 赋值. 最终要改到 AXI4-Lite 接口的应该也只是 imem、dmem 两个接口. 

<!-- ANSWER Q3 END -->

## 回答方式

请按题号直接在对应的 `ANSWER Qn BEGIN/END` 标记之间作答。可以画简短时序图或引用具体 RTL 表达式；不确定的判断请明确标出。

---

## Review（2026-09-26）

### 总体评价

本轮已经掌握了握手的核心判定、stall 时 source 的保持义务，以及连续吞吐时 `VALID` 不必插入低电平周期。主要需要修正两点：

1. `VALID` 与 `READY` 的依赖规则并不对称：source 不能等待 `READY` 才产生 `VALID`，但 destination 可以等待观察到 `VALID` 后再产生 `READY`，只要这种等待不是组合路径。
2. stall 时不仅不能撤销 `VALID`，payload 也不能改变；轨迹 B 同时违反了这两条规则。

你对 IFU redirect 与 AXI 握手保持规则之间的冲突判断是正确的。这不是“为了协议而增加的无意义操作”，而是 source 一旦向接口声明某个 payload 有效，就必须履行的承诺。

### 对问题 1 的 review

以下回答正确：

- transfer 在 ACLK 上升沿同时采样到 `VALID=1 && READY=1` 时发生。
- source 有可用 payload 时即可拉高 `VALID`，不能等待 `READY`。
- `VALID=1 && READY=0` 时，source 必须保持 `VALID` 和 payload，直至握手。
- destination 在尚未看到 `VALID` 时，可以撤回已经拉高的 `READY`。
- 如果每个连续的上升沿都采样到 `VALID && READY`，则每个上升沿都完成一次 transfer。

“`READY` 不应该依赖 `VALID`”需要修正。规范明确允许 destination 等待 `VALID` 后再拉高 `READY`。真正禁止的是：

- source 令 `VALID` 的产生依赖 `READY`；
- AXI 接口的输入与输出之间存在组合路径。

因此 destination 可以在某个上升沿采样到 `VALID`，更新内部状态，然后在后续周期拉高 `READY`；不能简单写成一条从输入 `VALID` 到输出 `READY` 的组合路径。允许 destination 等待，而禁止 source 等待，是为了避免双方互相等待造成死锁。

连续握手还需要补充一个细节：每个高电平重叠的采样边沿都是一笔新 transfer。即使相邻两笔 payload 的数值恰好相同，它们也仍然是两笔 transfer。source 如果只想传一笔，就必须在第一次握手后的下一采样边沿之前撤销 `VALID`，不能假设 destination 会替它撤销 `READY`。

#### 关于 `assert` 的含义

在协议正文中，`assert a signal` 表示把信号驱动到它的**有效状态**，`deassert` 表示驱动到无效状态：

- 对 `VALID`、`READY` 这类 active-HIGH 信号，assert 就是驱动为 1；
- 对 `ARESETn` 这类 active-LOW 信号，assert reset 反而是把 `ARESETn` 驱动为 0。

它在这里不是“判断信号是否为高”，也不是特指 SystemVerilog 的 `assert property`。

规范关于默认 `AWREADY=LOW` 的那句话，含义是：如果 slave 平时不声明自己可接收地址，而是先在一个上升沿观察到 `AWVALID`，再通过时序逻辑拉高 `AWREADY`，那么第一拍不能完成握手，至少要等后续采样边沿。若 slave 能提前保持 `AWREADY=1`，则地址第一次以 `AWVALID=1` 出现时就可以完成单周期握手。这不是协议要求 `VALID` 和 `READY` 必须分两拍 assert，而是在解释 reactive `READY` 带来的额外延迟。

### 对问题 2 的 review

轨迹 A 的判断正确：

- T3 完成一次 transfer，payload 为 A；
- T4 再完成一次 transfer，payload 为 B；
- source 在 T3 握手后可以保持 `VALID=1`，直接在下一个周期换成下一笔 payload B，不需要插入 `VALID=0` 的空拍。

原因是 T3 上升沿之后，A 的保持义务已经随着握手完成而结束。从 T3 到 T4 之间，source 可以准备下一笔 B；T4 再次采样到 `VALID && READY`，因此 B 被接收。这正是 ready/valid 接口能够做到每周期一笔吞吐的基础。

轨迹 B 确实没有发生 transfer，但它包含两项违规，而不只是撤销 `VALID`：

1. T1 已经进入 `VALID=1 && READY=0` 的 stall，payload A 必须保持，T2 却变成了 B；
2. 到 T2 仍未发生握手，T3 却撤销了 `VALID`，导致此前承诺的那一笔数据彻底丢失。

### 对问题 3 的 review

#### transfer 判定

当前模块都用 `valid && ready` 形成 `*_fire`，与 AXI 对单通道 transfer 的判定一致。源码中具体为：

- IFU：`req_fire`、`rsp_fire`；
- LSU 与 EXU 之间：`req_fire`、`rsp_fire`；
- LSU 与外部 memory 之间：`dmem_req_fire`、`dmem_rsp_fire`；
- FIFO：`push`、`pop`。

#### LSU 的两个 stability assertion

对 request assertion 的理解正确：在 `dmem_req_*` 接口上，LSU 是 source，外部 RAM 是 destination；stall 时检查 `dmem_req_valid` 继续为 1，并保持 `dmem_req_write`、`dmem_req_addr`、`dmem_req_size`、`dmem_req_wdata`。

对 response assertion 的 source 身份需要修正。`p_response_stable_when_stalled` 检查的是 LSU 输出给 EXU 的 `rsp_valid/rsp_rdata/rsp_error`：

- source 是 LSU；
- destination 是 EXU；
- EXU 通过 `rsp_ready=0` 对 LSU 施加 backpressure。

它不检查 RAM 输入 LSU 的 `dmem_rsp_*`。对于后者，外部 RAM 才是 source；当 `dmem_rsp_valid=1 && dmem_rsp_ready=0` 时，保持 response 的责任属于 RAM 或未来的 AXI slave/adapter。

#### redirect 与尚未握手的请求

你的判断正确：当前 IFU 明确允许 redirect 取消一个尚未被当前 memory interface 接受的请求，因此 assertion 把 `redirect_valid` 作为例外。如果直接把这些信号当成 `ARVALID/ARADDR`，这种撤回行为不符合 AXI。只要 `ARVALID` 已经对外 assert，即使尚未握手，master 也必须保持它和 `ARADDR`，直到 `ARREADY` 完成握手。

可行处理通常有两类：

1. **让 IFU 自己履行 AXI 承诺**：redirect 到来后仍完成旧 `AR` 握手，标记这笔请求为 stale，之后接收并丢弃旧 `R`，再发新地址。
2. **在 IFU 与 AXI 之间加入请求缓冲/adapter**：adapter 先用当前 `imem_req_ready` 接收并保存请求，此后由 adapter 独立保持 `ARVALID/ARADDR` 直到 AXI 握手。对 IFU 而言请求已经被接受，所以 redirect 可以沿现有 `WAIT -> DROP` 逻辑处理旧响应。

第二种方式更自然地保留当前 IFU 的接口语义。旧访问可能最终变成无用访问，但 AXI 没有取消已经发出的传输这一机制；丢弃 stale response 是正常的控制流代价。若目标是减少无用访问，只能在对外 assert `ARVALID` 之前决定不发，不能在 assert 后撤销承诺。

#### reset

你列出的 AXI reset 要求正确。按当前实现：

- LSU reset 到 `IDLE`，所以 `dmem_req_valid=0`、上游 `rsp_valid=0`；
- IFU reset 到 `REQ`，同时空 IFQ 令 `ifq_in_ready=1`，因此当前 `imem_req_valid` 在 reset 期间可能为 1。

当前 `imem_*` 还不是 AXI，所以这不等于现有 RTL 已违反其自定义接口约定；但若直接将 `imem_req_valid` 用作 `ARVALID`，就不满足 AXI master 在 reset 期间令 `ARVALID=0` 的要求。未来 AXI master/adapter 应通过 reset state 保证所有输出 `ARVALID/AWVALID/WVALID` 为 0，并且只能在 `ARESETn` 解除后的上升沿之后开始 assert 它们。

#### 组合路径

“搜索 valid 是否依赖 ready、ready 是否依赖 valid”是正确起点，但范围不能只限于同名信号的直接赋值，也不能只看 IFU/LSU 文件。需要从最终 AXI 模块边界跨子模块追踪完整组合链。

当前值得辨认的链包括：

- `imem_req_valid <- ifq_in_ready <- FIFO pop <- if_ctx_ready`；这里存在内部 pipeline 的反压链，但目前没有 `imem_req_ready -> imem_req_valid` 的直接组合依赖。
- `imem_rsp_ready <- ifq_in_ready <- if_ctx_ready`；它也把后端容量传播到 memory response 接收端，但不直接依赖 `imem_rsp_valid`。
- `dmem_req_valid` 只由 LSU 的寄存状态决定，不依赖 `dmem_req_ready`；`dmem_rsp_ready` 同样只由寄存状态决定。
- `ysyx_gnrl_fifo` 的 `in_ready` 组合依赖 `out_ready`，因此它可以形成跨级的 READY 反压链。FIFO 的 `out_valid` 来自寄存的 `count_q`，不直接依赖 `in_valid`。

未来加入 AXI adapter 后，应分别检查每个 AXI interface 上是否存在任意“接口输入经组合逻辑回到接口输出”的路径，而不仅是 `READY -> VALID`。尤其要避免为了让内部请求与 AXI 同拍完成，而把 `ARVALID` 写成依赖 `ARREADY`，或让一条 READY 链绕过缓冲后又影响同一接口的 VALID。

### 本轮结论

本轮主体理解正确。进入读事务前应固定两个心智模型：

1. source 的 `VALID` 是不可随意撤回的承诺，destination 的 `READY` 是可动态变化的接收能力声明；两者义务不对称。
2. `VALID` 无须在两笔连续 transfer 之间拉低；payload 可以在一次握手后立即切换，但绝不能在尚未握手的 stall 期间切换。
