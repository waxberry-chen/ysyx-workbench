#include "ram_model.h"

#include <assert.h>
#include <inttypes.h>
#include <random>

#include "dut.h"
#include "common.h"
#include "paddr.h"

extern NpcDut *dut;

#ifdef CONFIG_RAM
namespace {

constexpr uint8_t kAxiOkay = 0;
constexpr uint8_t kAxiSlverr = 2;

class AxiTiming {
 public:
  void init(uint32_t seed, uint32_t max_latency, uint32_t ready_percent) {
    assert(ready_percent >= 1 && ready_percent <= 100);
    max_latency_ = max_latency;
    ready_percent_ = ready_percent;
    rng_.seed(seed);
  }

  bool ready_now() { return (rng_() % 100u) < ready_percent_; }

  uint32_t response_latency() {
    const uint64_t range = static_cast<uint64_t>(max_latency_) + 1;
    return static_cast<uint32_t>(static_cast<uint64_t>(rng_()) % range);
  }

 private:
  uint32_t max_latency_ = 3;
  uint32_t ready_percent_ = 75;
  std::mt19937 rng_;
};

class InstructionAxiSlave {
 public:
  void init(uint32_t seed, uint32_t max_latency, uint32_t ready_percent) {
    timing_.init(seed, max_latency, ready_percent);
    reset();
    printf("I-AXI slave: seed=%u, max_latency=%u, ARREADY=%u%%\n",
           seed, max_latency, ready_percent);
  }

  void drive() {
    if (!dut->rst_n) {
      dut->ifu_axi_arready = 0;
      dut->ifu_axi_rvalid = 0;
      dut->ifu_axi_rdata = 0;
      dut->ifu_axi_rresp = kAxiOkay;
      return;
    }

    dut->ifu_axi_arready = state_ == IDLE && timing_.ready_now();
    dut->ifu_axi_rvalid = state_ == RESP;
    dut->ifu_axi_rdata = response_data_;
    dut->ifu_axi_rresp = response_resp_;
  }

  void sample() {
    ar_fire_ = dut->ifu_axi_arvalid && dut->ifu_axi_arready;
    r_fire_ = dut->ifu_axi_rvalid && dut->ifu_axi_rready;
    ar_stalled_ = dut->ifu_axi_arvalid && !dut->ifu_axi_arready;
    r_stalled_ = dut->ifu_axi_rvalid && !dut->ifu_axi_rready;
    sampled_araddr_ = dut->ifu_axi_araddr;
    sample_valid_ = true;
  }

  void tick() {
    assert(sample_valid_);
    sample_valid_ = false;

    if (!dut->rst_n) {
      reset();
      return;
    }

    ar_stall_cycles_ += ar_stalled_;
    r_stall_cycles_ += r_stalled_;

    switch (state_) {
      case IDLE:
        assert(!r_fire_);
        if (ar_fire_) {
          request_addr_ = sampled_araddr_;
          latency_left_ = timing_.response_latency();
          request_count_++;
          if (latency_left_ == 0) {
            prepare_response();
            state_ = RESP;
          } else {
            state_ = WAIT;
          }
        }
        break;

      case WAIT:
        assert(!ar_fire_ && !r_fire_ && latency_left_ > 0);
        latency_left_--;
        if (latency_left_ == 0) {
          prepare_response();
          state_ = RESP;
        }
        break;

      case RESP:
        assert(!ar_fire_);
        if (r_fire_) {
          response_count_++;
          state_ = IDLE;
        }
        break;
    }
  }

  void report() const {
    Log("I-RAM transactions: requests = %" PRIu64
        ", responses = %" PRIu64 ", errors = %" PRIu64
        ", AR stall cycles = %" PRIu64 ", R stall cycles = %" PRIu64,
        request_count_, response_count_, error_count_, ar_stall_cycles_,
        r_stall_cycles_);
  }

 private:
  enum State { IDLE, WAIT, RESP };

  void reset() {
    state_ = IDLE;
    request_addr_ = 0;
    response_data_ = 0;
    response_resp_ = kAxiOkay;
    latency_left_ = 0;
    request_count_ = 0;
    response_count_ = 0;
    error_count_ = 0;
    ar_stall_cycles_ = 0;
    r_stall_cycles_ = 0;
    sample_valid_ = false;
  }

  void prepare_response() {
    const bool error = !in_pmem_range(request_addr_, 4);
    response_resp_ = error ? kAxiSlverr : kAxiOkay;
    if (error) {
      response_data_ = 0;
      error_count_++;
      Log("I-RAM access error: addr = " FMT_PADDR ", size = 4",
          request_addr_);
    } else {
      response_data_ = host_read(guest_to_host(request_addr_), 4);
    }
  }

  AxiTiming timing_;
  State state_ = IDLE;
  paddr_t request_addr_ = 0;
  word_t response_data_ = 0;
  uint8_t response_resp_ = kAxiOkay;
  uint32_t latency_left_ = 0;
  uint64_t request_count_ = 0;
  uint64_t response_count_ = 0;
  uint64_t error_count_ = 0;
  uint64_t ar_stall_cycles_ = 0;
  uint64_t r_stall_cycles_ = 0;

  bool ar_fire_ = false;
  bool r_fire_ = false;
  bool ar_stalled_ = false;
  bool r_stalled_ = false;
  paddr_t sampled_araddr_ = 0;
  bool sample_valid_ = false;
};

class DataAxiSlave {
 public:
  void init(uint32_t seed, uint32_t max_latency, uint32_t ready_percent) {
    timing_.init(seed, max_latency, ready_percent);
    reset();
    printf("D-AXI slave: seed=%u, max_latency=%u, channel_ready=%u%%\n",
           seed, max_latency, ready_percent);
  }

  void drive() {
    if (!dut->rst_n) {
      dut->lsu_axi_arready = 0;
      dut->lsu_axi_rvalid = 0;
      dut->lsu_axi_rdata = 0;
      dut->lsu_axi_rresp = kAxiOkay;
      dut->lsu_axi_awready = 0;
      dut->lsu_axi_wready = 0;
      dut->lsu_axi_bvalid = 0;
      dut->lsu_axi_bresp = kAxiOkay;
      return;
    }

    // AR, AW and W use independent random decisions.  AW and W can therefore
    // complete in either order, including in the same cycle.
    dut->lsu_axi_arready = read_state_ == READ_IDLE && timing_.ready_now();
    dut->lsu_axi_rvalid = read_state_ == READ_RESP;
    dut->lsu_axi_rdata = read_data_;
    dut->lsu_axi_rresp = read_resp_;

    dut->lsu_axi_awready = write_state_ == WRITE_COLLECT && !aw_captured_ &&
                           timing_.ready_now();
    dut->lsu_axi_wready = write_state_ == WRITE_COLLECT && !w_captured_ &&
                          timing_.ready_now();
    dut->lsu_axi_bvalid = write_state_ == WRITE_RESP;
    dut->lsu_axi_bresp = write_resp_;
  }

  void sample() {
    ar_fire_ = dut->lsu_axi_arvalid && dut->lsu_axi_arready;
    r_fire_ = dut->lsu_axi_rvalid && dut->lsu_axi_rready;
    aw_fire_ = dut->lsu_axi_awvalid && dut->lsu_axi_awready;
    w_fire_ = dut->lsu_axi_wvalid && dut->lsu_axi_wready;
    b_fire_ = dut->lsu_axi_bvalid && dut->lsu_axi_bready;

    ar_stalled_ = dut->lsu_axi_arvalid && !dut->lsu_axi_arready;
    r_stalled_ = dut->lsu_axi_rvalid && !dut->lsu_axi_rready;
    aw_stalled_ = dut->lsu_axi_awvalid && !dut->lsu_axi_awready;
    w_stalled_ = dut->lsu_axi_wvalid && !dut->lsu_axi_wready;
    b_stalled_ = dut->lsu_axi_bvalid && !dut->lsu_axi_bready;

    sampled_araddr_ = dut->lsu_axi_araddr;
    sampled_awaddr_ = dut->lsu_axi_awaddr;
    sampled_wdata_ = dut->lsu_axi_wdata;
    sampled_wstrb_ = dut->lsu_axi_wstrb;
    sample_valid_ = true;
  }

  void tick() {
    assert(sample_valid_);
    sample_valid_ = false;

    if (!dut->rst_n) {
      reset();
      return;
    }

    ar_stall_cycles_ += ar_stalled_;
    r_stall_cycles_ += r_stalled_;
    aw_stall_cycles_ += aw_stalled_;
    w_stall_cycles_ += w_stalled_;
    b_stall_cycles_ += b_stalled_;

    tick_read();
    tick_write();
  }

  void report() const {
    Log("D-RAM transactions: requests = %" PRIu64
        " (loads = %" PRIu64 ", stores = %" PRIu64 ")"
        ", responses = %" PRIu64 ", errors = %" PRIu64,
        read_request_count_ + write_request_count_, read_request_count_,
        write_request_count_, read_response_count_ + write_response_count_,
        error_count_);
    Log("D-AXI channel stalls: AR = %" PRIu64 ", R = %" PRIu64
        ", AW = %" PRIu64 ", W = %" PRIu64 ", B = %" PRIu64,
        ar_stall_cycles_, r_stall_cycles_, aw_stall_cycles_, w_stall_cycles_,
        b_stall_cycles_);
  }

 private:
  enum ReadState { READ_IDLE, READ_WAIT, READ_RESP };
  enum WriteState { WRITE_COLLECT, WRITE_WAIT, WRITE_RESP };

  void reset() {
    read_state_ = READ_IDLE;
    write_state_ = WRITE_COLLECT;
    read_addr_ = 0;
    read_data_ = 0;
    read_resp_ = kAxiOkay;
    read_latency_left_ = 0;
    aw_captured_ = false;
    w_captured_ = false;
    write_addr_ = 0;
    write_data_ = 0;
    write_strobe_ = 0;
    write_resp_ = kAxiOkay;
    write_latency_left_ = 0;
    read_request_count_ = 0;
    read_response_count_ = 0;
    write_request_count_ = 0;
    write_response_count_ = 0;
    error_count_ = 0;
    ar_stall_cycles_ = 0;
    r_stall_cycles_ = 0;
    aw_stall_cycles_ = 0;
    w_stall_cycles_ = 0;
    b_stall_cycles_ = 0;
    sample_valid_ = false;
  }

  void tick_read() {
    switch (read_state_) {
      case READ_IDLE:
        assert(!r_fire_);
        if (ar_fire_) {
          read_addr_ = sampled_araddr_;
          read_latency_left_ = timing_.response_latency();
          read_request_count_++;
          if (read_latency_left_ == 0) {
            prepare_read_response();
            read_state_ = READ_RESP;
          } else {
            read_state_ = READ_WAIT;
          }
        }
        break;

      case READ_WAIT:
        assert(!ar_fire_ && !r_fire_ && read_latency_left_ > 0);
        read_latency_left_--;
        if (read_latency_left_ == 0) {
          prepare_read_response();
          read_state_ = READ_RESP;
        }
        break;

      case READ_RESP:
        assert(!ar_fire_);
        if (r_fire_) {
          read_response_count_++;
          read_state_ = READ_IDLE;
        }
        break;
    }
  }

  void tick_write() {
    switch (write_state_) {
      case WRITE_COLLECT: {
        assert(!b_fire_);
        if (aw_fire_) {
          assert(!aw_captured_);
          write_addr_ = sampled_awaddr_;
          aw_captured_ = true;
        }
        if (w_fire_) {
          assert(!w_captured_);
          write_data_ = sampled_wdata_;
          write_strobe_ = sampled_wstrb_;
          w_captured_ = true;
        }

        if ((aw_captured_ || aw_fire_) && (w_captured_ || w_fire_)) {
          write_request_count_++;
          write_latency_left_ = timing_.response_latency();
          if (write_latency_left_ == 0) {
            prepare_write_response();
            write_state_ = WRITE_RESP;
          } else {
            write_state_ = WRITE_WAIT;
          }
        }
        break;
      }

      case WRITE_WAIT:
        assert(!aw_fire_ && !w_fire_ && !b_fire_ &&
               write_latency_left_ > 0);
        write_latency_left_--;
        if (write_latency_left_ == 0) {
          prepare_write_response();
          write_state_ = WRITE_RESP;
        }
        break;

      case WRITE_RESP:
        assert(!aw_fire_ && !w_fire_);
        if (b_fire_) {
          write_response_count_++;
          aw_captured_ = false;
          w_captured_ = false;
          write_state_ = WRITE_COLLECT;
        }
        break;
    }
  }

  void prepare_read_response() {
    word_t data = 0;
    const bool okay = paddr_try_read(read_addr_, 4, &data);
    read_data_ = okay ? data : 0;
    read_resp_ = okay ? kAxiOkay : kAxiSlverr;
    if (!okay) {
      error_count_++;
      Log("D-RAM load access error: addr = " FMT_PADDR ", bus size = 4",
          read_addr_);
    }
  }

  static bool decode_write_strobe(uint8_t strobe, uint32_t *offset,
                                  uint32_t *size) {
    switch (strobe) {
      case 0x1: *offset = 0; *size = 1; return true;
      case 0x2: *offset = 1; *size = 1; return true;
      case 0x4: *offset = 2; *size = 1; return true;
      case 0x8: *offset = 3; *size = 1; return true;
      case 0x3: *offset = 0; *size = 2; return true;
      case 0xc: *offset = 2; *size = 2; return true;
      case 0xf: *offset = 0; *size = 4; return true;
      default: return false;
    }
  }

  void prepare_write_response() {
    uint32_t offset = 0;
    uint32_t size = 0;
    const bool lane_valid = decode_write_strobe(write_strobe_, &offset, &size);
    const paddr_t effective_addr = write_addr_ + offset;
    const word_t effective_data = write_data_ >> (offset * 8);
    const bool okay = lane_valid && (write_addr_ & 3u) == 0 &&
                      paddr_try_write(effective_addr, size, effective_data);
    write_resp_ = okay ? kAxiOkay : kAxiSlverr;
    if (!okay) {
      error_count_++;
      Log("D-RAM store access error: addr = " FMT_PADDR
          ", WSTRB = 0x%x", write_addr_, write_strobe_);
    }
  }

  AxiTiming timing_;
  ReadState read_state_ = READ_IDLE;
  WriteState write_state_ = WRITE_COLLECT;

  paddr_t read_addr_ = 0;
  word_t read_data_ = 0;
  uint8_t read_resp_ = kAxiOkay;
  uint32_t read_latency_left_ = 0;

  bool aw_captured_ = false;
  bool w_captured_ = false;
  paddr_t write_addr_ = 0;
  word_t write_data_ = 0;
  uint8_t write_strobe_ = 0;
  uint8_t write_resp_ = kAxiOkay;
  uint32_t write_latency_left_ = 0;

  uint64_t read_request_count_ = 0;
  uint64_t read_response_count_ = 0;
  uint64_t write_request_count_ = 0;
  uint64_t write_response_count_ = 0;
  uint64_t error_count_ = 0;
  uint64_t ar_stall_cycles_ = 0;
  uint64_t r_stall_cycles_ = 0;
  uint64_t aw_stall_cycles_ = 0;
  uint64_t w_stall_cycles_ = 0;
  uint64_t b_stall_cycles_ = 0;

  bool ar_fire_ = false;
  bool r_fire_ = false;
  bool aw_fire_ = false;
  bool w_fire_ = false;
  bool b_fire_ = false;
  bool ar_stalled_ = false;
  bool r_stalled_ = false;
  bool aw_stalled_ = false;
  bool w_stalled_ = false;
  bool b_stalled_ = false;
  paddr_t sampled_araddr_ = 0;
  paddr_t sampled_awaddr_ = 0;
  word_t sampled_wdata_ = 0;
  uint8_t sampled_wstrb_ = 0;
  bool sample_valid_ = false;
};

InstructionAxiSlave instruction_axi_slave;
DataAxiSlave data_axi_slave;

}  // namespace
#endif

void init_ram_model(uint32_t seed, uint32_t max_latency,
                    uint32_t ready_percent) {
#ifdef CONFIG_RAM
  instruction_axi_slave.init(seed, max_latency, ready_percent);
  data_axi_slave.init(seed ^ UINT32_C(0x9e3779b9), max_latency,
                      ready_percent);
#else
  (void)seed;
  (void)max_latency;
  (void)ready_percent;
#endif
}

void ram_model_drive() {
#ifdef CONFIG_RAM
  instruction_axi_slave.drive();
  data_axi_slave.drive();
#endif
}

void ram_model_sample() {
#ifdef CONFIG_RAM
  instruction_axi_slave.sample();
  data_axi_slave.sample();
#endif
}

void ram_model_tick() {
#ifdef CONFIG_RAM
  instruction_axi_slave.tick();
  data_axi_slave.tick();
#endif
}

void ram_model_report() {
#ifdef CONFIG_RAM
  instruction_axi_slave.report();
  data_axi_slave.report();
#endif
}
