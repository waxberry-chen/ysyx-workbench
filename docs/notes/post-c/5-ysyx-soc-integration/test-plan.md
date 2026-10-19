# M5 验收矩阵

> 2026-10-19：以下均为计划，尚未执行。阶段定义见 [plan](plan.md)。后续填写真实命令、输入版本、日志/波形及结论；不是运行一次 hello 就将整行标为 PASS。

## 必做项与独立预期

| ID / 阶段 | 检查内容与通过条件 | 必须保留的证据 |
| --- | --- | --- |
| M01 / S0 | 固定 upstream/submodules/patch 与生成工具；从约定入口生成 SoC，实际端口与 wrapper 契约一致，无依赖未解析 | revision、工具版本、命令、生成文件 hash、接口表 |
| M02 / S0 | 地址译码窗口与真实容量分别列出；CPU/SoC reset 域、极性/释放、外部 IRQ 源和模型缺口明确；RTT 容量路线已选定 | map/容量预算、reset 表、缺口处置表；未确认项不标完成 |
| M03 / S1 | AXI byte offset 0/1/2/3、halfword offset 0/2、word 对齐；raw address/size/WSTRB/数据 lane 正确。模拟有读副作用的 byte 寄存器，窄读仅作用目标寄存器 | 独立 bus scoreboard、定向用例、关键波形；不能只在宽容 RAM 模型验证 |
| M04 / S1 | AW 先/W 先/同周期，AR/AW/W/B/R 各通道反压；payload 稳定，RID/BID/RLAST 检查，响应完成前 owner 不变；读写全局 single-outstanding | 断言与事务计数；请求、响应、副作用逐笔相等；无重复 B/R 接收 |
| M05 / S1 | IFU/LSU 同时持续请求的公平性；redirect 时旧取指响应丢弃；SLVERR/DECERR 精确 fault；请求未收/部分写通道已收/等待响应时的共同复位 | accepted/completed/aborted 分类、各状态定向覆盖；延迟有界时无饥饿/超时；非法响应为诊断负例 |
| M06 / S2 | reset 后首个 MROM PC 与数据正确，ebreak 按当前退出约定结束；UART byte store 实际到达目标寄存器，仅输出一个 A | 取指/commit 与 UART 写波形、退出码；此时队列打印只能证明早期通路 |
| M07 / S3 | SRAM stack、8/16/32 位访存、64 位软件组合访存、byte mask、区域首尾、避栈 mem-test；data 复制/bss 清零/全局变量写正确；未对齐按既定 trap 策略验证 | ELF/map、链接容量断言、预填 RAM 后测试、错误原因/EPC；不要求 RV32 单条 64 位 load/store |
| M08 / S3 | MROM/SRAM/Flash 等普通存储逐指令 DiffTest；设备按平台识别；MMIO skip/同步只限相应提交；故意扰动一次普通指令结果能触发 mismatch | 参考端区域表、同步方案、skip 统计、检测能力负例、hello/适用 CPU tests 日志 |
| M09 / S4 | SPI 读与映射/XIP 访问一致；目标 RAM 预填图案后由 CPU 从 Flash 搬运，复制边界、data/bss、stack 与入口 PC 正确；超容量镜像构建/加载失败 | Flash 镜像/ELF/map/hash、boot 波形、目标区校验；无 harness 代搬运 |
| M10 / S4 | 验收程序真实容量足够；若启用 PSRAM，完成控制器/模型事务及 byte/half/word、连续/随机地址、首尾/越界、延迟测试，再运行 Flash → PSRAM 程序 | 实际容量、存储测试、boot 与栈/heap 余量；若不启用 PSRAM须用新 workload 预算证明可免 |
| M11 / S5 | mtime 单调/tick 换算/跨低字溢出读取；mtimecmp 分字写；比较阈值前后 pending；mask=0/1 与 pending=0/1 四组合；只读/不支持 CSR 访问语义 | 独立 timer/CSR scoreboard、RV32 程序自检、CSR 支持表与负例 |
| M12 / S5 | 精确 IRQ：ALU/branch、空闲、LSU pending、错误响应、同步异常同时出现、redirect、MRET 后仍 pending；保存正确 EPC/cause/MIE/MPIE，无重复 store 或跳过指令 | 优先级表和每类用例；trap/MRET 波形、提交与内存副作用独立预期 |
| M13 / S5 | AM timer event、真实中断开关、RV32E 上下文保存恢复；timer cause/EPC 独立验证后再比较 NEMU；中断返回不无条件增加 EPC | 手写 trap 程序、嵌入式上下文校验、DiffTest 注入/时间同步规则 |
| M14 / S6 | 有限 RT-Thread：至少两线程无需主动 yield 也能在 tick 下交替取得进展，阻塞/唤醒、上下文、heap/stack 正确；退出有固定 PASS 与超时 | workload/map、tick/调度计数、寄存器和内存自检、余量、日志；协作 fixture 仅作回归 |
| M15 / S6 | UART 配置波特率、轮询发送状态；实际 serial TX 解码长字符串，字符数量/顺序一致；系统在固定与随机总线延迟下完成 | 串行接收器输出与时序；不能仅依赖上游 RTL 的队列打印 |
| M16 / S1–S6 | legacy/B1 相关定向/系统回归不退化；SoC hello、适用 CPU tests、非法指令/异常、有限 microbench smoke；随机延迟及错误注入按层验证 | 命令、seed、通过数/排除原因、timeout 与覆盖清单；正常启动不混入预期失败错误测试 |
| M17 / S7 | 真实 DC/PT 对冻结的新 scope 完成；无未解析引用、非预期 latch/loop/未约束功能端点，setup/hold 与电气规则通过，coverage/告警有逐类处置 | manifest、SDC/端口预算、area/qor/timing/DRV/coverage、reset 例外和主要路径；未达标为诊断结果 |
| M18 / S8 | 干净运行目录重建镜像/SoC 仿真；S0–S7 证据对应最终版本；M6 的存储、程序、频率与统计口径固定 | signoff、复现命令、版本/hash、剩余风险、精选波形与 bug case |

## 执行组织

1. S1 协议测试先用独立 AXI responder，逐一控制握手/错误，不依赖真实 SoC 恰好产生所有情况。初始随机目标为 **10 个固定 seed，每 seed 至少 1000 笔完成事务**；必须同时检查定向 bins，事务总数不代替覆盖。
2. SoC 延迟注入作为专用仿真配置，不修改功能 RTL 来制造时序。系统先固定延迟通过，再对 hello/小 mem-test 做 10 个固定 seed；至少对有限 RT-Thread 做正常时序及一个有界延迟配置。若上游协议路径不允许直接插入现有 Lite shim，新增 AXI4 对应实现，不能误用旧 shim。
3. 按阶段运行最小受影响测试；S6 最终运行完整 B1 signoff 和 legacy 回归、SoC 验收程序。现有 `make -C npc b1-signoff` 等入口已存在；SoC 的回归命令待实施后写入对应阶段文档，不将拟定名称当成现有目标。
4. CPU tests 按 ISA/对齐策略和容量分类：小 SRAM 阶段允许明确子集；S4 容量闭环后运行适用全组。不能把未运行项算通过。microbench smoke 固定子项/输入规模，不声称完整 benchmark 性能评估。
5. 所有随机测试有 seed、最大等待周期与失败现场；无响应时先报告 timeout，不伪造成功响应。错误注入验证 cause/EPC/副作用，真实 SoC 默认错误路径另做可达性核对。

## 验收边界

普通功能、协议和中断由本地仿真验证；面积/时序需要服务器实测。Verilator 两值仿真不证明 X 安全、亚稳态或 reset 物理时序。原版章节未纳入的设备、formal、四值/GLS、完整 SoC memory macro、PnR/CTS、功耗及全 PVT 不自动计为 PASS。

M17 允许有明确理由且与实际设计相符的 reset/常量条件例外；不允许无法解释的功能路径漏约束或为了通过而忽略违例。所有例外须写明检查对象、依据、影响及后续关闭条件，不能直接照抄 M4 的计数。
