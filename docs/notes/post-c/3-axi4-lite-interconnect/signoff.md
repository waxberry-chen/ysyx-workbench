# M3 B1 功能与协议仿真验收

2026-10-15；**PASS**。S0–S5 规定的功能/协议仿真出口完成，当前无未解决功能阻塞。此结论适用于本工程单时钟、全局单事务 AXI4-Lite B1 系统及下述输入配置，不代表完整 ISA compliance、formal 或物理实现 sign-off。

- **设计**：双 master Core adapters → RR Arbiter → 四路 Xbar → RTL SRAM、最小 UART TX、只读 mtime、DECERR。生产 Core wrapper 对外为一套 master；默认生产构建不含随机 shim。
- **系统**：1 MiB SRAM、MTIME_HZ=1 MHz、RV32E AM workload、NEMU GPR/CSR DiffTest。53 个有限系统程序通过；额外 20 个随机 CPU runs、2 个 RT-Thread runs、空参数 hello 通过。
- **独立验证**：12 KiB 完整 fabric 的 10510 accepted / 10350 completed / 160 reset-aborted；10 seeds 各至少 1000 完成；69 reset 场景，全部 mask 与合法 response/route 组合通过。IFU+adapter+Arbiter 的 18 个 redirect 组合通过。
- **交付**：[实施与结果](5-closure.md)、[T01–T15 状态](test-status.csv)、[必测覆盖汇总](s5-coverage-summary.csv)、[N/A 原因](s5-exclusions.csv)、[源码及归档 manifest](s5-manifest.json)、[实际波形](waveforms/index.json)、[设计 Q&A](qa/README.md)。可复现入口：`make -C npc b1-signoff`。

版本标识为 S5 起点 `5947ffddd01b20df581e52375c8e7e8b3dcb52d1` 加 manifest 中候选源码 SHA-256；用户后续提交时由 Git commit 固化，不自动创建 tag。RT-Thread 为本地 `beb7fa16e7d282c9409cfbb78225249d193e276e`，使用仓库内冻结的最小协作配置，双线程各 100 次迭代和 heap 恢复检查通过；不声称 RX 或定时抢占可用。

S1–S3 模块验证及 S4 基线的历史范围见 [Arbiter](1-arbiter.md)、[Xbar](2-xbar.md)、[slaves](3-slaves.md)、[系统集成](4-integration.md)。S5 的精确最终命令/日志保存在长期本地归档，build 目录可清理；尚未建立远程备份。

已知边界继续保留：RTL array 未映射物理 SRAM；UART 无 RX/波特率/引脚；CLINT 无 mtimecmp/interrupt；RTL 仍有 32 项 GPR，RV32E 编码合规未完整收尾；Lite 接口不能恢复窄 MMIO read size。formal/四值工具本机不可用，相关结果未运行；无 DC/PT、功耗、网表或 PnR 结果。**进入 M4 准备实现基线，不能把本次仿真 PASS 写成完整 SoC PPA 或 tapeout 成果。**
