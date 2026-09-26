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

在这里作答。

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

在这里作答。

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

在这里作答。

<!-- ANSWER Q3 END -->

## 回答方式

请按题号直接在对应的 `ANSWER Qn BEGIN/END` 标记之间作答。可以画简短时序图或引用具体 RTL 表达式；不确定的判断请明确标出。
