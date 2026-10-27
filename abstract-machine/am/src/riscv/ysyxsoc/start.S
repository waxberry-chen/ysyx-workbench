.section entry, "ax"
.globl _start, __am_data_copy, __am_bss_clear, __am_runtime_ready
.type _start, @function
_start:
  mv s0, zero
  la sp, _stack_top
  /* S3 bring-up deliberately poisons *real* SRAM before initializing it.
   * No stack/call/global access is allowed here. This makes missing copies or
   * bss clearing visible even when the Verilator memory starts at zero. */
  la t0, _sram_start
  li t1, 0xa5a5a5a5
1:
  sw t1, 0(t0)
  addi t0, t0, 4
  bltu t0, sp, 1b
  /* Copy data section to SRAM */
__am_data_copy:
  la t0, _data_load
  la t1, _data_start
  la t2, _data_end
2:
  bgeu t1, t2, 3f
  lw a0, 0(t0)
  sw a0, 0(t1)
  addi t0, t0, 4
  addi t1, t1, 4
  j 2b
  /* Clear bss section */
3:
__am_bss_clear:
  la t0, _bss_start
  la t1, _bss_end
4:
  bgeu t0, t1, 5f
  sw zero, 0(t0)
  addi t0, t0, 4
  j 4b
  /* Call AM trm_init */
5:
__am_runtime_ready:
  call _trm_init
6:
  j 6b
