.section .text
.globl _start
.option norvc
_start:
    la t0,bad
    csrw mtvec,t0
    li s0,0x10000000
    li t0,0x80
    sb t0,3(s0)       // DLAB=1
    li t0,1
    sb t0,0(s0)       // divisor=1 => 16 CPU clocks / serial bit
    sb zero,1(s0)
    li t0,3
    sb t0,3(s0)       // 8N1, DLAB=0
    li t0,7
    sb t0,2(s0)       // enable and reset FIFOs
    li t0,0x5a
    sb t0,7(s0)       // scratch register: byte lane 3 round trip
    lbu t1,7(s0)
    bne t0,t1,bad
wait_ready:
    lbu t0,5(s0)      // LSR offset 5 must not become MCR offset 4
    andi t0,t0,0x20
    beqz t0,wait_ready
    li t0,65
    sb t0,0(s0)
wait_empty:
    lbu t0,5(s0)
    andi t0,t0,0x40   // TEMT: wait for actual serial shift register, not only FIFO
    beqz t0,wait_empty
    li a0,0
    ebreak
bad:
    li a0,1
    ebreak
