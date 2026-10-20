.section .text
.globl _start
.option norvc
_start:
    la t0,bad
    csrw mtvec,t0
    la s0,constant
    lbu t0,1(s0)
    li t1,0x22
    bne t0,t1,bad
    lhu t0,2(s0)
    li t1,0x4433
    bne t0,t1,bad
    li s0,0x0f000000
    li t0,0x44332211
    sw t0,0(s0)
    lw t1,0(s0)
    bne t0,t1,bad
    li t0,0x80
    sb t0,1(s0)
    lb t1,1(s0)
    li t2,-128
    bne t1,t2,bad
    li t0,0x8877
    sh t0,2(s0)
    lw t1,0(s0)
    li t2,0x88778011
    bne t1,t2,bad
    li s0,0x0f001ffc
    sw t2,0(s0)
    lw t1,0(s0)
    bne t1,t2,bad
    li s0,0x0f001fff
    lbu t1,0(s0)
    li t2,0x88
    bne t1,t2,bad
    li s0,0x20000fff
    lbu t0,0(s0)
    bnez t0,bad
    li a0,0
    ebreak
bad:
    li a0,1
    ebreak
.align 2
constant:
.word 0x44332211
