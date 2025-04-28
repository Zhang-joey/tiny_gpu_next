module SIMT_stack #(
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter THREADS_PER_BLOCK = 4
) (
    input wire clk,
    input wire reset,
    input wire [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    input wire decoded_sync,
    input wire decoded_ssy,
    input wire [2:0] decoded_nzp,
    input wire [PROGRAM_MEM_ADDR_BITS-1:0] decoded_immediate,
    input wire [3:0] core_state,
    input wire [2:0] nzp [THREADS_PER_BLOCK-1:0],
    input wire enable,
    input wire [THREADS_PER_BLOCK-1:0] current_mask,
    input wire [THREADS_PER_BLOCK-1:0] origin_mask,

    output reg [THREADS_PER_BLOCK-1:0] thread_mask,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] branch_pc,
    output reg [1:0] remain_route
);  
    
    //[modify] add thread mask 
    always @(posedge clk) begin
        if (reset) begin
            thread_mask <= {THREADS_PER_BLOCK{1'b1}};
        end
        else if (core_state == 4'b0110 && enable) begin //state == execute
            if (decoded_ssy) begin //state == execute and inst == SSYN
                thread_mask <= current_mask;
            end
            else if (decoded_sync) begin //state == execute and inst == SYNC
                if (remain_route == 2) begin
                    thread_mask <= (~thread_mask) & origin_mask;
                end
                else begin
                    thread_mask <= origin_mask;
                end
            end
        end
    end

    //[modify] add remain_route
    always @(posedge clk) begin
        if (reset) begin
            remain_route <= 0;
        end
        else if (core_state == 4'b0110 && enable) begin //state == execute
            if (decoded_ssy) begin //state == execute and inst == SSY
                if (current_mask == 0) begin
                    remain_route <= 1;
                end
                else begin
                    remain_route <= 2;
                end
            end
            else if (decoded_sync) begin //state == execute and inst == SYNC
                remain_route <= remain_route - 1;
            end
        end
    end

    //[modify] add branch_pc
    always @(posedge clk) begin
        if (reset) begin
            branch_pc <= 0;
        end
        else if (core_state == 4'b0110 && enable) begin //state == execute
            if (decoded_ssy) begin //state == execute and inst == SSY
                branch_pc <= decoded_immediate;
            end
        end
    end
endmodule