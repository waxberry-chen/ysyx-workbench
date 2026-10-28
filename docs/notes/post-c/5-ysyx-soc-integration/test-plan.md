# M5 验收矩阵

> 2026-10-28：S0–S6 完成，M01–M16 的对应阶段范围通过。S5 的 timer/IRQ/AM 见[精选归档](s5-validation/README.md)；S6 的完整有限抢占/唤醒、资源、UART 与系统回归见[实施记录](6-system-validation.md)和[精选归档](s6-validation/README.md)。M17/M18 待 S7/S8。

S0 证据：[manifest](s0-validation/manifest.json)、[61-port 表](s0-validation/cpu-ports.csv)、[生成日志](s0-validation/generation.log)、[静态展开诊断](s0-validation/elaboration-diagnostics.txt)、[容量检查](s0-validation/rtt-budget.txt)。空 CPU stub 只用于静态展开，没有运行指令；242 条上游诊断已分类，不构成全 SoC lint clean。

2026-10-20：改为直接升级当前接口，B1/legacy 兼容不再是 M5 出口。保留并迁移其中有效的 CPU/协议检查，旧配置仅供历史复现；S0 原始证据不改写。

## 必做项与独立预期

| ID / 阶段 | 检查内容与通过条件 | 必须保留的证据 |
| --- | --- | --- |
| M01 / S0：PASS | 固定 upstream/submodules/patch 与生成工具；真实重新生成，61-port ABI一致；空CPU stub静态展开无缺失模块，不含DPI链接/功能验证 | 上述生成日志、manifest、端口表与告警处置 |
| M02 / S0：PASS | 实际地址/容量、20周期共同reset与CPU释放延迟、IRQ固定0、模型缺口及负责阶段已明确；已选4MiB PSRAM路线 | S0 第4–7节、RTT静态预算；动态容量/IRQ/错误响应仍在后续验收 |
| M03 / S1：PASS | AXI byte offset 0/1/2/3、halfword offset 0/2、word 对齐；raw address/size/WSTRB/数据 lane 正确。模拟有读副作用的 byte 寄存器，窄读仅作用目标寄存器 | 独立 bus scoreboard、定向用例、关键波形；不能只在宽容 RAM 模型验证 |
| M04 / S1：PASS | AW 先/W 先/同周期，AR/AW/W/B/R 各通道反压；payload 稳定，RID/BID/RLAST 检查，响应完成前 owner 不变；读写全局 single-outstanding | 断言与事务计数；请求、响应、副作用逐笔相等；无重复 B/R 接收 |
| M05 / S1：PASS | IFU/LSU 同时持续请求的公平性；redirect 时旧取指响应丢弃；SLVERR/DECERR 精确 fault；请求未收/部分写通道已收/等待响应时的共同复位 | accepted/completed/aborted 分类、各状态定向覆盖；延迟有界时无饥饿/超时；非法响应为诊断负例 |
| M06 / S2：PASS | reset 后首个 MROM PC 与数据正确，ebreak 按当前退出约定结束；UART byte store 实际到达目标寄存器，仅输出一个 A | ebreak/uart FST、commit/bus/寄存器 CSV、独立 TX 解码精确 A、32 次精确 fault；见 S2 归档，未用队列打印代替 TX 验证 |
| M07 / S3：PASS | SRAM stack、8/16/32 位访存、软件64位、byte mask、首尾、避栈mem-test、data/bss、全局改写和8次独立异常预期通过 | [S3](3-runtime-difftest.md)：CPU预填2048word；分别移除copy/clear的负例失败；链接容量断言、布局和实际最小sp已记录 |
| M08 / S3：PASS（MROM/SRAM） | 31个正向workload所有提交逐指令比较并核对最终8KiB SRAM；UART/mtime仅单次输入同步，无整状态skip；普通addi结果扰动触发mismatch | [S3证据](s3-validation/README.md)：hello、24个CPU tests、sieve/fib smoke及分类；Flash/PSRAM随S4接通后再加入普通存储差分，未提前计PASS |
| M09 / S4：PASS | SPI 读与映射/XIP 访问一致；目标 RAM 预填图案后由 CPU 从 Flash 搬运，复制边界、data/bss、stack 与入口 PC 正确；超容量镜像构建/加载失败 | [S4 证据](s4-validation/README.md)：SPI 已知内容/XIP、两种启动、4 个 copy/clear 负例、镜像/链接容量负例；CSV 与本地 FST，无 harness 代搬运 |
| M10 / S4：PASS | 验收程序真实容量足够；若启用 PSRAM，完成控制器/模型事务及 byte/half/word、连续/随机地址、首尾/越界、延迟测试，再运行 Flash → PSRAM 程序 | [S4 证据](s4-validation/README.md)：4 MiB PSRAM，宽度/首尾/地址位/300 次固定 seed 混合访问；串行等待、guard 随机背压；34 个 CPU tests、RTT 协作 workload 的真实装载/预算/容量检查。完整水位与抢占留 S6 |
| M11 / S5：PASS | mtime 单调/tick 换算/跨低字溢出读取；mtimecmp 分字写；比较阈值前后 pending；mask=0/1 与 pending=0/1 四组合；只读/不支持 CSR 访问语义 | [S5 证据](s5-validation/README.md)：逐周期 timer 模型、CLINT/CSR 定向、timer-registers 溢出/重装、mip 只读和未知 CSR 自检 |
| M12 / S5：PASS | 精确 IRQ：ALU/branch、空闲、LSU pending、错误响应、同步异常同时出现、redirect、MRET 后仍 pending；保存正确 EPC/cause/MIE/MPIE，无重复 store 或跳过指令 | [S5 证据](s5-validation/README.md)：EXU 优先级、连续 redirect、固定 EPC 的 MRET pending 自检；10 个 seed 各 200 次物理 store/load 与提交数一致，含 FST |
| M13 / S5：PASS | AM timer event、真实中断开关、RV32E 上下文保存恢复；timer cause/EPC 独立验证后再比较 NEMU；中断返回不无条件增加 EPC | [S5 证据](s5-validation/README.md)：三种启动布局 AM、独立 cause/EPC 和 pre/post MTIP、23-word ABI、EPC 扰动/漏恢复 t0 负例、RTT tick smoke |
| M14 / S6：PASS | 有限 RT-Thread：至少两线程无需主动 yield 也能在 tick 下交替取得进展，阻塞/唤醒、上下文、heap/stack 正确；退出有固定 PASS 与超时 | [S6 证据](s6-validation/README.md)：正常/随机等待两种 RTT 运行各 15 IRQ，六轮忙等待交替、sleep 4/6 tick 后唤醒；四个栈独立 SP/图案检查、heap 峰值与归还 |
| M15 / S6：PASS | UART 配置波特率、轮询发送状态；实际 serial TX 解码长字符串，字符数量/顺序一致；系统在固定与随机总线延迟下完成 | [S6 证据](s6-validation/README.md)：divisor=8，正常/固定/随机等待各精确解码 528 字节，THRE 忙轮询与帧采样时间通过；错误接收波特率负例失败 |
| M16 / S1–S6：PASS | 在升级后的 AXI4 接口上验证原有 CPU 语义；S6 已运行 34 个适用 CPU tests、sieve/fib；hello/memory 各固定等待及 10 个随机 seed，实际 SoC 错误路径与独立注入分别验收 | [S1 迁移表](1-axi4-interface.md#6-旧检查点与入口迁移)与[S6 归档](s6-validation/README.md)：协议/CPU/responder 错误/guard 回归、CPU 分类、全部实际命令/seed/超时；unalign 明确排除 |
| M17 / S7 | 真实 DC/PT 对冻结的新 scope 完成；无未解析引用、非预期 latch/loop/未约束功能端点，setup/hold 与电气规则通过，coverage/告警有逐类处置 | manifest、SDC/端口预算、area/qor/timing/DRV/coverage、reset 例外和主要路径；未达标为诊断结果 |
| M18 / S8 | 干净运行目录重建镜像/SoC 仿真；S0–S7 证据对应最终版本；M6 的存储、程序、频率与统计口径固定 | signoff、复现命令、版本/hash、剩余风险、精选波形与 bug case |

## 执行组织

1. S1 协议测试先用独立 AXI responder，逐一控制握手/错误，不依赖真实 SoC 恰好产生所有情况。初始随机目标为 **10 个固定 seed，每 seed 至少 1000 笔完成事务**；必须同时检查定向 bins，事务总数不代替覆盖。
2. SoC 延迟注入作为专用仿真配置，不修改功能 RTL 来制造时序。系统先固定延迟通过，再对 hello/小 mem-test 做 10 个固定 seed；至少对有限 RT-Thread 做正常时序及一个有界延迟配置。若上游协议路径不允许直接插入现有 Lite shim，新增 AXI4 对应实现，不能误用旧 shim。
3. 按阶段运行最小受影响测试：S1 先用可控 AXI4 内存/错误 responder 验证升级后的 CPU 与协议，GPR/CSR/译码等独立测试继续使用；S2/S3 起接真实 SoC，S6 完成 SoC 系统回归。旧 `b1-signoff`/legacy 入口仅对应历史版本，不作为 M5 gate。S1 记录哪些检查直接复用、哪些迁移、哪些仅针对已退役平台而停止，并更新失效入口；新回归命令实施后再记录。
4. CPU tests 按 ISA/对齐策略和容量分类：小 SRAM 阶段允许明确子集；S4 容量闭环后运行适用全组。不能把未运行项算通过。microbench smoke 固定子项/输入规模，不声称完整 benchmark 性能评估。
5. 所有随机测试有 seed、最大等待周期与失败现场；无响应时先报告 timeout，不伪造成功响应。错误注入验证 cause/EPC/副作用，真实 SoC 默认错误路径另做可达性核对。

## 验收边界

普通功能、协议和中断由本地仿真验证；面积/时序需要服务器实测。Verilator 两值仿真不证明 X 安全、亚稳态或 reset 物理时序。原版章节未纳入的设备、formal、四值/GLS、完整 SoC memory macro、PnR/CTS、功耗及全 PVT 不自动计为 PASS。

M17 允许有明确理由且与实际设计相符的 reset/常量条件例外；不允许无法解释的功能路径漏约束或为了通过而忽略违例。所有例外须写明检查对象、依据、影响及后续关闭条件，不能直接照抄 M4 的计数。
