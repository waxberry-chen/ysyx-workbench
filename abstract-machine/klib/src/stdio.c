#include <am.h>
#include <klib.h>
#include <stdarg.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

typedef struct {
  char *buf;
  size_t size;
  size_t count;
  bool console;
} FormatOutput;

enum LengthModifier {
  LEN_DEFAULT,
  LEN_LONG,
  LEN_LONG_LONG,
  LEN_SIZE,
};

static void emit_char(FormatOutput *out, char ch) {
  if (out->console) {
    putch(ch);
  } else if (out->size > 0 && out->count < out->size - 1) {
    out->buf[out->count] = ch;
  }
  out->count++;
}

static void emit_repeat(FormatOutput *out, char ch, int count) {
  while (count-- > 0) emit_char(out, ch);
}

static void terminate_output(FormatOutput *out) {
  if (!out->console && out->size > 0) {
    size_t end = out->count < out->size ? out->count : out->size - 1;
    out->buf[end] = '\0';
  }
}

static int unsigned_to_reverse(char *buf, uint64_t value, unsigned base,
                               bool uppercase) {
  const char *digits = uppercase
    ? "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    : "0123456789abcdefghijklmnopqrstuvwxyz";
  int len = 0;

  do {
    buf[len++] = digits[value % base];
    value /= base;
  } while (value != 0);

  return len;
}

static uint64_t get_unsigned_arg(va_list *ap, enum LengthModifier length) {
  switch (length) {
    case LEN_LONG:      return va_arg(*ap, unsigned long);
    case LEN_LONG_LONG: return va_arg(*ap, unsigned long long);
    case LEN_SIZE:      return va_arg(*ap, size_t);
    default:            return va_arg(*ap, unsigned int);
  }
}

static int64_t get_signed_arg(va_list *ap, enum LengthModifier length) {
  switch (length) {
    case LEN_LONG:      return va_arg(*ap, long);
    case LEN_LONG_LONG: return va_arg(*ap, long long);
    case LEN_SIZE:      return va_arg(*ap, intptr_t);
    default:            return va_arg(*ap, int);
  }
}

static void emit_integer(FormatOutput *out, uint64_t value, bool negative,
                         unsigned base, bool uppercase, bool left_align,
                         bool zero_pad, bool force_sign, bool space_sign,
                         bool alternate, int width, int precision,
                         bool pointer) {
  char digits[65];
  int digit_count = unsigned_to_reverse(digits, value, base, uppercase);

  if (precision == 0 && value == 0 && !pointer) digit_count = 0;

  char sign = '\0';
  if (negative) sign = '-';
  else if (force_sign) sign = '+';
  else if (space_sign) sign = ' ';

  char prefix0 = '\0', prefix1 = '\0';
  if (pointer || (alternate && base == 16 && value != 0)) {
    prefix0 = '0';
    prefix1 = uppercase ? 'X' : 'x';
  } else if (alternate && base == 8 &&
             (digit_count == 0 || digits[digit_count - 1] != '0')) {
    prefix0 = '0';
  }

  int prefix_len = (prefix0 != '\0') + (prefix1 != '\0');
  int zero_count = precision > digit_count ? precision - digit_count : 0;
  int field_len = (sign != '\0') + prefix_len + zero_count + digit_count;
  int pad_count = width > field_len ? width - field_len : 0;

  if (zero_pad && !left_align && precision < 0) {
    zero_count += pad_count;
    pad_count = 0;
  }

  if (!left_align) emit_repeat(out, ' ', pad_count);
  if (sign != '\0') emit_char(out, sign);
  if (prefix0 != '\0') emit_char(out, prefix0);
  if (prefix1 != '\0') emit_char(out, prefix1);
  emit_repeat(out, '0', zero_count);
  while (digit_count-- > 0) emit_char(out, digits[digit_count]);
  if (left_align) emit_repeat(out, ' ', pad_count);
}

static int format_output(FormatOutput *out, const char *fmt, va_list args) {
  va_list ap;
  va_copy(ap, args);

  while (*fmt != '\0') {
    if (*fmt != '%') {
      emit_char(out, *fmt++);
      continue;
    }

    fmt++;
    if (*fmt == '\0') {
      emit_char(out, '%');
      break;
    }

    bool left_align = false;
    bool zero_pad = false;
    bool force_sign = false;
    bool space_sign = false;
    bool alternate = false;

    bool parsing_flags = true;
    while (parsing_flags) {
      switch (*fmt) {
        case '-': left_align = true; fmt++; break;
        case '0': zero_pad = true; fmt++; break;
        case '+': force_sign = true; fmt++; break;
        case ' ': space_sign = true; fmt++; break;
        case '#': alternate = true; fmt++; break;
        default: parsing_flags = false; break;
      }
    }

    int width = 0;
    if (*fmt == '*') {
      width = va_arg(ap, int);
      fmt++;
      if (width < 0) {
        left_align = true;
        width = -width;
      }
    } else {
      while (*fmt >= '0' && *fmt <= '9') {
        width = width * 10 + (*fmt++ - '0');
      }
    }

    int precision = -1;
    if (*fmt == '.') {
      fmt++;
      precision = 0;
      if (*fmt == '*') {
        precision = va_arg(ap, int);
        fmt++;
        if (precision < 0) precision = -1;
      } else {
        while (*fmt >= '0' && *fmt <= '9') {
          precision = precision * 10 + (*fmt++ - '0');
        }
      }
    }

    enum LengthModifier length = LEN_DEFAULT;
    if (*fmt == 'l') {
      fmt++;
      length = LEN_LONG;
      if (*fmt == 'l') {
        fmt++;
        length = LEN_LONG_LONG;
      }
    } else if (*fmt == 'z') {
      fmt++;
      length = LEN_SIZE;
    }

    char spec = *fmt++;
    switch (spec) {
      case 'd':
      case 'i': {
        int64_t signed_value = get_signed_arg(&ap, length);
        bool negative = signed_value < 0;
        uint64_t magnitude = negative
          ? 0 - (uint64_t)signed_value
          : (uint64_t)signed_value;
        emit_integer(out, magnitude, negative, 10, false, left_align,
                     zero_pad, force_sign, space_sign, false, width,
                     precision, false);
        break;
      }
      case 'u':
        emit_integer(out, get_unsigned_arg(&ap, length), false, 10, false,
                     left_align, zero_pad, false, false, false, width,
                     precision, false);
        break;
      case 'x':
      case 'X':
        emit_integer(out, get_unsigned_arg(&ap, length), false, 16,
                     spec == 'X', left_align, zero_pad, false, false,
                     alternate, width, precision, false);
        break;
      case 'o':
        emit_integer(out, get_unsigned_arg(&ap, length), false, 8, false,
                     left_align, zero_pad, false, false, alternate, width,
                     precision, false);
        break;
      case 'p':
        emit_integer(out, (uintptr_t)va_arg(ap, void *), false, 16, false,
                     left_align, zero_pad, false, false, true, width,
                     precision, true);
        break;
      case 'c': {
        char ch = (char)va_arg(ap, int);
        int padding = width > 1 ? width - 1 : 0;
        if (!left_align) emit_repeat(out, ' ', padding);
        emit_char(out, ch);
        if (left_align) emit_repeat(out, ' ', padding);
        break;
      }
      case 's': {
        const char *str = va_arg(ap, const char *);
        if (str == NULL) str = "(null)";
        int len = 0;
        while (str[len] != '\0' && (precision < 0 || len < precision)) len++;
        int padding = width > len ? width - len : 0;
        if (!left_align) emit_repeat(out, ' ', padding);
        for (int i = 0; i < len; i++) emit_char(out, str[i]);
        if (left_align) emit_repeat(out, ' ', padding);
        break;
      }
      case '%': {
        int padding = width > 1 ? width - 1 : 0;
        char pad = zero_pad && !left_align ? '0' : ' ';
        if (!left_align) emit_repeat(out, pad, padding);
        emit_char(out, '%');
        if (left_align) emit_repeat(out, ' ', padding);
        break;
      }
      default:
        emit_char(out, '%');
        emit_char(out, spec);
        break;
    }
  }

  terminate_output(out);
  va_end(ap);
  return (int)out->count;
}

int printf(const char *fmt, ...) {
  FormatOutput out = { .buf = NULL, .size = 0, .count = 0, .console = true };
  va_list ap;
  va_start(ap, fmt);
  int count = format_output(&out, fmt, ap);
  va_end(ap);
  return count;
}

int vsprintf(char *out, const char *fmt, va_list ap) {
  FormatOutput output = {
    .buf = out, .size = (size_t)-1, .count = 0, .console = false
  };
  return format_output(&output, fmt, ap);
}

int sprintf(char *out, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int count = vsprintf(out, fmt, ap);
  va_end(ap);
  return count;
}

int vsnprintf(char *out, size_t n, const char *fmt, va_list ap) {
  FormatOutput output = { .buf = out, .size = n, .count = 0, .console = false };
  return format_output(&output, fmt, ap);
}

int snprintf(char *out, size_t n, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int count = vsnprintf(out, n, fmt, ap);
  va_end(ap);
  return count;
}

int my_itoa(char *dst, int value) {
  char digits[16];
  bool negative = value < 0;
  uint32_t magnitude = negative ? 0 - (uint32_t)value : (uint32_t)value;
  int digit_count = unsigned_to_reverse(digits, magnitude, 10, false);
  int pos = 0;

  if (negative) dst[pos++] = '-';
  while (digit_count-- > 0) dst[pos++] = digits[digit_count];
  dst[pos] = '\0';
  return pos;
}

#endif
