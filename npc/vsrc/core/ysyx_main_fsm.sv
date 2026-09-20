`default_nettype none

module ysyx_main_fsm (
    input clk, 
    input rst_n,
    
    output reg          if_req_valid,
    input               if_req_ready,

    input               if_rsp_valid,
    output reg          if_rsp_ready, 

    input               d_access,
    output reg          d_req_valid,
    input               d_req_ready,
    input               d_rsp_valid,
    output reg          d_rsp_ready,

    output reg      commit_wb
);

localparam  IF_REQ   = 3'd0,
            IF_WAIT  = 3'd1,
            EXEC     = 3'd2,
            D_REQ    = 3'd3,
            D_WAIT   = 3'd4,
            D_COMMIT = 3'd5;

wire    [3-1:0] state;
reg     [3-1:0] next_state;


// current state register
ysyx_gnrl_dffr #(.DW(3)) ysyx_state_register (
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
    d_req_valid  = 0;
    d_rsp_ready  = 0;
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
                if (d_access) begin
                    next_state = D_REQ;
                end else begin
                    commit_wb = 1;
                    next_state = IF_REQ;
                end
            end
            D_REQ: begin
                d_req_valid = 1;
                if (d_req_ready) begin
                    next_state = D_WAIT;
                end
            end
            D_WAIT: begin
                d_rsp_ready = 1;
                if (d_rsp_valid) begin
                    next_state = D_COMMIT;
                end
            end
            D_COMMIT: begin
                commit_wb = 1;
                next_state = IF_REQ;
            end
            default: next_state = IF_REQ;
        endcase
    end
end


endmodule

`default_nettype wire
