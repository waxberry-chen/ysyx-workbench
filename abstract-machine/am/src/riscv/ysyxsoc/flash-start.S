/* This entire routine executes from Flash. No stack access, call, or RAM
 * instruction fetch is allowed until text/data copying and bss clearing end. */
.section entry, "ax"
.globl _start, __am_ram_poison, __am_text_copy, __am_data_copy
.globl __am_bss_clear, __am_runtime_ready
.type _start, @function
_start:
  mv s0, zero
  la sp, _stack_top
__am_ram_poison:
  /* Verification pattern only in the static destination, before it is live.
   * Never sweep the heap/stack from a later RAM-resident startup routine. */
  la t0, _text_start
  la t2, _bss_end
  li t1, 0xa5a5a5a5
1:
  bgeu t0, t2, __am_text_copy
  sw t1, 0(t0)
  addi t0, t0, 4
  j 1b
__am_text_copy:
  la t0, _text_load
  la t1, _text_start
  la t2, _text_end
2:
  bgeu t1, t2, __am_data_copy
  lw a0, 0(t0)
  sw a0, 0(t1)
  addi t0, t0, 4
  addi t1, t1, 4
  j 2b
__am_data_copy:
  la t0, _data_load
  la t1, _data_start
  la t2, _data_end
3:
  bgeu t1, t2, __am_bss_clear
  lw a0, 0(t0)
  sw a0, 0(t1)
  addi t0, t0, 4
  addi t1, t1, 4
  j 3b
__am_bss_clear:
  la t0, _bss_start
  la t1, _bss_end
4:
  bgeu t0, t1, __am_runtime_ready
  sw zero, 0(t0)
  addi t0, t0, 4
  j 4b
__am_runtime_ready:
  /* Linker resolves the far Flash->RAM call without any ABI port change. */
  call _trm_init
5:
  j 5b
