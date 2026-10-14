// A rejecting transaction must preserve the load destination and trap precisely.
    .section .text
    .globl _start
_start:
    la t0, handler
    csrw mtvec, t0
    li t1, 0x12345678
    li t2, FAULT_ADDR
fault_site:
#if FAULT_KIND == 1
    jalr zero, 0(t2)
#elif FAULT_KIND == 2
    lw t1, 0(t2)
#elif FAULT_KIND == 3
    sw t1, 0(t2)
#else
#error invalid FAULT_KIND
#endif
    li a0, 2
    ebreak
handler:
    li t0, 0x12345678
    bne t1, t0, bad
    csrr t0, mcause
    li t1, FAULT_CAUSE
    bne t0, t1, bad
    csrr t0, mepc
#if FAULT_KIND == 1
    li t1, FAULT_ADDR
#else
    la t1, fault_site
#endif
    bne t0, t1, bad
    li a0, 0
    ebreak
bad:
    li a0, 1
    ebreak
