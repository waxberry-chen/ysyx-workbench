/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include <isa.h>
#include <cpu/cpu.h>
#include <readline/readline.h>
#include <readline/history.h>
#include "sdb.h"
#include <memory/paddr.h>
#include <stdbool.h>

static int is_batch_mode = false;

void init_regex();
void init_wp_pool();

/* We use the `readline' library to provide more flexibility to read from stdin. */
static char* rl_gets() {
  static char *line_read = NULL;

  if (line_read) {
    free(line_read);
    line_read = NULL;
  }

  line_read = readline("(nemu) ");

//add the command to history list.
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
  nemu_state.state = NEMU_QUIT;
  return -1;
}

static int cmd_help(char *args);
static int cmd_test_expr(char *args);

//my code begin
static int cmd_si(char *args){
  int step_num;
  if (args == NULL){
    step_num = 1;
  }else{
    sscanf(args, "%d", &step_num);
  }
//should add limit to the step number. 添加对不合适步数(字符, 过大的数)的判断. 
  cpu_exec(step_num);
  printf("%d steps executed.\n", step_num);

  return 0;
};

static int cmd_info(char *args){
  if (strcmp(args, "r") == 0){
    //print registers.
    isa_reg_display();
   }else if (strcmp(args, "w") == 0){
    //print infomations of watchpoint.
    wp_display();
  }else{
    printf("ERROR: Wrong arguments given.(info r or w)\n");
  }
  
  return 0;
}

// Scan memory
static int cmd_x(char *args){
  int i;
  int wordlen;
  paddr_t base_addr;
if (args == NULL){
  // EXPR only hex number now
  printf("2 arguments needed\n format: x N EXPR\n");
}else{
  sscanf(args, "%d %x", &wordlen, &base_addr);
  paddr_t cur_addr = base_addr;
  for(i = 0; i < wordlen; i++){
    printf("0x%08x:\t%08x\n", cur_addr, paddr_read(cur_addr, 4));
    cur_addr = cur_addr + 4;
  }
}
return 0;
};

// Expression calculate
static int cmd_p(char *args){
  bool success;
  word_t result = expr(args, &success);
  if(!success){
    printf("Calculation failed\n");
  }else{
    printf("DEC:\t%d\nHEX:\t0x%x\n", result, result);
  }
  return 0;
};

// Watchpoint
static int cmd_w(char *args){
  if(!args){
    printf("Usage: w EXPR\n");
    return 0;
  }
  bool success;
  word_t res = expr(args, &success);
  if(!success){
    puts("Invalid expression");
  }else{
    wp_watch(args, res);
  }
  return 0;
}

// Delete watchpoint
static int cmd_d(char *args){
  char *arg = strtok(NULL, "");
  if(!arg){
    printf("Usage: d N\n");
    return 0;
  }
  int no = strtol(arg, NULL, 10);
  wp_remove(no);
  return 0;
}

static struct {
  const char *name;
  const char *description;
  int (*handler) (char *);
} cmd_table [] = {
  { "help", "Display information about all supported commands", cmd_help },
  { "c", "Continue the execution of the program", cmd_c },
  { "q", "Exit NEMU", cmd_q },
  { "si", "USAGE: si [N] -step into N steps, N=1 default", cmd_si},
  { "info", "USAGE: info r/w -print the information", cmd_info},
  { "x", "USAGE: x N EXPR -print 4N Byte base on base address EXPR", cmd_x},
  { "p", "USAGE: p EXPR -calculate the expression", cmd_p},
  { "w", "USAGE: w EXPR -set watchpoint at result of EXPR", cmd_w},
  { "d", "USAGE: d N -delete watchpoint NO.N", cmd_d},
  {"test", "Test expr()", cmd_test_expr}
  /* TODO: Add more commands */

};

#define NR_CMD ARRLEN(cmd_table)

static int cmd_help(char *args) {
  /* extract the first argument */
  char *arg = strtok(NULL, " ");
  int i;

  if (arg == NULL) {
    /* no argument given */
    for (i = 0; i < NR_CMD; i ++) {
      printf("%s - %s\n", cmd_table[i].name, cmd_table[i].description);
    }
  }
  else {
    for (i = 0; i < NR_CMD; i ++) {
      if (strcmp(arg, cmd_table[i].name) == 0) {
        printf("%s - %s\n", cmd_table[i].name, cmd_table[i].description);
        return 0;
      }
    }
    printf("Unknown command '%s'\n", arg);
  }
  return 0;
}

void sdb_set_batch_mode() {
  is_batch_mode = true;
}

void sdb_mainloop() {
  if (is_batch_mode) {
    cmd_c(NULL);
    return;
  }

  for (char *str; (str = rl_gets()) != NULL; ) {
    char *str_end = str + strlen(str);

    /* extract the first token as the command */
    char *cmd = strtok(str, " ");
    if (cmd == NULL) { continue; }

    /* treat the remaining string as the arguments,
     * which may need further parsing
     */
    //HERE WE NEED MULTIPLE ARGUMENTS
    char *args = cmd + strlen(cmd) + 1;
    if (args >= str_end) {
      args = NULL;
    }

#ifdef CONFIG_DEVICE
    extern void sdl_clear_event_queue();
    sdl_clear_event_queue();
#endif

    int i;
    for (i = 0; i < NR_CMD; i ++) {
      if (strcmp(cmd, cmd_table[i].name) == 0) {
        if (cmd_table[i].handler(args) < 0) {return; }
        break;
      }
    }

    if (i == NR_CMD) { printf("Unknown command '%s'\n", cmd); }
  }
}

void test_expr(){
  FILE *fp = fopen("/home/cym/prj/ysyx-workbench/nemu/tools/gen-expr/input", "r");
  if(fp == NULL){
    perror("test_expr: Failed to open the test file.");
  }
  //这里面answer和result只能对应%u, 不能%lu
  char *e = NULL;
  word_t answer;

  size_t len = 0;
  ssize_t read;
  bool success = false;

  while(true){
    if(fscanf(fp, "%u", &answer) == -1)
      break;
    read = getline(&e, &len, fp);
    e[read-1] = '\0';

    word_t result = expr(e, &success);

    assert(success);
    if(result != answer){
      puts(e);
      printf("Expected: %u\tGot: %u\n", answer, result);
      assert(0);
    }
  }

  fclose(fp);
  if(e)
    free(e);
  Log("test_expr: PASS");
}

// Test expression
static int cmd_test_expr(char *args){
  test_expr();
  return 0;
}

void init_sdb() {
  /* Compile the regular expressions. */
  init_regex();
  /* Test expression calculation. */
  //test_expr();
  /* Initialize the watchpoint pool. */
  init_wp_pool();
}
