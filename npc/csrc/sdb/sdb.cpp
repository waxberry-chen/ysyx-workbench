#include "common.h"



void init_regex();
void init_wp_pool();

extern void cpu_exec(uint32_t n);
extern word_t expr(char *e, bool *success);

// ***** add *****
/* We use the `readline' library to provide more flexibility to read from stdin. */
static char* rl_gets() {
  static char *line_read = NULL;

  if (line_read) {
    free(line_read);
    line_read = NULL;
  }

  line_read = readline("(sim) ");

  if (line_read && *line_read) {
    add_history(line_read);
  }

  return line_read;
}

static int cmd_c(char *args) {
  cpu_exec(-1);
  return 0;
}

static int cmd_q(char *args) {
  // Lab2 TODO: implement the quit command
  return 0;
}

static int cmd_si(char *args) {
  char *arg = strtok(NULL, " ");
  // Lab2 TODO: implement the si [N] command
  return 0;
}

static int cmd_info(char *args) {
  char *arg = strtok(NULL, " ");
  if (arg == NULL) {
    /* no argument given */
    printf("Usage: info r\n");
  } 
  else if(strcmp(arg, "r") == 0) {
  // Lab2 TODO: implement the info r command

  } 
  else {
    printf("Usage: info r\n");
  }
  return 0;
}

static int cmd_x(char *args) {
  char *arg = strtok(NULL, " ");
  if (arg == NULL) {
    /* no argument given */
    printf("Usage: x n addr\n");
    return 0;
  }
  int n = atoi(arg);
  char *tokens = strtok(NULL, " ");
  if(tokens == NULL){
    printf("Usage: x n addr\n");
    return 0;
  }
  bool success;

  paddr_t addr = expr(tokens, &success);

  if(addr < (paddr_t)CONFIG_MBASE || addr >= (paddr_t)CONFIG_MBASE + (paddr_t)CONFIG_MSIZE){
    printf("addr out of scope!\n");
    return 0;
  }
  for(int i = 0; i < n; i++){
    printf(FMT_WORD ":\t" FMT_WORD "\n", addr + 4 * i, paddr_read(addr + 4 * i, 4));
  }
  return 0;
}

static int cmd_p(char *args) {
  bool success = false;
  if(args == NULL){
    printf("Usage: p [expr]\n");
    return 0;
  }
  word_t val = expr(args, &success);
  if (success){
    printf("DEC: %d\n", val);
    printf("HEX: " FMT_WORD "\n", val);
  }
  else printf("p: wrong expr!\n");
  return 0;
}

static int cmd_help(char *args);

// ***** add *****

void sdb_mainloop() {
    if(is_batch_mode) {
        cmd_c();
        return;
    }
}

void init_sdb() {
    init_regex();

    init_wp_pool();
}