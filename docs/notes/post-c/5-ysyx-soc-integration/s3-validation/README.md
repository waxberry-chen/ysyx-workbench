# M5 S3 精选验收证据

> 2026-10-20：M07/M08 的 MROM/SRAM 范围 PASS。实现和源码导读见 [S3](../3-runtime-difftest.md)。

`make -C npc s3-test` 共运行 **31个正向workload、363861次提交**，每条均差分，31次最终整块8KiB SRAM比较通过。设备输入同步为55次读、168次写；整状态skip为0。此处的时间/指令数包含启动poison，不是性能评分。

| 证据 | 用途 |
| --- | --- |
| [manifest.json](manifest.json) | 测试前基准HEAD、实际SoC/RC版本、源码hash、工具、命令及生成产物hash；主仓库改动未提交，不能只用base HEAD代替最终源状态 |
| [run-summary.txt](run-summary.txt)、[results.json](results.json) | 实际运行摘要；results还包含构建和预期失败的负例，不应把条目数当作workload数 |
| [workloads.json](workloads.json) | 每个正向程序的提交/总线/同步计数、栈指针、最终内存检查 |
| [images.json](images.json)、[memory-layout.txt](memory-layout.txt) | binary hash、ROM容量、data/bss/heap/stack预算，代表性VMA/LMA/NOLOAD段 |
| [startup.json](startup.json) | 实际总线2048word非零预填、8word data copy、12word bss clear |
| [cpu-tests.json](cpu-tests.json) | 35项分类：24运行PASS，1超容量，10仅构建；未执行项不计PASS |
| `hello/memory/traps/timer/micro-sieve/micro-fib/endpoints.log` | 代表性原始运行输出 |
| [diff-negative.log](diff-negative.log) | 第5次提交的x5结果翻转1bit，PC `0x20000010` mismatch |
| [missing-data-copy.log](missing-data-copy.log)、[missing-bss-clear.log](missing-bss-clear.log) | 删除初始化store后，独立C自检均以非零a0失败 |
| [rom-overflow-build.log](rom-overflow-build.log)、[ram-overflow-build.log](ram-overflow-build.log) | 链接器拒绝ROM超限及静态数据侵占预留栈 |
| [cpu-hello-str-build.log](cpu-hello-str-build.log) | 原CPU test超MROM3912B的实际诊断 |
| [s2-regression.json](s2-regression.json) | 同一harness下S2完整回归通过；S2原归档未改写 |
| [am-run.log](am-run.log) | 用户AM `ARCH=riscv32e-ysyxsoc run`入口实测通过，默认开启差分 |
| [nemu-normal-check.log](nemu-normal-check.log) | 普通NEMU仍支持32 GPR和M；测试构建禁用tracer自动提交，宿主预加载原shared target所需readline |

全部ELF/map/反汇编/镜像、commit/bus CSV留在`npc/build/m5-s3/`，可用上述命令重建；不提交Verilator生成文件或二进制。manifest的源码hash集合覆盖S2源和本次AM/NEMU/测试依赖，包含部分共用目录源，不应解释为精确编译filelist。

Flash/PSRAM、timer IRQ、完整microbench/RT-Thread、随机系统延迟和新scope综合均未纳入本次PASS。源码变化后应重跑并形成新证据，不能把旧计数自动当成新版本的验收结果。
