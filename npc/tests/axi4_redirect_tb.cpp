#include "Vaxi4_redirect_test_top.h"
#include "verilated.h"
#include <fstream>
#include <iostream>
#include <stdexcept>
struct Bench {
 Vaxi4_redirect_test_top d;int cycles=0;bool allow_context=false;
 void check(bool ok,const char*s){if(!ok)throw std::runtime_error(s);}
 void step(){d.clk=0;d.eval();check(allow_context||!d.if_ctx_valid,"stale response entered IFQ");d.clk=1;d.eval();d.clk=0;d.eval();cycles++;check(cycles<4096,"watchdog");}
 template<class F>void until(F f){d.eval();while(!f())step();}
 void reset(bool write){d.rst_n=0;d.redirect_valid=0;d.redirect_target=0x80000100;
  d.m_axi_arready=d.m_axi_awready=d.m_axi_wready=0;d.m_axi_rvalid=d.m_axi_bvalid=0;
  d.m_axi_rdata=0x00100093;d.m_axi_rresp=d.m_axi_bresp=0;
  d.lsu_axi_arvalid=!write;d.lsu_axi_awvalid=d.lsu_axi_wvalid=write;
  d.lsu_axi_araddr=d.lsu_axi_awaddr=0x80004000;d.lsu_axi_arprot=d.lsu_axi_awprot=1;
  d.lsu_axi_wdata=0x1234;d.lsu_axi_wstrb=15;d.lsu_axi_rready=d.lsu_axi_bready=1;
  step();step();d.rst_n=1;d.eval();}
 void competitor(bool write){
  if(write){until([&]{return d.lsu_axi_awready&&d.lsu_axi_wready;});step();d.lsu_axi_awvalid=d.lsu_axi_wvalid=0;
   until([&]{return d.m_axi_awvalid&&d.m_axi_wvalid;});check(d.m_axi_awaddr==0x80004000,"LSU ownership");d.m_axi_awready=d.m_axi_wready=1;step();d.m_axi_awready=d.m_axi_wready=0;}
  else {until([&]{return d.lsu_axi_arready;});step();d.lsu_axi_arvalid=0;
   until([&]{return d.m_axi_arvalid;});check(d.m_axi_araddr==0x80004000,"LSU ownership");d.m_axi_arready=1;step();d.m_axi_arready=0;}
 }
 void reply(bool write,int resp){
  if(write){d.m_axi_bvalid=1;d.m_axi_bresp=resp;until([&]{return d.m_axi_bready;});step();d.m_axi_bvalid=0;}
  else{d.m_axi_rvalid=1;d.m_axi_rresp=resp;until([&]{return d.m_axi_rready;});step();d.m_axi_rvalid=0;}
  d.eval();
 }
 void redirect(){d.redirect_valid=1;step();d.redirect_valid=0;d.eval();}
 void ar(uint32_t addr){until([&]{return d.m_axi_arvalid;});check(d.m_axi_araddr==addr,"wrong fetch address after redirect");d.m_axi_arready=1;step();d.m_axi_arready=0;}
 void run(int phase,int resp,bool write){reset(write);competitor(write);
  until([&]{return d.tap_ifu_arvalid;});check(!d.tap_ifu_arready,"IFU should wait behind LSU");
  if(phase==0)redirect();
  reply(write,0);ar(0x80000000);
  if(phase==1)redirect();
  reply(false,resp);
  if(phase==2){until([&]{return d.tap_ifu_rvalid&&d.tap_ifu_rready;});redirect();}
  ar(0x80000100);d.m_axi_rdata=0x00000013;reply(false,0);allow_context=true;
  until([&]{return d.if_ctx_valid;});check(d.if_ctx_pc==0x80000100&&!d.if_ctx_error&&d.if_ctx_inst==0x00000013&&!d.if_ctx_pred_taken&&d.if_ctx_pred_npc==0x80000104,"new target lost or poisoned");
 }
};
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);try{
 std::ofstream f(argc>1?argv[1]:"redirect.csv");f<<"coverage_id,phase,rresp,competitor,hits\n";
 for(int phase=0;phase<3;phase++)for(int resp:{0,2,3})for(int write=0;write<2;write++){
  Bench b;b.run(phase,resp,write);f<<"C12,"<<phase<<","<<resp<<","<<write<<",1\n";
 }
 std::cout<<"Redirect + Arbiter PASS 18 phase/response/competitor bins\n";
 }catch(const std::exception&e){std::cerr<<"FAIL "<<e.what()<<"\n";return 1;}}
