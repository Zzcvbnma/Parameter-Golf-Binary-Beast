`timescale 1ns/1ps
// v4 coherence home agent (conceptual RTL reference)
// Small directory-based MESI-like controller for REQUESTERS agents.
// States are I/S/M. CPU/GPU agents are expected to snoop invalidations.
module coherence_manager_v4 #(
    parameter int REQUESTERS = 4,
    parameter int LINES = 256,
    parameter int LINE_ADDR_WIDTH = 16,
    parameter int REQ_ID_WIDTH = (REQUESTERS <= 1) ? 1 : $clog2(REQUESTERS)
)(
    input  logic clk,
    input logic rst_n,
    input logic req_valid,
    output logic req_ready,
    input logic req_write,
    input logic [REQ_ID_WIDTH-1:0] req_src,
    input logic [LINE_ADDR_WIDTH-1:0] req_line,
    output logic rsp_valid,
    input logic rsp_ready,
    output logic rsp_hit,
    output logic rsp_need_memory,
    output logic rsp_need_snoop,
    output logic [REQ_ID_WIDTH-1:0] rsp_owner,
    output logic snoop_valid,
    output logic [REQUESTERS-1:0] snoop_invalidate,
    output logic [REQ_ID_WIDTH-1:0] snoop_source,
    input logic [REQUESTERS-1:0] snoop_done,
    input logic [REQUESTERS-1:0] snoop_dirty,
    output logic mem_rd_valid,
    output logic mem_wr_valid,
    input logic mem_ready,
    input logic mem_wr_complete,
    input logic [LINE_ADDR_WIDTH-1:0] mem_line,
    input logic [63:0] mem_wdata,
    output logic [LINE_ADDR_WIDTH-1:0] mem_req_line,
    output logic [63:0] mem_req_wdata
);
    typedef enum logic [1:0] {ST_I, ST_S, ST_M} state_t;
    state_t state [0:LINES-1];
    logic [REQ_ID_WIDTH-1:0] owner [0:LINES-1];
    logic [REQUESTERS-1:0] sharers [0:LINES-1];
    logic busy;
    logic busy_write;
    logic [REQ_ID_WIDTH-1:0] busy_src;
    logic [LINE_ADDR_WIDTH-1:0] busy_line;
    logic [REQUESTERS-1:0] pending_inv;
    logic pending_mem;
    logic pending_dirty;
    integer idx;
    assign req_ready = !busy && (!rsp_valid || rsp_ready);
    always_comb begin
        rsp_valid = 1'b0;
        rsp_hit = 1'b0;
        rsp_need_memory = 1'b0;
        rsp_need_snoop = 1'b0;
        rsp_owner = '0;
        snoop_valid = busy && (pending_inv != '0);
        snoop_invalidate = pending_inv;
        snoop_source = busy_src;
        mem_rd_valid = busy && pending_mem && !busy_write;
        mem_wr_valid = busy && pending_mem && busy_write;
        mem_req_line = busy_line;
        mem_req_wdata = 64'h0;
        if (busy && pending_inv == '0 && !pending_mem) begin
            rsp_valid = 1'b1;
            rsp_hit = (state[busy_line % LINES] != ST_I);
            rsp_need_memory = 1'b0;
            rsp_need_snoop = pending_dirty;
            rsp_owner = owner[busy_line % LINES];
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0; busy_write <= 1'b0; busy_src <= '0; busy_line <= '0;
            pending_inv <= '0; pending_mem <= 1'b0; pending_dirty <= 1'b0;
            for (idx=0; idx<LINES; idx=idx+1) begin
                state[idx] <= ST_I; owner[idx] <= '0; sharers[idx] <= '0;
            end
        end else begin
            if (req_valid && req_ready) begin
                busy <= 1'b1; busy_write <= req_write; busy_src <= req_src; busy_line <= req_line;
                pending_inv <= '0; pending_mem <= 1'b0; pending_dirty <= 1'b0;
                if (req_line % LINES < LINES) begin
                    if (!req_write) begin
                        if (state[req_line % LINES] == ST_I) begin
                            pending_mem <= 1'b1;
                            pending_dirty <= 1'b0;
                        end else if (state[req_line % LINES] == ST_M && owner[req_line % LINES] != req_src) begin
                            pending_inv <= sharers[req_line % LINES];
                            pending_inv[req_src] <= 1'b0;
                            pending_dirty <= 1'b1;
                        end
                    end else begin
                        if (state[req_line % LINES] == ST_I) begin
                            pending_mem <= 1'b1;
                        end else begin
                            pending_inv <= sharers[req_line % LINES];
                            pending_inv[req_src] <= 1'b0;
                            if (state[req_line % LINES] == ST_M && owner[req_line % LINES] == req_src)
                                pending_inv <= '0;
                            pending_dirty <= (state[req_line % LINES] == ST_M && owner[req_line % LINES] != req_src);
                        end
                    end
                end
            end
            if (busy && pending_inv != '0) begin
                pending_inv <= pending_inv & ~snoop_done;
                if ((pending_inv & ~snoop_done) == '0) begin
                    pending_mem <= pending_dirty;
                    pending_dirty <= 1'b0;
                end
            end
            if (busy && pending_mem && mem_ready) pending_mem <= 1'b0;
            if (busy && rsp_valid && rsp_ready) begin
                if (busy_write) begin
                    state[busy_line % LINES] <= ST_M;
                    owner[busy_line % LINES] <= busy_src;
                    sharers[busy_line % LINES] <= '0;
                    sharers[busy_line % LINES][busy_src] <= 1'b1;
                end else begin
                    if (state[busy_line % LINES] == ST_I || state[busy_line % LINES] == ST_M)
                        state[busy_line % LINES] <= ST_S;
                    sharers[busy_line % LINES][busy_src] <= 1'b1;
                end
                busy <= 1'b0;
            end
        end
    end
endmodule
