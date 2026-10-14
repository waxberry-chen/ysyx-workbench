# M3 S4：Core/B1 系统集成

日期：2026-10-14。**S4 PASS，无未解决阻塞；下一步 S5 RT-Thread 与 coverage closure。** 起点为 `d5d4fcf647a93f32098ceb157a6ba3ad55471c99`，初始工作区干净。本轮候选源码与原始证据由 [s4-manifest.json](s4-manifest.json) 标识；本报告不是整个 M3 sign-off。

## 1. 系统与仿真边界

```text
ysyx_b1_top
  ysyx_core_axi4lite
    Core IFU adapter ─┐
                     ├─ Arbiter ─ single AXI4-Lite master
    Core LSU adapter ─┘                          │
                                               Xbar
                                     ┌──────────┼─────────┬─────────┐
                                    SRAM       UART     CLINT    DECERR
```

[Core wrapper](../../../../npc/vsrc/top/ysyx_core_axi4lite.sv) 保留原 Core 和两个 adapter，仲裁后只导出一个完整 master；[B1 wrapper](../../../../npc/vsrc/top/ysyx_b1_top.sv) 再连接 Xbar 与四类 slave。地址、PROT、WSTRB、错误响应沿用 S1–S3 契约。所有模块共用 clk/reset，现有协议 assertions 在系统构建中开启。Core 微架构及 NEMU reference ABI 未修改。

[platform.cpp](../../../../npc/csrc/platform.cpp) 只负责初始装载、UART 事件接收、被动统计和调试器读内存。B1 构建不链接旧 C++ RAM/MMIO/device 模型：

- loader 先检查镜像非空且不超容量，在 reset 期间将镜像及零填充余量写入 RTL SRAM；相同初始化内容复制到 REF。此为仿真初始化，不是硬件上电清零逻辑。
- 正常运行只有 AXI 能写 SRAM；SDB `x` 直接读 RTL array，不能回读只用于装载的 host pmem。B1 debugger write 明确不支持。
- 每周期接收 `tx_valid/tx_data`，stdout 与可选 `NPC_UART_LOG` 输出同一个字节流。没有第二份 C++ UART 回调；停止时可有 speculative outstanding，因此报告区分已接受与已完成事务，不声称强行 drain。
- 保留 commit、GPR/CSR DiffTest 与统计。异常路径先调用 REF trap 并比较状态，然后才考虑正常 MMIO skip，不能让 MMIO fault 被 skip 掩盖。
- 当前 REF 为 128 MiB PMEM，ABI 没有容量查询；B1 harness 编译时拒绝更大的 SRAM。换用其他 REF 配置仍须核对其实际容量和状态 ABI。

两个 wrapper 的 monitor 输出为被动观察信号，不参与 ready/valid 控制。系统默认最多运行 50000000 周期，可用正整数 `NPC_MAX_CYCLES` 调整；超过上限返回失败。

## 2. 构建与 AM profile

`ARCH=riscv32e-npc` 保持不变，新增 `NPC_PLATFORM=legacy|b1`，默认 legacy。B1 默认 `SRAM_BYTES=1048576`、`MTIME_HZ=1000000`。

| 对象 | legacy | B1 |
| --- | --- | --- |
| RTL 顶层/filelist | `ysyx_core` / `filelist.f` | `ysyx_b1_top` / `filelist-b1.f` |
| NPC 输出目录 | `npc/build/` | `npc/build/b1-<bytes>-<hz>/` |
| AM object/library/image 后缀 | `riscv32e-npc` | `riscv32e-npc-b1-<bytes>-<hz>` |
| 设备时间 | 旧 host timer 契约 | RTL mtime，每周期增加 1 |
| 延迟设置 | 原 C++ RAM 参数 | 固定 RTL 时序；拒绝 `--ram-*` 参数 |

容量同时决定 RTL、harness preload、AM heap 末端和 linker 检查。镜像/静态区、预留 stack 和 heap 起点超出容量时链接失败；这不等于对程序运行期间栈深度或 heap 使用做动态证明。

AM uptime 使用 high-low-high 重试，并把 ticks 按 MTIME_HZ 换算为微秒；先除后分余数，避免直接 `ticks * 1000000` 过早溢出。`has_rtc=false`，RTC 返回固定占位字段（year=1900，其余为 0），不访问不存在的日历寄存器。MTIME_HZ 是仿真时间单位，不是综合得到的 Fmax。

### 实际发现并修复的构建 bug

首次 B1 add 在 DiffTest 初始化时 segfault。GDB 定位到内存拷贝，反汇编仍出现 128 MiB 长度，而 B1 host pmem 只有 1 MiB。根因是 Verilator 自动把 `..` 加入 VPATH：嵌套的 B1 构建找到了父目录 legacy 的 `dut.o`，错误复用编译宏不同的对象。

修复是在项目 rewrite.mk 中移除该父目录搜索路径，保留源文件绝对路径；host 对象依赖配置 stamp。不同 profile/容量/频率分别保存对象、库和镜像。修复后 B1、legacy 和第二组容量/频率均通过。构建目录命名不同并不自动保证隔离，这是本轮可展示的实际 bug case。

首轮测试脚本还修正了 hello-str 的预期（它只检查 sprintf，不输出 UART）、AM TEST 参数避免递归覆盖库 NAME、缺失 klib 声明和裸机异常镜像的 PIE 编译选项。后者曾生成跨度约 2 GiB 的稀疏镜像，被 loader 容量检查拒绝。最终运行未观察到 RTL/DiffTest mismatch。

## 3. 验收结果

[系统测试脚本](../../../../npc/tests/b1_system_test.py) 对每个进程检查退出码和 GOOD TRAP，保存完整 commit trace，核对异常次数/原因、UART 精确字节流及必要的 route 统计。每个软件构建单独检查返回值，不依赖外层 make 的汇总状态。

| 用例 | 默认 1 MiB / 1 MHz 结果 |
| --- | --- |
| CPU tests | **34/34 PASS**，全部 DiffTest ON；排除与既有异常策略不兼容的原 unalign |
| hello | 460 commits / 7609 cycles；精确匹配 `Hello, AbstractMachine!` 与 `mainargs = 'I-love-ysyx'.` 两行 |
| lanes | 193 / 2925；真实末端 SRAM word 的 lb/lbu/lh/lhu/lw/sb/sh/sw、符号扩展与读回通过 |
| uptime | 5812 / 96664；100 次单调读取、原始 ticks 前后包围换算结果、has_rtc 与占位字段通过 |
| 有限 yield-os | 8225 / 135908；两个 AM kcontext 各 32 次输出/让出，输出严格 `AB` × 32；65 次 cause 11，GPR/CSR DiffTest 通过 |
| DECERR | 地址 0 与 SRAM 结束地址各测 fetch/load/store，共 6 例；cause 1/5/7、mepc、load 目的寄存器保持正确 |
| SLVERR | UART/CLINT fetch、UART read、CLINT write、UART reserved write、UART word-mask write，共 6 例；route 错误计数非零，UART 无副作用 |
| misaligned | cause 4/6 两例；LSU AR/AW/W 接受数均为 0 |
| redirect + 错误旧取指 | 在 SRAM 最后一个 word 执行返回，后继越界取指产生 **1 次实际 DECERR**；返回路径成功，架构异常提交数为 0 |
| 总数 | **53 个有限系统程序 PASS**（34 + hello/3 个 AM 程序 + 14 异常 + redirect） |

额外检查：

- 256 KiB / 2 MHz 独立构建运行 lanes、uptime、yield-os，**3/3 PASS**；uptime 为 280783 commits / 3506732 cycles，RV32 软件换算代码随常量改变，不能把它当作同一指令流的硬件性能对照。
- 两组配置的 SDB 均读到软件写入末 word 的 `0x13579bdf`；容量 + 1 byte 镜像拒绝、旧 RAM 参数拒绝、10-cycle watchdog 退出均通过。
- 4 B 的 AM 链接负例以指定容量/stack 诊断拒绝；大于当前 REF 容量的 harness 编译负例以 static_assert 拒绝。
- legacy **34/34 CPU tests**、固定 add trace、cause 1/4/5/6/7 回归、原 M2 IFU+adapter redirect 定向测试通过。
- Core、Core wrapper、B1 三个顶层 lint 通过，仅有原 `ysyx_gen_imm.inst[6:0]` 未使用告警；此处使用现有 `-Wno-fatal` lint 入口，不称为零 warning strict lint。系统仿真协议 assertions 开启。

### add 架构与周期记录

| 配置 | commits | cycles | CPI | IF 接受/完成 | LSU 完成 |
| --- | --- | --- | --- | --- | --- |
| legacy，seed=42 / max-latency=3 / ready=75% | 1095 | 7801 | 7.124 | 1310/1310 | 282 |
| B1，固定 RTL 时序 | 1095 | 16402 | 14.979 | 1308/1308 | 282 |

两者 trace 前五列（序号、PC、指令、next PC、架构状态 hash）的 SHA-256 均为 `bbf8496edf2329d695eb4437641ced89bba9cf0b6006f1a0b5955c32941e9284`。B1 的 LSU 为 243 loads + 39 stores，SRAM 全部 OKAY。互联寄存级与共享路径引入延迟，时序不同也改变 speculative fetch 数量。这个表是两种已注明模型的功能/周期基线，不是受控架构优化实验，更不是 PPA 结果。

## 4. 复现与证据

```bash
# 默认配置：构建 + 53 个系统程序 + debugger/loader/参数/watchdog 检查
make -C npc b1-system-test

# 第二组配置的 focused AM 检查
make -C npc NPC_PLATFORM=b1 SRAM_BYTES=262144 MTIME_HZ=2000000 build
python3 npc/tests/b1_system_test.py \
  --binary npc/build/b1-262144-2000000/Vysyx_b1_top \
  --out npc/build/b1-system-test-262144-2000000 \
  --sram-bytes 262144 --mtime-hz 2000000 --focused

# 常规 AM 程序入口
make -C am-kernels/kernels/hello ARCH=riscv32e-npc \
  NPC_PLATFORM=b1 mainargs=I-love-ysyx run

# 旧系统兼容性
make -C npc NPC_PLATFORM=legacy axi4lite-cpu-regress axi4lite-trace-test
make -C npc NPC_PLATFORM=legacy ifu-axi4lite-adapter-integ-test \
  access-fault-test address-misaligned-test
```

默认结果目录为 `npc/build/b1-system-test-1048576-1000000/`，包含 `commands.json`、`results.csv`、`guards.json`、逐项日志/trace/UART。工具与源码 hash、镜像、ELF、reference、测试二进制及失败/最终日志保存到 build 外的 `artifacts/m3-s4-20261014.tar.gz`，外层 hash 见 manifest；目前为本地归档。首轮 ccache 与 GDB ptrace 的沙箱限制经授权处理后解除，没有留下工具阻塞。

## 5. S5 保留项

S4 的系统集成出口已满足；T11 的 B1 异常来源有端到端证据，T12 只有上述实际 stale-error 场景及原 M2 定向回归。**不能把它标成全部 redirect phase × RRESP 覆盖完成。** 后续还需带 Arbiter 的受控竞争/同拍 redirect、完整 fabric 双 master scoreboard、随机反压/延迟 shim、reset epoch 和必要交叉覆盖。

RT-Thread 固定 BSP/workload、系统波形、完整覆盖矩阵、M3 sign-off 在 S5；RT-Thread 容量尚未量测。S4 没有新增随机时序系统测试，也没有执行 formal、四值仿真、综合/STA、SRAM macro 映射或 PPA。相关面试问答见 [qa/README.md](qa/README.md)。
