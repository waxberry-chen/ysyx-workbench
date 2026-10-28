// Two peers rendezvous repeatedly without a call, ECALL, yield or sleep.
// A peer can advance only if the timer has really switched to the other one.
.section .text
.globl preempt_registers
preempt_registers:
  addi sp, sp, -32
  sw ra, 0(sp)
  sw gp, 4(sp)
  sw tp, 8(sp)
  sw s0, 12(sp)
  sw s1, 16(sp)
  sw a0, 20(sp)
.macro SENTINEL reg, value
  li \reg, \value
  add \reg, \reg, a0
.endm
  SENTINEL ra, 0x12300100
  SENTINEL gp, 0x12300300
  SENTINEL tp, 0x12300400
  SENTINEL s0, 0x12300800
  SENTINEL s1, 0x12300900
  SENTINEL a1, 0x12300b00
  SENTINEL a2, 0x12300c00
  SENTINEL a3, 0x12300d00
  SENTINEL a4, 0x12300e00
  la t1, progress
  slli a5, a0, 2
  add t1, t1, a5
  xori a5, a0, 1
  slli a5, a5, 2
  la t2, progress
  add t2, t2, a5
  li t0, 0
next_round:
  addi t0, t0, 1
  sw t0, 0(t1)
wait_peer:
  lw a5, 0(t2)
  bltu a5, t0, wait_peer
.macro CHECK reg, value
  li a5, \value
  add a5, a5, a0
  bne \reg, a5, bad_context
.endm
  CHECK ra, 0x12300100
  CHECK gp, 0x12300300
  CHECK tp, 0x12300400
  CHECK s0, 0x12300800
  CHECK s1, 0x12300900
  CHECK a1, 0x12300b00
  CHECK a2, 0x12300c00
  CHECK a3, 0x12300d00
  CHECK a4, 0x12300e00
  lw a5, 20(sp)
  bne a0, a5, bad_context
  lw a5, 0(t1)
  bne t0, a5, bad_context
  li a5, 6
  bltu t0, a5, next_round
  lw ra, 0(sp)
  lw gp, 4(sp)
  lw tp, 8(sp)
  lw s0, 12(sp)
  lw s1, 16(sp)
  addi sp, sp, 32
  ret
bad_context:
  li a0, 91
  ebreak
