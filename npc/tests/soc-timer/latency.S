.section .text
.globl _start
_start:
  la t0, handler
  csrw mtvec, t0
  li a3, 0
  li s0, 0x02004000
  sw zero, 4(s0)
  li s1, 500
  sw s1, 0(s0)
  li t0, 128
  csrw mie, t0
  li t0, 0x80010000
  li t1, 0
  li a1, 200
  csrsi mstatus, 8
loop:
  addi t1, t1, 1
  sw t1, 0(t0)
  lw t2, 0(t0)
  bne t1, t2, bad
  blt t1, a1, loop
  csrci mstatus, 8
  beqz a3, bad
  li a0, 0
  ebreak
handler:
  csrr s0, mcause
  li s1, 0x80000007
  bne s0, s1, bad
  addi a3, a3, 1
  li s0, 0x0200bff8
  lw s1, 0(s0)
  addi s1, s1, 1000
  li s0, 0x02004000
  sw s1, 0(s0)
  mret
bad:
  li a0, 1
  ebreak
