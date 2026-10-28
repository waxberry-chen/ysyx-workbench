# 工程知识笔记

用于回顾可跨阶段复用的概念和工程方法。具体实验的配置、指标及验收结论仍以各 milestone 的记录为准。

| 笔记 | 内容 |
| --- | --- |
| [SoC 仿真与验证入门：谁在执行，谁在观察，谁来判断对错](soc-simulation-and-verification-basics.md) | 宿主机与目标 CPU；EXE、参考库和程序镜像；启动与检查链；poison、负例、a0 和 DiffTest 边界 |
| [读懂 Python 测试脚本：从对象来源到一次测试判定](python-test-runner-reading-guide.md) | 模块/类/对象、属性与方法；如何发现接口；Path、subprocess、JSON；逐步读懂 run/simulate；最小正负例实验 |
| [从源码名字到机器指令：汇编标签、符号表、ELF 与重定位入门](symbols-elf-and-relocation-basics.md) | 先修教程；名字/地址/内容的区别；标签、directive、伪指令与命名约定；可操作的汇编链接实验；S3 poison、负例补丁与 a0 观察 |
| [裸机程序如何启动：程序节、链接脚本与 ROM/RAM 布局](bare-metal-linker-script-and-startup.md) | 编译/链接/启动分工；section、VMA/LMA 与镜像偏移；GNU ld 基础语法；`_stack_top` 等链接器符号的 C/汇编引用；M5 S3 布局实例与检查方法 |
| [SoC 裸机程序的构建、存储布局与启动：M5 S3/S4 源码阅读笔记](soc-build-and-boot-reading-notes.md) | 旧 NPC 与三种 SoC 启动配置的文件对照；`.ld/.S`、AM、复位与镜像装载的阅读路线；产物检查方法与个人阅读记录 |
| [RT-Thread 系统测试入门：线程、抢占、睡眠与上下文切换](rtthread-scheduling-sleep-and-preemption-basics.md) | 线程状态、优先级与时间片；硬件计数与 OS tick；sleep 到唤醒的源码路径；AM 上下文切换；S6 抢占、数据保持与资源检查的目的 |
| [从评估指标反推 SDC：首次综合 / STA 的约束设计](metrics-aware-sdc.md) | 首次编写前的参数表；指标与约束映射；IO min/max 推导；cap/slew/fanout、clock/reset 决策；注释模板及新模型接手指南 |
| [阅读综合网表与 STA 报告：层次、实例、引脚和网络](netlist-and-timing-report-navigation.md) | 从报告路径定位单元及连接；常见引脚命名；FF 的 `_reg` 名称；跨层追踪信号的方法 |
| [综合 / STA 可信度评估：依据、检查命令与 synth 03 实例](synthesis-sta-credibility.md) | 分析可信与约束达标的区别；DC/PT 命令及检查范围；coverage/false path；03 的最小电容、复位脉宽、高扇出与禁用弧定位 |
