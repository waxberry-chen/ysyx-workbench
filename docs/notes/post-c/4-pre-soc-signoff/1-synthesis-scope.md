# M4 S1：综合范围与复位语义

2026-10-16：**S1 本地出口通过，下一步 S2**。输入 HEAD：`1ccf39d22f0107fbb5eb2a5327fe304942376d3e`。本次落实源码边界、硬件复位、文件清单和端口约束需求，并完成相关 RTL 回归；尚未运行 DC/PT，没有面积/时序数字，也没有四值或网表等价结论。

## 1. 冻结的实现配置

| 项目 | S1 决定 |
| --- | --- |
| top / 报告名称 | `ysyx_core_axi4lite` / **Core + adapters + Arbiter** |
| 内容 | IFU、decode、GPR、opbuf、EXU/ALU/branch、CSR、LSU、两个 AXI4-Lite adapter、Arbiter |
| 参数 | top 无参数覆盖；Core 默认 `PC_RST=0x80000000`、`IFQ_DEPTH=2`；opbuf 单项，payload 277 bit |
| 观察输出 | 保留全部 commit/monitor 端口，纳入约束和面积；不通过裁剪观察端口获得更好数字 |
| 寄存器/算术 | 保留 32 项 GPR 和当前组合乘法、除法、余数路径；软件 `riscv32e-npc` 配置不会自动裁成 16 项或移除 M 运算 |
| 不包含 | Xbar、1 MiB SRAM、UART、CLINT、B1 top、legacy DPI RAM、delay shim、TB 和 C++ harness |
| 实现模式 | 单 `clk` 上升沿、低有效异步 reset；普通非 topographical DC；不新增 clock gating |

当前小型 GPR/队列按 RTL 存储结构交给标准单元综合。**S1 不依赖 memory compiler**；B1 SRAM 宏映射属于另一个实现配置。组合除法和带复位 GPR 可能明显影响面积/时序，具体代价由 S3 报告确认，不能提前假设它们已经被优化掉。

输入入口：[npc/flow/README.md](../../../../npc/flow/README.md)、[core.f](../../../../npc/flow/00_indata/filelists/core.f)。清单包含 16 个 `.sv`，按 primitive → 组合运算/状态模块 → adapter → Core → Arbiter → top 排列。primitive 另行 include `vsrc/gnrl/ysyx_global.sv`，所以 hash 闭包为 17 个 RTL 文件。清单和 include 路径均相对 **npc/**；S2 的 launcher 必须切换到该目录或统一解析绝对路径，不能相对 run 目录直接读取。

以 SystemVerilog 模式解析，不照搬 C906 Verilog 读取设置。依据：本地 **DC User Guide P-2019.03，正文 6-3–6-5 / PDF 153–155**，区分 HDL 读取、analyze/elaborate 与 link；这些步骤的实际服务器兼容性仍需 S2/S3 验证。检索方式见 [manual-index.md](manual-index.md)。

## 2. 仿真与实现宏

| 配置 | defines | DPI | SVA | 功能/reset |
| --- | --- | --- | --- | --- |
| 正常 NPC + DiffTest | `NPC_SIM_DPI`、`DIFF` | GPR/CSR 指针导出 | 保留 | 与实现相同 |
| 无 DPI RTL TB | 无 | 无 | 保留 | 与实现相同 |
| 综合 | `SYNTHESIS` | 无 | 无 | 保留 |
| 防误配检查 | `SYNTHESIS`、`NPC_SIM_DPI`、`DIFF` | 无，SYNTHESIS 优先 | 无 | 保留 |

实现配置不定义 `DEBUG`、`B1_SIM_SHIM`、`NPC_SIM_DPI` 或 `DIFF`。`NPC_SIM_DPI` 仅控制 GPR/CSR import 和 initial 指针导出；主 Makefile 显式打开它，保持原 C++ DiffTest 观察接口。`SYNTHESIS` 屏蔽 Core、IFU、EXU、LSU、两个 adapter 的 property/assert，Arbiter 原本已有该保护。宏不切换 datapath 或 reset。

本次预处理检查确认综合配置无 `initial`、DPI、property/assert，正常仿真仍含 SVA；双宏组合不泄露 DPI。CSR read mux/target 改为使用已有语义别名，保持逻辑等价并消除无 DPI 配置下的冗余 alias 告警。

## 3. GPR 策略与状态审查

原 regfile 依赖仿真 `initial` 清零，且没有 reset 输入。本次增加 `rst_n`，x1–x31 在异步 reset 时清零，x0 两个读口独立固定为零、写入被屏蔽。数组第 0 项仅保留 reset-to-zero，供仿真 DPI 观察；综合中预期成为常量，实际裁剪结果需查看 DC 报告。

选择全 GPR 复位是为了保留当前 NPC/NEMU 首次启动后的全零约定，不引入启动汇编或 DiffTest 初始化协议变更。与原实现的明确差异是：**运行中再次复位也会清空 GPR**，原 `initial` 只在时间零执行。软件必须在 reset 后启动，不能依赖 reset 前的任意寄存器值。

代价是 31×32 个可写存储位的 reset 能力和复位网络负载；确切 cell/mux 面积待综合。后续可研究仅复位有效位或由启动代码初始化，但要单独配置、验证读前初始化及 DiffTest 契约，不能作为本次“去掉仿真代码”的顺带优化。

| 状态 | reset / 无效数据处理 |
| --- | --- |
| Core architectural PC | `u_arch_pc` 异步复位到 `PC_RST`，commit 时更新 |
| GPR / CSR | GPR 清零；四个 CSR 继续由 resettable DFF 清零；trap 优先于 mret，再优先于普通 CSR 写（对相关 CSR） |
| IFU | 状态回 REQ；fetch/request PC 回 `PC_RST` |
| IFQ | 指针和 count 清零；storage 不复位；空队列 `out_valid=0` 且 `out_data=0`，入队后才读取有效内容 |
| opbuf | valid 与 payload 清零；flush 清 valid；EXU commit/副作用受有效条件约束 |
| EXU | `mem_wait_q=0`；其余主要为组合逻辑 |
| LSU | 状态回 IDLE；请求上下文、response/error 清零 |
| 两个 adapter | 状态回 IDLE；payload/response/error 清零，LSU AW/W pending 清零 |
| Arbiter | 状态回 IDLE；owner/write/preference、AW/W 收集/发送位、payload/response 清零；外部握手输出受 reset 屏蔽 |

层次内时序逻辑使用同一个 `clk`，未发现功能性 CDC 或新增 gated/generated clock。`negedge rst_n` 是复位事件，不能算第二个功能时钟。外部负责异步 assertion、相对 `clk` 安全同步 deassertion；本 top 未加入 reset synchronizer。这是 S1 的设计意图；后续早期 STA 已按用户决定将实际释放/脉宽建模暂缓，见 [reset TODO](reset-timing-todo.md)。实际 SoC/reset 集成时仍需落实；两值仿真不能证明亚稳态、RDC 或 X 安全。

## 4. SDC 端口需求与预算接口

逐端口清单：[s1-port-budget.csv](s1-port-budget.csv)。共 **34 个命名端口**：10 输入 / 43 bit（含 clock/reset），24 输出 / 262 bit。除 clock/reset 外，AXI 输入共 41 bit；输出为 AXI 111 bit、commit 137 bit、monitor 14 bit。

| 对象 | S2 必须提供的预算 | S1 约定 |
| --- | --- | --- |
| `clk` | period、setup/hold uncertainty、source latency min/max、transition | 唯一时钟，pre-layout ideal network；数值与库单位在 S2 冻结 |
| `rst_n` | 外部 release 时序/输入电气条件、recovery/removal 检查策略 | 不 blanket false-path；还会直接控制握手输出，不能漏掉组合路径 |
| AXI 输入 | 相对 clk 的 input delay min/max；input transition 或 driving cell | 外部同步单时钟 AXI 环境；READY、VALID、data/resp 均约束 |
| AXI 输出 | output delay min/max、load | address/prot/data/strb、VALID/READY 均约束 |
| commit/monitor 输出 | output delay min/max、load | 视作同 clk 域的外部同步观察接口；不可因“调试信号”而漏约束 |

S1 冻结的是对象和假设，**不虚填频率、电容或库单位，也未生成可执行 SDC**。S2 需把上述字段变成明确数值和单位后才能运行；若采用占周期比例的初值，仍需在 manifest 中展开记录。monitor 含外部握手输入的组合观察路径，因此需检查 In2Out，不能只看 Reg2Reg。Reg2Out、In2Reg、常量端口裁剪和所有约束覆盖在 S3 对综合网表复核。当前没有新增 multicycle 或 false-path 例外。

## 5. 验证证据

工具：Verilator 5.008。以下命令从仓库根执行，最终退出码均为 0：

```bash
make -C npc synthesis-scope-check
make -C npc architectural-state-test
make -C npc b1-signoff axi4lite-directed-regress axi4lite-trace-test
```

| 检查 | 结果 |
| --- | --- |
| 4 种宏配置预处理/lint | PASS；源文件和 include hash 记录于 `npc/build/m4-s1/scope/manifest.json` |
| GPR/CSR 定向 | 普通无 DPI 与 `SYNTHESIS+NPC_SIM_DPI` 两种配置均 PASS；31 项写读、独立双读口、x0、write-enable、异步/重复复位、复位覆盖写入、CSR/target、trap/mret 优先级及复位后恢复 |
| B1 signoff | PASS；含 lint、独立单元/配置、18 个 redirect 组合、10 seed fabric、53 项系统测试和 23 项 closure；C01–C13 必测覆盖通过 |
| M2 定向 | primitive、IFU、LSU、EXU、两个 adapter、IFU 集成、访存错误与地址非对齐测试 PASS |
| legacy trace | PASS；add 1095 commits，架构 trace SHA-256 `bbf8496edf2329d695eb4437641ced89bba9cf0b6006f1a0b5955c32941e9284`，与既有基线一致 |

`synthesis-scope-check` 不把全局 `-Wno-fatal` 当作通过：收集诊断后按**类型、文件和信号**白名单检查，任何未审查 warning 仍退出失败。两个综合配置各有 9 个 `UNUSEDSIGNAL`：

- `ysyx_gen_imm.inst[6:0]`：opcode 已由上游 decode，非 immediate 组成部分。
- Core 的 `if_ctx_fire`、`op_rs1_idx`、`op_rs2_idx`、`exu_commit_pc`、`commit_mem_wdata`：仅供断言观察。
- EXU 的 `op_pred_taken`、`op_pred_npc`：仅供断言观察。
- LSU adapter 的 `local_request_aligned`：仅供断言检查。

普通配置各有 opcode 未使用告警与 `rst_n` 的 `SYNCASYNCNET`：SVA 同步采样硬件异步复位，限定到该 top/reset 信号。未发现其他 lint 告警；DC `check_design`、真实常量裁剪、latch/环与映射检查仍待 S3，不能用 Verilator 代替。

本地归档目录 `artifacts/m4-s1-20261016/` 保存通过的命令日志、输入/修改快照、源 hash 和相关结果/覆盖 CSV；临时二进制留在 `npc/build/`，不提交构建产物。首次构建遇到 ccache 沙箱临时目录只读，获准沙箱外构建后通过，不是 RTL 或 EDA 输入阻塞。

## 6. 后续与阻塞

当前 **无 S1 未解决阻塞**。下一步 S2 蒸馏最小 DC/PT 脚本、site/library 配置、数值 SDC、preflight/manifest 和失败退出机制，沿用服务器 PDK 路径。DC analyze/elaborate/link 与面积/时序首次实测属于后续服务器验收；没有运行不记 PASS。四值/GLS/PTPX 继续按计划延后。
