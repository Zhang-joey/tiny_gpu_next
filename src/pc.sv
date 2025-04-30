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
    parameter THREADS_PER_BLOCK = 4,
    //[modify] add branch nest layers
    parameter BRANCH_NEST_LAYERS = 4
) (
    input wire clk,
    input wire reset,
    //[modify] delete enable 

    // State   
    input reg [3:0] core_state, 
    // Control Signals
    input reg [2:0] decoded_nzp,
    input reg [DATA_MEM_DATA_BITS-1:0] decoded_immediate,
    //[modify] add decoded_ssy, decoded_sync
    input reg decoded_ssy,
    input reg decoded_sync,
    //[modify] delete decoded_nzp write enable
    input reg decoded_pc_mux, 
    //[modify] add decoded_jump
    input reg decoded_jump,
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
    //[modify] add remain_route
    wire [1:0]                          remain_route    [BRANCH_NEST_LAYERS-1:0];
    //[modify] add branch_pc
    wire [PROGRAM_MEM_ADDR_BITS-1:0]    branch_pc;
    wire [PROGRAM_MEM_ADDR_BITS-1:0]    stack_branch_pc [BRANCH_NEST_LAYERS-1:0];
    //[modify] add SIMT_stack_enable
    reg  [BRANCH_NEST_LAYERS-1:0]           SIMT_stack_enable;
    reg  [$clog2(BRANCH_NEST_LAYERS)-1:0]   SIMT_stack_deepest;
    wire [THREADS_PER_BLOCK-1:0]            stack_thread_mask [BRANCH_NEST_LAYERS-1:0];
    //[modify] add current_mask
    reg  [THREADS_PER_BLOCK-1:0]            current_mask;
    //[modify] add origin_mask
    reg  [THREADS_PER_BLOCK-1:0]            origin_mask;

    always @(posedge clk) begin
        if (reset) begin
            next_pc <= 0;
        end 
        else if (core_state == 4'b0110) begin //state == execute
            if (decoded_pc_mux == 1) begin 
                if (((nzp[0] & decoded_nzp) != 3'b0)) begin 
                    // On BRnzp instruction, branch to immediate if NZP case matches previous CMP
                    next_pc <= decoded_immediate;
                end else begin 
                    // Otherwise, just update to PC + 1 (next line)
                    next_pc <= current_pc + 1;
                end
            end 
            else if (decoded_jump == 1) begin
                next_pc <= decoded_immediate;
            end
            else if (decoded_ssy && current_mask == 0) begin
                next_pc <= decoded_immediate;
            end
            else if (decoded_sync && remain_route[SIMT_stack_deepest] == 2) begin
                next_pc <= branch_pc;
            end
            else begin 
                // By default update to PC + 1 (next line)
                next_pc <= current_pc + 1;
            end    
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            current_pc <= 0;
        end
        else if (core_state == 4'b0111) begin
            current_pc <= next_pc;
        end
    end
    
    //[modify] add SIMT_stack
    genvar i;
    generate
        for (i = 0; i < BRANCH_NEST_LAYERS; i = i + 1) begin : SIMT_stack_inst
            SIMT_stack #(
                .PROGRAM_MEM_ADDR_BITS  (PROGRAM_MEM_ADDR_BITS  ),
                .THREADS_PER_BLOCK      (THREADS_PER_BLOCK      )
            ) SIMT_stack_inst (
                .clk                    (clk                    ),
                .reset                  (reset                  ),
                .decoded_sync           (decoded_sync           ),
                .decoded_ssy            (decoded_ssy            ),
                .decoded_nzp            (decoded_nzp            ),
                .decoded_immediate      (decoded_immediate      ),
                .core_state             (core_state             ),
                .enable                 (SIMT_stack_enable[i]   ),
                .current_mask           (current_mask           ),
                .origin_mask            (origin_mask            ),
                .thread_mask            (stack_thread_mask[i]   ),
                .branch_pc              (stack_branch_pc[i]     ),
                .remain_route           (remain_route[i]        )
            );
        end
    endgenerate

    //[modify] add SIMT_stack_enable
    always @(posedge clk) begin
        if (reset) begin
            SIMT_stack_enable <= 0;
            SIMT_stack_deepest <= 0;
        end
        else if (core_state == 4'b0011) begin
            if (decoded_ssy && SIMT_stack_deepest < BRANCH_NEST_LAYERS - 1) begin
                if (SIMT_stack_enable == 0) begin
                    SIMT_stack_enable <= 1;
                end
                else begin
                    SIMT_stack_enable <= SIMT_stack_enable << 1;
                    SIMT_stack_deepest <= SIMT_stack_deepest + 1;
                end
            end
        end
        else if (core_state == 4'b0111) begin
            if (decoded_sync && remain_route[SIMT_stack_deepest] == 0) begin
                    SIMT_stack_enable <= SIMT_stack_enable >> 1;
                    SIMT_stack_deepest <= SIMT_stack_deepest - 1;
            end
        end
    end

    //[modify] add current_mask, origin_mask
    always @(posedge clk) begin
        if (reset) begin
            current_mask <= {THREADS_PER_BLOCK{1'b1}};
            origin_mask <= {THREADS_PER_BLOCK{1'b1}};
        end
        else if (core_state == 4'b0011 && decoded_ssy) begin
            for (int i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin
                if ((nzp[i] & decoded_nzp) != 3'b0) begin
                    current_mask[i] <= 1'b1; 
                end
                else begin
                    current_mask[i] <= 1'b0;
                end
            end
            origin_mask <= current_mask;
        end
    end

    // [modify] add thread_mask
    always @(posedge clk) begin
        if (reset) begin
            thread_mask <= {THREADS_PER_BLOCK{1'b1}};
        end
        else if (core_state == 4'b0111) begin
            if (SIMT_stack_enable == 0) begin
                    thread_mask <= {THREADS_PER_BLOCK{1'b1}};
            end
            else begin
                    thread_mask <= stack_thread_mask[SIMT_stack_deepest];
            end
        end
    end
    // assign thread_mask = 

    //[modify] add branch_pc
    assign branch_pc = stack_branch_pc[SIMT_stack_deepest];
    
endmodule
