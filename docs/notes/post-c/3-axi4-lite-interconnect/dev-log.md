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
