// Dedicated M5 S3 profile. Normal NEMU .config is intentionally independent.
#define CONFIG_YSYXSOC 1
#define CONFIG_ISA_riscv 1
#define CONFIG_ISA "riscv32"
#define CONFIG_RVE 1
#define CONFIG_MODE_SYSTEM 1
#define CONFIG_TARGET_SHARE 1
#define CONFIG_ENGINE_INTERPRETER 1
#define CONFIG_ENGINE "interpreter"
#define CONFIG_MBASE 0x20000000
#define CONFIG_MSIZE 0x1000
#define CONFIG_PC_RESET_OFFSET 0
#define CONFIG_TIMER_GETTIMEOFDAY 1
#define CONFIG_RT_CHECK 1
