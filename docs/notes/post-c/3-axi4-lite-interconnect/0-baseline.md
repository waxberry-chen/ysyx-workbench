# M3 S0：M2 基线保存与接口核对

> 日期：2026-10-14；状态：**S0 PASS，可进入 S1 Arbiter 实现**。  
> 本轮仅复测 M2 legacy 最小相关集合，不是 M2 全量重新验收，也不是 M3 interconnect sign-off。

## 1. 版本与范围

| 项目 | 本轮记录 |
| --- | --- |
| 工作区 HEAD | `94dbfd146dc774b405c79c2558d10d9b066df405` |
| M2 实现版本 | `5b6f29c`；完整对象 ID 见 [机器可读清单](s0-manifest.json) |
| 源码对照 | NPC RTL/C++/Makefile/scripts/filelist、受版本管理的 AM/NEMU 与 M2 实现版本无差异 |
| am-kernels 独立仓库 | `9804c83061d595712c0aef75c513318576480315`；测试开始时工作区干净 |
| 工作区改动 | 本轮运行前主仓库干净；本轮仅新增/更新阶段文档与结果摘要，未修改 RTL、harness、AM 或构建脚本 |
| 实际 top / filelist | `ysyx_core` / `npc/filelist.f`，两套 AXI master + C++ slaves |
| 构建目录 | `npc/build/m3-s0-20261014-legacy/`，新建目录重新生成 NPC 与模块测试程序 |
| 软件镜像 | 沿用现有 AM/workload 增量构建与 ELF，再执行 objcopy/参数写入；没有声称完整清理重编 AM |
| Reference | 使用现有 `riscv32-nemu-interpreter-so`；检查配置为 `CONFIG_TARGET_SHARE`，本轮没有重编 reference；二进制与配置均保存 hash |

实际输入、源码快照和所有运行日志已归档。NPC/AM/NEMU 在同一主仓库内，不能把它们的 `git rev-parse HEAD` 误报为三个独立上游版本。

## 2. 环境与运行配置

| 项目 | 值 |
| --- | --- |
| Verilator | 5.008，rev v5.008 |
| RISC-V GCC | Ubuntu 11.4.0，`riscv64-linux-gnu-` 工具链 |
| Host G++ / GNU Make / LLVM | 11.4.0 / 4.3 / 11.1.0 |
| 普通 AM workload | `ARCH=riscv32e-npc`，`-march=rv32e_zicsr -mabi=ilp32e`，AM 默认 `-O2` |
| 异常定向汇编 | 既有脚本采用 `-march=rv32i_zicsr -mabi=ilp32`；测试只使用当前支持的寄存器，不视为完整 RV32I/E 合规验证 |
| RTL 配置 | PC=`0x80000000`，IFQ_DEPTH=2，当前 GPR 仍为 32 项 |
| Memory | C++ PMEM 128 MiB，base=`0x80000000`，不是 M3 计划中的 RTL SRAM |
| Assertions / DiffTest | ON / ON；系统用例检查 GPR/CSR，MMIO 仍采用现有 reference skip 语义 |
| reset / 停止 | reset 3 cycles；在已提交 `ebreak` GOOD TRAP 停止，不另行 drain |
| FST | 编译保留 trace 支持；`CONFIG_FST` 未开启，本轮没有生成展示波形 |
| 默认时序 | seed=42，max latency=3，ready=75% |
| 随机回归 | add，seeds=1–10，max latency=7，ready=50% |
| 确定性样本 | seed=42，max latency=0，ready=100%；0 表示无额外随机 response 等待，不表示组合零延迟存储器 |

IFU PRNG 使用配置 seed，LSU 使用 `seed XOR 0x9e3779b9`。随机模型源码、编译参数入口、NEMU `.config`/generated header 和 NPC config 已保存；完整命令以归档 `commands.json` 为准。

## 3. 实测结果

| 检查 | 本轮结果 | 证据（归档内相对路径） |
| --- | --- | --- |
| Core lint | PASS，有一个既存 unused 位域 warning | `logs/directed-approved.log` |
| primitive、IFU、LSU、EXU | 4/4 PASS | 同上 |
| IFU adapter、IFU+adapter、LSU adapter | 3/3 PASS，assertions ON | 同上 |
| fetch/load/store access fault | 3/3 PASS，cause 1/5/7，测试程序检查 mepc；DiffTest ON | `tests/access-fault-test/` |
| load/store misaligned | 2/2 PASS，cause 4/6、零 D-RAM request；DiffTest ON | `tests/address-misaligned-test/` |
| CPU tests 子集 | add、bubble-sort，2/2 PASS；检查 PASS 数、GOOD TRAP 与 DiffTest ON | `logs/cpu.log` |
| add M2 固定样本 | 1095 commits、7801 cycles、CPI 7.124；架构与 full trace hash 均复现 M2 | `tests/axi4lite-signoff/add.*` |
| add 随机时序 | 10/10 seeds PASS，每份日志确认 GOOD TRAP 与 DiffTest ON | `tests/seed-logs/` |
| 确定性 add/bubble-sort/hello | 3/3 PASS；hello 正确输出 `I-love-ysyx` | `logs/*-deterministic.log`、`traces/` |

没有运行其余 32 项 CPU tests、RTC、yield-os、RT-Thread，也没有运行 M3 RTL tests、formal、综合或 STA。因此本轮不能表述为“34/34 重新通过”或“B1 system 已通过”。M3 T01–T15 的独立状态清单见 [test-status.csv](test-status.csv)，当前均未开始；已有 M2 证据只列为继承依据。

lint 的既存 warning 为 `ysyx_gen_imm.inst[6:0]` 未使用。新构建的 host C++ 编译另外出现 Verilator/LLVM 头文件的 `__STDC_FORMAT_MACROS`、`__STDC_LIMIT_MACROS` 重定义 warning；本轮未屏蔽或修复它们，没有发现新增 RTL warning。

### 3.1 后续比较用的确定性样本

所有行使用同一个 legacy simulator/reference 与 `max_latency=0, ready=100%`。

| Workload | Cycles | Commits | CPI | Redirects | IF req/rsp | D req/rsp |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| add | 5405 | 1095 | 4.936 | 212 | 1308 / 1308 | 282 / 282 |
| bubble-sort | 631047 | 132175 | 4.774 | 25274 | 157450 / 157450 | 6158 / 6158 |
| hello (`I-love-ysyx`) | 2471 | 460 | 5.372 | 155 | 616 / 616 | 111 / 111 |

六类现有 AXI stall/wait counter 在这些无随机停顿样本中均为 0，仍然存在 adapter/流水控制的固定周期成本；不能把 counter=0 解读为 CPI=1 或没有性能瓶颈。cycles 不含 reset，CPI 为 cycles/commits 的三位小数显示值；现有 redirects 按提交时 `npc != pc + 4` 计数，不等同于未来预测器 mispredict 次数。这些数据无综合频率、面积或功耗结果，不构成 PPA 评估。

后续 M3 使用相同镜像、相同停止口径及明示的 slave 固定延迟比较。M3 的仲裁、寄存缓冲和同步 SRAM 是待测设计成本；不能把相同随机 seed 直接当作旧 C++ 与新 RTL 的同一时序。软件/容量参数变化导致重新编译时，另建新 workload 基线。

### 3.2 关键 hash

add 架构 trace（只含 `nr pc inst npc architectural_state_hash`）在 M2 固定随机样本和本轮确定性样本中均为：

```text
bbf8496edf2329d695eb4437641ced89bba9cf0b6006f1a0b5955c32941e9284
```

M2 固定随机样本 full trace 也复现：

```text
af1a6979fa387c6fb1795cfb1079ae2073c9004f5c1c9cda97dbaed643b7ba6a
```

| 输入 | SHA-256 |
| --- | --- |
| add bin | `d28cd572a35085f9fc278b3f342a8774698e942459aa0a5944a180687cc1e4b5` |
| bubble-sort bin | `8364bd63c6909af0e0f3a479b820c7ae79cf560049c41ed4deee2895e8c80ed2` |
| hello bin（已写入参数） | `95dccde49fa3978b6e3d2fa8ab5d31757954cca106bbb2f8793452ab04673ec3` |
| NEMU reference | `70e2b9ff4c19032e8b8e505cc702886a49d39625a5499700088600f5e9aa1eec` |

其余 ELF、配置、simulator 与 trace hash 统一见 [s0-manifest.json](s0-manifest.json)，不另维护第二份完整列表。

## 4. 输入接口核对与构建隔离约定

已对照当前 Core/adapters 和 M3 plan：

- IFU 仅 AR/R；LSU 有 AR/R/AW/W/B；address/data 32 bit，PROT 3 bit，RESP 2 bit，WSTRB 4 bit。
- IFU/LSU adapter 各自一笔 outstanding，且先缓存 AXI response 再交给 local side；M3 Arbiter 服务槽与 adapter local pending 必须分开计数。
- IFU ARPROT=`101`，LSU ARPROT/AWPROT=`001`；低有效 reset；旧 fetch 不能由 Arbiter 擅自取消。
- LSU AW/W 独立握手，但真实 adapter 通常同时发布 VALID；S1 必须以独立 driver 补 WVALID-first 的请求发布测试。
- adapter 对齐 bus address，打包 WDATA/WSTRB 并右移读数据；M3 slaves 不得推断丢失的 read size/offset。稀疏/zero WSTRB 属于新 SRAM 必测项，不能靠旧 C++ model 证明。
- backend 无新增 AXI 依赖。没有发现阻塞 S1 的端口/协议冲突。

S0 **明确隔离约定，尚未实现 `NPC_PLATFORM` selector**：

| 阶段 | 实际/约定边界 |
| --- | --- |
| 本轮 S0 | 通过已支持的命令行 `OBJ_DIR=<绝对路径>` 隔离 NPC 与模块测试产物；默认 `npc/build/Vysyx_core` 不被本轮重建覆盖 |
| S1–S3 | 新模块单测使用独立 top/Mdir，旧 `ysyx_core` 和 `axi4lite-signoff` 保持 legacy；无需提前建立可运行 B1 系统 |
| S4 | 实现 `NPC_PLATFORM=legacy|b1` 与不同 top/filelist/OBJ_DIR，并让 AM/workload 构建配置隔离；配置切换必须可靠触发重编 |

当前 Makefile 会忽略未使用的变量，因此 **现在传 `NPC_PLATFORM=b1` 不会得到 B1 系统**。不要以该变量作为本轮证据。AM/workload 仍使用原有 build 目录，S0 通过复制实际消费的 ELF/bin 固定输入；不声称 AM profile 隔离已经完成。

## 5. 复现入口

在与本报告源码版本一致的工作区根目录执行。需具备上表工具及有效的共享 reference；若 reference 重建，先记录新 hash。以下 `S0_BUILD` 应选择一个新的绝对目录，避免把后续源码产物混入旧证据。

```bash
export AM_HOME="$PWD/abstract-machine"
export NEMU_HOME="$PWD/nemu"
export NPC_HOME="$PWD/npc"
S0_BUILD="$PWD/npc/build/m3-s0-replay-legacy"
mkdir -p "$S0_BUILD"

make -C npc OBJ_DIR="$S0_BUILD" axi4lite-directed-regress
make -C am-kernels/tests/cpu-tests ARCH=riscv32e-npc \
  ALL='add bubble-sort' OBJ_DIR="$S0_BUILD" run
make -C npc OBJ_DIR="$S0_BUILD" axi4lite-trace-test
make -C npc OBJ_DIR="$S0_BUILD" seed-regress \
  IMG="$PWD/am-kernels/tests/cpu-tests/build/add-riscv32e-npc.bin" \
  RAM_SEEDS='1 2 3 4 5 6 7 8 9 10' RAM_MAX_LATENCY=7 RAM_READY_PERCENT=50

for workload in add bubble-sort; do
  "$S0_BUILD/Vysyx_core" -b \
    -d "$NEMU_HOME/build/riscv32-nemu-interpreter-so" \
    --ram-seed=42 --ram-max-latency=0 --ram-ready-percent=100 \
    --commit-trace="$S0_BUILD/$workload-deterministic.trace" \
    "$PWD/am-kernels/tests/cpu-tests/build/$workload-riscv32e-npc.bin"
done

make -C am-kernels/kernels/hello ARCH=riscv32e-npc \
  OBJ_DIR="$S0_BUILD" mainargs=I-love-ysyx \
  NPCFLAGS="-b -d $NEMU_HOME/build/riscv32-nemu-interpreter-so --ram-seed=42 --ram-max-latency=0 --ram-ready-percent=100 --commit-trace=$S0_BUILD/hello-deterministic.trace" run
```

CPU tests 原聚合脚本可能在子测试失败后仍返回 0；必须同时核对两条 PASS、无 FAIL、两个 GOOD TRAP 与 DiffTest ON。本轮已完成这些检查。模块、异常、trace、seed 的既有目标另有自己的断言与退出检查。

为了复放**完全相同的软件输入**，可直接用本轮归档 `inputs/` 下的 `.bin` 和 reference 运行新建 simulator；普通 `make run` 则会重写 bin 中的 mainargs，必须重新核对 hash。完整现场命令及失败重试记录保存在 `commands.json`。

## 6. 归档与问题记录

本地原始归档目录为 `artifacts/m3-s0-20261014/`，压缩包为 `artifacts/m3-s0-20261014.tar.gz`，相对于仓库根目录。位置在 build 之外，`make -C npc clean` 不会删除它。压缩包 hash 与大小见 [s0-manifest.json](s0-manifest.json) 的 `archive` 字段。

内容包含命令与返回值、初始失败日志、最终成功日志、10 个 seed 的日志、异常 trace/ELF/bin、三个 workload 的 trace/ELF/bin、NPC/reference 二进制与配置、330 个源码文件的快照和逐文件 hash。大日志、二进制与源码快照保留在忽略的 artifacts 目录，不提交为手写源码；本目录只维护结果摘要。当前是本地归档，尚未复制到远端制品库。

本轮发现并处理了两项构建环境问题：

1. Verilator 创建嵌套 Mdir 时父目录不存在，第一次执行失败。显式创建 OBJ_DIR 后解决，复现命令已包含该步骤。
2. ccache 默认临时目录 `/run/user/1000/ccache-tmp` 不可在沙箱内写入，第二次执行失败。获准在沙箱外运行原定向回归后通过；无 RTL 修改，也未改变 ccache 配置以绕过限制。

**当前无未解决的 S0/S1 阻塞项。** 下一步按 S1 实现 Arbiter 与 T01–T04/T08 的独立测试；M3 容量、AM timer、RT-Thread、EDA 条件仍按原计划在后续步骤验证。
