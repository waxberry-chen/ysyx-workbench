# M3 面试 Q&A：AXI4-Lite 互联

> 更新：2026-10-15，随 S5 完整 fabric、RT-Thread 与验收更新。
> 当前 M3 功能/协议仿真验收通过，实测范围见 [S5 报告](../5-closure.md) 与 [signoff](../signoff.md)；formal/四值/EDA 不在此 PASS 内。

本文件按有价值的进展更新，不要求每次提交记录。回答用于解释本工程的决策，计划中的能力不表述为已完成。

## 1. 为什么第一版只允许全局一笔事务？代价是什么？

**简短回答：** 我希望先把双 master 的请求归属、AW/W 汇合和响应返回验证清楚，所以用一个服务槽串行处理 read/write。两个 adapter 仍可以各自持有请求，但只有一个进入 fabric。代价是 read/write 不能重叠，慢 slave 或 response backpressure 会阻塞另一个 master；全寄存缓冲还增加固定延迟。

**追问与取舍：** 后续可拆分读写服务槽或支持多 outstanding，但需要相应增加 owner 队列、路由状态与验证。是否值得做要结合系统 CPI/仲裁等待和综合关键路径；S5 已记录 add 固定 B1 的 16402 cycles / 1095 commits；没有等条件的优化或 Fmax 结果，不能声称该选择改善性能。

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

**追问与取舍：** RV32 分两次读 64-bit 时间仍可能撕裂，所以要 high1-low-high2，高位变化就重试。S3 在低位将溢出时实际触发一次重试，还验证了 64-bit 回绕。S4 已完成 AM 迁移，并以 1 MHz、2 MHz 两种名义频率检查微秒换算；MTIME_HZ 是时间单位配置，不是综合 Fmax。

**证据：** [CLINT RTL](../../../../../npc/vsrc/periph/ysyx_axi4lite_clint.sv) 与 [独立总线测试](../../../../../npc/tests/axi4lite_slaves_tb.cpp)；参考值来自独立时钟计数，不从 DUT mtime 读取生成。

## 15. Verilator 中的 1 MiB SRAM 能直接算作已实现的物理 SRAM 吗？

**简短回答：** 不能。目前是可仿真的 RTL word array 和 AXI 控制，还没有指定 macro、工艺库或映射结果。reset 不清空 array，预装载由仿真 host 在 reset 期间完成；不能把 Verilator 的默认零值当作硬件上电内容。

**追问与取舍：** 后续综合要明确 array 被映射成什么、容量和读写时序如何处理。若用 SRAM macro，需要其功能、面积和时序模型；不能排除存储面积却对外宣称完整 SoC PPA。S4 已统一镜像/零填充、heap/linker 容量和 debugger 真实访问源。

**证据：** [SRAM RTL](../../../../../npc/vsrc/periph/ysyx_axi4lite_sram.sv) 与 S3 的 1 MiB/12 KiB/4 B 回归、reset 内容保留测试；尚无综合/STA 结论。

## 16. 为什么分了 build 目录，仍可能串用两种硬件配置？

**简短回答：** 对象搜索路径也属于构建配置。S4 的 B1 子目录曾通过 Verilator 默认 VPATH=`..` 找到 legacy 的 dut.o，导致 1 MiB DUT 的 DiffTest 初始化仍拷贝 128 MiB 并崩溃。GDB 和反汇编定位后，移除父目录对象搜索，并让 host 对象依赖配置 stamp。

**追问与取舍：** RTL、host 宏、AM 对象、静态库和镜像都要按 profile/容量/频率区分。只改顶层模块名或只重建应用，仍可能链接错误的旧库。最终以 legacy/B1 来回构建和第二组容量/频率运行验证隔离。

**证据：** [S4 bug case 与归档](../4-integration.md)，修复前 crash 日志、修复后 53 个 B1 系统程序和 34 个 legacy CPU tests。

## 17. 接入 RTL SRAM 后，为什么调试器不能继续读 host pmem？

**简短回答：** host pmem 只是装载缓冲，运行中的 store 更新的是 RTL array。继续读 host 缓冲会看到旧值。S4 在初始 reset 把同一内容装入 DUT/REF；运行期 debugger 直接读真实 RTL SRAM，UART 只消费一次 TX 事件。

**追问与取舍：** 仿真 preload 不等于可综合的上电初始化。调试读也不能偷偷产生设备副作用，因此当前 B1 debugger 只支持 SRAM 读，不提供绕过 AXI 的运行期写。

**证据：** 两种容量的 lanes 程序写入末 word，SDB 均观察到 `0x13579bdf`；hello 与双上下文 UART 字节流精确匹配，见 [S4](../4-integration.md)。

## 18. MMIO 被 DiffTest skip 后，错误访问还验证得到吗？

**简短回答：** 必须先处理异常，再处理正常 MMIO skip。B1 的 UART/CLINT 可能返回 SLVERR；此时 REF 不执行原访存，而是在同一架构 PC 引发对应 trap，再比较 GPR/CSR。正常设备读的非确定值才同步 DUT 状态到 REF。

**追问与取舍：** 正常 MMIO skip 本身不证明设备正确，还要独立核对 UART 字节流、mtime 单调/单位和总线错误/副作用。错误旧取指也不能仅因收到 DECERR 就触发 trap，要核对 redirect 后是否仍属于有效指令。

**证据：** S4 的 14 个精确异常用例、65 次 yield trap，以及末端 SRAM 返回时实际产生但未提交异常的 speculative DECERR；S5 已完成含 Arbiter 的 18 个 redirect phase/response/竞争者组合。

## 19. 为什么 CPU tests 全通过，还需要独立的 fabric driver？

**简短回答：** 真实 adapter 通常同时发布 AW/W，也不会任意长时间拒收响应。CPU 程序能验证架构行为，却难以覆盖 W-first、每个通道的 64 周期 stall、复位时半笔写等协议情况。因此 S5 用两个独立 driver 加真实 RTL fabric，逐笔验证 owner、路由、数据和副作用，再用真实 Core 的 DiffTest 补架构检查。

**追问与取舍：** 单层注入也可能留下空洞：Xbar 收齐写后重新同时发 AW/W，因此 Arbiter 后的随机 delay 不保证设备端出现三种握手顺序。我在设备边界也加测试 shim，并按实际握手而不是配置值统计 order/gap。

**证据：** [S5 完整 fabric](../5-closure.md)：10 seeds 各至少 1000 完成，284 个有命中的 bin，最终 10510 = 10350 completed + 160 reset-aborted。

## 20. 随机延迟能直接用随机数门控 VALID 吗？

**简短回答：** 不能让已经发布但未握手的 VALID 下一拍消失。我的测试 shim 为每个通道缓存 payload，在接收时锁存延迟，倒计时完成后持续发布到握手；接受新输入的 READY 可以受门控，但输出不会随随机数撤销。

**追问与取舍：** shim 有寄存级和容量，会改变时序；它属于测试变体，不进入默认生产配置。随机 seed 可复现不等于对不同模型施加了完全相同的延迟序列，也不能拿两种模型的 CPI 差异宣称优化收益。

**证据：** [测试 shim](../../../../../npc/tests/axi4lite_delay_shim.sv) 的 holding assertion，及 add/bubble-sort 各 10 seed 的架构 trace 一致性。

## 21. MMIO skip 的情况下，如何知道 UART 和 timer 真正确？

**简短回答：** DiffTest 负责可比较的架构状态，设备行为由另一个 oracle 检查。S5 按实际 AR 接受边沿的独立计数器计算 mtime 预期，按 AW/W 接受边沿推导写执行；SRAM 实际写脉冲、字节数组和 UART 事件逐周期对照。不能以 DUT 的 target 或 error 输出生成预期。

**追问与取舍：** reset 不能撤销已经发生的字符输出或 SRAM 写。必须把 accepted、completed、aborted 和 effect 分开记账；否则 reset 后重复输出、丢 response 与合法中止容易混在一起。

**证据：** S5 的 69 reset 场景、完整内存扫描、76 个精确 UART 事件以及 high-low-high 拼接值与 low 采样时刻的严格相等检查。

## 22. RT-Thread 跑起来，能说明支持操作系统和中断了吗？

**简短回答：** 当前证明的是固定 RT-Thread kernel/BSP 配置下的协作线程切换和动态内存，不是完整设备或中断系统。两个线程各做 100 次可检查迭代，检查局部状态、heap buffer、交替输出及最终用量恢复，并在 203 次 cause 11 路径上通过 CSR DiffTest。

**追问与取舍：** B1 没有 RX、mtimecmp 或 timer IRQ；我冻结了不依赖这些功能的配置，没有把启动 banner 或 timeout 当成通过。未来接入 timer-preemptive scheduling 需要重新验证中断时序、上下文保存和 BSP 契约。

**证据：** [冻结 workload/config](../../../../../npc/tests/b1-rtthread/)；固定时序与 shim seed 42 的 262561 条架构提交完全一致，见 [S5](../5-closure.md)。

## 23. 必测 coverage 全命中与 formal proof 有什么差别？

**简短回答：** 功能覆盖说明约定的场景实际被激励，assertion/scoreboard 说明这些执行没有发现违例；它不穷举所有可能时序。我的 checker 对合法必测 bin 缺失直接失败，只把 IFU write 等结构性不可达情况标成 N/A。

**追问与取舍：** 无死锁/公平性还依赖环境最终补齐请求、给出响应并允许消费。fabric 的 1024/2048 周期 watchdog 是当前有界仿真的失败条件，不是无界证明。当前机器没有 formal/四值工具，所以 M3 只给功能/协议仿真 PASS。

**证据：** [覆盖汇总](../s5-coverage-summary.csv)、[N/A 原因](../s5-exclusions.csv) 与 [signoff 边界](../signoff.md)。
