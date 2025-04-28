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
    input wire [2:0] core_state,
    
    output reg [THREADS_PER_BLOCK-1:0] thread_mask,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] branch_pc,
    output reg [1:0] remain_route
);
        //[modify] add thread mask 
    always @(posedge clk) begin
        if (reset) begin
            thread_mask <= {THREADS_PER_BLOCK{1'b1}};
        end
        else if (core_state == 3'b101) begin //state == execute
            if (decoded_ssy) begin //state == execute and inst == SSYN
                for (int i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin
                    if ((nzp[i] & decoded_nzp) != 3'b0) begin
                        thread_mask[i] <= 1'b1; 
                    end
                    else begin
                        thread_mask[i] <= 1'b0;
                    end
                end
            end
            else if (decoded_sync) begin //state == execute and inst == SYNC
                if (remain_route == 2) begin
                    thread_mask <= ~thread_mask;
                end
                else begin
                    thread_mask <= {THREADS_PER_BLOCK{1'b1}};
                end
            end
        end
    end

    //[modify] add remain_route
    always @(posedge clk) begin
        if (reset) begin
            remain_route <= 0;
        end
        else if (core_state == 3'b101) begin //state == execute
            if (decoded_ssy) begin //state == execute and inst == SSY
                remain_route <= 2;
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
        else if (core_state == 3'b101) begin //state == execute
            if (decoded_ssy) begin //state == execute and inst == SSY
                branch_pc <= decoded_immediate;
            end
            else if (decoded_sync) begin //state == execute and inst == SYNC
                branch_pc <= current_pc + 1;
            end
        end
    end