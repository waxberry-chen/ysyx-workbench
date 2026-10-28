// Bare trap test: expected cause/EPC/count are software constants, not a
// reference model initialized from the DUT's reported exception.
.section .text
.globl _start
_start:
  la t0, handler
  csrw mtvec, t0
  li a3, 0
  li a4, 0
  li a5, 0
  li s1, 0x02004000
  sw zero, 4(s1)
  sw zero, 0(s1)         // timer remains pending until second interrupt
  csrr t0, mip
  li t1, 128
  bne t0, t1, bad
  csrw mip, zero        // MTIP is read-only, even through a legal CSR write
  csrr t0, mip
  bne t0, t1, bad
  csrsi mstatus, 8      // MIE=1, MTIE=0: no delivery
  addi a5, a5, 1
  csrci mstatus, 8
  li t0, -1
  csrw mie, t0
  csrr t0, mie
  bne t0, t1, bad       // only MTIE implemented
  addi a5, a5, 1        // MIE=0, MTIE=1: no delivery
  la s0, after_enable
  csrsi mstatus, 8
after_enable:
  addi a4, a4, 1        // must run once, after TWO entries at this same EPC
  csrci mstatus, 8
  li t0, 2
  bne a3, t0, bad
  bne a5, t0, bad
  li t0, 1
  bne a4, t0, bad
  la s0, illegal
illegal:
  csrr t0, 0x301        // unsupported CSR still illegal
  li t0, 3
  bne a3, t0, bad
  li a0, 0
  ebreak
handler:
  csrr t0, mepc
  bne t0, s0, bad
  csrr t0, mcause
  li t1, 2
  beq t0, t1, sync
  li t1, 0x80000007
  bne t0, t1, bad
  csrr t0, mstatus
  li t1, 0x1880
  bne t0, t1, bad
  addi a3, a3, 1
  li t0, 1
  beq a3, t0, return_pending
  li t0, -1
  sw t0, 4(s1)         // rearm far into future; deassert MTIP
return_pending:
  mret                 // never add 4 for an interrupt
sync:
  addi a3, a3, 1
  addi s0, s0, 4
  csrw mepc, s0
  mret
bad:
  li a0, 1
  ebreak
