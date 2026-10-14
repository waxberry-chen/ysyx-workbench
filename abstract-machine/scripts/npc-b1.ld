/* Supplement the common linker script for the bounded B1 SRAM. */
ASSERT(_heap_start < _pmem_start + _pmem_size, "B1 image/stack/heap exceeds SRAM_BYTES")
ASSERT(_stack_pointer <= _pmem_start + _pmem_size, "B1 stack exceeds SRAM_BYTES")
