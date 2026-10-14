#include <am.h>
#include <klib.h>
#include <klib-macros.h>

int main(void) {
  // The last SRAM word exercises the bounded adapter+fabric+device path.
  volatile uint32_t *word = (void *)(0x80000000u + PMEM_SIZE - 4);
  volatile uint8_t *byte = (void *)word;
  volatile uint16_t *half = (void *)word;
  *word = 0x12345678;
  assert(*word == 0x12345678);
  for (int i = 0; i < 4; i++) byte[i] = 0x80 + i;
  assert(*word == 0x83828180);
  for (int i = 0; i < 4; i++) {
    assert(byte[i] == 0x80 + i);
    assert(((volatile int8_t *)word)[i] == -128 + i);
  }
  half[0] = 0x8001; half[1] = 0xff02;
  assert(half[0] == 0x8001 && half[1] == 0xff02);
  assert(((volatile int16_t *)word)[0] == -32767);
  assert(((volatile int16_t *)word)[1] == -254);
  assert(*word == 0xff028001);
  // Fixed marker for debugger inspection after ebreak.
  *word = 0x13579bdf;
  putstr("lanes PASS\n");
  return 0;
}
