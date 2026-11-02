形成了第一版简历 (docs/notes/output/playground/261102-resume.pdf). 马上准备做第一轮复习+素材整理+可展示性准备. 

我预计: 
1. 讨论明确简历中出现的概念+顺着概念延伸出的具体问题, 从 “主观感受到陌生的概念” 到更多 “通过考察被动发现的概念”. 确保提问 “什么是 xxx” “xxx具体做了什么” 时候不能不知道. 
2. 制作专题 ppt 以复盘自己对于特定方面的掌握. 

第一波主观感受需要做的内容有: 

概念以及衍生出的问题: 
- 精确异常与定时器中断. 
- 提交训练. 
- AXI4 单拍适配. 
- 仲裁 (以及背后具体的仲裁算法). 
- Chisel blackbox. 
- SVA 和定向测试, 具体有哪些场景. 
- 总线随机延时是什么? 如何实现. 
- backpressure 的概念, 时序行为. 
- 异常, 中断怎么验证? 
- 分支重定向是什么? 如何验证? 

专题: 
- 微架构/处理器 RTL 架构图. 明确具体 feature 的 datapath 以及实现, 能描述清楚: 写回旁路发生在哪; 访存等待控制如何实现; 硬件层面如何支持精确异常与定时器中断; GShare 分支预测带来哪些硬件增量? 支持处理哪些指令? 有何种开销实现了何种收益? ; 提交训练如何进行? ; 预测失败时如何 redirect. (预计 2-3 页 ppt)

- SoC/ysyxSoC/Rocket-chip 的关系和架构. SoC wrapper 的架构. Chisel blackbox 的语法, AXI4-Lite 如何兼容到 SoC wrapper 接口. (预计 1 页 ppt)

- 完整的验证/仿真平台框架: 如何通过 Dynamic linking NEMU ref 实现 Difftest, 通过哪些 Difftest ABI (API) 实现. SVA 常见语法, SVA 包括哪些场景. (预计 2 页 ppt)

- 综合/STA flow 搭建: 完整 Digital ic (ASIC) flow, 当前工程的 pre-PnR flow 示意, 如何进行有质量的 PPA 评估, 收集典型场景. (预计 1 页 ppt)

- SoC 软件/启动: bare-metal 流程, AM 充当什么功能+是如何抽象的. linker script + startup code 语法、原理、实现哪些功能、如何实现. 异常/中断的软件层面如何配合支持. (预计 2 页 ppt)

