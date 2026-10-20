// Independent SoC guard oracle. Cases explicitly specify forwarding vs error;
// no DUT state/address decoder is read to compute expected results.
#include "Vnpc_axi4_guard.h"
#include "verilated.h"
#include <cstdint>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>

static void check(bool ok,const char *why){if(!ok)throw std::runtime_error(why);}
struct Tx {uint32_t addr;bool write;unsigned size,strb,resp;bool forward;};
struct Bench {
    Vnpc_axi4_guard d;std::mt19937 rng{27};unsigned completed=0,aborted=0;
    void edge(){d.clock=1;d.eval();Verilated::timeInc(5);d.clock=0;d.eval();Verilated::timeInc(5);}
    void clear(){
        d.in_arvalid=d.in_awvalid=d.in_wvalid=d.in_rready=d.in_bready=0;
        d.out_arready=d.out_awready=d.out_wready=d.out_rvalid=d.out_bvalid=0;
        d.in_arlen=d.in_awlen=0;d.in_arburst=d.in_awburst=1;d.in_wlast=1;
        d.out_rlast=1;
    }
    void reset(){clear();d.clock=0;d.reset=1;d.eval();edge();edge();d.reset=0;d.eval();}
    void transaction(Tx t,int input_order,int output_order,const std::string &abort="") {
        clear();unsigned id=3+rng()%12,aw_step=99999,w_step=99999,hold=0;
        bool ar=false,aw=false,w=false,da=false,dw=false,dr=false,response=false,finished=false;
        unsigned delay=0;uint32_t rd=0x88776655,wd=0xa5b6c7d8;
        d.in_arid=d.in_awid=id;d.out_rid=d.out_bid=id;
        d.in_araddr=d.in_awaddr=t.addr;d.in_arsize=d.in_awsize=t.size;
        d.in_wdata=wd;d.in_wstrb=t.strb;d.out_rdata=rd;d.out_rresp=d.out_bresp=t.resp;
        for(unsigned n=0;n<400;++n) {
            d.in_arvalid=!t.write&&!ar;
            d.in_awvalid=t.write&&!aw&&(input_order<=0 || (w&&n>w_step+3));
            d.in_wvalid=t.write&&!w&&(input_order>=0 || (aw&&n>aw_step+3));
            d.in_rready=d.in_bready=hold>=12;
            d.out_arready=n%8==0 || rng()%2;
            d.out_awready=(output_order<=0 || dw)&&(n%8==0 || rng()%2);
            d.out_wready=(output_order>=0 || da)&&(n%8==0 || rng()%2);
            d.out_rvalid=!t.write&&dr&&delay>=5&&!response;
            d.out_bvalid=t.write&&da&&dw&&delay>=5&&!response;
            d.eval();
            if(d.in_arvalid&&d.in_arready){check(!ar,"duplicate input AR");ar=true;}
            if(d.in_awvalid&&d.in_awready){check(!aw,"duplicate input AW");aw=true;aw_step=n;}
            if(d.in_wvalid&&d.in_wready){check(!w,"duplicate input W");w=true;w_step=n;}
            bool external=d.out_arvalid||d.out_awvalid||d.out_wvalid;
            check(!external||t.forward,"rejected access escaped to device");
            if(d.out_arvalid){check(d.out_araddr==t.addr && d.out_arsize==t.size && d.out_arid==id && !d.out_arlen && d.out_arburst==1,"forward AR payload");}
            if(d.out_awvalid){check(d.out_awaddr==t.addr && d.out_awsize==t.size && d.out_awid==id && !d.out_awlen && d.out_awburst==1,"forward AW payload");}
            if(d.out_wvalid){check(d.out_wdata==wd && d.out_wstrb==t.strb && d.out_wlast,"forward W payload");}
            if(d.out_arvalid&&d.out_arready){check(!dr,"duplicate output AR");dr=true;}
            if(d.out_awvalid&&d.out_awready){check(!da,"duplicate output AW");da=true;}
            if(d.out_wvalid&&d.out_wready){check(!dw,"duplicate output W");dw=true;}
            if(dr||(da&&dw))++delay;
            if((d.out_rvalid&&d.out_rready)||(d.out_bvalid&&d.out_bready))response=true;
            if(d.in_rvalid||d.in_bvalid){
                check((t.write?d.in_bvalid:d.in_rvalid) && !(d.in_rvalid&&d.in_bvalid),"response kind");
                check((t.write?d.in_bresp:d.in_rresp)==t.resp,"response code");
                check((t.write?d.in_bid:d.in_rid)==id,"response ID");
                if(!t.write)check(d.in_rlast && d.in_rdata==(t.forward?rd:0),"read payload/last");
                if(t.forward)check(response,"reply before downstream completion");
                ++hold;
                if(t.write?d.in_bready:d.in_rready)finished=true;
            }
            bool abort_now=(abort=="aw_only"&&aw&&!w)||(abort=="w_only"&&w&&!aw)||
                (abort=="down_aw"&&da&&!dw)||(abort=="down_w"&&dw&&!da)||
                (abort=="wait_r"&&dr&&!response)||(abort=="wait_b"&&da&&dw&&!response)||
                (abort=="response"&&hold>0);
            edge();
            if(abort_now){
                ++aborted;reset();
                for(int i=0;i<4;++i){check(!(d.in_rvalid||d.in_bvalid||d.out_arvalid||d.out_awvalid||d.out_wvalid),"stale after reset");edge();}
                transaction(Tx{0x0f000000,false,2,0,0,true},0,0);
                return;
            }
            if(finished){check(abort.empty(),"abort phase never reached");++completed;clear();for(int i=0;i<3;++i){d.eval();check(!(d.in_rvalid||d.in_bvalid||d.out_arvalid||d.out_awvalid||d.out_wvalid),"duplicate after retirement");edge();}return;}
        }
        throw std::runtime_error("guard watchdog");
    }
};
int main(int argc,char **argv){
    Verilated::commandArgs(argc,argv);
    try {
        Bench b;b.reset();
        const Tx cases[]={
            {0x0f000000,false,2,0,0,true},{0x0f001fff,false,0,0,0,true},
            {0x0f001ffc,true,2,15,0,true},{0x0f002000,false,2,0,3,false},
            {0x0f002000,true,2,15,3,false},{0x0f001fff,false,1,0,3,false},
            {0x20000000,false,2,0,0,true},{0x20000fff,false,0,0,0,true},
            {0x20001000,false,2,0,3,false},{0x20000000,true,2,15,2,false},
            {0x10000005,false,0,0,0,true},{0x10000003,true,0,8,0,true},
            {0x10000000,false,2,0,2,false},{0x10000000,true,0,0,2,false},
            {0x10001000,false,2,0,0,true},{0x10001000,true,2,15,0,true},
            {0x10001000,true,0,1,2,false},{0x10002000,false,2,0,2,false},
            {0x10011000,true,2,15,2,false},{0x21000000,false,2,0,2,false},
            {0x30000000,true,2,15,2,false},{0x80000000,false,2,0,2,false},
            {0xa0000000,false,2,0,2,false},{0x10003000,false,2,0,3,false},
            {0xc0000000,true,2,15,3,false},{0xffffffff,false,0,0,3,false},
            {0x0f000001,false,2,0,2,false},{0x0f000000,true,0,2,2,false}
        };
        for(auto t:cases)for(int in=-1;in<=1;++in)for(int out=-1;out<=1;++out)b.transaction(t,in,out);
        for(unsigned i=0;i<1000;++i)b.transaction(cases[b.rng()%(sizeof(cases)/sizeof(cases[0]))],int(b.rng()%3)-1,int(b.rng()%3)-1);
        // A real downstream error must survive the response buffer unchanged.
        b.transaction(Tx{0x0f000000,false,2,0,2,true},0,0);
        b.transaction(Tx{0x0f000000,true,2,15,3,true},0,0);
        Tx w{0x0f000000,true,2,15,0,true},r{0x20000000,false,2,0,0,true};
        b.transaction(w,-1,0,"aw_only");b.transaction(w,1,0,"w_only");
        b.transaction(w,0,-1,"down_aw");b.transaction(w,0,1,"down_w");
        b.transaction(w,0,0,"wait_b");b.transaction(r,0,0,"wait_r");
        b.transaction(Tx{0,true,2,15,3,false},0,0,"response");
        std::cout<<"Guard: PASS completed="<<b.completed<<" reset_aborted="<<b.aborted<<" cases=28 random_seed=27 random=1000 downstream_errors=2 reset_recovery=7\n";
    }catch(const std::exception &e){std::cerr<<"FAIL: "<<e.what()<<'\n';return 1;}
}
