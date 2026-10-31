#include "bpu_stats.h"
// Real ysyxSoCFull driver. Only ROM/Flash receive images. PSRAM backing is
// accessible through serial-model DPI; SRAM lives in RTL. No RAM preload.
#include "VysyxSoCFull.h"
#include "VysyxSoCFull__Dpi.h"
#include "difftest.h"
#include "timer.h"
#include "svdpi.h"
#include "verilated.h"
#include "verilated_fst_c.h"
#include <algorithm>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr uint64_t HalfPeriod=5000; // --timescale-override 1ns/1ps; 100 MHz
constexpr uint32_t RomBase=0x20000000;
#ifdef NPC_FLASH_BOOT
constexpr uint32_t ResetPC=0x30000000;
#else
constexpr uint32_t ResetPC=RomBase;
#endif
std::vector<uint8_t> psram(4*1024*1024,0);
uint64_t psram_reads=0,psram_writes=0;
uint32_t min_psram_sp=0x80400000;
std::vector<uint8_t> rom(4096,0),flash;
VerilatedContext *context=nullptr;
std::ofstream commits,bus,uart_events,irq_events,uart_frames;
std::string error,tx_bytes;
BpuStats bpu;
uint64_t commit_count=0,exceptions=0,ar_count=0,aw_count=0,w_count=0,r_count=0,b_count=0;
uint64_t cpu_release_ps=0,first_ar_ps=0,first_commit_ps=0,mrom_calls=0,flash_calls=0;
uint64_t thr_writes=0,uart_reads=0;
uint32_t min_sram_sp=0x0f002000;
uint32_t first_ar=0,first_inst=0,first_pc=0,last_pc=0,last_inst=0,last_a0=0;
bool stopped=false,seen_release=false,read_pending=false,aw_pending=false,w_pending=false;
svScope state_scope=nullptr,sram_scope=nullptr;
bool commit_pending=false;
SocCommit pending{};
SocTimer timer;
bool irq_pending=false;
uint32_t irq_pc=0;
uint64_t irq_count=0;
uint8_t uart_lcr=0;
// Named regions separate the boot stack from each RTOS thread stack. Observe
// architectural SP after every instruction/IRQ; never preload stack contents.
struct StackRegion {
    std::string name;
    uint32_t low,high,minimum;
    uint64_t samples=0;
};
std::vector<StackRegion> stacks;
bool stack_started=false;
void fail(const std::string &why) {if(error.empty())error=why;}
uint64_t now() {return context->time();}
void load(const std::string &path,std::vector<uint8_t> &dest,size_t capacity,uint8_t fill) {
    std::ifstream f(path,std::ios::binary|std::ios::ate);
    if(!f)throw std::runtime_error("Cannot open image: "+path);
    auto size=f.tellg();
    if(size<=0 || uint64_t(size)>capacity)throw std::runtime_error("Empty/oversized image: "+path);
    dest.assign(capacity,fill);f.seekg(0);f.read(reinterpret_cast<char*>(dest.data()),size);
    if(!f)throw std::runtime_error("Image read failed: "+path);
}
uint32_t word(const std::vector<uint8_t> &data,size_t offset) {
    return uint32_t(data[offset])|(uint32_t(data[offset+1])<<8)|
           (uint32_t(data[offset+2])<<16)|(uint32_t(data[offset+3])<<24);
}
uint64_t number(const std::string &s) {
    size_t end=0;auto n=std::stoull(s,&end,0);
    if(end!=s.size() || !n || s[0]=='-')throw std::runtime_error("Invalid positive number: "+s);
    return n;
}
}
extern "C" void npc_bpu_event(int mode,int flags,int kind,int flushed) { bpu.event(mode,flags,kind,flushed); }
extern "C" void npc_soc_state_scope() { state_scope=svGetScope(); }
extern "C" void npc_soc_timer(int reset_active,long long time_value,long long compare_value,
    int irq,int valid,int write_access,int addr,int size,int data,int strb,int response,
    int taken,int pc,int status,int mie) {
    try {timer.edge(reset_active,uint64_t(time_value),uint64_t(compare_value),irq,
        valid,write_access,uint32_t(addr),unsigned(size),uint32_t(data),unsigned(strb),uint32_t(response));}
    catch(const std::exception &e){fail(e.what());}
    if(!reset_active && taken) {
        if(irq_pending)fail("Unconsumed IRQ event");
        if(!timer.pre || !(status&8) || !(mie&128))fail("Masked/unpending IRQ accepted");
        irq_pending=true;irq_pc=uint32_t(pc);++irq_count;
        if(irq_events.is_open())irq_events<<std::dec<<now()<<','<<std::hex<<irq_pc<<','<<time_value<<','<<compare_value<<'\n';
    }
}
extern "C" void npc_soc_sram_scope() { sram_scope=svGetScope(); }
extern "C" void mrom_read(int raddr,int *rdata) {
    ++mrom_calls;uint32_t a=uint32_t(raddr)&~3u;
    if(a<RomBase || a-RomBase>rom.size()-4) {fail("mrom_read physical address out of bounds");*rdata=0;return;}
    *rdata=int(word(rom,a-RomBase));
}
extern "C" void flash_read(int addr,int *data) {
    ++flash_calls;uint32_t off=uint32_t(addr);
    if(flash.empty()) {fail("Unexpected flash_read: no --flash image loaded");*data=0;return;}
    if(uint64_t(off)+4>flash.size()) {fail("flash_read offset out of bounds");*data=0;return;}
    *data=int(word(flash,off));
}
extern "C" int psram_read(int addr) {
    ++psram_reads;
    if(uint32_t(addr)>=psram.size()){fail("PSRAM serial read out of bounds");return 0;}
    return psram[uint32_t(addr)];
}
extern "C" void psram_write(int addr,int data) {
    ++psram_writes;
    if(uint32_t(addr)>=psram.size()){fail("PSRAM serial write out of bounds");return;}
    psram[uint32_t(addr)]=uint8_t(data);
}
extern "C" void npc_soc_commit(int pc,int inst,int a0,int flags,int cause,int addr) {
    if(commit_pending)fail("Unconsumed architectural commit");
    commit_pending=true;pending={uint32_t(pc),uint32_t(inst),uint32_t(flags),uint32_t(cause),uint32_t(addr)};
    if(!commit_count) {first_pc=pc;first_inst=inst;first_commit_ps=now();}
    ++commit_count;exceptions+=bool(flags&1);last_pc=pc;last_inst=inst;last_a0=a0;
    if(commits.is_open())commits<<std::dec<<now()<<','<<std::hex<<uint32_t(pc)<<','<<uint32_t(inst)
        <<','<<uint32_t(a0)<<','<<uint32_t(flags)<<','<<uint32_t(cause)<<','<<uint32_t(addr)<<'\n';
    if(uint32_t(inst)==0x00100073 && !(flags&1))stopped=true;
}
extern "C" void npc_soc_bus(int reset_active,int flags,int araddr,int awaddr,int wd,int rd,
                            int arsize,int awsize,int strb,int rresp,int bresp) {
    if(reset_active) {
        if(flags)fail("CPU AXI transfer during reset");
        read_pending=aw_pending=w_pending=false;return;
    }
    if(!seen_release) {seen_release=true;cpu_release_ps=now();}
    if(flags&1) {if(read_pending||aw_pending||w_pending)fail("overlapping CPU read");read_pending=true;
        if(!ar_count){first_ar=araddr;first_ar_ps=now();}++ar_count;}
    if(flags&2) {if(aw_pending||read_pending)fail("overlapping CPU AW");aw_pending=true;++aw_count;}
    if(flags&4) {if(w_pending||read_pending)fail("overlapping CPU W");w_pending=true;++w_count;}
    if(flags&8) {if(!read_pending)fail("unsolicited CPU R");read_pending=false;++r_count;}
    if(flags&16){if(!aw_pending||!w_pending)fail("unsolicited CPU B");aw_pending=w_pending=false;++b_count;}
    if(flags && bus.is_open())bus<<std::dec<<now()<<','<<flags<<','<<std::hex<<uint32_t(araddr)<<','<<uint32_t(awaddr)
        <<','<<uint32_t(wd)<<','<<uint32_t(rd)<<','<<arsize<<','<<awsize<<','<<strb<<','<<rresp<<','<<bresp<<'\n';
}
extern "C" void npc_soc_uart(int write_access,int addr,int data) {
    if(uart_events.is_open())uart_events<<std::dec<<now()<<','<<write_access<<','<<addr<<','<<data<<'\n';
    if(write_access) {
        if(addr==3)uart_lcr=uint8_t(data);
        if(addr==0 && !(uart_lcr&0x80))++thr_writes;
    } else ++uart_reads;
}
int main(int argc,char **argv) {
    try {
        std::string image,flash_image,wave_path,uart_path,summary_path,diff_path;
        uint64_t max_cycles=2000000,bit_cycles=16,inject_at=0,irq_inject_at=0;
        SocDiff diff;
        auto output=[](std::ofstream &f,const std::string &path){f.open(path);if(!f)throw std::runtime_error("Cannot write: "+path);};
        for(int i=1;i<argc;++i) {
            std::string opt=argv[i];
            if(opt.rfind("+npc_delay_",0)==0) continue; // simulation shim plusargs
            if(opt=="--help") {std::cout<<"Boot profile is fixed at build time; reset PC=0x"<<std::hex<<ResetPC
                <<"\n[--mrom FILE] [--flash FILE] [--diff REF.so] [--diff-inject-at COMMIT] [--irq-inject-at EVENT] [--max-cycles N] [--trace FST] [--commit-trace CSV] [--bus-trace CSV] [--irq-trace CSV] [--uart-events CSV] [--uart-log FILE] [--summary JSON] [--uart-bit-cycles N] [--uart-serial-trace CSV] [--stack-region NAME:LOW:HIGH] (repeatable)\n";return 0;}
            if(i+1>=argc)throw std::runtime_error("Missing argument for "+opt);
            std::string val=argv[++i];
            if(opt=="--mrom")image=val;else if(opt=="--flash")flash_image=val;
            else if(opt=="--max-cycles")max_cycles=number(val);
            else if(opt=="--uart-bit-cycles")bit_cycles=number(val);
            else if(opt=="--diff")diff_path=val;
            else if(opt=="--diff-inject-at")inject_at=number(val);
            else if(opt=="--irq-inject-at")irq_inject_at=number(val);
            else if(opt=="--trace")wave_path=val;else if(opt=="--uart-log")uart_path=val;
            else if(opt=="--summary")summary_path=val;
            else if(opt=="--commit-trace")output(commits,val);
            else if(opt=="--bus-trace")output(bus,val);
            else if(opt=="--irq-trace")output(irq_events,val);
            else if(opt=="--uart-events")output(uart_events,val);
            else if(opt=="--uart-serial-trace")output(uart_frames,val);
            else if(opt=="--stack-region") {
                auto a=val.find(':'),b=val.find(':',a==std::string::npos?0:a+1);
                if(a==std::string::npos || b==std::string::npos || !a)
                    throw std::runtime_error("Stack region requires NAME:LOW:HIGH");
                auto name=val.substr(0,a);auto low=number(val.substr(a+1,b-a-1)),high=number(val.substr(b+1));
                if(name.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")!=std::string::npos ||
                   low>=high || high>UINT32_MAX)
                    throw std::runtime_error("Invalid stack region");
                for(const auto &s:stacks) if(name==s.name || (low<s.high && high>s.low))
                    throw std::runtime_error("Overlapping/duplicate stack region");
                stacks.push_back({name,uint32_t(low),uint32_t(high),uint32_t(high),0});
            }
            else throw std::runtime_error("Unknown option: "+opt);
        }
        if(ResetPC==RomBase && image.empty())throw std::runtime_error("--mrom image is required");
        if(ResetPC!=RomBase && flash_image.empty())throw std::runtime_error("--flash image is required");
        if(!image.empty())load(image,rom,4096,0);
        if(!flash_image.empty())load(flash_image,flash,16*1024*1024,0xff);
        if((inject_at || irq_inject_at) && diff_path.empty())throw std::runtime_error("DiffTest injection requires --diff");
        if(!diff_path.empty())diff.init(diff_path,rom,flash,ResetPC);
        auto ctx=std::make_unique<VerilatedContext>();context=ctx.get();ctx->commandArgs(argc,argv);
        ctx->traceEverOn(!wave_path.empty());
        auto dut=std::make_unique<VysyxSoCFull>(ctx.get());
        VerilatedFstC wave;if(!wave_path.empty()){dut->trace(&wave,99);wave.open(wave_path.c_str());}
        dut->clock=0;dut->reset=1;dut->externalPins_uart_rx=1;
        dut->externalPins_ps2_clk=1;dut->externalPins_ps2_data=1;dut->externalPins_gpio_in=0;
        dut->eval();if(!wave_path.empty())wave.dump(now());
        if(!state_scope || !sram_scope)throw std::runtime_error("Missing SoC simulation binding");
        uint64_t edge=HalfPeriod,cycles=0;
        uint64_t sample=std::numeric_limits<uint64_t>::max();
        const uint64_t bit_time=bit_cycles*2*HalfPeriod;
        int serial_bit=-2;uint8_t serial_data=0;bool prev_tx=true;uint64_t serial_start=0;
        // Advance to whichever happens first: an external edge, a Verilator
        // delayed event (#1/#Tp), or the UART decoder's sample time.
        while(error.empty() && !stopped && !ctx->gotFinish() && cycles<max_cycles) {
            uint64_t next=std::min(edge,sample);
            if(dut->eventsPending())next=std::min(next,dut->nextTimeSlot());
            if(next<=now())throw std::runtime_error("Event scheduler did not advance");
            ctx->time(next);
            if(next==edge) {
                dut->clock=!dut->clock;
                if(!dut->clock) {++cycles;if(cycles==20)dut->reset=0;}
                edge+=HalfPeriod;
            }
            dut->eval();if(!wave_path.empty())wave.dump(now());
            if(commit_pending || irq_pending) {
                // All NBA updates are now visible. Never compare the pre-edge
                // state observed by the commit callback with the stepped ref.
                svSetScope(state_scope);
                SocState state{};
                for(unsigned i=0;i<state.size();++i)state[i]=uint32_t(npc_soc_state(int(i)));
                if(state[2]>=0x0f000000 && state[2]<=0x0f002000)
                    min_sram_sp=std::min(min_sram_sp,state[2]);
                if(state[2]>=0x80000000 && state[2]<=0x80400000)
                    min_psram_sp=std::min(min_psram_sp,state[2]);
                bool in_stack=false;
                for(auto &s:stacks) if(state[2]>s.low && state[2]<=s.high) {
                    in_stack=true;s.minimum=std::min(s.minimum,state[2]);++s.samples;
                }
                if(!stacks.empty() && stack_started && !in_stack)fail("SP outside declared stack regions");
                stack_started|=in_stack;
                if(diff.active()) {
                    if(commit_count==inject_at)state[5]^=1; // comparator negative test only
                    if(irq_pending && irq_count==irq_inject_at)state[19]^=4; // corrupt sampled EPC only
                    try {
                        if(commit_pending && irq_pending)throw std::runtime_error("IRQ and instruction committed together");
                        if(irq_pending)diff.interrupt(irq_pc,state,timer.pre,timer.post);
                        else diff.step(pending,state,timer);
                    }catch(const std::exception &e){fail(e.what());}
                }
                commit_pending=false;
                irq_pending=false;
            }
            bool tx=dut->externalPins_uart_tx;
            if(!dut->reset) {
                if(serial_bit==-2 && prev_tx && !tx) {serial_bit=-1;serial_data=0;serial_start=now();sample=now()+bit_time/2;}
                if(now()==sample) {
                    if(serial_bit==-1) {if(tx)fail("UART false start");}
                    else if(serial_bit<8) serial_data|=uint8_t(tx)<<serial_bit;
                    else {if(!tx)fail("UART framing error");else {
                        tx_bytes.push_back(char(serial_data));
                        if(uart_frames.is_open())uart_frames<<serial_start<<','<<now()<<','<<unsigned(serial_data)<<'\n';
                    }}
                    ++serial_bit;
                    if(serial_bit==9){serial_bit=-2;sample=std::numeric_limits<uint64_t>::max();}
                    else sample+=bit_time;
                }
            }
            prev_tx=tx;
        }
        if(error.empty() && !stopped)fail(ctx->gotFinish()?"Unexpected RTL finish":"Simulation timeout");
        if(stopped && last_a0)fail("ebreak with nonzero a0");
        if(stopped && (first_ar!=ResetPC || first_pc!=ResetPC))fail("Wrong first boot address/PC");
        if(stopped && first_inst!=word(ResetPC==RomBase?rom:flash,0))fail("First instruction differs from image");
        if(error.empty() && stopped && diff.active()) {
            svSetScope(sram_scope);
            std::array<uint32_t,2048> state{};
            for(unsigned i=0;i<state.size();++i)state[i]=uint32_t(npc_soc_sram_word(int(i)));
            try {diff.memory(state);diff.psram_memory(psram);}catch(const std::exception &e){fail(e.what());}
        }
        dut->final();if(!wave_path.empty())wave.close();
        if(!uart_path.empty()){std::ofstream f(uart_path,std::ios::binary);f<<tx_bytes;if(!f)throw std::runtime_error("UART log write failed");}
        if(!summary_path.empty()) {
            std::ofstream f(summary_path);f<<"{\n  \"pass\": "<<(error.empty()?"true":"false")
             <<",\n  \"cycles\": "<<cycles<<",\n  \"commits\": "<<commit_count<<",\n  \"exceptions\": "<<exceptions
             <<",\n  \"ar\": "<<ar_count<<",\n  \"aw\": "<<aw_count<<",\n  \"w\": "<<w_count<<",\n  \"r\": "<<r_count<<",\n  \"b\": "<<b_count
             <<",\n  \"cpu_release_ps\": "<<cpu_release_ps<<",\n  \"first_ar_ps\": "<<first_ar_ps<<",\n  \"first_commit_ps\": "<<first_commit_ps
             <<",\n  \"mrom_dpi_calls\": "<<mrom_calls<<",\n  \"flash_dpi_calls\": "<<flash_calls
             <<",\n  \"uart_thr_writes\": "<<thr_writes<<",\n  \"uart_register_reads\": "<<uart_reads<<",\n  \"uart_serial_bytes\": "<<tx_bytes.size()
             <<",\n  \"interrupts\": "<<irq_count<<",\n  \"diff_interrupts\": "<<diff.interrupts<<",\n  \"timer_checks\": "<<timer.checks
             <<",\n  \"diff_steps\": "<<diff.steps<<",\n  \"diff_device_reads\": "<<diff.device_reads
             <<",\n  \"diff_device_writes\": "<<diff.device_writes<<",\n  \"diff_sram_checks\": "<<diff.memory_checks
             <<",\n  \"min_sram_sp\": "<<min_sram_sp
             <<",\n  \"min_psram_sp\": "<<min_psram_sp
             <<",\n  \"psram_read_bytes\": "<<psram_reads<<",\n  \"psram_write_bytes\": "<<psram_writes
             <<",\n  \"diff_psram_checks\": "<<diff.psram_checks
             <<",\n  \"uart_bit_cycles\": "<<bit_cycles
             <<",\n  \"reset_pc\": "<<ResetPC<<",\n  \"stacks\": [";
            for(size_t i=0;i<stacks.size();++i) {
                const auto &s=stacks[i];if(i)f<<',';
                f<<"\n    {\"name\": \""<<s.name<<"\", \"low\": "<<s.low<<", \"high\": "<<s.high
                 <<", \"min_sp\": "<<s.minimum<<", \"used\": "<<s.high-s.minimum
                 <<", \"remaining\": "<<s.minimum-s.low<<", \"samples\": "<<s.samples<<'}';
            }
            f<<"\n  ],\n  \"bpu\": "; bpu.json(f); f<<"\n}\n";
            if(!f)throw std::runtime_error("Summary write failed");
        }
        if(!error.empty()){std::cerr<<"NPC_SOC_FAIL: "<<error<<" pc=0x"<<std::hex<<last_pc<<"\n";return 1;}
        std::cout<<"HIT GOOD TRAP: real ysyxSoC commits="<<commit_count<<" cycles="<<cycles
                 <<" UART_TX="<<tx_bytes<<"\n";return 0;
    } catch(const std::exception &e) {std::cerr<<"NPC_SOC_FAIL: "<<e.what()<<"\n";return 1;}
}
