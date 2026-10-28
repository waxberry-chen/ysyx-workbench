.section .text
.globl timer_register_check
timer_register_check:
  addi sp, sp, -32
  sw ra, 0(sp)
  sw s0, 4(sp)
  sw s1, 8(sp)
  sw gp, 12(sp)
  sw tp, 16(sp)
  // The trap handler executes C and clobbers caller-saved registers. Each
  // sentinel therefore proves assembly context save/restore, not C ABI luck.
  li ra, 1
  li gp, 3
  li tp, 4
  li t0, 5
  li t1, 6
  li t2, 7
  li s0, 8
  li s1, 9
  li a0, 10
  li a1, 11
  li a2, 12
  li a3, 13
  li a4, 14
wait_tick:
  la a5, ticks
  lw a5, 0(a5)
  addi a5, a5, -4
  bnez a5, wait_tick
.macro CHECK reg, value
  li a5, \value
  bne \reg, a5, bad_register
.endm
  CHECK ra, 1
  CHECK gp, 3
  CHECK tp, 4
  CHECK t0, 5
  CHECK t1, 6
  CHECK t2, 7
  CHECK s0, 8
  CHECK s1, 9
  CHECK a0, 10
  CHECK a1, 11
  CHECK a2, 12
  CHECK a3, 13
  CHECK a4, 14
  lw ra, 0(sp)
  lw s0, 4(sp)
  lw s1, 8(sp)
  lw gp, 12(sp)
  lw tp, 16(sp)
  addi sp, sp, 32
  ret
bad_register:
  li a0, 2
  ebreak
