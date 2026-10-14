#include "Vysyx_axi4lite_decerr.h"
#include "verilated.h"
#include <fstream>
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>
struct Bench {
    Vysyx_axi4lite_decerr d;
    long cycle=0,accepted=0,completed=0,aborted=0;
    std::map<std::string,int> bins;
    void check(bool ok,const char* msg) {if(!ok) throw std::runtime_error(std::to_string(cycle)+": "+msg);}
    void tick() {d.clk=1;d.eval();Verilated::timeInc(1);d.clk=0;d.eval();Verilated::timeInc(1);++cycle;}
    void reset() {
        d.s_axi_arvalid=d.s_axi_awvalid=d.s_axi_wvalid=d.s_axi_rready=d.s_axi_bready=0;
        d.rst_n=0;d.eval();
        check(!(d.s_axi_arready||d.s_axi_awready||d.s_axi_wready||d.s_axi_rvalid||d.s_axi_bvalid),"reset gating");
        tick();tick();d.rst_n=1;d.eval();
        for(int n=0;n<3;n++) {check(!d.s_axi_rvalid&&!d.s_axi_bvalid,"stale response after reset");tick();}
    }
    // Abort phases: 0 complete; 1 reserved; 2 first request captured;
    // 3 both write channels captured; 4 response held.
    void run(bool wr,int order,int strb,int hold,int abort_phase=0) {
        bool ar=false,aw=false,w=false,counted=false;long first=-1,visible=-1;
        d.s_axi_araddr=0xffffffff;d.s_axi_awaddr=0xa00003f9;
        d.s_axi_arprot=5;d.s_axi_awprot=7;d.s_axi_wdata=0x12345678;d.s_axi_wstrb=strb;
        for(int n=0;n<2048;n++) {
            d.s_axi_arvalid=!wr&&!ar;
            d.s_axi_awvalid=wr&&!aw&&(order<=0||(w&&cycle>first+7));
            d.s_axi_wvalid=wr&&!w&&(order>=0||(aw&&cycle>first+7));
            d.s_axi_rready=!wr&&visible>=0&&cycle>=visible+hold;
            d.s_axi_bready=wr&&visible>=0&&cycle>=visible+hold;
            d.eval();
            check(!(d.s_axi_rvalid&&d.s_axi_bvalid),"dual response");
            bool reserved=!counted&&(d.s_axi_arready||d.s_axi_awready||d.s_axi_wready);
            bool fire=(d.s_axi_arvalid&&d.s_axi_arready)||(d.s_axi_awvalid&&d.s_axi_awready)||(d.s_axi_wvalid&&d.s_axi_wready);
            bool stop=abort_phase==1&&reserved;
            if(stop) {reset();return;}
            check(!(ar&&d.s_axi_arready)&&!(aw&&d.s_axi_awready)&&!(w&&d.s_axi_wready),"duplicate acceptance slot");
            if(fire&&!counted) {++accepted;counted=true;first=cycle;}
            if(d.s_axi_arvalid&&d.s_axi_arready) ar=true;
            if(d.s_axi_awvalid&&d.s_axi_awready) aw=true;
            if(d.s_axi_wvalid&&d.s_axi_wready) w=true;
            bool valid=wr?d.s_axi_bvalid:d.s_axi_rvalid;
            check(!(wr?d.s_axi_rvalid:d.s_axi_bvalid),"wrong response type");
            bool done=false;
            if(valid) {
                check(wr?(aw&&w):ar,"response before request complete");
                check((wr?d.s_axi_bresp:d.s_axi_rresp)==3,"not DECERR");
                if(!wr) check(d.s_axi_rdata==0,"error RDATA not zero");
                if(visible<0) visible=cycle;
                check(!(d.s_axi_arready||d.s_axi_awready||d.s_axi_wready),"accept while response held");
                done=wr?d.s_axi_bready:d.s_axi_rready;
            }
            stop=(abort_phase==2&&counted)||(abort_phase==3&&aw&&w)||(abort_phase==4&&valid);
            tick();
            if(stop) {++aborted;reset();return;}
            if(done) {++completed;d.s_axi_arvalid=d.s_axi_awvalid=d.s_axi_wvalid=0;d.s_axi_rready=d.s_axi_bready=0;
                for(int i=0;i<3;i++) {d.eval();check(!d.s_axi_rvalid&&!d.s_axi_bvalid,"duplicate response");tick();}
                ++bins[std::string(wr?"write/":"read/")+std::to_string(order)+"/strb/"+std::to_string(strb)];return;}
        }
        check(false,"watchdog");
    }
    void contention() {
        reset();bool ar=false,aw=false,w=false,r=false,b=false;
        d.s_axi_rready=d.s_axi_bready=1;
        for(int n=0;n<128;n++) {
            d.s_axi_arvalid=!ar;d.s_axi_awvalid=!aw;d.s_axi_wvalid=!w;d.eval();
            if(d.s_axi_awready||d.s_axi_wready) check(r,"reset must prefer read");
            if(d.s_axi_arvalid&&d.s_axi_arready) {ar=true;++accepted;}
            if(d.s_axi_awvalid&&d.s_axi_awready) {aw=true;++accepted;}
            if(d.s_axi_wvalid&&d.s_axi_wready) w=true;
            if(d.s_axi_rvalid) {check(ar&&!r&&d.s_axi_rresp==3&&d.s_axi_rdata==0,"contention read");r=true;++completed;}
            if(d.s_axi_bvalid) {check(aw&&w&&!b&&d.s_axi_bresp==3,"contention write");b=true;++completed;}
            tick();if(r&&b) {++bins["contention/read_then_write"];reset();return;}
        }
        check(false,"contention watchdog");
    }
};
int main(int argc,char**argv) {
    Verilated::commandArgs(argc,argv);
    try {
        Bench b;b.reset();
        for(int order=-1;order<=1;order++) for(int strb=0;strb<16;strb++) for(int hold:{0,1,64}) {
            b.run(true,order,strb,hold);b.run(false,0,0,hold);
        }
        for(int phase=1;phase<=4;phase++) for(int order=-1;order<=1;order++) {
            b.run(true,order,15,64,phase);b.run(false,0,0,0);b.run(true,0,0,0);
            ++b.bins["reset/write/"+std::to_string(phase)+"/order/"+std::to_string(order)];
        }
        for(int phase:{1,2,4}) {b.run(false,0,0,64,phase);b.run(true,0,15,0);++b.bins["reset/read/"+std::to_string(phase)];}
        b.contention();b.check(b.accepted==b.completed+b.aborted,"epoch accounting");
        std::ofstream csv(argc>1?argv[1]:"decerr-coverage.csv");csv<<"bin,hits\n";
        for(auto x:b.bins) csv<<x.first<<','<<x.second<<'\n';
        b.check(bool(csv),"coverage file");
        std::cout<<"DECERR PASS accepted="<<b.accepted<<" completed="<<b.completed<<" aborted="<<b.aborted<<" bins="<<b.bins.size()<<" cycles="<<b.cycle<<'\n';
    } catch(const std::exception& e) {std::cerr<<"FAIL "<<e.what()<<'\n';return 1;}
}
