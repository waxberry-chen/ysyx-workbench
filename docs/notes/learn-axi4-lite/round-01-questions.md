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

在这里作答。

<!-- ANSWER Q1 END -->

### 2. AXI4-Lite 相对完整 AXI 做了哪些关键简化？

请从 B1.1 中选出你认为对当前 32 位 NPC memory interface 最重要的 3～5 点，用自己的话说明它们对一次访问意味着什么。

请特别思考下面这个看似矛盾的问题：规范说 AXI4-Lite 的访问使用完整数据总线宽度，但它又保留了 `WSTRB`；那么 RV32 的 `SB`、`SH` 应当如何通过 32 位 AXI4-Lite 数据总线表达？

#### 我的回答

<!-- ANSWER Q2 BEGIN -->

在这里作答。

<!-- ANSWER Q2 END -->

### 3. 当前接口与 AXI4-Lite 之间存在哪些结构差异？

分别观察 IFU 的 `imem_*` 和 LSU 的 `dmem_*` 信号，回答：

- 当前接口如何表示“请求被接受”和“响应被接受”？请指出源码中判断这两个事件的具体表达式。
- 一次取指、一次 load、一次 store，在当前接口上各需要经历哪些阶段？
- 如果未来把它们接到 AXI4-Lite，哪些当前信号可以较自然地对应到某个 AXI 通道，哪些信息必须被拆分、转换或补充？
- 尤其对于 store，当前的一个 `dmem_req_*` 请求与 AXI4-Lite 写事务之间为什么不能简单视为一次完全相同的握手？

#### 我的回答

<!-- ANSWER Q3 BEGIN -->

在这里作答。

<!-- ANSWER Q3 END -->

## 回答方式

请按题号作答，优先用自己的话描述；可以引用信号名和少量源码，但不必抄写规范。遇到不确定之处请明确标出来，后续反馈会针对这些位置展开。
