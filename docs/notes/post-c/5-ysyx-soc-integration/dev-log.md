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
