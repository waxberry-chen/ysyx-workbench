// Train PHT entry 119 with 39 taken branches at word index 8, then one NT.
// History is now 126; entry 119 decremented from 3 to 2 (still predicts T).
// Victim at word index 9 aliases that entry.
// It is actually NT; its target must never execute/train/raise a trap.
.option norvc
.option norelax
.section .text
.globl _start
_start:
    li s0, 0x0f000000
    li t0, 0x55
    sw t0, 0(s0)
    li a1, 40
    la t2, fail
    csrw mtvec, t2
.org 0x1c
loop:
    addi a1, a1, -1
    bnez a1, loop
    j victim
.org 0x224
victim:
#if WRONG_KIND == 4
    .word 0x5c001ee3 // BNE x0,x0,+0xddc -> 0x20001000; prevent assembler long-branch rewrite
#else
    bne zero, zero, wrong
#endif
    j good
    nop
wrong:
#if WRONG_KIND == 0
    sw zero, 0(s0)
#elif WRONG_KIND == 1
    csrw mtvec, zero
#elif WRONG_KIND == 2
    .word 0xffffffff
#elif WRONG_KIND == 3
    beq zero, zero, fail
#else
    nop
#endif
    j fail
good:
    lw t0, 0(s0)
    li t1, 0x55
    bne t0, t1, fail
    csrr t0, mtvec
    bne t0, t2, fail
    li a0, 0
    ebreak
fail:
    li a0, 1
    ebreak
