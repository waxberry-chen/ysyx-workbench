// End-to-end precise load/store address-misaligned workload.
//
// The trap handler checks mcause and mepc.  The Make target also checks that
// no data-memory transaction was issued for the faulting instruction.

#define FAULT_LOAD  2
#define FAULT_STORE 3

    .section .text
    .globl _start
    .align 2

_start:
    la      t0, trap_handler
    csrw    mtvec, t0

    la      t0, fault_site
    addi    t0, t0, 1

fault_site:
#if FAULT_KIND == FAULT_LOAD
    lw      t1, 0(t0)
#elif FAULT_KIND == FAULT_STORE
    sw      zero, 0(t0)
#else
#error "unsupported FAULT_KIND"
#endif

    li      a0, 2
    ebreak

trap_handler:
    csrr    t0, mcause
    li      t1, FAULT_CAUSE
    bne     t0, t1, bad

    csrr    t0, mepc
    la      t1, fault_site
    bne     t0, t1, bad

    li      a0, 0
    ebreak

bad:
    li      a0, 1
    ebreak
