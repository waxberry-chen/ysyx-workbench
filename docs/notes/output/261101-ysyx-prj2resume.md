# 2026-11-01：一生一芯项目 → 简历 v1 展示材料

> 用途：提供给简历撰写工程，先完成项目条目的选材与排版；PDF 回传后再调整篇幅、措辞和复习重点。正文突出做了什么、采用什么机制和可展开的追问，测试规模留作备查。
> 工程状态：M5 与限定 GShare 增量已在约定范围内验收，代码冻结入口为 `4dbccf6` + 固定依赖/既有补丁，见 [最终交接](../post-c/gshare-bpu/signoff.md)。本文件为第一版展示草稿，个人口述和迁移练习尚未考察。

## 1. 可直接用于简历的第一版正文

**项目名称：RISC-V 前后端解耦处理器设计与 SoC 集成**

基于一生一芯；Verilog / SystemVerilog / Verilator / Synopsys DC、PrimeTime

**项目简介：** 设计前后端解耦的 RISC-V 处理器，完成 SoC 集成、软件启动适配与系统验证，结合程序执行性能及 pre-PnR 面积、时序分析，评估实现的收益与代价。

- **微架构与 RTL：** 设计单发射、顺序提交的 RV32E 前后端解耦处理器核心，通过指令队列和 ready/valid 握手协调取指与执行，实现写回旁路及访存等待控制；支持精确异常与定时器中断，实现轻量级 GShare 分支预测器，支持处理条件分支、提交训练及 JAL 提前取指。
- **SoC 集成与总线：** 实现 CPU 取指/访存的 AXI4 单拍适配与仲裁，通过 Chisel BlackBox 将自研核心接入一生一芯开源 SoC 框架 ysyxSoC（复用 Rocket Chip 互联组件），完成系统的外设访问联调。
- **验证计划与仿真平台：** 系统层面搭建 Verilator/C++ 仿真环境并与 NEMU ref 进行提交级差分测试（DiffTest）；编写 SVA 和定向测试，加入随机总线延迟，检查握手反压、异常/中断及分支重定向等场景。
- **综合与 STA：** 基于 Synopsys DC、PT 搭建 synthesis + STA 的 pre-PnR 面积/时序评估流程，分析处理器在 TSMC 28 nm 工艺库下的关键路径、电气 DRC 及综合映射后的标准单元面积，简要评估前端设计的面积/时序代价。
- **SoC 软件构建与启动：** 熟悉 bare-metal 构建流程，通过 AbstractMachine (AM) 抽象底层软件栈, 通过 linker script 和 startup code 组织程序布局、代码/数据搬运、BSS 清零及栈初始化，支持多存储 (e.g. MROM/SRAM、Flash→SRAM/PSRAM) 启动运行；适配异常/中断处理及上下文保存恢复。

若版面允许，可在处理器架构与 RTL 条目后补一组体现 GShare 方案取舍的结果：**固定六程序相对 OFF 加速约 1.11～1.20×，CPU 子系统单元面积增加约 21.1%。** 详细比较条件见第 3 节。

可选技术关键词：SystemVerilog、C/C++、Python/Tcl、AXI4、Verilator、NEMU、Design Compiler、PrimeTime。

项目时间和个人角色由本人按实际经历填写。正文按五项工作领域组织，GShare 作为处理器微架构增量放入第一项，软件构建与启动单独展示。最终条数由版面决定；技术关键词可与技能栏合并，保留结果数字时同时保留“固定程序”“CPU 子系统”“pre-PnR”等范围。

### 正文选材原则

优先表达 **具体问题或约束 → 采用的设计/验证方法 → 实现的行为或结果**。每条选一两个值得展开的机制；正文让读者看到设计判断，完整覆盖清单与运行日志由项目材料承接。

测试项数、提交条数用于回答“验证到什么规模”，本身不能说明检查器是否独立、覆盖了什么边界，因此不作为默认正文亮点。性能、面积和时序数字在说明设计取舍时可以保留少量；不要求每条经历都量化，也不为显得量化而填入运行计数。

工程特点通过事实呈现：适应可变延迟的事务控制、处理已接受请求与重定向的关系、接通实际 SoC 启动链路、验证检查器、定位综合/STA 差异。流水级数或 feature 数量本身不决定项目深度，正文不使用“比普通五级流水更高级”等比较性评价。

## 2. 核心主题与可展开素材

项目主线是：**处理器在可变访存延迟下正确执行，经 AXI 接入 SoC 后完成启动和中断，再用功能验证与综合/STA 评价实现和优化方案。** 按处理器、SoC 集成、验证、综合/STA、软件启动五个工作领域组织，正文与下表一一对应。GShare 的实现属于第一项；相关功能检查和面积/时序评估分别由第三、四项支撑，不另设同级类别。

| 能力主题 | 本工程值得讲清的内容 | 简历中的位置与证据入口 |
| --- | --- | --- |
| **1. ISA、微架构与 RTL** | RV32E 的 16 个 GPR；单发射、顺序执行/提交；两项 IFQ、单项 opbuf；写回旁路、等待与反压；异常/IRQ/redirect；GShare 查询、随指令保存索引、提交训练和恢复 | 第 1 条；[core 源码](../../../npc/vsrc/core/ysyx_core.sv)、[ISA 合同](../post-c/4-pre-soc-signoff/2.5-isa-contract.md)、[预测器](../post-c/gshare-bpu/1-predictor.md)、[预测闭环](../post-c/gshare-bpu/2-integration.md) |
| **2. SoC 集成与总线** | 将 IFU/LSU 请求转换为 AXI4 单拍事务，公平仲裁并保持 owner 到事务完成；处理 AW/W 独立握手、窄访问、响应反压和错误；内部 CLINT 与外部 SoC 地址路由 | 第 2 条；[AXI 接口与实现](../post-c/5-ysyx-soc-integration/1-axi4-interface.md)、[SoC bring-up](../post-c/5-ysyx-soc-integration/2-bringup.md) |
| **3. 验证计划与仿真平台** | C++ harness 驱动 RTL、连接模型和观察提交；NEMU 提供指令级参考；scoreboard 用独立事务预期检查协议，SVA 检查时序规则；随机等待覆盖事件交错，负例检查验证环境是否能发现错误 | 第 3 条；[运行时与 DiffTest](../post-c/5-ysyx-soc-integration/3-runtime-difftest.md)、[系统检查](../post-c/5-ysyx-soc-integration/s6-validation/README.md)、[GShare 功能验证](../post-c/gshare-bpu/3-functional-validation.md) |
| **4. 综合、STA 与量化评估** | 明确可综合 CPU 子系统 scope，裁剪参考流程并搭建 DC/PT；编写时钟、IO、负载及电气约束；检查关键路径、违例与未测试项；固定条件比较优化的周期收益和面积/时序代价 | 第 4 条；[flow](../../../npc/flow/README.md)、[M5 S7 实施](../post-c/5-ysyx-soc-integration/7-synthesis-sta.md)、[GShare 实验](../post-c/gshare-bpu/4-performance-ppa.md) |
| **5. SoC 软件构建与启动** | bare-metal C→ELF/BIN；AM 平台适配；链接脚本分配运行地址和加载地址，启动代码搬运程序/数据、清零 BSS、设置栈；AM trap 上下文支撑 timer/RT-Thread 用例 | 第 5 条；[MROM/SRAM](../post-c/5-ysyx-soc-integration/3-runtime-difftest.md)、[Flash/PSRAM](../post-c/5-ysyx-soc-integration/4-boot-memory.md)、[timer IRQ](../post-c/5-ysyx-soc-integration/5-timer-interrupt.md) |

第一版优先保留 **RTL 中的事务/控制流处理、验证方法、GShare 的量化取舍**。SoC 启动与软件栈用来说明处理器已经接入真实控制器并运行程序；篇幅紧张时，省略全部外设容量和文件名，保留启动路线与实际运行结果。

AM 提供面向上层程序的统一硬件抽象接口，本工程完成相应平台适配和运行时支持。RT-Thread 作为验证中断、上下文切换和多任务运行的系统用例，保留在支撑材料中；当前正文优先写启动及异常/中断的软件配合，不单独突出 RTOS。

期望引出的追问包括：“已被接受的取指事务为什么不能随 redirect 直接取消？”“DUT 与 REF 一致还可能漏掉什么？”“为什么训练时不能重新计算 PHT index？”“同一份网表为什么 DC 与 PT 判断不同？”正文中的机制与案例应能自然引出这些问题，后续复习按最终保留的条目准备。

## 3. 数字的含义、条件和证据

以下保留量化结果及测试规模，供追问时核对；测试项数、提交数默认不放正文。口述可以先说明“几十项 CPU 程序、百万级提交差分”，再按需要查到准确范围；理解测了什么和怎样判断，比背下精确计数更重要。

| 可用结果 | 准确口径 | 证据 |
| --- | --- | --- |
| **34 项适用 CPU tests 通过** | Flash/PSRAM 系统回归中的适用集合；原 `unalign` 按项目异常合同排除，非对齐数据访问另有 trap 定向检查。不是所有程序都能放进 4 KiB MROM | [GShare S3](../post-c/gshare-bpu/3-functional-validation.md) |
| **3,372,127 条差分提交，47 次 IRQ** | GSHARE 模式复用 M5 S3～S6 suites 的 146 次正向系统运行，检查 GPR/CSR 等架构状态及最终 RAM。146 是运行次数，含跨阶段重复程序，不是 146 个不同测试 | [system-summary.json](../post-c/gshare-bpu/validation/system-summary.json) |
| **六程序加速 1.114～1.201×** | `cycles_OFF / cycles_GSHARE`；同镜像、同存储延迟、冷启动、无随机 AXI delay，统计从 reset/boot 到正常结束。每个程序单列，范围不是平均值 | [逐程序结果](../post-c/gshare-bpu/4-performance-ppa.md)、[performance.json](../post-c/gshare-bpu/validation/performance.json) |
| **JAL_ONLY/GSHARE 为 1.001～1.198×** | 三模式共有 18 次性能运行。此项用于区分共同 JAL/恢复框架之上的条件分支预测增量；可选量化句的 1.11～1.20× 是完整方案收益的舍入值，包含 JAL 提前处理 | 同上 |
| **CPU 子系统面积增加 21.076%** | 同批 OFF/GSHARE 分别为 9583.727856 / 11603.591918 `library_area`；包含预测表、预译码、元数据、恢复逻辑及重新映射，不是只有方向表的面积 | [PPA 审查](../post-c/gshare-bpu/validation/ppa/README.md) |
| **两模式满足 5 ns 数据时序目标** | 28 nm TT / 0.9 V / 25°C，DC Ultra + PT；GSHARE 最差 setup/hold slack 为 +1.801808/+0.008700 ns，PT 约束违例为 0 | 同上 |

本稿使用 **pre-PnR（布局布线前）** 标明流程阶段。已有工程材料中的 pre-layout 在这里指同一阶段；更具体的流程是 **普通 DC 逻辑综合 → PT STA，ideal clock / ZeroWireload，无实际布线寄生**。pre-PnR 本身只说明阶段，分析模型与假设仍由这些条件界定。

EDA scope 为 CPU + AXI adapters/arbiter/router + CLINT，不含外部 SoC 控制器或存储宏。功耗未验收，reset 物理时序继续暂缓，DC 自动 leakage 零目标已有记录处置；PT 的其余 untested 均已分类解释。正文用“pre-PnR 面积/时序评估”说明实际完成的工作，详细条件留在本节。

功能/性能仿真的时钟为 100 MHz，200 MHz 是独立 STA 的约束点；不要把两组结果合写成“整机已在 200 MHz 运行”。六个固定程序的速度提升均小于 21.076% 的面积增幅，适合陈述为**性能与面积的取舍**，不据此声称吞吐/面积或能效改善。

### 综合报告中的面积是什么

当前采用 DC `report_area -hierarchy` 的 **Total cell area**。综合将 RTL 映射为工艺库里的门、触发器、缓冲器等实例，再对叶级实例对应的库面积求和：

\[
A_{\mathrm{cell}}=\sum_{i\in\text{叶级单元实例}} A_{\mathrm{lib}}(\mathrm{type}(i))
=\sum_{t\in\text{单元类型}} N_t\,A_{\mathrm{lib}}(t)
\]

这里每个实例只计一次；不同单元类型、驱动强度对应的库面积可以不同。本轮没有 macro/blackbox，因此统计的是标准单元面积。GSHARE 的 [area.rpt](../post-c/gshare-bpu/validation/ppa/gshare/reports/syn/area/area.rpt) 给出 `Total cell area = 11603.591918`，由组合与时序单元面积组成；`Buf/Inv area` 已包含在组合面积中，不能再加一次，也不能把父子层次的 Global area 重复累加。

这是**已映射网表的库面积统计值**，有具体单元实现作为依据；它不是最终 core/die 的版图面积。布局利用率、单元间空白、宏及其布局约束、供电与 IO 等物理需求未由这项统计给出，后续 CTS/时序修复还会改变单元集合。当前报告的 `Net Interconnect area` 和 `Total area` 均为 `undefined`，不能拿 `Total cell area` 直接当作芯片面积。

面积单位暂记为 `library_area`，与 μm² 的换算尚未独立确认。**area overhead** 指相对于基线的额外面积；本轮计算为 `(A_GSHARE - A_OFF) / A_OFF ≈ 21.1%`。描述单次综合结果时用“标准单元面积”，描述同条件方案差值时用“面积增量/开销”。简历以实际面积/时序评估工作体现前端设计中的 PPA 意识，功耗仍未评估。

## 4. 个人工作、复用关系与表述约定

本项目有一生一芯课程和开源软件基础。NEMU 是已有 ISA 模拟器，本工程实现/适配其所需行为并接入参考端；AM、RT-Thread、测试程序和 ysyxSoC 均有上游基础。重点陈述本工程的 **Core 实现与重构、CPU 总线与中断、仿真/验证、软件平台适配、DC/PT 流程裁剪及优化实验**。外围控制器与存储模型按实际情况复用或改造，不能将上游整个 SoC、OS 或编译工具链写成个人从零实现。

早期 NEMU、AM、NPC harness 与 RTL 已由本人手工跑通，后续增量有 AI 辅助。个人贡献的口述应具体到设计选择、实现/审查、问题定位和验证工作；简历中的熟练程度按实际掌握填写。本文件记录已完成的工程工作，个人理解结果另记在 [JOB-PREP-01](interview-readiness.md)。

| 主题 | 建议采用的说法 | 对应的实际范围 |
| --- | --- | --- |
| Core | “RV32E、单发射、顺序提交、弹性前后端” | 当前结构不是经典五级流水；无 M/C、MMU；ISA/CSR/异常按项目合同实现，指令地址非对齐异常仍有既有边界 |
| 总线 | “AXI4 单拍子集，single-outstanding” | 固定 ID、LEN=0，外部读写合计最多一笔在途事务；“AXI4-Lite 加强型”仅适合解释演化历史，不作为正式协议名称 |
| 预测 | “GShare + predecode，条件分支预测与 JAL 提前取指” | 128 × 2-bit PHT、7-bit 提交历史，无 BTB/RAS，JALR 保留执行端恢复；表规模没有扫参选优 |
| 系统运行 | “支持三种启动布局，验证 RT-Thread 抢占/唤醒用例” | MROM→SRAM 数据初始化、Flash→SRAM、Flash→PSRAM；Flash 启动代码通过 XIP 执行后搬运主体程序。没有交互 shell 或完整 OS 功能验收 |
| 综合与时序 | “搭建 DC 逻辑综合 + PT STA 的 pre-PnR 面积/时序评估流程” | 综合与 STA 实际执行；PnR、CTS、寄生提取、实板和流片未实施。这里的电气 DRC/DRV 是电容、转换时间、扇出等检查 |
| 验证能力 | “差分 + 独立协议/边界检查 + 随机时序 + 负例” | 已有检查范围和失效检测证据；不写完整 ISA compliance、形式等价、UVM 或全状态覆盖 |

面积单位及开销口径见第 3 节，简历优先采用同库面积增幅。详细库名、服务器路径、源码 hash 和各阶段编号留在工程材料，正文不需要列出。

## 5. 可以支撑追问的具体案例

这些案例作为后续讲解素材，不必都放进简历正文。先选择最能独立讲清的两个，按“现象 → 判断依据 → 原因 → 修改 → 验证”准备。

| 案例 | 可以说明的能力 | 阅读入口 |
| --- | --- | --- |
| **连续 redirect 与未完成取指** | 前端处于 DROP 时再次重定向，必须更新目标并继续排空旧响应；清空年轻指令不能取消已接受的事务。结合 IRQ/MRET 推导死锁原因和修复 | [M5 S5](../post-c/5-ysyx-soc-integration/5-timer-interrupt.md) |
| **启动程序也需要独立检查** | 对 RAM 做 poison，再故意跳过 data-copy/BSS-clear 的 store，要求程序自检以非零 a0 失败；说明软件自检、DiffTest 和负例分别检查什么 | [M5 S3](../post-c/5-ysyx-soc-integration/3-runtime-difftest.md) |
| **DC 通过而 PT 报最大电容违例** | 对同一网表核对标量引脚电容与 CCS 接收模型的差异；在 DC 使用 10% 电容裕量及增量修复，PT 按原库独立验收。10% 是本库/设计的试验选择 | [M5 S7](../post-c/5-ysyx-soc-integration/7-synthesis-sta.md) |
| **预测准确率不等于程序加速** | 用 OFF/JAL_ONLY/GSHARE 分离贡献；解释提交历史、保存查询索引、错误路径不训练，以及无 cache、串行存储延迟下的收益与面积代价 | [GShare QA](../post-c/gshare-bpu/qa/README.md)、[实测](../post-c/gshare-bpu/4-performance-ppa.md) |

已有 Core、SoC、验证框架三张图的规划可继续用于口述；当前 GShare 的结构以 [S2 闭环图](../post-c/gshare-bpu/2-integration.md)为准。第一版简历先落文字，展示图和深入案例随后按 PDF 的重点完善。

## 6. 交给简历撰写侧，以及 PDF 回传后的工作

**本次交付使用方式：** 第 1 节是可直接排版的草稿，第 2 节提供选材层次，第 3～4 节供数字/贡献核对，第 5 节保留面试展开入口。正文围绕机制、方法和可追问的案例组织，测试运行计数留在备查材料；只在支撑设计结论时选用少量数字。简历侧可以调整顺序、压缩措辞，但不要将未测项目补成成果，或改变比较范围。正文默认突出处理器设计与 SoC 集成，暂不另拆 DV 版本。

PDF 回传后依次处理：

1. **篇幅与重点：** 检查该项目与另一个项目的比例，保留能体现具体工作的动词、机制和少量结果，减少重复工具名。
2. **事实与口径：** 核对每句话对应的实现/证据，特别是 GShare 收益归因、AXI 子集、pre-PnR 目标和上游复用。
3. **针对性复习：** 逐条回答“实现了什么、为什么这样设计、怎样验证、遇到什么问题”，定位源码或报告；缺口优先围绕最终写进 PDF 的内容补齐。
4. **小变化练习：** 从已选主题安排至少一次局部推导、改动或新增测试，记录实际表现；个人考察记录进入 [interview-readiness.md](interview-readiness.md)，与工程 PASS 分开保存。

当前完成的是项目展示草稿。整份简历 v1、PDF 审阅和个人理解考察仍按上述顺序推进；无需为撰写简历重跑已有功能或 DC/PT 验收。
