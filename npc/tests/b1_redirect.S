// Return from the final SRAM word. Sequential fetch beyond the range must
// never retire its DECERR after the jump redirects execution back to SRAM.
    .section .text
    .globl _start
_start:
    la t0, bad
    csrw mtvec, t0
    li t0, 0x80000000 + SRAM_BYTES - 4
    li t1, 0x00008067  // jalr zero, 0(ra)
    sw t1, 0(t0)
    jalr ra, 0(t0)
    li a0, 0
    ebreak
bad:
    li a0, 1
    ebreak
