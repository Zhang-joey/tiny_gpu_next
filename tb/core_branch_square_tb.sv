`default_nettype none
`timescale 1ns/1ns

// CORE TESTBENCH
// > Tests the functionality of the core module
module core_branch_square_tb;
    // Parameters
    parameter DATA_MEM_ADDR_BITS     = 8;
    parameter DATA_MEM_DATA_BITS     = 8;
    parameter PROGRAM_MEM_ADDR_BITS  = 8;
    parameter PROGRAM_MEM_DATA_BITS  = 16;
    parameter THREADS_PER_BLOCK      = 4;
    parameter PROGRAM_MEM_DATA_READ_NUM = 4;
    parameter DATA_MEM_DATA_READ_NUM = 4;
    
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
    reg [PROGRAM_MEM_DATA_READ_NUM * PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data;
    
    // Data Memory
    wire                            data_mem_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0]   data_mem_read_address;
    reg                             data_mem_read_ready;
    reg [DATA_MEM_DATA_READ_NUM * DATA_MEM_DATA_BITS-1:0] data_mem_read_data;
    wire                            data_mem_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0]   data_mem_write_address;
    wire [DATA_MEM_DATA_BITS-1:0]   data_mem_write_data;
    reg                             data_mem_write_ready;
    
    // Program Memory Model
    reg [PROGRAM_MEM_DATA_BITS-1:0] program_memory [64:0];
    
    // Data Memory Model
    reg [DATA_MEM_DATA_BITS-1:0] data_memory [64:0];
    
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
            for(int i=0; i<PROGRAM_MEM_DATA_READ_NUM; i++) begin
                program_mem_read_data[i*PROGRAM_MEM_DATA_BITS +: PROGRAM_MEM_DATA_BITS] <= program_memory[program_mem_read_address + i];
            end
        end else begin
            program_mem_read_ready <= 0;
        end
    end
    
    // Data Memory Model
    always @(posedge clk) begin
        // Read operation
        if (data_mem_read_valid) begin
            data_mem_read_ready <= 1;
            for(int j=0; j<DATA_MEM_DATA_READ_NUM; j++) begin
                data_mem_read_data[j*DATA_MEM_DATA_BITS +: DATA_MEM_DATA_BITS] <= data_memory[data_mem_read_address + j];
            end
        end else begin
            data_mem_read_ready <= 0;
        end
        
        // Write operation
        if (data_mem_write_valid) begin
            data_mem_write_ready <= 1;
            data_memory[data_mem_write_address] <= data_mem_write_data;
        end else begin
            data_mem_write_ready <= 0;
        end
    end
    
    //initial program_mem
    initial begin
        program_memory = {default: 'h0};
        
        program_memory[0] = {4'b0111, 4'd0, 4'd15, 4'd0};   //LDR R0, [R15]
        program_memory[1] = {4'b1001, 4'd2, 8'd1};          //CONST R2, 1
        program_memory[2] = {4'b1001, 4'd4, 8'd4};          //CONST R4, 4   
        program_memory[3] = {4'b0011, 4'd4, 4'd4, 4'd15};   //ADD R4, R4, R15
        program_memory[4] = {4'b0010, 4'd0, 4'd1, 4'd0};    //CMP R1, R0
        program_memory[5] = {4'b1011, 4'b0010, 8'd9};       //SSYN <, 9
        program_memory[6] = {4'b0011, 4'd3, 4'd3, 4'd0};    //ADD R3, R3, R0
        program_memory[7] = {4'b0011, 4'd1, 4'd1, 4'd2};    //ADD R1, R1, R2
        program_memory[8] = {4'b1101, 4'b0010, 8'd4};       //JUMP  4
        program_memory[9] = {4'b1100, 4'd0, 4'd0, 4'd0};    //SYNC
        program_memory[10] = {4'b1100, 4'd0, 4'd0, 4'd0};   //SYNC
        program_memory[11]= {4'b1000, 4'd0, 4'd4, 4'd3};    //STR [R4] R3
        program_memory[12] = {4'b1111, 4'd0, 4'd0, 4'd0};   //RET
    end

    // Initialize data memory
    initial begin
        data_memory = {default: 'h0};
        
        data_memory[0] = 1;
        data_memory[1] = 2;
        data_memory[2] = 3;
        data_memory[3] = 4;
    end

    // Test stimulus
    initial begin
        // Initialize
        reset = 1;
        start = 0;
        block_id = 0;
        thread_count = 4;
        program_mem_read_ready = 0;
        data_mem_read_ready = 0;
        data_mem_write_ready = 0;

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
        $display("\n=== output ===");
        $display("mem addr: 4-7:");
        for(int i=0; i<4; i++) begin
            $display("data_memory[%0d] = %0d", 4+i, data_memory[4+i]);
        end
        $display("==================\n");

        $display("Test completed!");
        $finish;
        
        
        // End simulation
        #100;
        $finish;
    end
    
endmodule 