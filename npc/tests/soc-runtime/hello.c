#include <am.h>
int main(const char *args) {
  (void)args;
  const char *s="Hello, ysyxSoC!\n";
  while (*s) putch(*s++);
  return 0;
}
