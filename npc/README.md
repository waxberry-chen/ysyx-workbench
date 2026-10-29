# NPC：M5 SoC 集成与验收

当前维护的硬件路径为 `ysyx_core → AXI4 adapter/arbiter → router/CLINT → ysyx_25030087`。
已实现真实 SPI/XIP、Flash → SRAM/PSRAM 启动、存储/IRQ DiffTest、machine timer interrupt 与有限 RT-Thread 抢占/唤醒；MROM 配置保留用于诊断回归。

```sh
make -C npc s2-test
make -C npc s3-test
make -C npc s4-test
make -C npc s5-test
make -C npc s6-test
# 干净功能复现；目录必须尚不存在，不调用 DC/PT：
make -C npc s8-test S8_ARGS="--out /绝对路径/新的S8目录"
make -C npc/tests/soc-runtime ARCH=riscv32e-ysyxsoc run
make -C npc run IMG="$PWD/npc/build/m5-s2/uart.bin" \
  ARGS="--trace build/m5-s2/uart.fst --uart-log build/m5-s2/uart.tx"
make -C npc s1-test
# 按需单独运行：
make -C npc s1-protocol-test
make -C npc s1-cpu-test
make -C npc s1-elaboration-test
```

依赖 Verilator（支持 `--timing`）、C++17、Python3、`riscv64-linux-gnu-gcc/objcopy/nm`；
SoC 构建还需要 S0 的 Java/Mill/firtool 环境；`build/run/s2-test` 自动检查并生成 `ysyxSoC/build/ysyxSoCFull.v`。运行产物在 `npc/build/m5-s1/`；
代表性波形为 `memory-1.fst`，commit 明细为 `memory-1.trace`。ISA 程序明细保留在 `npc/build/isa-contract-test/`。

- `filelist-soc.f` 是当前 CPU 子系统源闭包；`filelist.f` 仅列 core 与 adapters，不能直接配旧 C++ harness 运行。
- `NPC_PLATFORM=legacy/b1`、旧 `b1-*`/`axi4lite-*` 系统验收入口已停用；`build/run/sim` 当前运行真实 SoC，默认 IMG 是最多 4 KiB 的 MROM raw binary；`SOC_BOOT=flash` 时为最多 16 MiB 的 Flash 镜像。
- `filelist-b1.f`、B1 设备/fixture、`scripts/build.mk` 和旧 `csrc` 暂留作迁移参考，不属于当前可运行入口，不构成第二条兼容实现；历史运行使用 M4/S0 对应 Git revision。
- 旧 `ARCH=riscv32e-npc` 系统测试不再是当前运行入口。新平台 `ARCH=riscv32e-ysyxsoc` 的 `run` 默认开启差分，使用独立 `nemu/build/ysyxsoc/nemu-ref.so`，不修改普通 NEMU `.config`。
- `flow/` 的 M4 Lite scope 已停用并给出明确诊断；已存在 run 仍可 inspect，历史基线用原 Git revision 复现。M5 CPU scope/SDC 与 cap90 基线见 [S7](../docs/notes/post-c/5-ysyx-soc-integration/7-synthesis-sta.md)，不包含完整 SoC 存储/外设物理实现。

设计与测试迁移说明见 [M5 S1](../docs/notes/post-c/5-ysyx-soc-integration/1-axi4-interface.md)。

S2 产物位于 `npc/build/ysyxsoc/` 和 `npc/build/m5-s2/`；harness 不预加载 SRAM。默认100 MHz、UART接收器8N1/每bit16周期；波特率变化时设置 `--uart-bit-cycles`。详细运行、错误策略与证据见 [M5 S2](../docs/notes/post-c/5-ysyx-soc-integration/2-bringup.md)。

S3 产物位于 `npc/build/m5-s3/`；MROM限制4KiB，SRAM8KiB，CPU执行非零预填/data搬运/bss清零，栈预留2KiB。31个正向workload、容量分类和负例说明见 [M5 S3源码导读](../docs/notes/post-c/5-ysyx-soc-integration/3-runtime-difftest.md)。原始 `run IMG=...` 可用 `ARGS="--diff /absolute/path/nemu-ref.so"` 开启差分；S2无差分模式仍用于定向测试。

S4 入口为 `make -C npc s4-test`，产物位于 `npc/build/m5-s4/`。MROM 与 Flash 仿真器分别位于 `build/ysyxsoc/`、`build/ysyxsoc-flash/`，Flash 配置的 reset PC 为 `0x30000000`。AM 应用选择 `SOC_BOOT=flash-sram` 或 `SOC_BOOT=flash-psram`，`run` 自动转换成 NPC 的 Flash 硬件配置并开启 DiffTest。harness 不预装 RAM；全部代码/data 搬运和 bss 清零由 CPU 执行。容量、串行模型边界与阅读顺序见 [M5 S4](../docs/notes/post-c/5-ysyx-soc-integration/4-boot-memory.md)。

S5 的 IRQ/上下文检查见 [定时器中断](../docs/notes/post-c/5-ysyx-soc-integration/5-timer-interrupt.md)；S6 的四组系统回归见 [系统验证](../docs/notes/post-c/5-ysyx-soc-integration/6-system-validation.md)。S8 从本地仓库建立独立源码工作区，重新生成 SoC、构建四种仿真器/参考端/软件并补齐各阶段测试；必须同时具有独立的 `am-kernels`、`rt-thread-am` checkout 和完整 SoC 递归依赖。复现边界、证据和后续比较条件见 [S8](../docs/notes/post-c/5-ysyx-soc-integration/8-reproduction-handoff.md)。
