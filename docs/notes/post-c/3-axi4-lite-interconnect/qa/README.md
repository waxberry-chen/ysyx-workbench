# M3 面试 Q&A：AXI4-Lite 互联

> 更新：2026-10-14，随 S1 Arbiter 实现与验证新增。
> 当前已实现并验证 standalone Arbiter；Xbar/slaves/Core 集成尚未完成。实测范围见 [S1 报告](../1-arbiter.md)。

本文件按有价值的进展更新，不要求每次提交记录。回答用于解释本工程的决策，计划中的能力不表述为已完成。

## 1. 为什么第一版只允许全局一笔事务？代价是什么？

**简短回答：** 我希望先把双 master 的请求归属、AW/W 汇合和响应返回验证清楚，所以用一个服务槽串行处理 read/write。两个 adapter 仍可以各自持有请求，但只有一个进入 fabric。代价是 read/write 不能重叠，慢 slave 或 response backpressure 会阻塞另一个 master；全寄存缓冲还增加固定延迟。

**追问与取舍：** 后续可拆分读写服务槽或支持多 outstanding，但需要相应增加 owner 队列、路由状态与验证。是否值得做要结合系统 CPI/仲裁等待和综合关键路径；S1 尚未有整核性能数据，不能声称该选择改善性能。

**证据：** [设计契约 §3.2](../plan.md#32-全局一笔的精确定义)、[RTL](../../../../../npc/vsrc/bus/ysyx_axi4lite_arbiter.sv)；[S1 的状态与验证范围](../1-arbiter.md)。

## 2. owner 应该在第一次握手后才锁定吗？

**简短回答：** 我的实现先在 IDLE 选择并寄存 owner/type，下一周期才向它开放 READY。预留后不会因另一个请求到达而切换。这样请求 stall 期间的选择稳定，也容易保持接口输出只依赖寄存状态。

**追问与取舍：** “先预留”不是 AXI 要求的唯一实现；组合选择也可以正确，但一旦发布 VALID 就必须保持对应 payload，不能随竞争者变化切换。我的第一版用一个固定周期换取简单的时序与 ownership 边界。代价是若已选 master 不按契约继续发送，服务槽会停住，不能靠重新仲裁撤销事务。

**证据：** RTL `IDLE/COLLECT_R/COLLECT_W` 与 `a02_owner_type_holding`；TB 的 `reset/reserved` 和持续竞争检查。验证遵循合法 master 的 VALID holding 前提。

## 3. W 比 AW 先到时，怎样知道它属于哪笔写？

**简短回答：** 在本模块里只有 LSU 能写，而且 LSU 自身只有一笔事务。Arbiter 可以凭 WVALID 预留 LSU 的写服务槽，先把 WDATA/WSTRB 存入独立槽，再等 AW。收齐后分别向下游发送 AW/W；不能用旧地址去转发 W，也不能要求 AWVALID 与 WVALID 同时出现。

**追问与取舍：** 这依赖本项目“IFU 只读、LSU 单事务”的边界。推广到多个可写 master 时，必须保证 AW 和无地址的 W 属于同一个被选中的 master。Xbar 还需要在接受 AW 后锁存 target；那部分是 S2，当前尚未实现。

**证据：** RTL `aw_have_q/w_have_q`、`aw_sent_q/w_sent_q`；[独立测试台](../../../../../npc/tests/axi4lite_arbiter_tb.cpp)覆盖上下游 AW-first/same/W-first 的全部 9 个组合。真实 LSU adapter 通常同时发布 AWVALID/WVALID，因此额外使用独立 driver。

## 4. 下游 B 已经握手，为什么不能马上释放 owner？

**简短回答：** 下游 B 握手只表示 Arbiter 已接收响应，上游 LSU 可能还没有接收。我把响应放入寄存缓冲，并保持 owner 到上游 B 握手；否则另一笔请求可能覆盖旧 response 或使响应归属丢失。read 的 R 同理。

**追问与取舍：** 有额外 response queue、每项 ownership 和容量跟踪时，可以让请求侧提前继续服务；当前只有一项全局服务槽，所以选择等到上游完成。等待时必须保持 RDATA/RRESP/BRESP 与 VALID，而不是等待 READY 才产生响应。

**证据：** RTL `RESP_R/RESP_W`、`a04_response_blocks_requests` 和 `a01_*_holding`；独立测试中的 64 周期 response hold 与另一 master 持续请求。

## 5. round-robin 是否保证不会死锁或饥饿？

**简短回答：** round-robin 解决的是有服务机会时的公平选择，不能让无限停顿的事务自动结束。我的策略在每笔上游 response 完成后把优先权交给另一 master；前提是 master 补齐 AW/W、slave 响应、上游最终接收响应。在这些前提下，持续请求者不会被另一方连续服务多笔而饿死。

**追问与取舍：** 必须区分 arbitration starvation 与被已授予事务阻塞。RTL 不用 timeout 强行释放 owner，因为那会丢失 AXI 事务。验证环境使用有界延迟和 watchdog，并检查等待请求的超越次数；这是仿真证据，未完成无界 formal proof。

**证据：** `prefer_lsu_q` 只在上游完成时更新；TB 定向检查初始/轮转优先权，随机检查 `overtakes <= 1`。10 个 seed 各完成 1000 笔，范围见 [S1 报告](../1-arbiter.md)。

## 6. reset 中途发生，写操作需要回滚吗？

**简短回答：** reset 会清掉未完成事务及响应状态，但已经在 slave 执行的写不能假设能回滚。例如字符已经输出，reset 也不能收回。我的契约要求系统参与者一起 reset，丢弃旧 epoch 响应，并保证 reset 后不重发旧写。

**追问与取舍：** 统计应区分 completed、reset-aborted 和已发生的 side effect。不能跨 reset 强求 request=response，也不能把清空响应误认为写从未发生。单独 reset 一个 slave 的恢复协议不在当前范围内。

**证据：** 13 个 reset 时点测试；本轮 `10143 accepted = 10132 completed + 11 aborted`。scripted slave 检查 reset 后不重复执行旧事务；真实 UART/存储器的 reset 副作用仍待后续 slave 验证。

## 7. 为什么需要独立总线测试，CPU 跑通不够吗？

**简短回答：** CPU 能产生的通道顺序有限，正常软件也很难稳定命中 AW-only/W-only、长响应反压或特定 reset 时点。我用独立 driver 控制这些情况，再由外部握手 scoreboard 检查数据与归属，不把 DUT 内部 owner 当成参考答案。

**追问与取舍：** SVA 检查局部不变量，scoreboard 检查事务结果，覆盖计数确认场景实际命中。CPU/DiffTest 还要在集成后检查架构状态，几种验证不能互相替代。当前 74 个命中 bin 不是完整 M3 coverage closure，也不是代码覆盖率。

**证据：** [测试台](../../../../../npc/tests/axi4lite_arbiter_tb.cpp)、[T01–T15 总矩阵](../test-plan.md)与 [阶段状态](../test-status.csv)。
