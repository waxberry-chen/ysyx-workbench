/* Called from AM main. No AM handler needed: check cause/EPC independently,
 * return via MRET, and verify failed writes/loads had no architectural effect. */
.section .text
.globl main, mis_lh, mis_lw, mis_sh, mis_sw, oob_load, oob_store, rom_store, do_ecall
main:
  addi sp, sp, -8
  sw s0, 0(sp)
  sw s1, 4(sp)
  la t0, handler
  csrw mtvec, t0
  li a3, 0
  la a1, cell
  li t0, 0x87654321
  sw t0, 0(a1)
  li a4, 0x12345678
  la s0, mis_lh
  li s1, 4
mis_lh:
  lh a4, 1(a1)
  la s0, mis_lw
mis_lw:
  lw a4, 2(a1)
  la s0, mis_sh
  li s1, 6
mis_sh:
  sh t0, 1(a1)
  la s0, mis_sw
mis_sw:
  sw t0, 2(a1)
  li a2, 0x0f002000
  la s0, oob_load
  li s1, 5
oob_load:
  lw a4, 0(a2)
  la s0, oob_store
  li s1, 7
oob_store:
  sw t0, 0(a2)
  li a2, 0x20000000
  la s0, rom_store
rom_store:
  sw t0, 0(a2)
  la s0, do_ecall
  li s1, 11
do_ecall:
  ecall
  li t1, 8
  bne a3, t1, bad
  li t1, 0x12345678
  bne a4, t1, bad
  lw t1, 0(a1)
  bne t0, t1, bad
  lw s0, 0(sp)
  lw s1, 4(sp)
  addi sp, sp, 8
  li a0, 0
  ret
handler:
  csrr t1, mcause
  bne t1, s1, bad
  csrr t1, mepc
  bne t1, s0, bad
  addi t1, t1, 4
  csrw mepc, t1
  addi a3, a3, 1
  mret
bad:
  li a0, 1
  ebreak
.section .bss
.align 2
cell: .space 4
