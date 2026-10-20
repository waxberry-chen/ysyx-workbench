/* VMA: CPU run address; LMA: where the reset-time ROM image stores the bytes. */
MEMORY {
  mrom (rx)  : ORIGIN = 0x20000000, LENGTH = 4K
  sram (rwx) : ORIGIN = 0x0f000000, LENGTH = 8K
}
ENTRY(_start)
SECTIONS {
  .text : { KEEP(*(entry)) *(.text .text.*) } > mrom
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) . = ALIGN(4); } > mrom
  .data : {
    _data_start = .;
    *(.data .data.* .sdata .sdata.*)
    . = ALIGN(4); _data_end = .;
  } > sram AT> mrom
  _data_load = LOADADDR(.data);
  _rom_end = LOADADDR(.data) + SIZEOF(.data);
  .bss (NOLOAD) : {
    _bss_start = .;
    *(.bss .bss.* .sbss .sbss.*) *(COMMON)
    . = ALIGN(16); _bss_end = .;
  } > sram
  _heap_start = _bss_end;
  _stack_top = ORIGIN(sram) + LENGTH(sram);
  _stack_bottom = _stack_top - 2K;
  _heap_end = _stack_bottom;
  _sram_start = ORIGIN(sram);
  /DISCARD/ : { *(.eh_frame .eh_frame.* .comment) }
}
ASSERT(_rom_end <= ORIGIN(mrom) + LENGTH(mrom), "MROM image exceeds 4 KiB")
ASSERT(_heap_start <= _heap_end, "SRAM data/bss overlaps reserved 2 KiB stack")
