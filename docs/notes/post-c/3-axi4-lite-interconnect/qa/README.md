# M3 面试 Q&A：AXI4-Lite 互联

> 更新：2026-10-14，随 S3 SRAM/UART/CLINT 实现与验证更新。
> 当前已验证 standalone Arbiter、Xbar/default、SRAM/UART/CLINT；完整 fabric 与 Core 集成尚未完成。实测范围见 [S1 报告](../1-arbiter.md)、[S2 报告](../2-xbar.md)、[S3 报告](../3-slaves.md)。

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

**追问与取舍：** 这依赖本项目“IFU 只读、LSU 单事务”的边界。推广到多个可写 master 时，必须保证 AW 和无地址的 W 属于同一个被选中的 master。S2 Xbar 在接受 AW 后锁存 target；W-first 时 target 无效，不向任何 slave 转发，具体见下文。

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

**证据：** S1 的 13 个 reset 时点测试；该轮 `10143 accepted = 10132 completed + 11 aborted`。scripted slave 检查 reset 后不重复执行旧事务；S3 又以真实 UART/SRAM/CLINT 的 24 个 reset 场景验证不重放字符、保留内存和 timer 清零；完整系统 reset 仍待集成。

## 7. 为什么需要独立总线测试，CPU 跑通不够吗？

**简短回答：** CPU 能产生的通道顺序有限，正常软件也很难稳定命中 AW-only/W-only、长响应反压或特定 reset 时点。我用独立 driver 控制这些情况，再由外部握手 scoreboard 检查数据与归属，不把 DUT 内部 owner 当成参考答案。

**追问与取舍：** SVA 检查局部不变量，scoreboard 检查事务结果，覆盖计数确认场景实际命中。CPU/DiffTest 还要在集成后检查架构状态，几种验证不能互相替代。S1 的 74 个命中 bin 不是完整 M3 coverage closure，也不是代码覆盖率。

**证据：** [测试台](../../../../../npc/tests/axi4lite_arbiter_tb.cpp)、[T01–T15 总矩阵](../test-plan.md)与 [阶段状态](../test-status.csv)。

## 8. Xbar 为什么需要 target_valid？AWADDR 保持不就够了吗？

**简短回答：** AW 还没被接受时，当前 AWADDR 可能没有意义；上次事务留下的地址也不能用于本次 W。我的 Xbar 在 AW 握手时同时锁存地址和 target，并置 target_valid。W-first 只保存数据，收齐后才向目标发送。上游握手后可以改变地址，因此转发和响应归路都必须用已保存的上下文。

**追问与取舍：** target 一直保持到上游 response 握手；下游完成不等于上游完成。收齐再发送增加延迟，但简化第一版写事务归属；未来提前发送 AW 需要重新验证部分发送、reset 与占槽行为。

**证据：** [Xbar RTL](../../../../../npc/vsrc/bus/ysyx_axi4lite_xbar.sv) 的 `target_valid_q`、`a05_target_holding`；[S2 测试](../2-xbar.md) 覆盖四路 W-first、握手后输入地址变化、响应反压及 reset。

## 9. DECERR 和 SLVERR 的责任分别在哪里？为什么错误 slave 也要等 W？

**简短回答：** 地址不在任何窗口内，由 Xbar 选择 default slave 返回 DECERR；地址映射到了设备，但操作不合法，由设备返回 SLVERR。即使已经知道地址无效，AXI 写响应也必须等 AW/W 都被接受，不能收到 AW 就提前回 B，否则留下的 W 可能污染下一笔事务。

**追问与取舍：** default 不做存储/设备访问，WSTRB=0 也不能把未映射地址变成成功。它返回稳定的 DECERR，读数据为零，等待上游接收，然后才能服务新事务。Xbar 原样转发 mapped 未对齐地址；不能把地址对齐后误访问另一个合法寄存器。S2 已验证 default；S3 已独立验证 mapped slave 的 SLVERR 生成和无副作用，完整 fabric 的端到端传播仍待集成。

**证据：** [DECERR RTL](../../../../../npc/vsrc/bus/ysyx_axi4lite_decerr.sv)、[直接 slave 测试](../../../../../npc/tests/axi4lite_decerr_tb.cpp)及 Xbar/default 连接回归；错误后继续运行 mapped 请求。

## 10. SRAM 容量为什么用范围比较，如何避免地址镜像和加法溢出？

**简短回答：** 只截取地址低位做索引可能把越界地址映射回 SRAM。Xbar 先比较完整地址是否在 `[base, base+bytes)` 内，结束地址用 33-bit 计算，并拒绝零容量、未对齐、溢出或与 MMIO 重叠的配置。SRAM 自身也检查完整范围和对齐，再按相对索引访问；S3 已用同一容量参数验证索引和边界。

**追问与取舍：** 不依赖 2 的幂次容量可以让边界更明确，但不能据此宣称面积更优。验证应包含第一/最后合法 word、结束地址、未对齐末字节和镜像风险地址，并换一个非 2 的幂次容量重跑，避免测试和实现共享同一错误假设。

**证据：** [S2 报告](../2-xbar.md)：1 MiB 与 12 KiB 完整回归、七种参数守卫检查。尚无真实 SRAM macro 或综合 PPA 结论。

## 11. 为什么把公共 AXI 控制和设备逻辑分开？

**简短回答：** 三个 slave 都需要独立收 AW/W、串行处理事务、保持 R/B，并在 reset 时清理控制状态。我把这些放进同一个 frontend，设备后端只决定读值、合法性和副作用，减少三份握手逻辑各自演化的风险。

**追问与取舍：** 当前后端时序是固定的：AR 握手边沿采样读数据，AW/W 收齐后下一边沿执行一次写。它没有通用的可变延迟后端握手；换 SRAM macro 时要重新核对时序，不能只替换 array 后就宣称完成适配。

**证据：** [frontend RTL](../../../../../npc/vsrc/bus/ysyx_axi4lite_slave_frontend.sv) 与 [S3 报告](../3-slaves.md)，三个设备均通过独立 AW/W 顺序和长响应反压测试。

## 12. UART 为什么在写执行时输出，而不是每次 BVALID 时输出？

**简短回答：** BVALID 可能因 BREADY=0 持续很多周期，它表达的是同一个未被消费的响应。UART 的副作用只在完整写执行边沿发生一次，输出一个周期的 tx_valid；之后无论 B 等多久，都只保持响应，不重新输出。

**追问与取舍：** 本项目 sink 必须每周期能接收。如果将来连接有流控的串口或 FIFO，就需要明确事件接受与缓冲契约。reset 只能丢弃未完成控制状态，不能收回已输出字符；验证要分别数事件、完成响应和 reset-aborted。

**证据：** [UART RTL](../../../../../npc/vsrc/periph/ysyx_axi4lite_uart.sv) 的 A09 属性；S3 每种容量观察 93 个正确字节，包含完整字符串、长 B hold 和已执行写后的 reset。

## 13. WSTRB=0 是不是所有设备都应该成功？

**简短回答：** strobe 表示哪些 byte 被写，不等于绕过地址或权限检查。我的 SRAM 在合法 data-write 地址上把零 strobe 当作 OKAY no-op；UART 的合法 TX word 也如此。CLINT 只读，任何写都返回 SLVERR；default 对未映射地址仍返回 DECERR。

**追问与取舍：** SRAM 对稀疏 strobe 逐 byte 更新，支持全部 16 种；UART 只接受 lane0 或 zero。非法地址、未对齐地址或 instruction-tagged write 不能因 strobe 为零而变成成功。这些设备权限是本项目策略，不能泛化成所有 AXI slave 的固定规则。

**证据：** [S3 的 byte mask 与错误用例](../3-slaves.md)，包括首末 word、非法地址零 strobe、全部 PROT 和写后内容核对。

## 14. mtime 在 R 被反压时还会增长，为什么读值不能跟着变？

**简短回答：** RVALID 一旦发布，RDATA 必须保持到握手。我在 AR 接受边沿采样更新前的 mtime 半字，之后由响应寄存器保持；计数器继续走。这使一次总线读有明确采样点。

**追问与取舍：** RV32 分两次读 64-bit 时间仍可能撕裂，所以要 high1-low-high2，高位变化就重试。S3 在低位将溢出时实际触发一次重试，还验证了 64-bit 回绕。AM 迁移和微秒换算属于 S4；名义 MTIME_HZ 只是时间单位配置，不是综合 Fmax。

**证据：** [CLINT RTL](../../../../../npc/vsrc/periph/ysyx_axi4lite_clint.sv) 与 [独立总线测试](../../../../../npc/tests/axi4lite_slaves_tb.cpp)；参考值来自独立时钟计数，不从 DUT mtime 读取生成。

## 15. Verilator 中的 1 MiB SRAM 能直接算作已实现的物理 SRAM 吗？

**简短回答：** 不能。目前是可仿真的 RTL word array 和 AXI 控制，还没有指定 macro、工艺库或映射结果。reset 不清空 array，预装载由仿真 host 在 reset 期间完成；不能把 Verilator 的默认零值当作硬件上电内容。

**追问与取舍：** 后续综合要明确 array 被映射成什么、容量和读写时序如何处理。若用 SRAM macro，需要其功能、面积和时序模型；不能排除存储面积却对外宣称完整 SoC PPA。镜像、BSS、heap 和 debugger 的真实访问源还要在 S4 对齐。

**证据：** [SRAM RTL](../../../../../npc/vsrc/periph/ysyx_axi4lite_sram.sv) 与 S3 的 1 MiB/12 KiB/4 B 回归、reset 内容保留测试；尚无综合/STA 结论。
