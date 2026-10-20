#include <benchmark.h>
#ifdef SMOKE_FIB
static Setting chosen = FIB_S;
#define PREPARE bench_fib_prepare
#define RUN bench_fib_run
#define VALIDATE bench_fib_validate
#else
static Setting chosen = SIEVE_S;
#define PREPARE bench_sieve_prepare
#define RUN bench_sieve_run
#define VALIDATE bench_sieve_validate
#endif
Setting *setting=&chosen;
static uintptr_t next;
void *bench_alloc(size_t size) {
  if (!next) next=(uintptr_t)heap.start;
  size=(size+7)&~7u;
  if (next+size>(uintptr_t)heap.end) halt(1);
  void *ret=(void *)next; next+=size; return ret;
}
int main(const char *args) {
  (void)args;
  PREPARE(); RUN();
  return VALIDATE() ? 0 : 1;
}
