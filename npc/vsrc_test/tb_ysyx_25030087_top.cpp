#include "verilated.h"
#include "verilated_vcd_c.h"
//modify name of the module (1/4)
#include "obj_dir/Vysyx_25030087_top.h"

#define BIN_PART(a) (a##U)

VerilatedContext *contextp = NULL;
VerilatedVcdC* tfp = NULL;

// variables
#define MAX_SIM_TIME 90 // 2 times clk
#define VERIF_START_TIME 7
vluint64_t sim_time = 0;
vluint64_t posedge_cnt = 0;

//add name of the module (2/4)
static Vysyx_25030087_top *top;

void step_and_dump_wave(){
    top->eval();
    contextp->timeInc(1);
    tfp->dump(contextp->time());
}

void sim_init(){
    contextp = new VerilatedContext;
    tfp = new VerilatedVcdC;
    //add name of the module(3/4)
    top = new Vysyx_25030087_top;

    contextp->traceEverOn(true);
    top->trace(tfp, 0);
    tfp->open("waveform.vcd");
}

void sim_exit(){
    step_and_dump_wave();
    tfp->close();
    delete top;
    exit(EXIT_SUCCESS);
}

// name (4/4)
void top_reset(Vysyx_25030087_top *top, vluint64_t &sim_time){
     top->rst = 0;
    if(sim_time > 1 && sim_time < 5){
        top->rst = 1;
        top->inst = 0;
    }
}

void set_module_inputs(int rst, int inst){
    //top->clk,
    top->rst = rst;
    top->inst = inst & 0xffffffff;
}

void sim_timebased(){
    while(sim_time < MAX_SIM_TIME){
        // 5 clock to reset
        top_reset(top, sim_time);

        top->clk ^= 1;
        top->eval();

        if(top->clk == 1){
            posedge_cnt++;
            switch(posedge_cnt){
                case 10:
                    set_module_inputs(0, 
                    (BIN_PART(0b000000000001)<<20) | 
                    (BIN_PART(0b00000)<<15) |
                    (BIN_PART(0b000)<<12) |
                    (BIN_PART(0b00001)<<7) |
                    (BIN_PART(0b0011011))
                    );
                break;
                case 13:
                    set_module_inputs(0, 
                    (BIN_PART(0b000000000000)<<20) | 
                    (BIN_PART(0b00000)<<15) |
                    (BIN_PART(0b000)<<12) |
                    (BIN_PART(0b00000)<<7) |
                    (BIN_PART(0b0011011))
                    );
                break;
                case 15:
                    set_module_inputs(0, 
                    (BIN_PART(0b000000000010)<<20) | 
                    (BIN_PART(0b00001)<<15) |
                    (BIN_PART(0b000)<<12) |
                    (BIN_PART(0b00001)<<7) |
                    (BIN_PART(0b0011011))
                    );
                break;
            }
            
        }
            tfp->dump(sim_time);
            sim_time++;
    }
}

int main(){
    sim_init();

    sim_timebased();

    sim_exit();
}
