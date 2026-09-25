# SystemVerilog Assertions（SVA）初学者教程

> 本文面向了解基本 Verilog 时序逻辑、但没有接触过形式化时序性质描述的读者。示例以同步单时钟 RTL 和当前 NPC 的 ready/valid、IFU、LSU、commit 接口为主。

## 1. SVA 到底解决什么问题

普通 testbench 常按“输入一组数据，再检查输出”的方式验证功能：

```systemverilog
drive_request();
wait_for_response();
if (response != expected)
  $fatal("wrong response");
```

这适合检查某个具体 case，却不容易持续检查以下规则：

- `valid=1 && ready=0` 时 payload 不能变化；
- 没有 outstanding request 时不能出现 response；
- load/store 未收到 response 前不能 commit；
- flush 后的错误路径 instruction 不能更新 architectural state；
- 仲裁器授予同一资源的 grant 最多只能有一个；
- 每次接受的 request 最终都应产生一个 response。

这些规则不是某个输入对应某个输出，而是对**所有周期、所有 transaction**都成立的时序契约。SystemVerilog Assertions（SVA）就是描述和自动检查这些契约的语言。

可以把验证分成三层：

```text
stimulus       让哪些情况发生
checker/model  结果的具体数值是否正确
assertion      任何时候都不能违反哪些规则
```

SVA 不会自动产生测试输入，也不能代替 reference model。它最擅长检查控制、协议、状态转换和跨周期因果关系。

SVA 通常属于 verification code：仿真器执行它，形式化工具证明它，综合工具则通常忽略或移除它。除非专门实现 on-chip monitor，否则写一条 assertion 并不意味着芯片中会多出对应的检查电路。具体综合 flow 是否接受某类 SVA，需要查看所用工具的支持范围。

## 2. 第一个 mental model：每个时钟沿拍一张照片

并发 assertion 通常写成：

```systemverilog
assert property (@(posedge clk) expression);
```

可先把它理解为：

> 每个 `posedge clk` 对相关信号拍一张快照，再用连续多张快照判断某条规则是否成立。

假设有以下波形：

```text
sample edge        e0     e1     e2     e3
valid               0      1      1      0
ready               0      0      1      1
data               10     20     20     30
```

在 `e1`，`valid && !ready` 成立，因此 transaction 被 stall。协议要求 `e2` 采样时 `valid` 仍为 1，`data` 仍为 20。`e2` 上 `valid && ready` 成立，transaction 才完成。

这条规则可以写成：

```systemverilog
assert property (@(posedge clk)
  valid && !ready |=> valid && $stable(data));
```

这里不是在检查模拟时间中任意瞬间的毛刺，而是在检查相邻采样沿之间的协议行为。

## 3. immediate assertion 与 concurrent assertion

### 3.1 Immediate assertion

Immediate assertion 像普通的程序 `if`，执行到该语句时立刻检查一次：

```systemverilog
always_comb begin
  assert (!(read_en && write_en))
    else $error("read and write cannot happen together");
end
```

它适合：

- 组合逻辑中的局部合法性；
- testbench task 中的单次检查；
- 不需要表达跨周期关系的条件。

### 3.2 Concurrent assertion

Concurrent assertion 使用 `property` 描述采样时序：

```systemverilog
property p_no_response_without_request;
  @(posedge clk) response_valid |-> outstanding;
endproperty

assert property (p_no_response_without_request);
```

它适合：

- 跨周期 request/response；
- handshake holding；
- pipeline latency；
- reset、flush 和 commit；
- protocol ordering。

本文后续主要讨论 concurrent assertion。

## 4. `sequence`、`property` 和 `assert` 分别是什么

### 4.1 Sequence：描述一段时间模式

```systemverilog
sequence s_req_then_rsp;
  req_fire ##[1:4] rsp_fire;
endsequence
```

含义是：发生 `req_fire` 后，第 1～4 个采样周期内发生 `rsp_fire`。

Sequence 只描述“什么时间模式算匹配”，本身还没有要求它必须发生。

### 4.2 Property：把模式变成规则

```systemverilog
property p_request_gets_response;
  @(posedge clk) req_fire |-> ##[1:4] rsp_fire;
endproperty
```

Property 可以包含：

- clocking event；
- reset disable condition；
- antecedent 和 consequent；
- sequence；
- 布尔条件和 sampled-value function。

### 4.3 Assert：要求 property 成立

```systemverilog
a_request_gets_response:
  assert property (p_request_gets_response)
  else $error("accepted request did not receive response in 4 cycles");
```

给 assertion 加 label（如 `a_request_gets_response`）能让失败日志更容易定位。

## 5. 最核心语法：`|->` 与 `|=>`

一条 implication 分为：

```text
antecedent |-> consequent
    前件          后件
```

只有前件匹配时，才要求后件成立。

### 5.1 Overlapped implication：`|->`

```systemverilog
A |-> B
```

如果 A 是单周期布尔表达式，则 B 从**同一个采样周期**开始检查。

```text
edge    e0  e1  e2
A        0   1   0
B        x   1   x   PASS
```

适合检查同周期约束：

```systemverilog
assert property (@(posedge clk)
  response_valid |-> state == WAIT_RESPONSE);
```

### 5.2 Non-overlapped implication：`|=>`

```systemverilog
A |=> B
```

如果 A 在本采样周期成立，则从**下一个采样周期**开始检查 B。

```text
edge    e0  e1  e2
A        0   1   0
B        x   x   1   PASS
```

适合检查“发生某事后，下一周期应处于什么状态”：

```systemverilog
assert property (@(posedge clk)
  req_valid && !req_ready
  |=> req_valid && $stable(req_payload));
```

### 5.3 一个常见错误

错误写法：

```systemverilog
valid && !ready |-> $stable(payload);
```

`$stable(payload)` 在当前采样点比较当前值与上一次采样值。这条性质检查的是“进入 stall 的第一拍与前一拍相比是否稳定”，而不是“stall 后下一拍是否保持”。正确写法通常是：

```systemverilog
valid && !ready |=> valid && $stable(payload);
```

选择 `|->` 还是 `|=>` 前，应先用自然语言明确“后件从本周期还是下一周期开始”。

## 6. 周期延迟与重复

### 6.1 固定延迟 `##n`

```systemverilog
req_fire |-> ##2 rsp_valid;
```

表示 request handshake 后 2 个采样周期，`rsp_valid` 必须成立。

### 6.2 延迟范围 `##[m:n]`

```systemverilog
req_fire |-> ##[1:8] rsp_fire;
```

表示第 1～8 个周期内至少有一个匹配点。它适合有明确最大 latency 的接口。

### 6.3 连续重复 `[*n]`

```systemverilog
start |-> busy[*3] ##1 done;
```

表示 `start` 发生后，`busy` 连续保持 3 个采样周期，然后下一周期 `done` 成立。

还可以写范围：

```systemverilog
start |-> busy[*1:4] ##1 done;
```

初学阶段先掌握固定/范围延迟和连续重复即可。不同开源模拟器对完整 SVA repetition 语法的支持程度不同，使用前应通过一个最小 testbench 确认工具支持。

其他常见但可稍后学习的组合符包括 `throughout`（某条件贯穿一段 sequence）、`within`（一个 sequence 完整出现在另一个 sequence 内）、`intersect`（两个 sequence 在同一终点匹配）和 `first_match`（只取最早匹配）。它们适合更复杂的协议窗口，但不应在基本 implication 已能清楚表达时增加阅读成本。

## 7. Reset：`disable iff`

最常见模板是：

```systemverilog
property p_example;
  @(posedge clk) disable iff (!rst_n)
    antecedent |=> consequent;
endproperty
```

`disable iff (!rst_n)` 表示 reset 有效时：

- 不启动新的 property attempt；
- 取消尚未完成的 attempt；
- 不把 reset 期间的正常状态清空过程报告为协议错误。

它与下面的写法不完全等价：

```systemverilog
rst_n |-> property_body;
```

后者只是 implication，不能自然地取消已经启动、仍在等待未来结果的检查。

注意：`disable iff` 的 reset 表达式具有异步 abort 语义，和 assertion 采样表达式的普通同步判断不同。若设计要求“reset 释放后再等待一拍才开始检查”，应显式增加 history-valid 或 reset-done 状态，而不是只依赖 `disable iff`。

## 8. 常用 sampled-value functions

这些函数都基于 property 的采样时钟理解。

### 8.1 `$past`

```systemverilog
$past(expr)
$past(expr, 2)
```

分别取得上一次、前两次采样的值。

例如 request handshake 后，下一周期状态必须进入 WAIT：

```systemverilog
assert property (@(posedge clk) disable iff (!rst_n)
  req_fire |=> state == WAIT);
```

若要检查锁存的地址：

```systemverilog
assert property (@(posedge clk) disable iff (!rst_n)
  req_fire |=> saved_addr == $past(req_addr));
```

在仿真最初几个采样点，历史值可能不存在。应使用 reset、history-valid 或足够的前置条件保护 `$past`。

### 8.2 `$stable` 与 `$changed`

```systemverilog
$stable(payload)  // 当前采样值与上一采样值相同
$changed(payload) // 当前采样值与上一采样值不同
```

多个字段可以拼接后统一检查：

```systemverilog
$stable({write, addr, size, wdata})
```

### 8.3 `$rose` 与 `$fell`

```systemverilog
$rose(valid)
$fell(valid)
```

它们检查采样值相对上一采样值的边沿，适合检测事件进入/退出，但不应把一个本来按 level 定义的 ready/valid 协议错误地改写成只检查 `$rose(valid)`。

### 8.4 `$isunknown`

```systemverilog
assert property (@(posedge clk) disable iff (!rst_n)
  !$isunknown({valid, ready, addr}));
```

可检查 `X/Z`。但二值 Verilator 无法完整替代四值模拟器的 X-propagation 检查，因此该 property 在不同工具上的发现能力不同。

### 8.5 `$onehot` 与 `$onehot0`

```systemverilog
$onehot(grant)   // 恰好一位为 1
$onehot0(grant)  // 最多一位为 1，也允许全 0
```

Arbiter 常用：

```systemverilog
assert property (@(posedge clk) $onehot0(grant));
```

## 9. Safety、liveness 与 bounded response

### 9.1 Safety property

Safety 描述“坏事永远不能发生”：

- 无 outstanding 时不能 response；
- 两个 grant 不能同时有效；
- stall 时 payload 不能变化；
- flush 后错误路径不能 commit。

它通常有有限反例：一旦失败，可以指出第几个周期违反。

### 9.2 Liveness property

Liveness 描述“好事最终会发生”：

```systemverilog
req_fire |-> ##[1:$] rsp_fire;
```

纯仿真很难证明“最终”：测试结束时 response 可能只是还没来。形式化验证也需要公平性或环境假设，例如 slave 不会永久拒绝请求。

工程中常先使用 bounded liveness：

```systemverilog
req_fire |-> ##[1:16] rsp_fire;
```

它实际上是在规定最大 latency。只有接口 specification 确实保证 16 周期上界时，这条性质才合理；不能为了让仿真结束随意捏造上界。

## 10. `assert`、`assume` 与 `cover`

### 10.1 `assert property`

描述 DUT 必须满足的责任：

```systemverilog
assert property (@(posedge clk)
  rsp_valid |-> outstanding);
```

### 10.2 `assume property`

主要用于形式化环境，限制外部环境必须遵守的条件：

```systemverilog
assume property (@(posedge clk)
  req_valid && !req_ready |=> req_valid && $stable(req_payload));
```

如果正在验证 slave，上述 request holding 是 master 的责任，可以作为 assumption；如果正在验证 master，同一规则就应是 assertion。

不要用 assumption 把 DUT bug 约束掉。判断标准是：这条规则究竟属于当前 DUT，还是属于它的合法环境。

### 10.3 `cover property`

确认某个场景确实发生过：

```systemverilog
cover property (@(posedge clk)
  req_fire ##[1:8] rsp_fire);
```

Cover 不要求所有执行都满足，只寻找或记录至少一个 witness。它可用于：

- 确认随机测试真的制造过 backpressure；
- 确认 FIFO 到过 full；
- 确认 branch redirect 与 outstanding fetch 同时发生；
- 在 formal 中寻找能到达目标状态的路径。

## 11. Vacuous pass：最危险的“绿色”

对于：

```systemverilog
req_fire |-> ##[1:4] rsp_fire;
```

如果整个测试中 `req_fire` 从未发生，property 不会失败。这叫 vacuous pass：逻辑上 implication 成立，但目标场景根本没被测试。

因此 assertion 应与 cover/coverage 配合：

```systemverilog
a_req_rsp:
  assert property (@(posedge clk) disable iff (!rst_n)
    req_fire |-> ##[1:4] rsp_fire);

c_req_seen:
  cover property (@(posedge clk) disable iff (!rst_n)
    req_fire);

c_req_stalled:
  cover property (@(posedge clk) disable iff (!rst_n)
    req_valid && !req_ready);
```

还要警惕过强 antecedent：

```systemverilog
rare_state && req_fire && magic_condition |-> ...
```

如果前件几乎不可能发生，assertion 很容易“永远通过”。应分别 cover 前件，并检查条件是否真的属于 specification。

## 12. 面向 ready/valid 的实用模板

### 12.1 Stall 时保持 valid 和 payload

```systemverilog
property p_hold_when_stalled;
  @(posedge clk) disable iff (!rst_n)
    valid && !ready
    |=> valid && $stable(payload);
endproperty

a_hold_when_stalled: assert property (p_hold_when_stalled);
```

如果 payload 有多个字段：

```systemverilog
$stable({write, addr, size, wdata})
```

### 12.2 Response 必须有 owner/outstanding

```systemverilog
assert property (@(posedge clk) disable iff (!rst_n)
  rsp_valid |-> outstanding);
```

这是同周期约束，所以用 `|->`。

### 12.3 Outstanding 计数不溢出

单 outstanding 接口可以直接检查：

```systemverilog
assert property (@(posedge clk) disable iff (!rst_n)
  outstanding |-> !req_ready);
```

多 outstanding 接口更适合在 RTL/testbench 中维护 counter，再检查：

```systemverilog
assert property (@(posedge clk) disable iff (!rst_n)
  outstanding_count <= MAX_OUTSTANDING);
```

### 12.4 接受 request 后锁存 payload

```systemverilog
assert property (@(posedge clk) disable iff (!rst_n)
  req_valid && req_ready
  |=> saved_addr == $past(req_addr));
```

### 12.5 同一资源最多一个 grant

```systemverilog
assert property (@(posedge clk) disable iff (!rst_n)
  $onehot0({ifu_grant, lsu_grant}));
```

### 12.6 Owner 在 transaction 完成前不变

```systemverilog
assert property (@(posedge clk) disable iff (!rst_n)
  outstanding && !rsp_fire
  |=> outstanding && $stable(owner));
```

这类性质对 Arbiter/Xbar 很重要：response 到达时不能重新根据当前 request 组合判断 owner。

## 13. 面向 CPU commit 的实用模板

### 13.1 Memory 指令只能在 response 后 commit

```systemverilog
assert property (@(posedge clk) disable iff (!rst_n)
  commit_valid && commit_is_memory
  |-> lsu_rsp_valid);
```

如果 LSU response 已先进入 buffer，应检查内部 `result_valid`，而不是强行检查外部 memory 的瞬时 `rsp_valid`。

### 13.2 没有 commit 就不能写 GPR

```systemverilog
assert property (@(posedge clk) disable iff (!rst_n)
  gpr_write_valid |-> commit_valid);
```

### 13.3 Commit PC 与执行 context 对齐

```systemverilog
assert property (@(posedge clk) disable iff (!rst_n)
  commit_valid |-> commit_pc == op_pc);
```

### 13.4 Trap 不允许普通写回

若 specification 规定 trap instruction 不产生普通 GPR/memory write：

```systemverilog
assert property (@(posedge clk) disable iff (!rst_n)
  trap_commit |-> !normal_gpr_write && !store_commit);
```

### 13.5 Flush 后年轻指令不能 commit

下面的简单写法往往不够：

```systemverilog
flush |=> !commit_valid;
```

因为 flush 的同周期可能正有一条**老指令**合法 commit，下一周期 redirect target 的正确指令也可能很快到达。真正需要证明的是“被 flush 的那份年轻 context 不得 commit”。

通常需要给 context 增加 identity、sequence number、epoch 或 valid tracking，再检查具体 transaction：

```text
context with old epoch is flushed
        -> no future commit may carry old epoch
```

这说明 SVA 不能脱离 microarchitecture 语义，只靠表面信号名称拼接。

## 14. 从当前 NPC 源码读 SVA

### 14.1 LSU request holding

[`ysyx_lsu.sv`](../../npc/vsrc/core/ysyx_lsu.sv) 中：

```systemverilog
property p_request_stable_when_stalled;
  @(posedge clk) disable iff (!rst_n)
    dmem_req_valid && !dmem_req_ready
    |=> dmem_req_valid &&
        $stable({dmem_req_write, dmem_req_addr,
                 dmem_req_size, dmem_req_wdata});
endproperty
```

逐句解释：

1. 每个上升沿采样；
2. reset 期间取消检查；
3. 若本周期 request 有效但 slave 不接收；
4. 下一周期 request 必须仍有效；
5. direction/address/size/data 必须与上一采样周期相同。

### 14.2 IFU stale response

[`ysyx_ifu.sv`](../../npc/vsrc/core/ysyx_ifu.sv) 中：

```systemverilog
property p_dropped_response_never_enters_ifq;
  @(posedge clk) disable iff (!rst_n)
    state_q == DROP && imem_rsp_valid |-> !ifq_in_valid;
endproperty
```

这是同周期组合关系：在 DROP 状态看见旧 response 时，写 IFQ 的 valid 必须为 0，因此使用 `|->`。

### 14.3 Writeback bypass

[`ysyx_core.sv`](../../npc/vsrc/core/ysyx_core.sv) 中：

```systemverilog
if_ctx_fire && gpr_write_valid &&
(dec_rs1_idx == gpr_write_idx)
|=> op_valid && op_rs1_data == $past(gpr_write_data);
```

本周期 decode/read 与上一条 writeback 相遇；下一周期新 context 已在 opbuf，所以比较 opbuf operand 与 `$past(gpr_write_data)`。

### 14.4 Memory commit 因果关系

[`ysyx_exu.sv`](../../npc/vsrc/core/ysyx_exu.sv) 中：

```systemverilog
commit_valid && op_is_mem |-> mem_wait_q && lsu_rsp_valid;
```

它要求 memory commit 的同一采样周期已经处于等待 transaction 的状态，且 LSU result 有效。若 EXU 因 bug 提前 commit，这条 property 会比最终 DiffTest mismatch 更早指出根因。

## 15. Assertion 在仿真调度区中看到什么

考虑：

```systemverilog
always_ff @(posedge clk)
  if (enable)
    count <= count + 1;

assert property (@(posedge clk)
  enable |=> count == $past(count) + 1);
```

在上升沿：

1. assertion 对信号采样；
2. property 使用采样值判断 attempt；
3. `always_ff` 的 nonblocking assignment 更新寄存器；
4. 下一次采样时才能自然看到更新后的 `count`。

因此“本 edge 发生寄存器更新”的后状态通常用 `|=>` 在下一采样点检查。不要根据波形查看器把同一 timestamp 下的 delta-cycle 显示方式误认为 assertion 已经看到了 NBA 更新后的值。

更严格地说，SystemVerilog 将 concurrent assertion 的 sampling、evaluation 和 action block 放在规定的 simulation regions 中。初学阶段记住“在 clocking event 采样，寄存器 NBA 更新后的状态通常在下一采样沿检查”即可。

## 16. 常见错误与 Debug 方法

### 16.1 把 signal level 当作 transaction event

错误：

```systemverilog
req_valid |-> ...;
```

`req_valid` 可以连续保持多周期，这会每周期启动一个 attempt。若真正关注 request 被接受，应使用：

```systemverilog
req_fire = req_valid && req_ready;
```

### 16.2 Assertion 检查了实现，而不是接口契约

例如直接断言内部 FSM 必须按某个具体编码跳转，会让正常重构造成大量无意义失败。优先检查：

- transaction 没有丢失或重复；
- payload 保持；
- owner 正确；
- architectural side effect 与 commit 对齐。

内部状态 assertion 只用于确实重要的 local invariant。

### 16.3 后件引用了错误层级的信号

若 memory response 已进入 LSU response buffer，backend commit 时外部 `dmem_rsp_valid` 可能已经为 0。此时应该检查 `lsu_rsp_valid`，而不是外部 response。Property 必须与真实 transaction boundary 对齐。

### 16.4 忘记 cover antecedent

Assertion 全绿可能只是前件从未发生。对重要 corner case 同时添加 cover 或 functional coverage。

### 16.5 无上界的“最终响应”用于普通仿真

`##[1:$]` 在 finite simulation 中难以得到有意义的完成结论。仿真可用合理 timeout checker；formal 中则需要 fairness assumption 或 bounded proof。

### 16.6 Reset 后第一拍误用 `$past`

若历史样本尚未有效，比较可能产生 X 或工具相关结果。可使用：

```systemverilog
logic history_valid;

always_ff @(posedge clk or negedge rst_n)
  if (!rst_n)
    history_valid <= 1'b0;
  else
    history_valid <= 1'b1;

assert property (@(posedge clk) disable iff (!rst_n)
  history_valid && condition |-> expr == $past(expr));
```

### 16.7 失败信息没有 transaction context

给 assertion 加 label，并在 action block 输出必要信息：

```systemverilog
a_req_hold:
  assert property (p_req_hold)
  else $error("request changed: addr=%08x state=%0d", addr, state);
```

不要打印大量无关信号；优先打印 seed、cycle、state、owner、address 和 transaction sequence number。

## 17. 如何组织 assertions

### 17.1 初期：靠近 RTL 接口

当前 NPC 将少量 property 放在 IFU、LSU、EXU、core 文件末尾。优点是：

- 信号容易访问；
- property 与接口实现靠近；
- 重构时容易同步更新；
- Verilator 直接启用。

### 17.2 规模增大：checker + `bind`

当 assertions 变多，或希望同一 protocol checker 复用于多个 instance 时，可以写独立 checker：

```systemverilog
module rv_channel_checker (...);
  // assertions and coverage
endmodule

bind target_module rv_channel_checker u_checker (...);
```

这样 verification code 不必侵入 design module，也便于 formal/simulation 使用不同配置。初学阶段不必为了形式立即引入 `bind`；先把 property 语义写正确更重要。

### 17.3 推荐命名

```text
p_*  property
s_*  sequence
a_*  assertion instance
c_*  cover property
```

名字应描述契约，例如 `p_request_stable_when_stalled`，不要写成含义模糊的 `p_check1`。

## 18. 在当前 NPC 中运行

NPC 的 Verilator 构建已加入 `--assert`。可以运行：

```bash
make -C npc lint
make -C npc primitive-test
make -C npc ifu-test
make -C npc lsu-test
make -C npc exu-test
```

`lint` 只会解析和 elaboration property，不能证明它在运行时成立；后四个目标才会执行定向 stimulus 并动态检查 assertions。

然后使用完整 workload 和随机 seed：

```bash
make -C am-kernels/tests/cpu-tests ARCH=riscv32e-npc ALL=add run
make -C npc seed-regress \
  IMG=/absolute/path/to/add-riscv32e-npc.bin \
  ARGS='-d /absolute/path/to/riscv32-nemu-interpreter-so'
```

验证 assertion 是否真的有能力发现错误时，可以进行范围很小的 fault injection：

- stall 时故意改变 request address；
- 没有 outstanding 时注入 response；
- load 尚未返回时提前 commit；
- DROP 状态故意把 stale response 写入 IFQ。

确认 assertion 在预期的第一个错误周期失败后立即恢复 RTL，并重新运行回归。不要把 fault injection 与正式功能改动混在同一提交。

## 19. 从 simulation assertions 到 formal

同一条 SVA 可以用于 simulation 和 formal，但两种方法回答的问题不同：

### Simulation

```text
在本次 test stimulus 实际走过的路径上，property 是否失败？
```

优点是能运行真实软件和复杂模型；缺点是只能覆盖发生过的路径。

### Formal

```text
在所有满足 assumptions 的有限或无限输入序列中，property 是否可能失败？
```

优点是能系统探索 corner case；难点是 state-space、environment assumptions、abstraction 和 proof convergence。

适合当前工程的入门 formal 对象：

- 1-entry ready/valid register；
- small FIFO；
- single-outstanding LSU controller；
- Arbiter mutual exclusion 与 owner holding；
- Xbar target holding；
- AXI-Lite channel adapter。

不要一开始就试图形式化证明整个 CPU ISA correctness。先从边界明确、状态较少的 protocol block 开始。

## 20. 一套实用的编写流程

为一个新模块添加 SVA 时，建议按以下顺序：

1. 写接口契约：producer、consumer、payload、handshake、允许的 latency；
2. 列出 safety invariant；
3. 明确每条规则检查本周期还是下一周期；
4. 确定属于 DUT 的责任写 assert，属于环境的责任写 assume；
5. 给重要 antecedent/scenario 写 cover；
6. 用 directed test 触发每条 property 的前件；
7. 做一次 fault injection，确认 property 会失败；
8. 再运行 random regression；
9. 检查 assertion 是否绑定了过多内部实现细节；
10. 保存失败 seed、首错周期和必要 transaction context。

## 21. 练习建议

### 练习 1：Ready/valid register

为 `ysyx_gnrl_rv_reg` 编写并验证：

- stalled output 保持；
- flush 周期不发生 input/output handshake；
- empty buffer 且 input handshake 后，下一周期 output valid；
- current output 被消费且 input 同周期有效时可以无气泡替换。

### 练习 2：FIFO

- count 永不超过 depth；
- empty 时不能 pop；
- full 且不 pop 时不能 push；
- 同时 push/pop 时 count 不变；
- flush 后 FIFO empty；
- 写入 A、B 后读出顺序仍是 A、B。

最后一条需要保存 symbolic/local data，或借助 reference queue/checker，不是简单布尔 implication 就能完整表达。

### 练习 3：Arbiter

- grant onehot0；
- transaction 未结束前 owner stable；
- response 只能送回 recorded owner；
- 两个 requester 同时请求时遵循规定优先级；
- 若规格要求公平，则等待方在规定上界内获得服务。

## 22. 与真实工程的联系

工业 verification 不会只追求 assertion 数量。高价值 property 通常位于：

- IP protocol boundary；
- clock/reset crossing；
- arbitration/ownership；
- FIFO overflow/underflow；
- pipeline valid/flush/stall；
- architectural commit；
- error/timeout/recovery；
- low-power isolation 和 power-state transition。

一条好的 assertion 应满足：

- 来自明确 specification；
- 失败时接近根因；
- antecedent 可被覆盖；
- 不过度依赖实现细节；
- 仿真和 formal 至少有一种执行方式；
- 能进入 regression，而不是只运行一次。

## 23. 工业界中的相关岗位

- **Design Verification Engineer**：根据 specification 编写 assertions、stimulus、checker 和 coverage，并用 simulation/formal 完成 verification closure。
- **Digital IC / RTL Design Engineer**：用 local assertions 表达模块接口和状态不变量，在 RTL 开发阶段尽早发现 handshake、flush、FIFO 和 side-effect 错误。
- **SoC Design Engineer**：重点使用 SVA 检查 AXI/interconnect、Arbiter、Xbar、CDC wrapper 和 peripheral integration。
- **Formal Verification Engineer**：将 assertions、assumptions、abstraction 和 coverage 组合成可收敛的 proof environment，分析 counterexample 和 proof completeness。
- **EDA / Verification Methodology Engineer**：开发 assertion/coverage flow、reusable checker、regression infrastructure 和 debug automation。

## 24. 真正需要记住的内容

1. SVA 描述的是跨采样周期必须成立的契约，不是另一种 test stimulus。
2. 先用自然语言写清“什么时候触发、何时检查、检查多久”，再翻译成语法。
3. `|->` 从同周期开始检查；`|=>` 从下一周期开始检查。
4. ready/valid 最基本性质是 handshake 才转移，stall 时 valid 和 payload 保持。
5. `$past/$stable` 使用的是采样历史，不等同于任意模拟时间中的值变化。
6. `disable iff` 用于 reset 时取消检查，不只是普通 implication 条件。
7. Assertion 通过不代表场景发生过；必须警惕 vacuous pass，并配合 cover/coverage。
8. Assert DUT 的责任，assume 环境的责任；不要用 assumption 隐藏 DUT bug。
9. Property 应对齐真实 transaction/commit boundary，而不是随便引用一个名字相似的信号。
10. 少量来自 specification、做过 fault injection 的 assertion，胜过大量从未触发或无法解释的模板。
