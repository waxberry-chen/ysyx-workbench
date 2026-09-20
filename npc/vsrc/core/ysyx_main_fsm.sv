`default_nettype none

module ysyx_main_fsm (
    input clk, 
    input rst_n,
    
    output reg          if_req_valid,
    input               if_req_ready,

    input               if_rsp_valid,
    output reg          if_rsp_ready, 

    input               lsu_access,
    output reg          lsu_op_valid,
    input               lsu_op_ready,
    input               lsu_rsp_valid,
    output reg          lsu_rsp_ready,

    output reg      commit_wb
);

localparam  IF_REQ   = 2'd0,
            IF_WAIT  = 2'd1,
            EXEC     = 2'd2,
            LSU_WAIT = 2'd3;

wire    [1:0] state;
reg     [1:0] next_state;


// current state register
ysyx_gnrl_dffr #(.DW(2)) ysyx_state_register (
    .dnxt   (next_state), 
    .qout   (state), 
    .clk    (clk), 
    .rst_n  (rst_n)
);

// next state & output logic
always @(*) begin
    next_state   = state;
    if_req_valid = 0;
    if_rsp_ready = 0;
    lsu_op_valid = 0;
    lsu_rsp_ready = 0;
    commit_wb    = 0;
    if (!rst_n) begin
        next_state = IF_REQ;
    end else begin
        case (state)
            IF_REQ: begin
                if_req_valid = 1;
                if (if_req_ready) begin
                    next_state = IF_WAIT;
                end
            end
            IF_WAIT: begin
                if_rsp_ready = 1;
                if (if_rsp_valid) begin
                    next_state = EXEC;
                end
            end
            EXEC: begin
                if (lsu_access) begin
                    lsu_op_valid = 1;
                    if (lsu_op_ready) begin
                        next_state = LSU_WAIT;
                    end
                end else begin
                    commit_wb = 1;
                    next_state = IF_REQ;
                end
            end
            LSU_WAIT: begin
                lsu_rsp_ready = 1;
                if (lsu_rsp_valid) begin
                    commit_wb = 1;
                    next_state = IF_REQ;
                end
            end
            default: next_state = IF_REQ;
        endcase
    end
end

property p_memory_commit_requires_lsu_response;
    @(posedge clk) disable iff (!rst_n)
        commit_wb && lsu_access |-> lsu_rsp_valid;
endproperty
assert property (p_memory_commit_requires_lsu_response);

endmodule

`default_nettype wire
