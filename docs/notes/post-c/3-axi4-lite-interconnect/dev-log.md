# M3 开发日志

设计契约：[plan.md](plan.md)；验收矩阵：[test-plan.md](test-plan.md)。

## 2026-10-14：建立设计与验收计划

### 本次完成

- 阅读展示入口、post-c roadmap、M2 plan/interface freeze/sign-off、NPC Makefile 与测试脚本、当前 Core/adapters、C++ RAM/MMIO/DiffTest、AM NPC timer/heap/linker 和本地 RT-Thread AM BSP。
- 核对[官方 B1 讲义](https://ysyx.oscc.cc/docs/2407/b/1.html)与本地 AXI4-Lite write-strobe 规范，区分课程练习范围和本项目的具体设计选择。
- 建立 M3 计划、T01–T15 测试矩阵与本文；尚未新增 RTL、测试代码或 Make target，未运行 RTL/CPU/RT-Thread 回归。
- 在 roadmap 的 M3 段落增加入口；检查本地文档链接、代码围栏与 T01–T15 条目完整性，均通过。

读取时 HEAD 为 `c6dd719`（文档更新），M2 已提交实现基线为 `5b6f29c`。初始工作区有未跟踪的 `npc/ref-flow/`；本次未修改或审计其内容。

### 关键设计决定

1. 全局单事务、RR 仲裁，先寄存 owner/type 再独立接收 AW/W，响应由原 owner 接收后才释放；Xbar 在地址握手时锁存 target。
2. 保留当前双 master `ysyx_core` 作为内部模块与 M2 验证对象，新增单 master wrapper 和 B1 system top。
3. B1 沿用 UART/mtime 基地址；SRAM 初始配置 1 MiB、容量参数贯穿 RTL/harness/AM，实际 workload fit 尚待验证。
4. SRAM 支持全部 WSTRB；UART 限定 lane0/zero；CLINT 只读。正常非法访问经 DECERR/SLVERR 返回，不让 host abort 代替异常。
5. mtime 为 RTL 周期计数器，AM high-low-high 重试；日历能力关闭。确定性名义频率与 host 速率校准实验分开记录。
6. legacy/b1 构建与验收分开；旧固定取指事务数、RAM 错误日志、RTC 日历和 128 MiB heap 契约不能原样套用到新系统。

### 当前状态与下一步

| 项目 | 状态 |
| --- | --- |
| 设计契约与测试矩阵 | 已写入文档，实施过程中若修改须记录原因和受影响测试 |
| Arbiter/Xbar/slaves RTL | 未开始 |
| 新测试、coverage、回归入口 | 未开始 |
| B1 harness/AM/RT-Thread | 待迁移与验证 |
| 首次综合/STA | 待单独审计 flow、工具与库；本次未声称可运行 |
| 阻塞项 | 当前无阻塞 S0/S1 的外部输入；容量、BSP 与工具条件是对应后续步骤的待验证项 |

下一步按 S0 保存可复现的 M2 最小基线，然后实现 Arbiter 与 T01–T04/T08 对应的独立测试。Xbar、slaves 和软件迁移在各自步骤推进，避免一开始同时改动所有层次。

后续每次记录：改变了什么契约/实现、为何改变、实际测试命令与结果、未验证范围、阻塞与下一步。失败实验和覆盖空洞同样保留；正式 M3 sign-off 另建报告，不回填虚构的历史数据。

## 2026-10-14：S0 基线保存与最小回归完成

状态：**PASS，无未解决阻塞，可进入 S1**。详细配置、命令、结果与归档说明见 [0-baseline.md](0-baseline.md)，结构化记录见 [s0-manifest.json](s0-manifest.json)。

- 运行起点为 `94dbfd1`，主仓库和 am-kernels 工作区干净；确认 NPC RTL/仿真/构建和受管理的 AM/NEMU 源码与 `5b6f29c` 相同。
- 使用新的 `npc/build/m3-s0-20261014-legacy/` 构建 NPC/模块测试；AM/workload 沿用增量构建，reference 使用已有共享库，精确输入均归档并计算 SHA-256。
- lint、7 个模块/集成测试、5 个 access-fault/misaligned 程序、add/bubble-sort、add seeds 1–10 均通过；系统测试 DiffTest ON。
- 固定 add 的架构与 full trace hash 均复现 M2；补充无额外随机停顿的 add/bubble-sort/hello 样本，cycles 分别为 5405/631047/2471。未运行全量 34 项 CPU tests、RTC、yield-os 或 RT-Thread。
- 核对 M3 输入端口与事务语义；明确 S0 独立 OBJ_DIR 与 S4 profile/AM 构建隔离的区别。当前 `NPC_PLATFORM` 仍未实现，不能用传入该变量的 legacy 运行冒充 B1 验证。
- 建立 [test-status.csv](test-status.csv)，覆盖 T01–T15 及对应 A/C ID，M3 实施和验证状态仍为未开始。
- 日志、镜像、二进制、配置、330 个源码文件及 hash 保存到 build 之外的本地 `artifacts/m3-s0-20261014.tar.gz`；归档 digest 见 manifest，不提交原始构建产物。

失败与处理：第一次因嵌套 Mdir 父目录不存在失败，创建 OBJ_DIR 后解决；第二次因沙箱阻止 ccache 写临时目录失败，获得沙箱外运行许可后原回归通过。保留两次失败日志，未为此修改 RTL。已知 lint unused 位域和 host 头文件宏重定义 warning 单独记录。

本轮未改 RTL、harness、AM 或构建脚本。下一步只进入 Arbiter 与 T01–T04/T08 的 S1 范围；后续容量、AM timer、RT-Thread 与 EDA 待验证项继续保留。

## 2026-10-14：S1 Arbiter 实现与独立验证完成

状态：**S1 PASS，无阻塞，可进入 S2**。报告：[1-arbiter.md](1-arbiter.md)；实测 manifest：[s1-manifest.json](s1-manifest.json)。运行起点为 `4f9356d`，初始主仓库工作区干净。

- 新增 `ysyx_axi4lite_arbiter.sv`：先预留 owner/type，独立缓存 AW/W、独立发送、寄存响应，直到上游响应握手才释放全局服务槽；采用两 master RR。
- 新增独立 C++ AXI driver/scripted slave/scoreboard，不读取 DUT 内部状态；检查输出和输入双方 holding、请求唯一性、payload、错误码、owner、前进性及 reset epoch。
- 新增 `b1-arbiter-lint` / `b1-arbiter-test`，后者自动运行定向、13 类 reset 和 seeds 1–10 每 seed 1000 笔随机事务，输出 74 个命中 coverage bin。
- T01–T04/T08 的 Arbiter 子集通过；总接受 10143 笔、完成 10132 笔、reset 中止 11 笔，无剩余 outstanding。上下游 AW/W 顺序的 9 个组合均命中。
- 最终 SVA lint、关闭属性的 synthesis 分支 lint、Core lint 和三个既有 adapter 测试通过。未运行 formal、真实综合/STA，也未重跑未受影响的 CPU/DiffTest 系统基线。
- 新模块尚未接入 Core/filelist；Xbar、真实 slave、wrapper 与 AM/harness 均未改动。更新状态表时使用 `ARBITER_PASS`，不将整个 M3 的 T01–T15 标为完成。
- 按 roadmap 的有价值进展规则新增 [qa/README.md](qa/README.md)，记录单事务取舍、owner 预留、AW/W 分离、响应回压、公平性前提、reset 与独立验证。

问题记录：最初 strict lint 报 reset/SVA 的 `SYNCASYNCNET`，在新测试入口只豁免这一项并说明原因，其他 RTL warnings 仍为 fatal；关闭 SVA 的 synthesis 分支 lint 无告警。编译再次遇到 ccache 沙箱权限，获准沙箱外执行后通过。没有观察到功能性错误。

最终源码副本、命令、日志、coverage 和测试程序归档在 build 外的 `artifacts/m3-s1-20261014.tar.gz`；对应 hash 见 manifest。下一步实现 S2 的 target holding、地址 decode、default DECERR 及独立验证，沿用 S1 单 master 输出。

## 2026-10-14：S2 Xbar/default 实现与独立验证完成

状态：**S2 PASS，无阻塞，可进入 S3**。报告：[2-xbar.md](2-xbar.md)；源码/日志/归档摘要：[s2-manifest.json](s2-manifest.json)。运行起点为 `be83ff5`，初始工作区干净。

- 实现四路范围译码、AR/AW 握手锁存 target、W-first 独立缓存、AW/W 独立转发与寄存响应；仅目标端口允许握手。
- 实现独立 DECERR slave，read 返回零数据，write 收齐 AW/W 后返回错误，包含 WSTRB=0；共同 reset 丢弃旧响应。
- 新增 `b1-xbar-test`（含 default 独立测试）和 `b1-xbar-config-test`；默认 1 MiB 与 12 KiB 各通过定向及 seeds 1–10 × 1000 笔随机测试。
- 每个容量配置的 Xbar 记账为 10488 accepted / 10446 completed / 42 aborted，215 个 bin；DECERR 独立测试为 328 / 317 / 11，65 个 bin。四路各 12 个 reset 阶段及真实 default 连接恢复通过。
- 七个容量守卫用例通过，其中四个非法配置按预期拒绝；SVA lint、synthesis 分支静态 lint、S1 Arbiter 回归通过。未运行真实综合/STA、formal 或 Core 系统回归。
- 处理 ccache 沙箱权限、Verilator 5.008 顶层数组/SVA 生成 C++ 不兼容及无尺寸零参数告警；修正 TB 缩进告警与误计真实 DECERR 为成功写的统计，保留失败日志。未观察到 RTL 功能 mismatch。
- 更新阶段状态及有价值的 Q&A。未改变 production filelist、Core、harness、AM/NEMU；mapped slave 的 SLVERR、SRAM 字节写、UART/CLINT 副作用仍待 S3。

原始日志、源码、CSV 与测试程序已保存到 build 外的 `artifacts/m3-s2-20261014.tar.gz`。当前无未解决阻塞；下一步 S3 SRAM/UART/CLINT。

## 2026-10-14：S3 SRAM/UART/CLINT 实现与独立验证完成

状态：**S3 PASS，无阻塞，可进入 S4**。报告：[3-slaves.md](3-slaves.md)；证据：[s3-manifest.json](s3-manifest.json)。运行起点 `6fb1750`，初始工作区干净。

- 新增公共 slave frontend：AR 边沿采样，独立 AW/W 槽，收齐后的独立执行阶段，寄存 R/B，read/write 串行和 RR。
- SRAM 支持全部 16 个 strobe、完整范围/对齐检查、reset 保留内容；UART 用单周期 tx 事件连接始终可消费的仿真 sink；CLINT 按时钟计数、AR 边沿采样、reset 清零。
- 明确 data-write 权限：mapped slave 拒绝 AWPROT[2]=1，包括零 strobe；低两位不实施权限隔离。正常 Core 的请求编码不受影响。
- 新增 `b1-slaves-test` 与 `b1-slaves-config-test`。1 MiB、12 KiB、4 B 均完成 seeds 1–10 × 三设备 × 1000 笔；每种容量总记账 32125 accepted / 32107 completed / 18 aborted，436 个 coverage bin。
- 全部 byte mask × 首末 word、错误访问无副作用、UART 字符流、24 个 reset 场景、CLINT 低位/64-bit rollover 均通过；high-low-high 实际重试一次。
- 三种容量各观察 93 个 UART 事件、核对 2442 笔非零 mask 的 SRAM 写。六个参数守卫用例、strict SVA lint、synthesis 分支静态 lint、S2 Xbar/default 回归通过。
- 首次编译遇 ccache 沙箱权限，授权后通过；首轮功能测试已通过，后续补强 reset 数据差异、非法地址零 strobe 和最小容量边界。没有观察到 RTL 功能 mismatch。
- 仿真 host 只在初始 reset 装载 SRAM，mtime 预置只用于 rollover 实验；正常事务由 AXI 驱动。具体镜像 loader、harness 输出、AM timer/容量和 Core 集成仍在 S4。

本轮未修改 production Core/filelist、harness、AM/NEMU，未重跑 CPU/DiffTest，也未执行实际综合/STA/formal。更新阶段状态、Q&A 与展示入口；源码、日志、CSV 和测试程序归档到 build 外的 `artifacts/m3-s3-20261014.tar.gz`。下一步 S4 系统集成。

## 2026-10-14：S4 Core/B1 系统集成完成

状态：**S4 PASS，无未解决阻塞，可进入 S5**。报告：[4-integration.md](4-integration.md)；证据：[s4-manifest.json](s4-manifest.json)。起点 `d5d4fcf`，初始工作区干净。

- 新增 Core+Arbiter、B1 两个 wrapper 与独立 filelist/profile；harness 负责有界 preload、真实 RTL SRAM 调试读取、UART event sink 和被动统计，B1 不链接旧 C++ slave。
- AM 的容量、heap/linker、对象/库/镜像路径及 high-low-high/MTIME_HZ/has_rtc 契约统一。默认 1 MiB / 1 MHz；另测 256 KiB / 2 MHz。
- 默认配置 53 个有限程序 PASS：34 CPU、hello、lanes、uptime、有限 yield-os、14 个异常、SRAM 末端 redirect；全部 DiffTest ON。第二配置的 3 个 AM 程序通过；debugger/loader/参数/watchdog 与链接容量负例通过。
- legacy 34 CPU、固定 add trace、原 IFU+adapter redirect 和 cause 1/4/5/6/7 通过。B1 add 1095 commits / 16402 cycles，与 legacy 架构 trace hash 一致；时序模型不同，不宣称 PPA 或优化收益。
- 实际修复 Verilator VPATH 复用父目录 legacy 对象导致 B1 DiffTest 初始化按 128 MiB 拷贝并崩溃的问题。测试开发还修正 UART 预期、AM TEST/NAME 递归传参、头文件和裸机 PIE 选项；未观察到最终 RTL 功能 mismatch。
- 三顶层 lint 只有既有 immediate 未使用位告警。源码、镜像、reference、逐项日志、commit/UART trace、CSV 与工具版本归档到 build 外；更新 Q&A 与展示入口。

S5 保留完整 fabric 随机 shim/scoreboard、redirect phase × response/reset 交叉覆盖、RT-Thread、波形及 M3 closure。当前没有综合/STA/formal/PPA 结果，不将 S4 通过等同于 M3 sign-off。

## 2026-10-15：S5 完整互联、RT-Thread 与功能仿真 closure 完成

状态：**S5 PASS，M3 功能/协议仿真 sign-off PASS，无未解决功能阻塞**。报告：[5-closure.md](5-closure.md)，验收范围：[signoff.md](signoff.md)，证据：[s5-manifest.json](s5-manifest.json)。起点 `5947ffd`，初始工作区干净。

- 增加测试专用五通道寄存 delay shim，生产默认无 shim；真实 Core 变体与默认构建隔离。新增完整双 master + Arbiter/Xbar/真实设备 scoreboard，检查 byte memory、独立 mtime、实际写执行/UART 事件、owner/RR/路由/响应、reset epoch。
- 最终 fabric 为 10510 accepted / 10350 completed / 160 aborted，780 个成功非零 write effect（704 SRAM、76 UART），371658 cycles，284 个 bin；10 seeds 各至少 1000 completed。覆盖 69 reset 场景、全部 strobe/合法 response cross、五通道 0/1/7/64/129 stall 与实际 AW/W 顺序/gap。
- IFU+adapter+Arbiter 的 18 个 redirect phase/response/LSU 竞争组合通过；保留 M2 定向测试与真实 Core stale DECERR 用例。模块回归、参数守卫、三顶层 lint 通过。
- S4 系统入口 53/53 通过，yield-os 扩大到每上下文 100 次；另有 add/bubble-sort 各 10 seed、RT-Thread 固定/shim、空参数 hello，共 23/23。架构 trace 对照均一致；legacy 固定 add trace 通过。
- 冻结 RT-Thread `beb7fa1` 的最小 kernel + AM BSP context 配置，双线程各 100 次、heap buffer/释放后用量与 203 次 trap 检查通过。修正测试首次假定同优先级 ready queue 插入顺序的问题，不修改 scheduler；默认 1 MiB 足够此配置。
- 真实 VCD 与三段 SVG、覆盖汇总/N/A、源码/BSP/config/镜像/hash 和日志归档到 build 外。新增一条 `b1-signoff` 聚合入口与单独的 directed/random/system/coverage 入口，并更新有价值的 Q&A。
- 开发期补上仅在 Arbiter 后加 shim 时无法命中下游三种 AW/W 顺序的覆盖 hole，修正 TB 波形采样/类型、观察信号和实际 gap 统计；最终未发现生产 RTL 功能 mismatch。ccache 沙箱权限经授权解除。

本机未找到 sby/yosys/iverilog，formal/四值未运行；DC/PT、SRAM macro、网表/功耗/PnR 仍无结果。下一步 M4 审计工具/工艺输入与最小 synthesis+STA flow，形成首版实现基线。
