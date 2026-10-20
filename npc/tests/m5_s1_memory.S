// Directed CPU load/store lanes + byte-side-effect responder + local CLINT.
.section .text
.globl _start
.option norvc
_start:
    la t0, bad
    csrw mtvec,t0
    la s0, scratch
    li t0,0x44332211
    sw t0,0(s0)
    lbu t1,0(s0)
    li t2,0x11
    bne t1,t2,bad
    lbu t1,1(s0)
    li t2,0x22
    bne t1,t2,bad
    lbu t1,2(s0)
    li t2,0x33
    bne t1,t2,bad
    lbu t1,3(s0)
    li t2,0x44
    bne t1,t2,bad
    lhu t1,0(s0)
    li t2,0x2211
    bne t1,t2,bad
    lhu t1,2(s0)
    li t2,0x4433
    bne t1,t2,bad
    li t0,0x80
    sb t0,1(s0)
    lb t1,1(s0)
    li t2,-128
    bne t1,t2,bad
    li t0,0x8001
    sh t0,2(s0)
    lh t1,2(s0)
    li t2,-32767
    bne t1,t2,bad
    lw t1,0(s0)
    li t2,0x80018011
    bne t1,t2,bad
    // Every write lane, then both halfword positions; untouched bytes survive.
    li t0,0x11
    sb t0,0(s0)
    li t0,0x22
    sb t0,1(s0)
    li t0,0x33
    sb t0,2(s0)
    li t0,0x44
    sb t0,3(s0)
    lw t1,0(s0)
    li t2,0x44332211
    bne t1,t2,bad
    li t0,0x6655
    sh t0,0(s0)
    li t0,0x8877
    sh t0,2(s0)
    lw t1,0(s0)
    li t2,0x88776655
    bne t1,t2,bad
    // A byte register bank: every read increments a host side-effect counter.
    li s0,0x10000000
    lbu t0,5(s0)
    li t1,0xa5
    bne t0,t1,bad
    sb t0,3(s0)
    li s0,0x0200bff8
    li t0,0x12345678
    sw t0,4(s0)
    lw t1,4(s0)
    bne t0,t1,bad
    sw zero,0(s0)
    lw t0,0(s0)
    lw t1,0(s0)
    bgeu t0,t1,bad
    // An unsupported CLINT byte access returns SLVERR -> load access fault.
    la t0,handler
    csrw mtvec,t0
fault_site:
    lbu t1,0(s0)
    j bad
handler:
    csrr t0,mcause
    li t1,5
    bne t0,t1,bad
    csrr t0,mepc
    la t1,fault_site
    bne t0,t1,bad
    li a0,0
    ebreak
bad:
    li a0,1
    ebreak
.align 2
scratch:
.word 0
