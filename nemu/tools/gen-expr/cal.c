#include <stdio.h>

int main(int argc, char **argv){
    unsigned int num = 4294967293;
    int int_num = (int) num;
    printf("%d", int_num);
    return 0;
}