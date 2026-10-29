# M5 开发日志

当前生效决定：2026-10-20 起直接升级现有接口，取消 B1/SoC 双路径兼容；下面2026-10-19的“保留 B1 Lite”是已被替代的初始规划。

## 2026-10-19：建立计划

- 输入：M4 已验收；本地 HEAD `d7c5b139eca8f6ffc467ecea472d4395998b1cea`。阅读 roadmap、M4 交接、原版 2607 C5/2306 B2、本地重组讲义及现有 core/AM/harness/RT-Thread 实现。
- 建立 [S0–S8 计划](plan.md)与 [M01–M18 验收矩阵](test-plan.md)，未执行 SoC 集成或修改源码。
- 关键决定：保留 B1 Lite；从 local req/rsp 边界引入保留 byte address/size 的原生 AXI4 单拍路径；CPU 内部 CLINT 与 timer interrupt 分步实现；Flash → SRAM 先证明启动，PSRAM 按真实容量纳入。
- 发现现有 RT-Thread 两线程静态栈合计 16 KiB，另有 heap > 32 KiB 断言，不适合讲义中的 8 KiB SRAM；S0 需固定容量路线，不能直接复制 B1 的 1 MiB SRAM 配置。
- 发现现有 MMIO 标记按 `0xa...` 地址判断，必须随新平台修改，否则 UART 与未来 SDRAM 的 DiffTest 分类错误。AM 中断开关当前为空实现，协作 RT-Thread 不构成中断验收证据。
- 当前无计划编写阻塞；实施前置为上游 revision/依赖生成、模型缺口审查、reset/IRQ/容量契约。在线 `ysyx6` 仅作调研线索，尚未固定或生成。
- 下一步：S0。完成后新增真实 `0-upstream-contract.md` 和验证记录；不预先创建 signoff 或填写 PASS。

## 2026-10-19：S0 完成，上游与平台契约冻结

- 输入主仓库 `30bc679`，ysyxSoC `df38a4d...`，分支 `npc-integration`；用户已安装工具、初始化依赖并生成。本次重新执行 `make -B -C ysyxSoC verilog` 成功，Rocket Chip实际diff与上游补丁一致。
- 新增 [实际契约](0-upstream-contract.md)、[检查脚本](../../../../npc/tests/ysyx_soc_contract_check.py)及精选 [manifest](s0-validation/manifest.json)。上游spec与生成实例61个端口一致；真实外围源加空CPU的静态展开通过，242条告警分类保留；没有NPC运行/完整SoC lint clean结论。
- 冻结仿真top为`ysyxSoCFull`、CPU占位名`ysyx_00000000`、关闭ChipLink/FAST_FLASH、SDRAM走APB但不使用；CPU外部IRQ固定0。reset经10级移位链，初始共同reset约定至少20个上升沿；默认仿真100MHz，不与S7的200MHz约束混淆。
- 核对真实地址：SRAM8KiB、MROM4KiB、PSRAM4MiB；现有RTT ELF静态段42,932B，确定S4接通PSRAM。Flash backing限制16MiB，PSRAM颗粒模型及真实XIP需实现。
- 发现原上游不能保证所有非法地址均返回DECERR，MROM写会断言，空外设有未驱动输出；已分配S2处理。另有DPI backing、旧MMIO分类、带延时外围仿真配置，以及S5的AM/RTT中断链缺口。
- M01/M02 的S0范围通过；没有当前外部阻塞，下一步S1。未修改NPC/SoC功能RTL，保留用户`.gitignore`修改与预期Rocket Chip补丁，未git add/commit。

## 2026-10-20：S1 改为单一接口演进

- 用户明确 B1 只是接入 SoC 前的系统测试，后续不必兼容；取消同时维护 Lite/SoC 两套 transport 的要求。
- S1 直接升级现有 adapter/仲裁/顶层，保留 local req/rsp 语义与必要的 CPU/协议检查；CLINT 改用 SoC 合同地址，不保留 B1 地址别名。
- 更新架构图、S1 出口与 M16：S1 用 AXI4 responder 做 CPU/协议验证，S2/S3 起切入真实 SoC，S6 不再以旧 B1/legacy signoff 为 gate。实施时同步迁移或停用旧构建/测试/flow 引用，记录检查点去向。
- M3/M4 历史验收与 S0 原始证据不改写，旧平台通过 Git revision 复现。本次只调整文档，未修改 RTL/构建脚本，未执行 git add/commit；下一步仍为 S1。

## 2026-10-20：S1 完成，直接升级 AXI4 与内部 CLINT

- 原 adapters/arbiter/top 直接升级并重命名；增加 raw byte address/SIZE，外部固定 ID=0、LEN=0、INCR、WLAST=1，检查 RID/BID/RLAST；保留单服务槽、公平性和既有 CPU req/rsp 语义。
- 增加仲裁后 router、mtime-only CLINT、`ysyx_soc_cpu` 和精确61-port `ysyx_00000000`。W-first 写先缓冲等待 AW，CLINT 副作用只执行一次；不增加通用 burst/slave/IRQ 功能。
- `make -C npc s1-test` 通过：模块/360192项译码检查、两组10×1000协议随机、复位/公平性/顺序覆盖、8项预期失败诊断、97项非法编码的两seed回归、访存错误/未对齐与10seed memory/CLINT；真实wrapper默认MROM PC和真实SoC静态展开通过。详情见 [S1](1-axi4-interface.md)。
- 迁移时发现旧 LSU 测试仍期待 word 对齐地址，按已确认的窄传输合同修正为 raw address，并加入 SIZE 检查。未靠恢复旧行为让测试通过。
- 旧 legacy/B1 系统入口和 M4 Lite 新建 flow 明确停用；保留历史复现说明，AM/SoC DiffTest 尚未执行。新增 `npc/README.md` 说明当前可运行入口。
- 无 S1 阻塞；下一步 S2。上游与嵌套子模块未修改，未 git add/commit。

## 2026-10-20：S2 完成，真实 SoC 最小启动

- 接入真实 `ysyxSoCFull`、MROM/可选 Flash backing、仿真 bind monitor；100 MHz、20周期外部复位，正确推进 `--timing` 内部事件。CPU 首次释放采样305ns，首AR355ns，首提交445ns。
- ysyxSoC fork 新增 SoC 侧 guard，先完整检查地址/访问形态，再进入上游简化译码；非法/禁用/只读写产生 DECERR/SLVERR。GPIO/PS2/VGA 空壳补确定输出；Flash XIP/PSRAM 暂隔离至 S4。没有修改嵌套 Rocket Chip，保留已有补丁。
- MROM ebreak、UART divisor1/8N1实际TX=`A`、SRAM/MROM窄访存/首尾通过。31次数据fault+1次取指fault精确cause/EPC通过，越界写不改变SRAM，无非法UART副作用。
- 测试定位到取指fault之后可能还有PC+4预取：总线多一个DECERR，redirect正确丢弃，架构只提交一次cause1；在独立预期中明确区分事务与trap计数。
- 新guard独立测试1261笔完成、7笔复位终止并恢复；5类harness负例通过。`make -C npc s2-test`、完整 `s1-test` 回归通过；[结果与版本证据](s2-validation/README.md)。
- G02的harness/分类部分、G03/G04/G07关闭，DiffTest留S3。无当前阻塞；下一步AM/linker/SRAM初始化/参考端同步。主仓库与ysyxSoC均有本步改动，未git add/commit；以后提交需先记录子模块改动，再更新主仓库gitlink。

## 2026-10-20：CPU 顶层改名并复验 S2

- 按用户指定将 `ysyx_00000000.sv` / `ysyx_00000000` 改为 `ysyx_25030087.sv` / `ysyx_25030087`，同步 ysyxSoC Scala BlackBox、源列表、lint、bind、wrapper 测试和接口审计脚本；端口与 reset PC 不变。
- 重新执行 SoC 生成、S2 完整验收、S1 完整回归和61-port接口检查，全部通过。ebreak/UART/memory/faults全部统计与改名前一致，归档的取指/UART CSV逐字节一致；更新 [S2 manifest 与复验记录](s2-validation/README.md)。
- 无新增阻塞。S0/S1 原始报告保留旧占位名；本次未修改 Rocket Chip，未暂存或提交。

## 2026-10-20：补齐 S2 实现与源码导读

- 按用户反馈扩写 [S2 实施记录](2-bringup.md)，建立功能/改动位置/验证对应表，串起构建、MROM与PC复位、SoC guard、UART、monitor及退出路径，给出文件行定位与关键符号。
- 区分S2新增、S1复用和上游已有机制，并明确Flash backing、完整SoC中途复位、SPI内部副作用等尚未验证的范围；M5后续实施文档沿用这一组织方式。
- 本次仅更新文档，核对源码位置、链接和既有验收数据；未修改功能源码或重跑硬件仿真，原验收结果不变。

## 2026-10-20：S3 AM/SRAM/DiffTest 完成

- 输入主仓库 `c33bbfa`，ysyxSoC `65238f4b`；保留预期的 Rocket Chip 补丁。本次修改在主仓库，无 CPU 功能 RTL 或子模块源码改动，未 add/commit。
- 新增 `ARCH=riscv32e-ysyxsoc`、4KiB MROM/8KiB SRAM linker、2KiB 栈预算，以及 poison/data-copy/bss-clear 启动代码。SRAM 全部由真实 CPU store 初始化，harness 只加载 MROM。UART 支持初始化/THRE/TEMT，AM uptime 读取内部 mtime。
- 新增提交后21-word状态快照、每条指令差分和最终整块SRAM比较。UART/mtime使用单次输入同步，无整状态skip。独立NEMU profile不修改普通`.config`，参考端从自身状态推导访存fault，未用DUT cause作注入依据。
- `make -C npc s3-test`通过：31个正向workload，含24个CPU tests、AM hello/memory/traps/timer、sieve/fib smoke和区域首尾汇编；35个CPU tests全部尝试构建，`hello-str`超MROM3912B，10项只构建未运行。8次异常cause/EPC有独立预期。
- 比较器GPR扰动、删除data-copy、删除bss-clear、ROM/RAM链接超容量五类负例按预期失败。S2完整回归、普通NEMU 32GPR/M smoke、新AM `run`入口均通过。普通NEMU shared target已有readline依赖，测试宿主预加载后完成检查，本轮不改普通构建系统。
- 新增[实现与源码导读](3-runtime-difftest.md)和[精选证据](s3-validation/README.md)，更新QA/plan/验收矩阵/roadmap。说明VMA/LMA、采样顺序、同步边界和容量分类，而非只记录PASS。
- M07/M08的MROM/SRAM范围关闭，无当前阻塞；下一步S4真实Flash/PSRAM启动。timer IRQ、完整benchmark/RTT、随机系统延迟及新scope综合仍待后续。


## 2026-10-26：S4 Flash 启动与 PSRAM 容量闭环

- 复用已有 SPI/Flash 与 PSRAM controller，新增真实 XIP FSM、4 MiB PSRAM 串行颗粒模型；Flash backing 限 16 MiB，guard 与 reference 同步范围/权限。未修改生成 RTL 或原有 Rocket Chip 补丁，未恢复 B1 transport。
- MROM/Flash 硬件构建配置隔离；AM 增加 `flash-sram`/`flash-psram`，Flash reset PC 为 `0x30000000`。CPU 执行静态区非零预填、text/data 搬运、bss 清零与 RAM 跳转，harness 不预装 RAM。
- 首尾测试发现原 PSRAM 控制器 DONE 后仍多发一个 SCK，末 word 读会越界；修正 reader/writer 的 SCK/CE 收尾，并将 PSRAM 启动限定在 APB access phase。独立 byte/half/word、地址位、混合随机访问与最终整块 RAM 比较通过。
- 41 个正向 workload、34 个适用 CPU tests 与 9 个启动/容量负例通过；S1/S2/S3 回归通过。普通 Flash/PSRAM 参与逐提交差分，SPI 寄存器仅单次设备输入同步；RTT 203 次 ECALL 协作调度不计 timer IRQ。
- RTT 新镜像21,832 B、静态RAM42,992 B，预留64 KiB主栈后heap区间4,085,776 B；100轮AB线程交替、heap释放恢复和实际UART通过。完整分线程/主栈水位与heap峰值数字留S6补充。
- [S4 源码导读](4-boot-memory.md)按职责/功能/位置/机制/验证展开；[精选证据](s4-validation/README.md)记录源码hash、ELF布局、启动提交、正反例和回归。Q16–Q18记录XIP/搬运、DPI位置与存储边界测试价值。
- 本步无未解决阻塞；下一步S5 timer interrupt。工作区包含主仓库和ysyxSoC改动，未git add/commit；先提交SoC再更新主仓库gitlink，嵌套Rocket Chip原补丁无需因S4新增提交。

## 2026-10-28：S5 timer IRQ 与精确入口完成

- CLINT 增加 64-bit mtimecmp 与持续 MTIP；保留 word-only、一次请求一次副作用、mtime 半字写优先于 tick 的合同。CPU 内部接线不改变 61-port SoC ABI。
- CSR/IDU 增加 mie.MTIE、只读 mip.MTIP；EXU 在无待完成 LSU 操作且无已知同步异常时接受独立 IRQ 事件。保存下一条未执行 PC，不把 IRQ 计作普通提交；AM 实现 timer event、真实 iset/ienabled 和上下文恢复。
- 修复 MRET 后立即再次 pending 暴露的 IFU 死锁：第二次 redirect 不能丢失 DROP 中尚待排空的旧取指。另补齐 NEMU regcpy 长度，SoC snapshot 统一为 23 word 并静态检查；普通 NEMU ABI 不变。
- 增加独立周期 timer 模型、pre/post MTIP 同步和 IRQ 比较；CLINT 事务的实际地址/方向/次数/写数据与参考指令核对。EPC 取样扰动与漏恢复 t0 两类负例分别验证比较器和软件合同。
- 最终 `make -C npc s5-test` 通过：6 个 SoC 程序共 139,396 条提交、17 次 IRQ 全部差分；每次完成 SRAM/PSRAM 全内存比较；10 个随机延迟 seed 各 200 次物理 store/load 与提交数一致；单元/译码定向通过。`make -C npc s1-test` 和 `make -C npc s2-test s3-test s4-test` 功能回归通过，包含 34 个适用 CPU tests 与 RTT 协作容量用例；最终仅加强 CLINT 事务检查后再以 S5 统一入口复验。详见 [S5](5-timer-interrupt.md)与[证据](s5-validation/README.md)。
- RT-Thread BSP 修复单核 interrupt-switch 原型与临界区旧状态恢复，接通显式开启的 tick；单线程 smoke 完成三次 IRQ 并输出 `RTT TICK PASS`。独立 checkout 的改动已导出 [rtthread-bsp.patch](../../../../npc/tests/soc-timer/rtthread-bsp.patch)，基础 revision、hash 与应用方式已记录；未提交任何仓库。
- 当前无阻塞。下一步 S6 验证完整的非主动 yield 双线程抢占、阻塞唤醒及各栈/heap 水位；本步不宣称完整 RTOS 交互功能或新范围 DC/PT 已通过。既有 ysyxSoC/嵌套 Rocket Chip 工作区改动未修改。

## 2026-10-28：S6 系统回归完成

- 输入主仓库 `debe357f384e22978f7856ca2db503f525c02585`。新增 `soc-system` 固定 RT-Thread 配置、双线程汇编屏障/寄存器哨兵、sleep 唤醒及 heap/栈自检；复用 S5 的 AM/NEMU/BSP，没有修改功能 RTL。保留已有 ysyxSoC/嵌套 Rocket Chip 状态，未 add/commit。
- 新增仿真专用五通道 AXI 延迟模型和生成器，正常/延迟构建目录隔离；源 wrapper 和上游生成 RTL 不修改。通道验证在零附加等待、固定等待、随机等待各完成 1,000 笔；VALID/payload、独立数据预期和计数通过。
- harness 增加按 ELF 区间分类的 SP 统计和 UART 串行帧时间；线程另扫描 RT-Thread 填充图案。首轮测试的切换次数阈值过严，六轮屏障实际最低需要每方向三次切入，修正预期后通过；这是测试模型修正，没有放宽进度、Context 或副作用检查。
- 四组定向/回归共 68 个真实 SoC 正向运行，1,824,069 条提交及 30 次 IRQ 全部差分，每次比较最终 SRAM/PSRAM；34 个适用 CPU tests 通过，unalign 明确排除。独立 S1 协议/CPU/错误和 SoC guard 回归通过，合计 10 个预期失败检查有效。
- 正常和随机等待 RTT 各 15 IRQ，均完成六轮非主动 yield 交替、sleep 4/6 tick 后于 4/7 tick 恢复、idle 运行；heap 峰值544 B并归零。主栈/worker0/worker1/idle 最大观测使用224/448/372/268 B。UART divisor=8，在正常、固定、随机等待下各精确输出528字节，并实际出现忙轮询。
- [实施导读](6-system-validation.md)按层次说明功能/改动位置、抢占证明、阻塞唤醒、水位、延迟模型、真实 UART 与验证分工。[精选证据](s6-validation/README.md)保存分组原始 manifest、source patch、镜像/ELF hash、汇总与关键日志；最后的帮助/provenance及栈负例补充单独注明，不将增量验收称为 S8 干净重建。
- M14–M16 关闭，无未处置阻塞。下一步 S7 是 CPU 子系统 pre-layout 面积/时序评估，由用户执行服务器 DC/PT；不包含 whole-SoC PPA 或新增交互 shell。

## 2026-10-29：S7 本地准备完成，待服务器 DC/PT

- 新建 `npc_soc_cpu.tcl/soc_cpu.f/soc_cpu.sdc`，综合实际 `ysyx_25030087` Flash wrapper：20 个 SV 源及 include，包含 core、AXI adapters/arbiter/router 和内部 CLINT；排除完整 SoC、memory/仿真模型。观察输出按真实未连接关系处理，不将 M4 面积差称为优化收益。
- 初始目标沿用 TT / 5 ns，11 个活动 AXI 输入和 29 个输出施加完整 min/max、slew/load；19 个禁用外部 IRQ/slave 输入显式置零；仅 reset false path，内部 timer IRQ 保持活动。上游 reset 延长链在 scope 外，物理释放/脉宽仍待实际机制评估。
- flow 默认选择新配置，修正 top/clock/reset、manifest 范围、网表 top 检查和 LSU 电容诊断的层次；保留旧 M4 输入/产物，历史 RTL 通过固定 revision 复现。
- `make -C npc/flow check test scope-check` 通过：48 项 flow 测试、4 种宏配置预处理/lint；SDC 对象与禁止错误例外检查通过。[本地证据](s7-validation/README.md)只记录脚本/展开检查，没有真实 PPA 数字。
- [S7 实施文档](7-synthesis-sta.md)说明范围、逐组端口预算、修改位置、检查边界和服务器命令。本次未修改功能 RTL、未重跑 S6 长系统回归；既有嵌套 Rocket Chip 工作区状态保留。
- 无本地准备阻塞；用户手工同步并运行 DC/PT 后回传。M17/S7 尚未完成，不能提前进入 S8 总验收。

## 2026-10-29：S7 基线审查与归档完成

- 采用 `soc-cpu-tt-5ns-s7-cap90`，HEAD `11a2608c224f05ed46c2bee57805a5300aa35135`。普通 compile 的 7 条零负载违例经 Ultra 消除；Ultra 的 9 条最大电容违例经 DC 库引脚 10% 裕量与增量 DRC pass 消除。数据时序和电气验收通过，面积 9530.135856 library_area，setup/hold 最差 slack +2.444726/+0.009693 ns。
- PWR-884 明确该版本 Ultra 自动漏电优化不能关闭，之前的 `set_leakage_optimization false` 请求无效。用户决定仅在文档说明零 leakage 优化目标，无需为清空报告 re-synth；保留原 DC CONSTRAINT_FAIL、PT REVIEW_REQUIRED 和完整报告，人工验收范围独立记录。
- 完成 9120 项 untested 分类：8958 项 reset 释放/脉宽暂缓，162 项对应 81 个常量输出；无其他未解释类别和 loop-breaking 弧。1623 个 FF 的 CP 与顶层时钟直接连接集合一致；1228 条 unloaded 告警均指层次输出。其余 warning 按具体对象和原因在基线表中处置，不做全局编号豁免。
- 逐条核对 45 个冻结输入、49 个阶段产物 hash；[baseline](s7-validation/baseline/README.md)归档 72 份原始文本、archive.json 和 review.json。21 份 RTL/include 中仅 core 的两条连续赋值位置区别于 S6，已核对表达式不变；原 dirty.patch 保留。本次不运行 EDA、功能回归或网表等价，不修改 flow 脚本、RTL 或回传结果。
- M17 / S7 在约定范围内通过，无未处置阻塞；reset 物理时序、功耗和全 SoC 物理实现边界仍保留。下一步 S8 冻结版本干净复现与交接，随后限定 GShare；交接继续关联 JOB-PREP-01。

## 2026-10-30：补记 DC 声明顺序修复的原因与提交

- 用户说明服务器上 `ysyx_core.sv` 的声明顺序导致 DC 报错：redirect_target 的连续赋值引用了后面才声明的 trap_target。`9912da3` 将两条 redirect assign 移到 wire 声明区后；这是 DC 前端兼容性修复，逻辑表达式不变，本地 lint 未发现该问题。
- 核对 commit、当前本地 core 与 cap90 冻结快照逐字节一致；cap90 的原 dirty.patch 已包含修复，S7 结论保持有效，无需重综合。补充 [S7 §4.1](7-synthesis-sta.md#41-dc-前端兼容性先声明信号再引用2026-10-30-补记)、基线追溯说明及 Q29，原报告/manifest/review.json 保持历史状态。
- 后续 RTL 按“声明在前、引用在后”组织；Verilator lint 通过不等于 DC 前端兼容。本次仅文档补记及 hash 核对，没有修改 RTL 或重新运行功能/EDA 测试。
