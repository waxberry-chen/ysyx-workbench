# GShare BPU 开发日志

## 2026-10-31：建立限定增量计划

- 用户确定目录 `docs/notes/post-c/gshare-bpu`；范围为条件分支与 JAL，GShare + predecode，无 BTB。
- 无 BTB 的依据是当前 Fetch 单 outstanding，响应返回前不能继续发起下一次取指，预期提前供给目标的额外收益有限；本轮未做 BTB 对比，不把预期写成结果。
- 初版计划使用 128 × 2-bit PHT、7-bit 提交 GHR、预测时保存 index、提交时按真实方向训练；JAL 提前计算目标，JALR 保留原执行端恢复。
- 建立 [设计计划](plan.md)、[验收矩阵](test-plan.md)和 [Q&A](qa/README.md)；设置 OFF/JAL_ONLY/GSHARE 对照，沿用 M5 固定程序、真实存储延迟及 S7 DC/PT 条件。
- 已阅读当前 IFU/core/opbuf/EXU、IDU、monitor、scope check 以及本地参考 IFU/BPU；本次只新增规划与路线入口，未修改 RTL、未执行功能或 EDA 验收。
- S0–S5 均待实施，当前无已知前置阻塞。下一步为 S0 接口／参数／测量基线核对；完成整个增量后交接 JOB-PREP-01。

## 2026-10-31：澄清参考参数与 JALR 范围

- 在 plan 中补充参数对照：128 × 2-bit 表规模相同，但 GHR 长度、更新／恢复策略、PC hash 和进入历史的指令范围不同；不声称当前参数已由实验选优。
- 按用户倾向维持 JALR 前端提前处理暂缓，正常 JALR 仍由 EXU 执行；记录参考设计的 x0/x1/通用寄存器路径，以及 NPC 移植所需的读口、依赖、等待／取消、同拍写回和验证增量。
- JALR 提前处理作为未来中等复杂度独立扩展；后续依据恢复开销测量再讨论，不加入当前 S0–S5 验收。仅更新文档，未改变 RTL 或执行测试。

## 2026-10-31：实施 S0–S3，完成 S4 本地性能部分

- 新增 `ysyx_predecode`、`ysyx_gshare`；默认 128×2-bit、7-bit 提交历史。IFU 响应接收时选择下一 PC，IFQ/opbuf 保存预测 index，EXU 按实际／预测 NPC 恢复，正常条件分支提交时训练。保留 JALR 执行端处理、单 outstanding 和 CPU ABI。
- 接入 OFF/JAL_ONLY/GSHARE、只读 BPU monitor/summary 与固定六镜像比较入口。OFF 完全复现 M5 周期／提交序列；三模式 18 次比较均通过，整体 1.114～1.201×，条件分支增量 1.001～1.198×，不把 JAL 收益全算给方向表。
- 单元独立模型、30000 拍 IFU scoreboard、EXU 恢复矩阵、两项检查器负例通过。新增五类错误路径及 OFF/GSHARE IRQ 共 12 次真实 SoC 定向通过，补充总线请求／错误响应证据。
- M5 S3～S6 适用功能全组通过：146 次真实 SoC 正向运行、3372127 条差分提交、47 IRQ，原有 26 项预期失败检查通过。真实 UART、随机 AXI delay、RT-Thread 抢占／唤醒／资源检查保留。详见 S3 及 validation。
- 记录并修正 Verilator 数组 reset 展开限制、测试 JAL WB mux 选择、assembler 远 branch 展开和 flow 宏白名单；没有为绕过检查而改动参考模型或软件功能。失败原因见 [实施问题摘录](validation/development-failures.md)。
- Flow 增加两份对照配置及模式追溯；本地 12 个 scope profile、57 个 mock 检查通过。保持 SDC、Ultra、cap90 与原 PVT/5 ns 条件。
- **服务器 DC/PT 待用户手动执行并回传；S4 未完整关闭，S5 未最终冻结。** 本地未发现遗留功能阻塞，命令见 S4。最终关闭后交接 JOB-PREP-01，不自动扩展 cache/BTB。
- 保留已有 `ysyx_soc_cpu.sv` 注释、roadmap 规划和 ysyxSoC 子模块工作区；本次未执行 git add/commit。
