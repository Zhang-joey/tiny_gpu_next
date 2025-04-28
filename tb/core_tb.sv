`default_nettype none
`timescale 1ns/1ns

// CORE TESTBENCH
// > Tests the functionality of the core module
module test_core;
    // Parameters
    parameter DATA_MEM_ADDR_BITS     = 8;
    parameter DATA_MEM_DATA_BITS     = 8;
    parameter PROGRAM_MEM_ADDR_BITS  = 8;
    parameter PROGRAM_MEM_DATA_BITS  = 16;
    parameter THREADS_PER_BLOCK      = 4;
    
    // Clock and Reset
    reg clk;
    reg reset;
    
    // Kernel Execution
    reg start;
    wire done;
    
    // Block Metadata
    reg [7:0] block_id;
    reg [$clog2(THREADS_PER_BLOCK):0] thread_count;
    
    // Program Memory
    wire program_mem_read_valid;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address;
    reg program_mem_read_ready;
    reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data;
    
    // Data Memory
    wire [THREADS_PER_BLOCK-1:0] data_mem_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [THREADS_PER_BLOCK-1:0];
    reg [THREADS_PER_BLOCK-1:0] data_mem_read_ready;
    reg [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [THREADS_PER_BLOCK-1:0];
    wire [THREADS_PER_BLOCK-1:0] data_mem_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [THREADS_PER_BLOCK-1:0];
    reg [THREADS_PER_BLOCK-1:0] data_mem_write_ready;
    
    // Program Memory Model
    reg [PROGRAM_MEM_DATA_BITS-1:0] program_memory [0:255];
    
    // Data Memory Model
    reg [DATA_MEM_DATA_BITS-1:0] data_memory [0:255];
    
    // Instantiate the core
    core #(
        .DATA_MEM_ADDR_BITS     (DATA_MEM_ADDR_BITS),
        .DATA_MEM_DATA_BITS     (DATA_MEM_DATA_BITS),
        .PROGRAM_MEM_ADDR_BITS  (PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS  (PROGRAM_MEM_DATA_BITS),
        .THREADS_PER_BLOCK      (THREADS_PER_BLOCK)
    ) core_inst (
        .clk                    (clk),
        .reset                  (reset),
        .start                  (start),
        .done                   (done),
        .block_id               (block_id),
        .thread_count           (thread_count),
        .program_mem_read_valid (program_mem_read_valid),
        .program_mem_read_address(program_mem_read_address),
        .program_mem_read_ready (program_mem_read_ready),
        .program_mem_read_data  (program_mem_read_data),
        .data_mem_read_valid    (data_mem_read_valid),
        .data_mem_read_address  (data_mem_read_address),
        .data_mem_read_ready    (data_mem_read_ready),
        .data_mem_read_data     (data_mem_read_data),
        .data_mem_write_valid   (data_mem_write_valid),
        .data_mem_write_address (data_mem_write_address),
        .data_mem_write_data    (data_mem_write_data),
        .data_mem_write_ready   (data_mem_write_ready)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Program Memory Model
    always @(posedge clk) begin
        if (program_mem_read_valid) begin
            program_mem_read_ready <= 1;
            program_mem_read_data <= program_memory[program_mem_read_address];
        end else begin
            program_mem_read_ready <= 0;
        end
    end
    
    // Data Memory Model
    genvar i;
    generate
        for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin : data_mem_model
            always @(posedge clk) begin
                // Read operation
                if (data_mem_read_valid[i]) begin
                    data_mem_read_ready[i] <= 1;
                    data_mem_read_data[i] <= data_memory[data_mem_read_address[i]];
                end else begin
                    data_mem_read_ready[i] <= 0;
                end
                
                // Write operation
                if (data_mem_write_valid[i]) begin
                    data_mem_write_ready[i] <= 1;
                    data_memory[data_mem_write_address[i]] <= data_mem_write_data[i];
                end else begin
                    data_mem_write_ready[i] <= 0;
                end
            end
        end
    endgenerate
    
    // Test stimulus
    initial begin
        // Initialize
        reset = 1;
        start = 0;
        block_id = 0;
        thread_count = 4;
        program_mem_read_ready = 0;
        for (int i = 0; i < THREADS_PER_BLOCK; i++) begin
            data_mem_read_ready[i] = 0;
            data_mem_write_ready[i] = 0;
        end
        
        // Initialize program memory with a simple test program
        // This program will:
        // 1. Load a value from memory into register 0
        // 2. Add 1 to it
        // 3. Store the result back to memory
        // 4. Return

        //CONST R0 2
        program_memory[0] = {4'b1001, 4'd0, 8'd2};

        //CONST R1 5
        program_memory[1] = {4'b1001, 4'd1, 8'd5};

        //CMP R15 R0
        program_memory[2] = {4'b0010, 4'd0, 4'd15, 4'd0};
        
        //SSY < else to 6
        program_memory[3] = 16'hb206;
        
        //CONST R0 5
        program_memory[4] = {4'b1001, 4'd0, 8'd5};
        
        //SYNC
        program_memory[5] = {4'b1100, 12'b0};
        
        //CONST R0 6
        program_memory[6] = {4'b1001, 4'd0, 8'd6};
        
        //BRnzp < to 15
        //program_memory[3] = 16'h120f;
        
        //MOVC R0, R1 0010
        //program_memory[4] = {4'b1010, 4'd0, 4'd1, 4'b0010};

        //NOP
        //program_memory[5] = 16'h0FFE;
        
        // LDR R0, [R14] - Load from memory address in R14 (blockDim) into R0
        //program_memory[5] = 16'h700E;
        
        // ADD R0, R0, R15 - Add R0 and R15 (threadIdx) and store in R0
        // program_memory[6] = 16'h300F;
        
        // STR R0, R14 - Store R14 to Mem[R0]
        program_memory[7] = 16'h800E;
        
        //CMP R0, R14 
        program_memory[8] = 16'h200E;
        
        //BRnzp lt 15 - if R0 < R14, PC = 15
        program_memory[9] = 16'h120f;
        
        //CONST R8 256
        program_memory[10] = 16'h98ff;
        
        // RET - Return
        program_memory[15] = 16'hF000;
        
        // Initialize data memory
        for (int i = 0; i < 16; i++) begin
            data_memory[i] = 3 * i + 3;
        end

        // Reset for 10 clock cycles
        #50;
        reset = 0;
        
        // Start the kernel
        #10;
        start = 1;
        #10;
        start = 0;
        
        // Wait for completion
        wait(done);
        
        // Check results
        #10;
        $display("\n Test completed. Results:");
        $display("Data memory[%d] = %h", THREADS_PER_BLOCK, data_memory[THREADS_PER_BLOCK]);
        
        // Expected result: 0x42 + threadIdx for each thread
//        for (int i = 0; i < THREADS_PER_BLOCK; i++) begin
//            $display("Thread %d: Expected = %h, Actual = %h", 
//                    i, 8'h42 + i, data_memory[THREADS_PER_BLOCK]);
//        end
        
        // End simulation
        #100;
        $finish;
    end
    
endmodule 