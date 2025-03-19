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

#include "sdb.h"

#define NR_WP 32

typedef struct watchpoint{
  int NO;
  struct watchpoint *next;

  /* TODO: Add more members if necessary */
  char expr[32];
  word_t old;

} WP;

static WP wp_pool[NR_WP] = {};
static WP *head = NULL, *free_ = NULL;

void init_wp_pool() {
  int i;
  for (i = 0; i < NR_WP; i ++) {
    wp_pool[i].NO = i;
    wp_pool[i].next = (i == NR_WP - 1 ? NULL : &wp_pool[i + 1]);
  }

  head = NULL;
  free_ = wp_pool;
}

/* TODO: Implement the functionality of watchpoint */
static WP* new_wp(){
  assert(free_);
  WP* ret = free_;
  free_ = free_->next;
  ret->next = head;
  head = ret;
  return ret;
}

static void free_wp(WP *wp){
  WP* h = head;
  if(h == wp){
    head = wp->next;
  }else{
    while(h && h->next != wp){
      h = h->next;
    }
    assert(h);
    h->next = wp->next;
  }
  wp->next = free_;
  free_ = wp;
}

void wp_watch(char *expr, word_t res){
  if(expr == NULL){
    fprintf(stderr, "Error: NULL expression pointer.\n");
    return;
  }
  WP *wp = new_wp();
  if(wp == NULL){
    fprintf(stderr, "Error: Failed to allocate new watchpoint.\n");
    return;
  }
  strcpy(wp->expr, expr); //may cause segmentation fault.
  wp->old = res;
  printf("Watchpoint %d set: %s\n", wp->NO, expr);
}

void wp_remove(int no){
  assert(no < NR_WP);
  WP *wp = &wp_pool[no];
  free_wp(wp);
  printf("Delete watchpoint %d: %s\n", wp->NO, wp->expr);
}

void wp_display(){
  WP *cur = head;
  if(!cur){
    puts("No watchpoints");
    return;
  }
  printf("%-8s%-8s\n", "No", "Expr");
  while (cur){
    printf("%-8d%-8s\n", cur->NO, cur->expr);
    cur = cur->next;
  }
}

void wp_difftest(){
  WP *cur = head;
  while(cur){
    bool valid;
    word_t new = expr(cur->expr, &valid);
    if(cur->old != new){
      printf("Watchpoint No.%d triggered: %s\tValue: %u->%u\n", cur->NO, cur->expr, cur->old, new);
      cur->old = new;
      nemu_state.state = NEMU_STOP;
    }
    cur = cur->next;
  }
}