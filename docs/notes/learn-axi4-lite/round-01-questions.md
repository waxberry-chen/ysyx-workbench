# AXI4-Lite 学习：第 1 轮问题

## 本轮主题

建立 AXI4-Lite 的整体接口地图，并辨认它与 NPC 当前 memory interface 的结构差异。

这一轮不要求设计 RTL，也不必深入分析复杂时序。请先形成对“一个事务由哪些通道共同完成”的直觉。

## 建议阅读范围

- `docs/ref-spec/b-amba-axi4-lite-extract.pdf`
  - B1.1 Definition of AXI4-Lite
  - B1.1.1 Signal list
  - B1.1.2 Bus width
  - B1.1.3 Write strobes
  - B1.1.4 Optional signaling
- `docs/ref-spec/a2-signal-description.pdf`
  - A2.1～A2.6，只需阅读各通道的信号表和 Source 列
- 当前工程：
  - `npc/vsrc/core/ysyx_ifu.sv`
  - `npc/vsrc/core/ysyx_lsu.sv`
  - `npc/vsrc/core/ysyx_core.sv` 中 IFU、LSU 的外部 memory interface

## 问题

### 1. AXI4-Lite 的五个通道分别承担什么职责？

请为每个通道说明：

- 它传递的是地址、数据还是响应；
- 信息流向是 master 到 slave，还是 slave 到 master；
- 该通道的 `VALID` 和 `READY` 分别由哪一方产生。

然后解释：为什么不能只把五个通道看成“一组较宽的请求线”和“一组较宽的响应线”？

#### 我的回答

<!-- ANSWER Q1 BEGIN -->

AR channel: 

- 传递两个东西: 读地址 araddr, 以及标志着读操作一些属性的 3-bit arprot[2:0] 信号. 
- 信息流: master -> slave.
- valid: master 产生; ready: slave 产生. 

R channel: 

- 传递: 读数据 rdata 和 指示本次读操作状态的 rresp[2:0], 但是 AXI4-Lite 协议中没有独占访问 (0b01: EXOKAY)
- 信息流向: master <- slave.
- valid 由 slave 产生, ready 由 master 产生. 

AW channel: 

- 传递写地址 awaddr 和写属性的 awprot[2:0]. 
- master -> slave.
- valid: master; ready: slave. 

W channel: 

- 传递写数据 wdata 和标志写数据有效 byte lane 的 wstrb. 
- master -> slave.
- valid: master; ready: slave. 

B channel: 

- 传递写返回状态 bresp. 
- master <- slave. 
- valid: slave; ready: master. 

关于: 为什么不能只把五个通道看成“一组较宽的请求线”和“一组较宽的响应线”? 
答: 这五个 channel 各自独立握手传输, 由 master 和 slave 两侧的状态控制逻辑控制, 在时间上通常是有先后顺序, 一次读/写操作不是简单的单次握手或者并发传输, 而是对应不同通道多次握手, 因此不能视作“一组较宽的请求线”和“一组较宽的响应线”. 

<!-- ANSWER Q1 END -->

### 2. AXI4-Lite 相对完整 AXI 做了哪些关键简化？

请从 B1.1 中选出你认为对当前 32 位 NPC memory interface 最重要的 3～5 点，用自己的话说明它们对一次访问意味着什么。

请特别思考下面这个看似矛盾的问题：规范说 AXI4-Lite 的访问使用完整数据总线宽度，但它又保留了 `WSTRB`；那么 RV32 的 `SB`、`SH` 应当如何通过 32 位 AXI4-Lite 数据总线表达？

#### 我的回答

<!-- ANSWER Q2 BEGIN -->

Answer 1: 最重要的 3-5 点: 
1. burst length = 1, 单次读/写 transaction 由 AR/AW channel 握手发起后, 只传输一个 data beat, 双方只传输一拍数据. 从而省略了很多描述 burst 特性的相关信号 (如 AxLEN, AxBURST, AxLAST). 
2. AXI4-Lite 固定 data bus width 为 32-bits 或 64-bits, 并通过 wstrb (write strobe) 信号控制数据有效的 byte lane. 值得注意的是似乎只有 W channel 有这个 strobe 信号. 
3. 对于单笔 transaction 没有 AXI id 编码, 因此 AXI4-Lite 支持的 multi-outstanding 应该是顺序返回提交的. 多次 AR/AW 注册了多笔 transaction 后, 返回数据时候也应该按照注册顺序返回注销. 

Answer 2: AXI4-Lite 使用完整总线宽度 + strobe 信号来控制信号有效的部分. 
所以按照我的理解, 例如对于 32-bit data width (4 byte), 拥有 wstrb[3:0]. SB (Store Byte): wstrb = 4'b0001; SH (Store Halfword): wstrb = 4'b0011;

<!-- ANSWER Q2 END -->

### 3. 当前接口与 AXI4-Lite 之间存在哪些结构差异？

分别观察 IFU 的 `imem_*` 和 LSU 的 `dmem_*` 信号，回答：

- 当前接口如何表示“请求被接受”和“响应被接受”？请指出源码中判断这两个事件的具体表达式。
- 一次取指、一次 load、一次 store，在当前接口上各需要经历哪些阶段？
- 如果未来把它们接到 AXI4-Lite，哪些当前信号可以较自然地对应到某个 AXI 通道，哪些信息必须被拆分、转换或补充？
- 尤其对于 store，当前的一个 `dmem_req_*` 请求与 AXI4-Lite 写事务之间为什么不能简单视为一次完全相同的握手？

#### 我的回答

<!-- ANSWER Q3 BEGIN -->

- req_fire = xmem_req_valid & xmem_req_ready; 和 rsp_fire = xmem_rsp_valid & xmem_rsp_ready; ? valid 和 ready 同时拉高即成功. 
- 一次取指: req channel 握手传递 fetch_pc_q, 等待 rsp 握手传回 instruction 和 error bit. 一次 load: lsu_req channel 握手 -> dmem_req channel 握手 -> dmem_rsp channel 握手 -> lsu_rsp channel 握手. store 从接口来看也是如此, 只是 *_req_write 信号标识是读还是写, store 时候 req 约等于 AW + W, 目前读写通道未区分, 共用 req + rsp channel, 都是握手两次. 
- 对于单纯读功能的接口 (如 IFU 中接口), req -> AR, rsp -> R, 但是 AR 新增 arprot[2:0], R 中 rsp_error -> rresp. 对于读写单元比如 LSU, 则必须做读写通道的分离, dmem interface: req + rsp -> AW + W + B + AR + R, 加入 awprot, wstrb, bresp. 
- 现在的情况是写地址、写数据在 req channel 单次握手内完成, 然后 rsp channel 给出一个 error response. 而 AXI4-Lite 写事物需要 AW 握手 -> W 握手写 -> B 握手返回, 写 transaction 需要三次握手. 

<!-- ANSWER Q3 END -->

## 回答方式

请按题号作答，优先用自己的话描述；可以引用信号名和少量源码，但不必抄写规范。遇到不确定之处请明确标出来，后续反馈会针对这些位置展开。

---

## Review（2026-09-26）

### 总体评价

本轮已经建立了正确的主体框架：能够辨认五个通道、信号方向和 `VALID/READY` 的驱动方，也能看出当前 NPC 的 request/response 接口与 AXI4-Lite 五通道接口不是一一对应关系。

进入下一轮前需要修正三个关键点：

1. `RRESP` 和 `BRESP` 都是 **2 bit**，不是 3 bit。
2. `WSTRB[3:0]` 必须结合地址低位决定具体置位方式，不能为所有 `SB`、`SH` 固定使用同一个值。
3. `AW` 和 `W` 是独立通道，不存在协议规定的“先 AW、再 W”的固定握手顺序。

### 对问题 1 的 review

五个通道的职责、信息方向以及 `VALID/READY` 的驱动方均回答正确。把它们理解成各自握手的单向通道，也是正确的切入点。

有两处需要修正或收紧表述：

- `RRESP` 应为 `RRESP[1:0]`，`BRESP` 同样是 `BRESP[1:0]`。完整编码包括 `OKAY=2'b00`、`EXOKAY=2'b01`、`SLVERR=2'b10`、`DECERR=2'b11`；AXI4-Lite 不支持其中的 `EXOKAY`，但字段宽度不会因此改变。
- “在时间上通常是有先后顺序”容易引出错误直觉。准确说法是：五个通道独立握手，协议只规定必要的依赖关系。例如读数据必须在对应读地址之后返回；写响应必须等写地址和写数据都被接收后才能产生。除此之外，不能自行假定通道间顺序。

另外，“一次事务包含多次握手”是对的，但这些握手未必占据不同的时钟周期。只要依赖关系允许，不同通道的握手可以发生在同一拍。

### 对问题 2 的 review

以下理解正确：

- AXI4-Lite 的 burst length 固定为 1，一笔事务只有一个 data beat。
- 它没有 AXI ID，但仍允许存在多笔 outstanding transaction；没有 ID 意味着不能依靠 ID 进行乱序完成，同类事务的响应必须保持顺序。
- 窄写通过 `WSTRB` 表示哪些 byte lane 有效，只有写数据通道需要 strobe。

需要修正和补充的地方：

- 规范中没有名为 `AxLAST` 的信号。完整 AXI 使用的是 `WLAST` 和 `RLAST`；AXI4-Lite 不携带它们，因为唯一的 data beat 隐含地就是最后一个 beat。
- “只传输一拍数据”最好表述成“只传输一个 data beat”。遇到 backpressure 时，发送方可能连续多拍保持 `VALID` 和 payload，直到发生一次有效握手；不能把一个 beat 理解成信号只维持一个时钟周期。
- “由 AR/AW 握手发起后传输数据”对读事务基本成立，但对写事务不够准确。写地址 `AW` 与写数据 `W` 是两个独立的输入通道，二者可以同拍握手，也可以任意一个先握手。
- 你已正确指出 32-bit 是 4 byte，因此有四个 byte lane，恰好对应 `WSTRB[3:0]`。不过，给出的 `SB -> 0001`、`SH -> 0011` 只适用于目标落在最低 byte lane 的情况。对于对齐访问，可以形成下面的直觉：

  | 访问及地址低位 | `WSTRB[3:0]` |
  | --- | --- |
  | `SB`，`addr[1:0]=00/01/10/11` | `0001/0010/0100/1000` |
  | `SH`，`addr[1:0]=00` | `0011` |
  | `SH`，`addr[1:0]=10` | `1100` |
  | `SW`，`addr[1:0]=00` | `1111` |

  与此同时，待写字节也必须出现在 `WDATA` 对应的 byte lane 上。当前 `lsu_req_wdata` 直接来自 `op_rs2_data`，所以将来生成 AXI 写通道信号时，不能只生成 `WSTRB`，还要明确是否以及如何按 `addr[1:0]` 对 `WDATA` 做 lane 对齐。

关于 multiple outstanding，你的结论对同方向事务基本正确，但不要进一步推导成读写之间存在一个统一的总顺序。读通道和写通道彼此独立；之后讨论仲裁和内存可见顺序时，需要单独处理跨读写方向的关系。当前 IFU 和 LSU 的外部状态机实际上都只允许 single outstanding，这属于当前实现的限制，不是 AXI4-Lite 协议本身的限制。

### 对问题 3 的 review

对当前事务路径的描述基本正确：

- IFU 外部请求和响应的接受事件分别是 `imem_req_valid && imem_req_ready`、`imem_rsp_valid && imem_rsp_ready`。
- LSU 外部 memory interface 的对应事件是 `dmem_req_valid && dmem_req_ready`、`dmem_rsp_valid && dmem_rsp_ready`。
- LSU 内部还各有一层与 EXU 相连的 `req_valid/req_ready` 和 `rsp_valid/rsp_ready`，所以你列出的 load/store 四阶段路径是正确的。

这里建议使用源码中的实际信号名，而不是 `xmem_*`，因为 IFU 和 LSU 对响应的处理并不完全相同：IFU 还存在用于 redirect 后丢弃旧响应的 `DROP` 状态。

接口映射的总体判断也正确，但方向和转换关系应更精确：

- 对取指和 load，内部请求可以转换成 `AR`，`RDATA` 转换成内部响应数据；适配器应当把 `RRESP` 解码成 `imem_rsp_error` 或 `dmem_rsp_error`，不是把内部 `rsp_error` 驱动到 `RRESP`。
- 对 store，当前一个 `dmem_req_*` 握手同时交付地址、访问宽度和原始写数据；适配器必须把它拆成彼此独立的 `AW` 与 `W` 两次通道传输，并等待 `B` 响应。`dmem_req_size` 在 AXI4-Lite 中没有可直接对应的 `AWSIZE`，需要转换成 `WSTRB` 和相应的 `WDATA` byte-lane 布局。
- `dmem_rsp_error` 应由 `BRESP` 或 `RRESP` 是否表示错误来产生；store 的内部响应数据可以忽略，但仍然必须等到 `B` 通道完成，才能向当前 LSU 报告这笔 store 已完成。

最后一句“`AW` 握手 -> `W` 握手 -> `B` 握手”是本题最重要的误解。正确的依赖关系是：

- `AW` 和 `W` 可以同拍完成，也可以 `AW` 先完成，还可以 `W` 先完成；
- master 必须分别记住地址和数据通道是否已经握手，不能因为其中一个完成就撤销另一个；
- slave 只有在对应的 `AW` 与 `W` 都完成握手之后，才可以给出 `BVALID`；随后 `BVALID && BREADY` 完成写响应握手。

### 本轮结论

本轮可视为“主体理解正确，但需要带着修正进入下一轮”。最值得保留的工程直觉是：当前接口把一笔请求作为一个整体接收，而 AXI4-Lite 把事务拆成多个独立、可分别 backpressure 的通道；未来的适配器必须保存这些通道各自的进度。
