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

/* We use the POSIX regex functions to process regular expressions.
 * Type 'man regex' for more information about POSIX regex functions.
 */
#include <regex.h>
#include "expr.h"
#include <memory/paddr.h>

enum {
  TK_NOTYPE = 256, 
  TK_EQ, TK_NEQ,
  TK_NUM = 1,
  TK_HEX = 2,
  TK_REG = 3,

  TK_POS, TK_NEG, TK_DREF,
  TK_AND, TK_OR, TK_GT, TK_LT, TK_GE, TK_LE


  /* TODO: Add more token types */

};

static int bound_types[] = {')', TK_NUM, TK_REG};
static int nop_types[] = {'(', ')', TK_NUM, TK_REG};
static int op1_type[] = {TK_NEG, TK_POS, TK_DREF};
//static int op_type[] = {'+', '-', '*', '-'};
static int cal_depth = 0;

static bool oftypes(int type, int types[], int size){
  for(int i = 0; i < size; i++){
    if(type == types[i]){
      return true;
    }
  }
  return false;
}

static struct rule {
  const char *regex;
  int token_type;
} rules[] = {

  /* TODO: Add more rules.
   * Pay attention to the precedence level of different rules.
   */

  {" +", TK_NOTYPE},    // spaces
  {"\\+", '+'},         // plus
  {"-", '-'},
  {"\\*", '*'},
  {"/", '/'},
  {"==", TK_EQ},        // equal
  {"!=", TK_NEQ},
  {"\\(", '('},
  {"\\)", ')'},
  {"(0x)?[0-9a-fA-F]+", TK_NUM},
  {"\\$[a-zA-Z]*[0-9]*", TK_REG},
  {"&&", TK_AND},
  {"\\|\\|", TK_OR},
  {">", TK_GT}, 
  {"<", TK_LT}, 
  {">=", TK_GE},
  {"<=", TK_LE},

};

#define NR_REGEX ARRLEN(rules)

static regex_t re[NR_REGEX] = {};

/* Rules are used for many times.
 * Therefore we compile them only once before any usage.
 */
void init_regex() {
  int i;
  char error_msg[128];
  int ret;

  for (i = 0; i < NR_REGEX; i ++) {
    ret = regcomp(&re[i], rules[i].regex, REG_EXTENDED);
    if (ret != 0) {
      regerror(ret, &re[i], error_msg, 128);
      panic("regex compilation failed: %s\n%s", error_msg, rules[i].regex);
    }
  }
}

typedef struct token {
  int type;
  char str[32];
} Token;

static Token tokens[1024] __attribute__((used)) = {};
static int nr_token __attribute__((used))  = 0;

//Get tokens[]
static bool make_token(char *e) {
  int position = 0;
  int i;
  regmatch_t pmatch;

  nr_token = 0;

  while (e[position] != '\0') {
    /* Try all rules one by one. */
    for (i = 0; i < NR_REGEX; i ++) {
      //从左向右匹配
      if (regexec(&re[i], e + position, 1, &pmatch, 0) == 0 && pmatch.rm_so == 0) {
        char *substr_start = e + position;
        int substr_len = pmatch.rm_eo;

        Log("match rules[%d] = \"%s\" at position %d with len %d: %.*s",
            i, rules[i].regex, position, substr_len, substr_len, substr_start);

        position += substr_len;

        /* TODO: Now a new token is recognized with rules[i]. Add codes
         * to record the token in the array `tokens'. For certain types
         * of tokens, some extra actions should be performed.
         */

        Token token;

        switch (rules[i].token_type) {
          case TK_NOTYPE:
          break;
          default: 
          token.type = rules[i].token_type;
          strncpy(token.str, substr_start, substr_len );
          token.str[substr_len] = '\0';
          tokens[nr_token] = token;
          //TEST
          //printf("token[%d]: \ntype: %c\ncontent: %s\n", nr_token, token.type, token.str);
          nr_token = nr_token +1;
          break;
        }

        break;
      }
    }

    if (i == NR_REGEX) {
      // Point out the error position
      printf("no match at position %d\n%s\n%*.s^\n", position, e, position, "");
      return false;
    }
  }

  return true;
}

//False, parentheses need to be matched! 
bool check_parentheses(int p, int q){
  if((tokens[p].type == '(') && (tokens[q].type == ')')){
    int par = 0;
    for(int i = p; i <= q; i++){
      if(tokens[i].type == '('){
        par++;
      }else if(tokens[i].type == ')'){
        par--;
      }

      if(par == 0 && i < q){
        return false;
      }
    }
    return par == 0;
  }else{
    return false;
  }
}

int find_op(int p, int q){
  int i;
  int op = -1;
  int par = 0;
  int op_priority = 0;
  for(i = p; i <= q; i++){
    //skip the parentheses
    if(tokens[i].type == '('){
      par++;
    }else if(tokens[i].type == ')'){
      if (par == 0){
        return -1;
      }
      par--;
    }else if(OFTYPES(tokens[i].type, nop_types)){
      continue;
    }else if(par > 0){
      continue;
    }else{
      int tmp_priority = 0;
      switch(tokens[i].type){
        case TK_OR: tmp_priority++;
        case TK_AND: tmp_priority++;
        case TK_EQ: case TK_NEQ: tmp_priority++;
        case TK_GT: case TK_LT: case TK_GE: case TK_LE: tmp_priority++;
        case '+': case '-': tmp_priority++;
        case '*': case '/': tmp_priority++;
        case TK_NEG: case TK_POS: case TK_DREF: tmp_priority++; break;
        default: assert(0);
      }
      //here the judgement logic
      if(tmp_priority >= op_priority || (tmp_priority == op_priority && !OFTYPES(tokens[i].type, op1_type))){
        op_priority = tmp_priority;
        op = i;
      }
    }
  }
  if(par != 0){
    return -1;
  }

  return op;
}

static word_t parse_operand(int i, bool *valid){
  switch(tokens[i].type) {
    case TK_NUM:
      if(strncmp("0x", tokens[i].str, 2) == 0){
        return strtol(tokens[i].str, NULL, 16);
      }else{
        return strtol(tokens[i].str, NULL, 10);
      }
    case TK_REG:
      return isa_reg_str2val(tokens[i].str, valid);
    default:
      *valid = false;
      return 0;
  }
}

//unary calculation
word_t unary_cal(int op, word_t val, bool *valid){
  switch(tokens[op].type){
    case TK_NEG: return -val;
    case TK_POS: return val;
    case TK_DREF: return paddr_read(val, 4);
    default: *valid = false;
  }
  return 0;
}

word_t binary_cal(word_t val1, int op, word_t val2, bool *valid){
  switch (tokens[op].type) {
    case '+': return val1 + val2;
    case '-': return val1 - val2;
    case '*': return val1 * val2;
    case '/': 
      if(val2 == 0){
        printf("ERROR: Zero can't be divided");
        return 0;
      }else{
        return (int)val1 / (int)val2;
      }
    case TK_AND: return val1 && val2;
    case TK_OR: return val1 || val2;
    case TK_EQ: return val1 == val2;
    case TK_NEQ: return val1 != val2;
    case TK_GT: return val1 > val2;
    case TK_LT: return val1 < val2;
    case TK_GE: return val1 >= val2;
    case TK_LE: return val1 <= val2;
    default: *valid = false; return 0;
    //default: assert(0);
  }
}

word_t eval(int p, int q, bool *valid){
  *valid = true;
  int op;
  if (p > q) {
    /* Bad expression */
    *valid = false;
    return 0;
  }else if (p == q) {
    /* Single token.
     * For now this token should be a number.
     * Return the value of the number.
     */
    return parse_operand(p, valid);
    //return atoi(tokens[p].str);
  }else if (check_parentheses(p, q) == true) {
    /* The expression is surrounded by a matched pair of parentheses.
     * If that is the case, just throw away the parentheses.
     */
    return eval(p + 1, q - 1, valid);
  }else {
    //find main operator
    op = find_op(p, q);
    //op = the position of 主运算符 in the token expression;
    if(op < 0){
      printf("ERROR: find_op() failed\n");
      assert(0);
      return -1;
    }
    /* ------------------------------- TEST EXPR -------------------------------- */
    // else{
    //   cal_depth++;
    //   printf("LEVEL %d:", cal_depth);
    //   // for(int i = 0; i<cal_depth;i++){
    //   //   printf("\t");
    //   // }
    //   for(int i = p; i < op; i++){
    //     printf("%s", tokens[i].str);
    //   }
    //   printf(" %s ", tokens[op].str);
    //   for(int i = op+1; i < q+1; i++){
    //     printf("%s", tokens[i].str);
    //   }
    //   printf("\n");
    // }
    /* ------------------------------- TEST EXPR -------------------------------- */
    bool valid1, valid2;
    word_t val1 = eval(p, op - 1, &valid1);
    word_t val2 = eval(op + 1, q, &valid2);

    //
    //printf("%d %s %d\n", val1, tokens[op].str, val2);
    //

    if(!valid2){
      valid = false;
      return 0;
    }
    if(valid1){
      word_t rc = binary_cal(val1, op, val2, valid);
      return rc;
    }else{
      word_t rc = unary_cal(op, val2, valid);
      return rc;
    }
  }
}



word_t expr(char *e, bool *success) {
  if (!make_token(e)) {
    *success = false;
    return 0;
  }else{
    *success = true;
  }

  /* TODO: Insert codes to evaluate the expression. */
  for(int i = 0; i < nr_token; i++){
    if(tokens[i].type == '*' || tokens[i].type == '-' || tokens[i].type == '+'){
      if(i == 0 || !OFTYPES(tokens[i-1].type, bound_types)){
        switch(tokens[i].type){
          case '-': tokens[i].type = TK_NEG; break;
          case '+': tokens[i].type = TK_POS; break;
          case '*': tokens[i].type = TK_DREF; break;
        }
      }
    }
  }

  return eval(0, nr_token-1, success);
  cal_depth = 0;
}
