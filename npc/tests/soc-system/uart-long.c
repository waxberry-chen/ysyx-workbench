#include <am.h>
#include <stdint.h>
#define UART ((volatile uint8_t *)0x10000000)
int main(void) {
  // Slow enough to exercise THRE polling even on this uncached CPU.
  UART[3]=0x80; UART[0]=8; UART[1]=0; UART[3]=3; UART[1]=0;
  static const char line[]="0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz!\n";
  for (unsigned n=0;n<8;n++)
    for (unsigned i=0;i<sizeof(line)-1;i++) putch(line[i]);
  return 0; // AM halt waits for TEMT, including the final stop bit.
}
