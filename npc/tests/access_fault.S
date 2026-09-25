// End-to-end precise access-fault workload.
//
// Build this file three times with FAULT_KIND/FAULT_CAUSE set by the NPC
// Makefile.  The trap handler checks mcause and mepc, then returns a0=0 through
// ebreak.  No AM runtime is needed, which keeps the test focused on hardware.

#define FAULT_FETCH 1
#define FAULT_LOAD  2
#define FAULT_STORE 3

    .section .text
    .globl _start
    .align 2

_start:
    la      t0, trap_handler
    csrw    mtvec, t0

#if FAULT_KIND == FAULT_FETCH
fault_site:
    jalr    zero, 0(zero)
#elif FAULT_KIND == FAULT_LOAD
fault_site:
    lw      t1, 0(zero)
#elif FAULT_KIND == FAULT_STORE
fault_site:
    sw      zero, 0(zero)
#else
#error "unsupported FAULT_KIND"
#endif

    // The faulting instruction must not continue along its normal path.
    li      a0, 2
    ebreak

trap_handler:
    csrr    t0, mcause
    li      t1, FAULT_CAUSE
    bne     t0, t1, bad

    csrr    t0, mepc
#if FAULT_KIND == FAULT_FETCH
    bnez    t0, bad
#else
    la      t1, fault_site
    bne     t0, t1, bad
#endif

    li      a0, 0
    ebreak

bad:
    li      a0, 1
    ebreak
