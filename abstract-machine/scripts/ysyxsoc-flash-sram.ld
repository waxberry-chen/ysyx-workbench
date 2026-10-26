/* Flash contains the boot routine and LMA bytes; all application sections
 * execute/live in RAM. objcopy emits the compact, contiguous Flash image. */
MEMORY {
  flash (rx) : ORIGIN = 0x30000000, LENGTH = 16M
  ram (rwx) : ORIGIN = 0x0f000000, LENGTH = 8K
}
ENTRY(_start)
SECTIONS {
  .boot : { KEEP(*(entry)) . = ALIGN(4); } > flash
  .text : {
    _text_start = .;
    *(.text .text.*) *(.rodata .rodata.* .srodata .srodata.*)
    . = ALIGN(4); _text_end = .;
  } > ram AT> flash
  _text_load = LOADADDR(.text);
  .data : {
    _data_start = .;
    *(.data .data.* .sdata .sdata.*)
    . = ALIGN(4); _data_end = .;
  } > ram AT> flash
  _data_load = LOADADDR(.data);
  _rom_end = LOADADDR(.data) + SIZEOF(.data);
  .bss (NOLOAD) : {
    _bss_start = .;
    *(.bss .bss.* .sbss .sbss.*) *(COMMON)
    . = ALIGN(16); _bss_end = .;
  } > ram
  _heap_start = _bss_end;
  _stack_top = ORIGIN(ram) + LENGTH(ram);
  _stack_bottom = _stack_top - 2K;
  _heap_end = _stack_bottom;
  /DISCARD/ : { *(.eh_frame .eh_frame.* .comment) }
}
ASSERT(_rom_end <= ORIGIN(flash)+LENGTH(flash), "Flash image exceeds 16 MiB")
ASSERT(_heap_start <= _heap_end, "RAM static sections overlap reserved stack")
