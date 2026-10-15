// Independent transaction oracle for the complete two-master RTL fabric.
#include "Vaxi4lite_fabric_test_top.h"
#include "Vaxi4lite_fabric_test_top___024root.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <algorithm>
#include <array>
#include <deque>
#include <fstream>
#include <iostream>
#include <map>
#include <random>
#include <stdexcept>
#include <vector>
#include <string>
struct Tx {
 int owner=0; bool write=false; uint32_t addr=0x80000000,data=0xdeadbeef,expected=0;
 int prot=5,strb=15,order=0,gap=0,hold=0,resp=0,route=0;
 long ar=-1,aw=-1,w=-1,da=-1,dw=-1,dr=-1,visible=-1,start=-1;
 uint64_t sampled=0;
 bool effect=false,responded=false;
 std::array<int,5> delay{};
};
struct Bench {
 Vaxi4lite_fabric_test_top d; VerilatedVcdC wave; bool tracing=false;
 std::deque<Tx> q[2]; Tx *active=nullptr,last;
 std::vector<uint8_t> memory=std::vector<uint8_t>(12288);
 std::map<std::string,long> bins;
 long cycle=0,accepted=0,completed=0,aborted=0,effects=0,uart=0;
 uint64_t timer=0; std::mt19937 rng{1}; int prefer=0,previous_type=-1; bool random_gate=false; int block=-1,block_left=0;
 auto& mem(){return d.rootp->axi4lite_fabric_test_top__DOT__sram__DOT__mem;}
 auto& mtime(){return d.rootp->axi4lite_fabric_test_top__DOT__clint__DOT__mtime_q;}
 void check(bool ok,const std::string& why){if(!ok)throw std::runtime_error("cycle="+std::to_string(cycle)+" "+why);}
 void count(const std::string& key){++bins[key];}
 uint32_t word(unsigned a){return memory[a]|uint32_t(memory[a+1])<<8|uint32_t(memory[a+2])<<16|uint32_t(memory[a+3])<<24;}
 int route(uint32_t a){return a>=0x80000000&&uint64_t(a)<0x80003000?0:a>=0xa00003f8&&a<0xa0000400?1:a>=0xa0000048&&a<0xa0000050?2:3;}
 int response(const Tx&t){
  if(t.route==3)return 3;
  if(t.addr&3)return 2;
  if(t.route==0)return t.write&&(t.prot&4)?2:0;
  if(t.route==1)return t.write&&!(t.prot&4)&&t.addr==0xa00003f8&&(t.strb==0||t.strb==1)?0:2;
  return !t.write&&!(t.prot&4)?0:2;
 }
 void push(Tx t){check(t.owner||!t.write,"IFU write not allowed");t.route=route(t.addr);t.resp=response(t);q[t.owner].push_back(t);}
 void clear(){d.ifu_axi_arvalid=d.lsu_axi_arvalid=d.lsu_axi_awvalid=d.lsu_axi_wvalid=0;d.ifu_axi_rready=d.lsu_axi_rready=d.lsu_axi_bready=0;
  d.ifu_axi_araddr=d.lsu_axi_araddr=d.lsu_axi_awaddr=0xbadbad00;d.ifu_axi_arprot=d.lsu_axi_arprot=d.lsu_axi_awprot=0;d.lsu_axi_wdata=0x01010101;d.lsu_axi_wstrb=0;}
 void tick(){if(tracing)wave.dump(uint64_t(cycle*2));d.clk=1;d.eval();if(tracing)wave.dump(uint64_t(cycle*2+1));d.clk=0;d.eval();++cycle;}
 void memory_check(){for(unsigned i=0;i<memory.size();i+=4)check(mem()[i/4]==word(i),"SRAM whole-array oracle mismatch offset="+std::to_string(i));}
 void reset(bool init=false){
  if(active)++aborted;active=nullptr;q[0].clear();q[1].clear();clear();d.rst_n=0;d.eval();prefer=0;previous_type=-1;
  check(!d.tx_valid&&!d.ifu_axi_rvalid&&!d.lsu_axi_rvalid&&!d.lsu_axi_bvalid,"reset response/event");
  tick();tick();timer=0;
  if(init){for(unsigned i=0;i<memory.size();i++)memory[i]=(i*73)^0xa5;for(unsigned i=0;i<memory.size();i+=4)mem()[i/4]=word(i);}
  memory_check();d.rst_n=1;d.eval();block_left=0;
  for(int i=0;i<5;i++)step();check(accepted==completed+aborted,"reset epoch conservation");
 }
 bool publish(const Tx&t,bool aw){return t.order==0||(aw?t.order<0:t.order>0)||((aw?t.w:t.aw)>=0&&cycle>=(aw?t.w:t.aw)+std::max(1,t.gap));}
 void step(){
  clear();d.sim_accept=random_gate&&cycle%8? rng()&31:31;

  for(int i=0;i<5;i++)d.sim_delay[i]=active?active->delay[i]:0;
  for(int owner=0;owner<2;owner++)if(!q[owner].empty()){
   Tx&t=q[owner].front();if(t.start<0)t.start=cycle;check(cycle-t.start<2048,"head request exceeds 2048-cycle service bound");
   if(!t.write){
    if(owner){d.lsu_axi_arvalid=t.ar<0;d.lsu_axi_araddr=t.addr;d.lsu_axi_arprot=t.prot;}
    else{d.ifu_axi_arvalid=t.ar<0;d.ifu_axi_araddr=t.addr;d.ifu_axi_arprot=t.prot;}
   }else{
    d.lsu_axi_awvalid=t.aw<0&&publish(t,true);d.lsu_axi_awaddr=t.addr;d.lsu_axi_awprot=t.prot;
    d.lsu_axi_wvalid=t.w<0&&publish(t,false);d.lsu_axi_wdata=t.data;d.lsu_axi_wstrb=t.strb;
   }
  }
  if(active&&active->visible>=0&&cycle>=active->visible+active->hold){
   if(active->write)d.lsu_axi_bready=1;else if(active->owner)d.lsu_axi_rready=1;else d.ifu_axi_rready=1;
  }
  d.eval();
  if(block_left>0 && (d.shim_valid&(1<<block))){d.sim_accept&=~(1<<block);--block_left;d.eval();count("observed_stall/"+std::to_string(block));}
  bool up_ar[2]={bool(d.ifu_axi_arvalid&&d.ifu_axi_arready),bool(d.lsu_axi_arvalid&&d.lsu_axi_arready)};
  bool up_aw=d.lsu_axi_awvalid&&d.lsu_axi_awready,up_w=d.lsu_axi_wvalid&&d.lsu_axi_wready;
  for(int owner=0;owner<2;owner++)if(up_ar[owner]||(owner&&(up_aw||up_w))){
   Tx&t=q[owner].front();if(!active){if(!q[0].empty()&&!q[1].empty()){check(owner==prefer,"A02 RR fairness");count("rr/"+std::to_string(owner)+"/"+std::to_string(q[1].front().write));}active=&t;++accepted;count("owner/"+std::to_string(owner));}
   check(active==&t,"A02/A04 wrong owner or second transaction");
   if(up_ar[owner]){check(t.ar<0,"duplicate AR");t.ar=cycle;}
   if(owner&&up_aw){check(t.aw<0,"duplicate AW");t.aw=cycle;}
   if(owner&&up_w){check(t.w<0,"duplicate W");t.w=cycle;}
  }
  bool expected_sram=false;bool expected_uart=false;uint8_t uart_byte=0;
  for(int p=0;p<4;p++){
   unsigned mask=1u<<p;
   if((d.monitor_ar|d.monitor_aw|d.monitor_w|d.monitor_r|d.monitor_b)&mask){check(active,"downstream without owner");check(active->route==p,"A05 wrong selected route");}
   if(!active)continue;Tx&t=*active;
   if(d.monitor_ar&mask){check(!t.write&&t.dr<0,"duplicate or wrong AR");check(d.tap_araddr[p]==t.addr&&d.tap_arprot[p]==t.prot,"AR payload corrupt");t.dr=cycle;t.sampled=timer;
    t.expected=t.resp?0:p==0?word(t.addr-0x80000000):uint32_t(timer>>((t.addr&4)?32:0));}
   if(d.monitor_aw&mask){check(t.write&&t.da<0,"duplicate AW at device");check(d.tap_awaddr[p]==t.addr&&d.tap_awprot[p]==t.prot,"AW payload corrupt");t.da=cycle;}
   if(d.monitor_w&mask){check(t.write&&t.dw<0,"duplicate W at device");check(d.tap_wdata[p]==t.data&&d.tap_wstrb[p]==t.strb,"W payload corrupt");t.dw=cycle;}
   if(d.monitor_r&mask){check(!t.write&&t.dr>=0&&!t.responded,"R before AR/duplicate");check(((d.monitor_rresp>>(2*p))&3)==unsigned(t.resp)&&d.tap_rdata[p]==t.expected,"A06/A10 device R mismatch");t.responded=true;}
   if(d.monitor_b&mask){check(t.write&&t.da>=0&&t.dw>=0&&!t.responded,"B before AW/W or duplicate");check(((d.monitor_bresp>>(2*p))&3)==unsigned(t.resp),"device B mismatch");t.responded=true;}
  }
  if(active){Tx&t=*active;
   if(t.write&&!t.effect&&t.da>=0&&t.dw>=0&&cycle==std::max(t.da,t.dw)+1){
    t.effect=true;
    if(t.resp==0&&t.strb){++effects;
     if(t.route==0){expected_sram=true;unsigned off=t.addr-0x80000000;for(int i=0;i<4;i++)if(t.strb&(1<<i))memory[off+i]=t.data>>(8*i);}
     if(t.route==1){expected_uart=true;uart_byte=t.data;++uart;}
    }
   }
  }
  bool finish=false;
  for(int owner=0;owner<2;owner++){
   bool rv=owner?d.lsu_axi_rvalid:d.ifu_axi_rvalid,bv=owner&&d.lsu_axi_bvalid;
   if(rv||bv){check(active&&active->owner==owner,"A04 response owner");Tx&t=*active;check(bv==t.write&&t.responded,"response type or before downstream response");
    check((bv?d.lsu_axi_bresp:owner?d.lsu_axi_rresp:d.ifu_axi_rresp)==t.resp,"upstream response corrupt");
    if(rv)check((owner?d.lsu_axi_rdata:d.ifu_axi_rdata)==t.expected,"upstream RDATA corrupt");
    if(t.visible<0)t.visible=cycle;
    finish=bv?d.lsu_axi_bready:owner?d.lsu_axi_rready:d.ifu_axi_rready;
   }
  }
  check(bool(d.tap_sram_effect)==expected_sram,"A07 SRAM write execution missing/duplicate/illegal");
  tick();++timer;
  check(mtime()==timer,"A10 independent mtime clock mismatch");
  check(bool(d.tx_valid)==expected_uart,"A09 UART missing/duplicate/illegal effect");if(expected_uart)check(d.tx_data==uart_byte,"UART byte");
  if(finish){Tx t=*active;last=t;++completed;prefer=1-t.owner;
   if(previous_type>=0)count("transition/"+std::to_string(previous_type)+"/"+std::to_string(t.write)+"/"+std::to_string(t.owner));previous_type=t.write;
   count("cross/"+std::to_string(t.owner)+"/"+std::to_string(t.write)+"/"+std::to_string(t.route)+"/"+std::to_string(t.resp));
   count("hold/"+std::to_string(t.write)+"/"+std::to_string(t.hold));
   if(t.route==1)count("uart/"+std::to_string(t.owner)+"/"+std::to_string(t.write)+"/"+std::to_string(t.strb)+"/"+std::to_string(t.resp));
   if(t.route==2)count("clint/"+std::to_string(t.owner)+"/"+std::to_string(t.write)+"/"+std::to_string(t.addr&4)+"/"+std::to_string(t.resp));
   if(t.write){count("order/up/"+std::to_string((t.aw>t.w)-(t.aw<t.w)));count("order/down/"+std::to_string((t.da>t.dw)-(t.da<t.dw)));count("gap/up/"+std::to_string(std::abs(t.aw-t.w)));count("publish/"+std::to_string(t.order)+"/"+std::to_string(t.order?t.gap:0));
    if(t.route==0&&t.resp==0)count("mask/"+std::to_string(t.addr==0x80002ffc)+"/"+std::to_string(t.strb));}
   q[t.owner].pop_front();active=nullptr;
  }
 }
 template<class F>void until(F pred){for(int n=0;n<1024;n++){if(pred())return;step();}check(false,"1024-cycle watchdog");}
 void drain(){long prev=completed,stamp=cycle;while(!q[0].empty()||!q[1].empty()){
  check(cycle-stamp<2048,"2048-cycle progress watchdog");step();if(prev!=completed){stamp=cycle;prev=completed;}}
  for(int i=0;i<8;i++)step();check(accepted==completed+aborted,"drain conservation");memory_check();}
 Tx run(Tx t){push(t);drain();return last;}
};
Tx tx(int owner,int route,bool write=false){Tx t;t.owner=owner;t.write=write;t.prot=owner?1:5;t.route=route;t.addr=route==0?0x80000000:route==1?0xa00003f8:route==2?0xa0000048:0;t.strb=route==1?1:15;return t;}
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);Verilated::traceEverOn(true);
 try{Bench b;b.reset(true);b.count("reset/idle");
  // Compact waveform exhibits competition, W-first, delayed response and DECERR.
  if(argc>2){b.d.trace(&b.wave,6);b.wave.open(argv[2]);b.tracing=true;}
  Tx w=tx(1,0,true);w.order=1;w.gap=7;w.hold=7;b.push(w);b.push(tx(0,0));b.drain();b.run(tx(0,3));
  if(b.tracing){b.wave.close();b.tracing=false;}
  const uint32_t boundaries[]={0x7ffffffc,0x80000000,0x80000001,0x80002fff,0x80002ffc,0x80003000,0xa00003f4,0xa00003f8,0xa00003f9,0xa00003fc,0xa0000400,0xa0000044,0xa0000048,0xa0000049,0xa000004c,0xa0000050,0xffffffff};
  for(int owner=0;owner<2;owner++)for(int wr=0;wr<=owner;wr++)for(uint32_t addr:boundaries){Tx t=tx(owner,0,wr);t.addr=addr;t.strb=1;t.hold=7;b.run(t);}
  for(int edge=0;edge<2;edge++)for(int mask=0;mask<16;mask++){Tx t=tx(1,0,true);t.addr+=edge?12284:0;t.strb=mask;t.data=0xfedcba98^mask;b.run(t);t.write=false;b.run(t);}
  for(int order=-1;order<=1;order++)for(int delay:{0,1,7,64,129})for(int port=0;port<5;port++){
   Tx t=tx(1,0,port!=0&&port!=3);t.order=order;t.gap=delay;t.hold=delay;t.delay[port]=delay;
   b.block=port;b.block_left=delay;b.run(t);b.check(b.block_left==0,"requested channel stall never applied");b.count("channel_delay/"+std::to_string(port)+"/"+std::to_string(delay));}
  // Prove downstream AW/W order independently of upstream publication order.
  for(int order=-1;order<=1;order++){Tx t=tx(1,1,true);t.delay[order<0?2:1]=order?64:0;b.run(t);}
  // Repeated contention: after each winner the waiting peer must be next.
  long before=b.completed;for(int i=0;i<40;i++){b.push(tx(0,0));b.push(tx(1,i%4,i%2));}b.drain();b.check(b.completed-before==80,"contention drain");
  // Reset at observation-defined phases; completed effects remain in byte oracle.
  for(int route=0;route<4;route++)for(int phase=0;phase<12;phase++){
   b.reset();Tx t=tx(1,route,phase!=0&&phase!=1&&phase!=6&&phase!=9&&phase!=10);t.hold=64;t.gap=64;t.data=~b.word(0);
   if(phase==2)t.order=-1;if(phase==3)t.order=1;b.push(t);
   b.until([&]{if(phase==0)return bool(b.d.lsu_axi_arready);if(!b.active)return false;auto&a=*b.active;
    if(phase==1)return a.ar>=0&&a.dr<0;if(phase==2)return a.aw>=0&&a.w<0;if(phase==3)return a.w>=0&&a.aw<0;
    if(phase==4)return a.aw>=0&&a.w>=0&&a.da<0;if(phase==5)return a.da>=0&&a.dw>=0&&!a.effect;
    if(phase==6||phase==7)return a.visible>=0;if(phase==8)return a.effect&&a.visible<0;
    if(phase==9)return a.dr>=0&&a.visible<0;return a.responded&&a.visible<0;});
   b.reset();b.count("reset/"+std::to_string(route)+"/"+std::to_string(phase));b.run(tx(0,0));}
  // IFU owner reset phases, including device-sampled and buffered R.
  for(int route=0;route<4;route++)for(int phase:{0,1,6,9,10}){
   b.reset();Tx t=tx(0,route);t.hold=64;b.push(t);
   b.until([&]{if(phase==0)return bool(b.d.ifu_axi_arready);if(!b.active)return false;auto&a=*b.active;
    if(phase==1)return a.ar>=0&&a.dr<0;if(phase==6)return a.visible>=0;
    if(phase==9)return a.dr>=0&&a.visible<0;return a.responded&&a.visible<0;});
   b.reset();b.count("reset_ifu/"+std::to_string(route)+"/"+std::to_string(phase));b.run(tx(0,0));
  }
  b.mtime()=0xfffffff0ull;b.timer=0xfffffff0ull;b.d.eval();int retries=0;
  for(int i=0;i<8;i++){Tx h=tx(1,2);h.addr+=4;Tx hi=b.run(h),lo=b.run(tx(1,2)),again=b.run(h);if(hi.expected!=again.expected){retries++;continue;}b.check(((uint64_t(hi.expected)<<32)|lo.expected)==lo.sampled,"torn timer");break;}
  b.check(retries>0,"rollover retry missing");b.count("rollover/retry");
  // 10 fixed seeds, at least 1000 completed descriptors each. Reset interrupts extras.
  for(unsigned seed=1;seed<=10;seed++){b.rng.seed(seed);b.random_gate=true;long start=b.completed;
   for(int batch=0;batch<10;batch++){
    for(int i=0;i<100;i++){int o=b.rng()%2,r=b.rng()%4;Tx t=tx(o,r,o&&b.rng()%2);t.order=int(b.rng()%3)-1;t.gap=b.rng()%8;t.hold=b.rng()%8;t.strb=b.rng()%16;t.data=b.rng();if(r==0)t.addr+=4*(b.rng()%3072);if(r==2)t.addr+=4*(b.rng()%2);for(auto&x:t.delay)x=b.rng()%8;b.push(t);}
    b.drain();Tx t=tx(1,b.rng()%4,true);t.hold=64;b.push(t);for(int i=0,n=3+b.rng()%25;i<n;i++)b.step();b.reset();
   }
   b.check(b.completed-start>=1000,"random completed count");b.bins["seed/"+std::to_string(seed)]=b.completed-start;
  }
  for(int owner=0;owner<2;owner++)for(int wr=0;wr<=owner;wr++)for(int route=0;route<4;route++){
   Tx t=tx(owner,route,wr);b.check(b.bins["cross/"+std::to_string(owner)+"/"+std::to_string(wr)+"/"+std::to_string(route)+"/"+std::to_string(b.response(t))]>0,"missing route cross");}
  for(int o=-1;o<=1;o++){b.check(b.bins["order/up/"+std::to_string(o)]>0,"up order hole");b.check(b.bins["order/down/"+std::to_string(o)]>0,"down order hole");}
  for(int edge=0;edge<2;edge++)for(int mask=0;mask<16;mask++)b.check(b.bins["mask/"+std::to_string(edge)+"/"+std::to_string(mask)]>0,"mask hole");
  std::ofstream f(argc>1?argv[1]:"coverage.csv");f<<"coverage_id,bin,hits\n";for(auto&kv:b.bins){const auto&k=kv.first;std::string id=k.find("mask/")==0?"C07":(k.find("reset/")==0||k.find("reset_ifu/")==0)?"C08":(k.find("rollover/")==0||k.find("clint/")==0)?"C10":k.find("uart/")==0?"C09":k.find("cross/")==0?"C05+C06":k.find("rr/")==0?"C02":k.find("order/")==0||k.find("publish/")==0||k.find("gap/")==0?"C03":k.find("seed/")==0?"C01-C10":k.find("transition/")==0||k.find("owner/")==0?"C04":"C01";f<<id<<","<<k<<","<<kv.second<<"\n";}
  std::cout<<"Fabric PASS accepted="<<b.accepted<<" completed="<<b.completed<<" aborted="<<b.aborted<<" effects="<<b.effects<<" uart="<<b.uart<<" cycles="<<b.cycle<<" bins="<<b.bins.size()<<"\n";
 }catch(const std::exception&e){std::cerr<<"FAIL "<<e.what()<<"\n";return 1;}
}
