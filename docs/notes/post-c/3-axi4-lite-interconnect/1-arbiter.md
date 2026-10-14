# M3 S1：双 master AXI4-Lite Arbiter

> 2026-10-14；状态：**S1 PASS，可进入 S2 Xbar/default slave**。
> 运行起点：`4f9356d`；本轮实现尚未提交，精确源码 hash 与归档见 [s1-manifest.json](s1-manifest.json)。

## 1. 实现与边界

新增 [ysyx_axi4lite_arbiter.sv](../../../../npc/vsrc/bus/ysyx_axi4lite_arbiter.sv)，输入为 IFU read-only 和 LSU read/write，输出一套 AXI4-Lite master。端口沿用 `ifu_axi_*`、`lsu_axi_*`、`m_axi_*` 命名，位宽与 [设计计划](plan.md) 一致；模块无地址译码、无 DPI、无存储器副作用。

第一版采用全寄存、全局一笔服务槽。状态路径为：

```text
                COLLECT_R -> SEND_R -> WAIT_R -> RESP_R
IDLE -> reserve                                       -> IDLE
                COLLECT_W -> SEND_W -> WAIT_W -> RESP_W
```

`reserve` 表示 IDLE 边沿选择并寄存 owner/type，不是另一个状态；选择当周期不接受请求，进入 COLLECT 后才开放 READY。reset 后竞争时 IFU 优先，每次上游响应握手后将下次竞争优先权交给另一个 master。

关键责任如下：

- **请求持有**：COLLECT_R 捕获 AR；COLLECT_W 分别捕获 AW/W，支持 WVALID 先出现并握手。W 无地址，因此 Arbiter 只保存 W，不推断 target。
- **向下游发送**：write 收齐 AW/W 后分别驱动两个 VALID，独立记录 sent；一条通道握手后停止发送它，另一条继续保持。地址、PROT、数据、WSTRB 原样转发。
- **响应持有**：R/B 先进入寄存缓冲，仅向原 owner 返回；response code 原样转发。服务槽直到上游 R/B 握手才释放，不能在下游 response 握手时提前让另一笔进入。
- **reset**：清空事务控制和响应状态，关闭所有握手控制。master、Arbiter 和 slave 同时 reset，中止旧事务；已执行的 slave 写不会回滚或被重放。
- **前进性**：在请求最终补齐、slave 最终响应、master 最终接收响应的前提下使用 RR；无限 backpressure 不承诺完成，RTL 没有超时取消逻辑。

没有加入 fall-through、同拍释放/接收或 read/write 并行。理想时序下，上游 read 在边沿 N 被捕获，AR 最早 N+1 完成，下游 R 最早 N+2 捕获，上游 R 最早 N+3 完成；这是状态结构的推导，尚未测量整核 CPI。

S1 使用 standalone top，**未接入 `ysyx_core` 或 production filelist**。Core wrapper、harness、AM profile 仍属于 S4；现有 CPU 系统仍运行 M2 legacy 路径。

### 架构选择依据与代价

当前设计是**以完整事务为轮转单位的两 master round-robin，加上全局 single-outstanding 和寄存缓冲**。只有一个 master 请求时直接选择它；同时竞争时按优先位选择，并在上游响应完成后把优先权交给另一方。轮转单位是事务，不是周期；RR 提供有条件的服务机会公平性，不保证相等的占用时间或带宽。

| 选择 | 当前依据 | 代价 |
| --- | --- | --- |
| 两 master RR | 一个优先位即可实现、检查公平性，作为尚无系统性能数据时的基线 | 没有优先照顾可能阻塞提交的 LSU |
| 全局一笔服务槽 | 两个输入 adapter 本就各自单事务；串行服务可缩小 ownership、返回顺序与 reset 的验证状态空间 | read/write 不并行，慢事务阻塞另一方 |
| 先寄存 owner，再接收请求 | grant 在等待期间稳定，避免接口间组合选择路径 | 增加选择阶段的固定延迟 |
| AW/W 独立缓存，收齐后发送 | W-first 与部分握手的责任清晰，下游只接触收齐的写事务 | AW 早到时无法提前向下游推进 |
| 响应缓冲并持有 owner 至上游完成 | 一项响应缓冲即可保持归属，防止新事务覆盖旧响应 | 下游已空闲时仍可能等待上游接收 |

这些依据来自当前接口约束和初版验证复杂度；全寄存、全局单事务、收齐 AW/W 后发送都是本项目的实现取舍，并非 RR 或 AXI 强制要求。目前尚未通过性能/面积对比证明它们最优。

LSU 优先是后续可比较的方案：当前顺序提交 Core 的访存可能直接阻塞提交，而 IFU 有前端缓冲，但净收益仍需测量。集成后应固定 workload/存储延迟，比较 cycles、仲裁等待、前端停顿及综合结果，再决定是否调整优先级、提前转发 AW、减少寄存阶段或拆分读写服务槽。尤其要关注 Arbiter 与 Xbar 逐层缓存产生的固定延迟叠加。

## 2. 独立验证环境

新增 [axi4lite_arbiter_tb.cpp](../../../../npc/tests/axi4lite_arbiter_tb.cpp)。采用 C++ pin-level driver + scripted AXI slave + transaction scoreboard，不读取 DUT 的 owner/state 等内部信号。

每个 master 在一笔事务完成前只持有一个描述符。driver 可以分别推迟 AWVALID/WVALID 的发布；downstream READY 延迟与其独立。scoreboard 从实际握手记录接受、下游请求、响应、上游完成及 reset 中止，检查：

- 不允许第二个 owner/type 在旧响应完成前被接受。
- 每个 AR/AW/W 只发送一次，所有 payload 与原描述符匹配；输入握手后主动改变输入 payload，检查 DUT 是否真正保存了上下文。
- RDATA/RRESP/BRESP 不串路、不丢失；正常、SLVERR、DECERR 均原样返回。
- 六个 DUT 输出通道和六个 TB 输入通道均有 holding monitor，避免错误 driver 生成非法激励后得到假结论。
- 脚本 slave 在完整 write 被接受时记录一次成功写事件；reset 后不重复发旧请求。这里验证的是 Arbiter 不重发事务，不等同于实际 UART slave 的 exactly-once 验证。
- 每个持续发布请求的等待 master 最多被另一 master 完成一笔事务超越；另用定向用例检查 reset 初始优先权及 IFU 完成后的 LSU 优先权。

每 4096 周期无完成进度则 watchdog 失败。随机激励的发布/READY/response delay 有界；另有 64 周期和 257 周期长停顿定向测试。该 watchdog 是验证环境约束，不是 RTL 的功能性 timeout。

## 3. 实测结果与覆盖范围

复现入口：

```bash
make -C npc b1-arbiter-test
```

入口先 lint，再编译带 `--assert` 的 standalone 仿真程序，运行定向/reset/10 个固定随机 seed。CSV 输出到 `npc/build/b1-arbiter-test/coverage.csv`；可用既有 `OBJ_DIR=<绝对路径>` 改变构建根目录。

| 检查 | 本轮结果 |
| --- | --- |
| Arbiter lint，SVA 开启 | PASS；其余 warning 均为 fatal，仅对下述 reset 诊断作定向豁免 |
| `-DSYNTHESIS` 分支 lint | PASS，无 warning；这只是静态 elaboration，不是综合或 STA |
| T01–T04 Arbiter 定向子集 | PASS：请求/响应 holding、owner、RR、AW/W 分离、response backpressure |
| AW/W 顺序 | ingress × egress 的 AW-first/same/W-first 共 9 个组合全部命中 |
| stalls / response delay | none、short(1–7)、long(≥64) 必测 bin 全命中；另测 257 周期停顿 |
| WSTRB/PROT | 全部 16 种 WSTRB 转发；多种 PROT 随机转发检查，未把 PROT 固定为 Core 常量 |
| response code | IFU read、LSU read/write × OKAY/SLVERR/DECERR 共 9 个 bin 全命中 |
| T08 Arbiter reset 子集 | 13 个场景通过，各场景后重新执行 LSU write、IFU read、LSU read |
| Arbiter 随机测试 | seeds 1–10，每 seed 完成 1000 笔，共 10000 笔 PASS |
| 总事务记账 | accepted=10143，completed=10132，reset_aborted=11；无剩余 outstanding |
| scripted slave 成功写事件 | 893；包含 reset 前已执行、尚未完成上游响应的写，不应仅与正常完成的写数量比较 |
| 机器可读覆盖 | 74 个有命中的 bin；不是代码覆盖率或完整 M3 cross coverage closure |
| legacy 兼容检查 | Core lint 与三个既有 adapter/IFU+adapter 测试 PASS |

13 个 reset 场景为：idle、预留 owner 尚未接受请求、AR 已缓冲、AW-only、W-only、AW/W 均已缓冲、下游 AW-only、下游 W-only、等待 R、等待 B、IFU R 被回压、LSU R 被回压、B 被回压。前两种没有已接受事务，因此中止计数为其余 11 笔。

功能覆盖按实际握手/停顿命中计数，完成时检查必测 ordering/stall/strobe/response bin 非零；reset 场景在到达目标事务阶段并完成恢复检查后记为命中。没有建立完整系统的 route/stall/response 交叉覆盖；不能将这些结果作为 T05–T15 全部通过的证据。

RTL 属性以 `a01_*`、`a02_*`、`a03_*`、`a04_*` 命名，分别关联 payload holding、owner holding/唯一选择、AW/W 汇合、响应唯一归属/占槽。A08 的 reset handshake gating 与 epoch accounting 当前由 C++ monitor 检查。**未运行 formal**，SVA 仿真通过不等于无界协议或公平性证明。

### 本轮具体命令

```bash
verilator --lint-only --sv -Wall -DSYNTHESIS \
  --top-module ysyx_axi4lite_arbiter npc/vsrc/bus/ysyx_axi4lite_arbiter.sv

make -C npc b1-arbiter-test lint \
  ifu-axi4lite-adapter-test ifu-axi4lite-adapter-integ-test \
  lsu-axi4lite-adapter-test
```

使用 Verilator 5.008、G++ 11.4.0、GNU Make 4.3。新 target 没有 `-Wno-fatal`；单独豁免 `SYNCASYNCNET`，因为异步复位状态寄存器和 SVA 的 `disable iff (!rst_n)` 同时使用 reset。`-DSYNTHESIS` 分支关闭验证属性后不需要该豁免。legacy Core lint 仍有既存的 immediate 位域 unused warning。

本轮未重跑 CPU tests/DiffTest：新模块尚未连接 Core，未改变 Core、adapter、RAM 或 AM；S0 的系统基线保持原有范围。集成后必须重新执行系统与异常验证。

## 4. 记录、限制与下一步

初次 strict lint 因 reset/SVA 诊断退出，加入有说明的定向豁免后通过；第一次编译因 ccache 临时目录的沙箱权限失败，获准在沙箱外运行后通过。未观察到 functional mismatch，没有据此编造 RTL bug story。

原始结果归档在 `artifacts/m3-s1-20261014.tar.gz`，包括最终源码副本、构建命令、日志、coverage.csv、测试二进制和源码 hash；位置在 build 之外。摘要和压缩包 hash 见 [s1-manifest.json](s1-manifest.json)，当前仅做本地归档。M3 状态与后续缺口见 [test-status.csv](test-status.csv)。

本轮有价值的设计/验证问答已整理到 [qa/README.md](qa/README.md)。当前无阻塞项。下一步是 **S2 Xbar + default DECERR slave**：沿用已验证的单 master 输出，解决 target 锁存、W-first 尚无地址、边界译码和响应归路；尚不接入 Core 系统。
