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
