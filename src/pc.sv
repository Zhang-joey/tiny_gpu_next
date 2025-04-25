`default_nettype none
`timescale 1ns/1ns

// PROGRAM COUNTER
// > Calculates the next PC for each thread to update to (but currently we assume all threads
//   update to the same PC and don't support branch divergence)
// > Currently, each thread in each core has it's own calculation for next PC
// > The NZP register value is set by the CMP instruction (based on >/=/< comparison) to 
//   initiate the BRnzp instruction for branching
module pc #(
    parameter DATA_MEM_DATA_BITS = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter THREADS_PER_BLOCK = 4
) (
    input wire clk,
    input wire reset,
    //[modify] delete enable 

    // State   
    input reg [2:0] core_state, 
    // Control Signals
    input reg [2:0] decoded_nzp,
    input reg [DATA_MEM_DATA_BITS-1:0] decoded_immediate,
    //[modify] delete decoded_nzp write enable
    input reg decoded_pc_mux, 
    //[modify] change nzp to input
    input reg [2:0] nzp [THREADS_PER_BLOCK-1:0],

    //[modify] delete aluout and nzp in pc module

    //[modify] add thread mask
    output reg [THREADS_PER_BLOCK-1:0] thread_mask,
    // Current & Next PCs
    //[modify] change current_pc to output
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] next_pc
);

    always @(posedge clk) begin
        if (reset) begin
            next_pc <= 0;
        end 
        else if (core_state == 3'b101) begin //state == execute
            if (decoded_pc_mux == 1) begin 
                if (((nzp[0] & decoded_nzp) != 3'b0)) begin 
                    // On BRnzp instruction, branch to immediate if NZP case matches previous CMP
                    next_pc <= decoded_immediate;
                end else begin 
                    // Otherwise, just update to PC + 1 (next line)
                    next_pc <= current_pc + 1;
                end
            end 
            else begin 
                // By default update to PC + 1 (next line)
                next_pc <= current_pc + 1;
            end    
        end
    end

    //[modify] add current_pc issue
    always @(posedge clk) begin
        if (reset) begin
            current_pc <= 0;
        end 
        else if (core_state == 3'b110) begin //state == update
            current_pc <= next_pc;
        end
    end
    
    //[modify] add thread mask issue
    always @(posedge clk) begin
        if (reset) begin
            thread_mask <= {THREADS_PER_BLOCK{1'b1}};
        end
    end
endmodule
