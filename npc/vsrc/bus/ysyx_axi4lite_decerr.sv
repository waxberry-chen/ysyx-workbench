`default_nettype none

// Terminate any address with DECERR. No memory or device side effects.
module ysyx_axi4lite_decerr (
    input wire clk,
    input wire rst_n,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    input  wire [31:0]  s_axi_araddr,
    input  wire [2:0]   s_axi_arprot,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready,
    output wire [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_awaddr,
    input  wire [2:0]   s_axi_awprot,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,
    output wire [1:0]   s_axi_bresp
);

typedef enum logic [2:0] {IDLE, COLLECT_R, COLLECT_W, RESP_R, RESP_W} state_t;
state_t state_q;
reg prefer_write_q, aw_have_q, w_have_q;
wire write_pending = s_axi_awvalid || s_axi_wvalid;
wire choose_write = write_pending && (!s_axi_arvalid || prefer_write_q);
wire aw_fire = s_axi_awvalid && s_axi_awready;
wire w_fire = s_axi_wvalid && s_axi_wready;
// Payload has no meaning for an error sink; every request is rejected.
wire unused_payload = ^{s_axi_araddr,s_axi_arprot,s_axi_awaddr,s_axi_awprot,s_axi_wdata,s_axi_wstrb};
assign s_axi_arready = rst_n && state_q == COLLECT_R;
assign s_axi_awready = rst_n && state_q == COLLECT_W && !aw_have_q;
assign s_axi_wready = rst_n && state_q == COLLECT_W && !w_have_q;
assign s_axi_rvalid = rst_n && state_q == RESP_R;
assign s_axi_bvalid = rst_n && state_q == RESP_W;
assign s_axi_rdata = 32'b0;
assign s_axi_rresp = 2'b11;
assign s_axi_bresp = 2'b11;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q <= IDLE; prefer_write_q <= 0; aw_have_q <= 0; w_have_q <= 0;
    end else case (state_q)
        IDLE: if (s_axi_arvalid || write_pending)
            state_q <= choose_write ? COLLECT_W : COLLECT_R;
        COLLECT_R: if (s_axi_arvalid && s_axi_arready) state_q <= RESP_R;
        COLLECT_W: begin
            if (aw_fire) aw_have_q <= 1;
            if (w_fire) w_have_q <= 1;
            if ((aw_have_q || aw_fire) && (w_have_q || w_fire)) state_q <= RESP_W;
        end
        RESP_R: if (s_axi_rready) begin prefer_write_q <= 1; state_q <= IDLE; end
        RESP_W: if (s_axi_bready) begin
            prefer_write_q <= 0; aw_have_q <= 0; w_have_q <= 0; state_q <= IDLE;
        end
        default: state_q <= IDLE;
    endcase
end
`ifndef SYNTHESIS
a03_b_requires_both: assert property (@(posedge clk) disable iff (!rst_n)
    s_axi_bvalid |-> aw_have_q && w_have_q);
a04_one_type: assert property (@(posedge clk) disable iff (!rst_n)
    !(s_axi_arready && (s_axi_awready || s_axi_wready)) && !(s_axi_rvalid && s_axi_bvalid));
a01_r_holding: assert property (@(posedge clk) disable iff (!rst_n)
    s_axi_rvalid && !s_axi_rready |=> s_axi_rvalid && $stable({s_axi_rdata,s_axi_rresp}));
a01_b_holding: assert property (@(posedge clk) disable iff (!rst_n)
    s_axi_bvalid && !s_axi_bready |=> s_axi_bvalid && $stable(s_axi_bresp));
`endif
endmodule
`default_nettype wire
