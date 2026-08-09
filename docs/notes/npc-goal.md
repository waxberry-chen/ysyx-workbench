
# ysyx npc 期望

预期实现 Processor 可以描述为：

> A RV32 RISC-V MCU-class SoC processor featuring a pipelined in-order core with decoupled frontend, GShare branch prediction, L1 cache subsystem, AXI-based SoC interconnect, and RTOS support.

> 一个面向嵌入式 SoC 的 RV32 RISC-V 处理器，实现基于五级流水线的顺序执行核心，并引入前端解耦、GShare 分支预测、L1 Cache、AXI 总线互联以及 RTOS 运行支持。

---

# 1 Processor Features

## 1.1 ISA / System Support

### 1.1.1 RISC-V RV32 Core

* 支持 RV32 ISA（建议 RV32IM/A/F 根据工作量选择）
* 完整异常与中断机制
* CSR（Control and Status Register）支持
* 特权级支持：

  * Machine Mode (M-mode)
  * 可选 User Mode (U-mode)

目标：

支持裸机程序、RTOS 运行环境。

---

## 1.2 SoC Integration

### 1.2.1 MMIO Peripheral Support

支持简单外设：

* UART
* Timer
* GPIO（可选）

通过 memory mapped interface 访问：

```
CPU Load/Store
        |
        |
   Address Decoder
        |
 +------+------+
 |             |
RAM        Peripheral
```

---

### 1.2.2 AXI-based SoC Interconnect

采用 AXI 总线连接：

```
              CPU Core

                 |
              AXI Master

                 |

          AXI Interconnect

          /            \

       SRAM          Peripheral
```

目标：

模拟工业 SoC 中 CPU 与 memory/peripheral 的连接方式。

（初期实现 AXI interconnect，而非复杂多 master crossbar。）

---

# 2 Microarchitecture Features

## 2.1 Improved 5-stage Pipeline

基础：

```
IF
ID
EX
MEM
WB
```

在经典五级流水基础上增强：

* Data forwarding
* Hazard detection
* Pipeline stall
* Branch flush

目标：

实现稳定、高性能的 in-order pipeline。

---

## 2.2 Decoupled Frontend

引入 frontend/backend 解耦思想：

```
          Frontend

PC
 |
Branch Predictor
 |
Instruction Fetch
 |
Instruction Buffer
 |
          Backend

Decode
Execute
Memory
Writeback
```

通过 instruction buffer：

* 吸收 fetch latency
* 提高 pipeline utilization
* 支持预测驱动取指

---

## 2.3 Branch Prediction Unit

实现：

### 2.3.1 GShare Predictor

组成：

* Global History Register (GHR)
* Pattern History Table (PHT)
* 2-bit Saturating Counter

例如：

```
PC XOR GHR
      |
      v
     PHT
      |
      v
 Taken / Not Taken
```

---

### 2.3.2 简易 BTB

Branch Target Buffer：

保存：

```
Branch PC
     |
Target Address
```

用于快速生成下一条 fetch 地址。

目标：

实现接近工业 MCU core 的 branch prediction。

---

## 2.4 L1 Cache

实现一级 Cache：

优先：

* Instruction Cache
* Data Cache

例如：

```
             CPU

          /       \

      I-Cache    D-Cache

          \       /

              AXI
```

目标：

学习：

* cache organization
* tag/index/offset
* refill
* write policy

---

# 3 Software Target

## 3.1 RTOS Support

目标：

能够运行 RT-Thread（优先 Nano 版本）。

需要支持：

* Timer interrupt
* External interrupt
* Context switch
* System call/trap mechanism

验证处理器具备完整 SoC 执行环境。

---

# 4 Security / Verification Extension（可选）

结合个人方向，可以扩展：

## 4.1 PMP

Physical Memory Protection：

* 地址区域权限控制
* 安全隔离

比 MMU 更适合 MCU 场景。

---

## 4.2 Verification Infrastructure

建议作为项目亮点：

* ISA differential testing
* Assertion-based verification
* Random instruction testing
* Performance counters

例如：

```
cycle counter

branch prediction accuracy

cache miss counter

stall reason counter
```

---

# 暂不实现

## MMU

暂不作为核心目标。

原因：

* MMU 更偏向 Linux/Application Processor
* 需要：

  * Sv32 page table
  * TLB
  * Page fault
  * Virtual memory management
* 会显著扩大工程范围

未来可作为扩展：

```
RV32
 |
Sv32 MMU
 |
Linux-capable processor
```

---


