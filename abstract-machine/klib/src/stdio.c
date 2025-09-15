#include <am.h>
#include <klib.h>
#include <klib-macros.h>
#include <stdarg.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

int printf(const char *fmt, ...) {
  panic("Not implemented");
}

int vsprintf(char *out, const char *fmt, va_list ap) {
  panic("Not implemented");
}

// Write to a character string
int sprintf(char *out, const char *fmt, ...) {
  va_list ap;
  int d;
  char c, *s, *dst_ptr;
  dst_ptr = out;
  va_start(ap, fmt);
  while (*fmt) {
    if (*fmt == '%') {
       switch(*++fmt) {
        case 's':
          s = va_arg(ap, char *);
          strcat(dst_ptr, s);
          dst_ptr += strlen(s);
          fmt++;
          break;
        case 'c':
          c = va_arg(ap, int); // no char here
          *dst_ptr = c;
          dst_ptr++;
          fmt++;
          break;
        case 'd':
          d = va_arg(ap, int);
          int d_len = my_itoa(dst_ptr, d);
          dst_ptr += d_len;
          fmt++;
          break;
       }
    } else {
      *dst_ptr = *fmt;
      dst_ptr++;
      fmt++;
    }
  }
  *dst_ptr = '\0';
  va_end(ap);
  return (int)strlen(out);
}

int snprintf(char *out, size_t n, const char *fmt, ...) {
  panic("Not implemented");
}

int vsnprintf(char *out, size_t n, const char *fmt, va_list ap) {
  panic("Not implemented");
}

// integer to ascii - my_itoa
int my_itoa(char *dst, int d) {
  int i=0, j=0;
  while (d) {
    dst[i++] = d%10 + '0';
    d /= 10; 
  }
  while (j < i/2) {
    int temp = dst[j]; 
    dst[j] = dst[i-j-1]; 
    dst[i-j-1] = temp;
    j++;
  }
  if (i==0) {
    dst[i++] = '0';
  }
  dst[i]='\0';
  return i;
}

#endif
