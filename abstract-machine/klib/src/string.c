#include <klib.h>
#include <klib-macros.h>
#include <stdint.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

// exclude '\0'
size_t strlen(const char *s) {
  size_t i; 
  for (i=0; s[i]!='\0'; i++); 
  return i;
}

char *strcpy(char *dst, const char *src) {
  size_t i;
  for (i=0; src[i] != '\0'; i++) dst[i] = src[i];
  dst[i] = '\0'; 
  return dst;
}

char *strncpy(char *dst, const char *src, size_t n) {
  size_t i; 
  for (i=0; i<n&&src[i]!='\0'; i++) dst[i] = src[i]; 
  for (; i<n; i++) dst[i] = '\0';
  return dst;
}

char *strcat(char *dst, const char *src) {
  size_t dst_len = strlen(dst); 
  size_t i; 
  for(i=0; src[i]!='\0'; i++) {
    dst[dst_len+i] = src[i]; 
  }
  dst[dst_len+i]='\0';
  return dst;
}

/*
  Compare s1 and s2 by byte
  return a integer
    >0, s1>s2
    =0, s1=s2
    <0, s1<s2
*/
int strcmp(const char *s1, const char *s2) {
  while (*s1&&*s1==*s2) {
    s1++;
    s2++;
  }
  return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

int strncmp(const char *s1, const char *s2, size_t n) {
  if (n==0) {
    return 0;
  }
  while (*s1 && *s1==*s2 && --n) {
    s1++; 
    s2++;
  }
  return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

void *memset(void *s, int c, size_t n) {
  unsigned char *p = s; 
  size_t i; 
  for(i=0; i<n; i++) {
    p[i] = c; // why here p cant be const?
  }
  return s;
}

void *memmove(void *dst, const void *src, size_t n) {
  // CONVERT
  unsigned char *ptr_src = (unsigned char *)src;
  unsigned char *ptr_dst = (unsigned char *)dst;
  if(dst<src)
  for(size_t i=0; i<n; i++) ptr_dst[i]=ptr_src[i];
  else if (dst>src)
  for(size_t i=n; i>0; i--) ptr_dst[i-1]=ptr_src[i-1];
  return dst; 
}

void *memcpy(void *out, const void *in, size_t n) {
  // CONVERT
  unsigned char *p1 = (unsigned char *)out;
  unsigned char *p2 = (unsigned char *)in;
  size_t i;
  for(i=0; i<n;i++) {
    p1[i] = p2[i];
  }
  return out;
}

int memcmp(const void *s1, const void *s2, size_t n) {
  // Need to convert to unsigned char to compare
  const unsigned char *p1 = s1; // must initialization
  const unsigned char *p2 = s2;  
  while(n>0) {
    if (*p1 != *p2) return *p1 - *p2; 
    p1++; // why const can change?
    p2++;
    n--;
  }
  return 0; 
}

#endif
