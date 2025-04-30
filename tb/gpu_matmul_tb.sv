`default_nettype none
`timescale 1ns/1ns

module gpu_matmul_tb;
    // 参数定义
    localparam DATA_MEM_ADDR_BITS = 8;
    localparam DATA_MEM_DATA_BITS = 8;
    localparam DATA_MEM_NUM_CHANNELS = 2;
    localparam PROGRAM_MEM_ADDR_BITS = 8;
    localparam PROGRAM_MEM_DATA_BITS = 16;
    localparam PROGRAM_MEM_NUM_CHANNELS = 1;
    localparam NUM_CORES = 2;
    localparam THREADS_PER_BLOCK = 4;
    localparam PROGRAM_MEM_DATA_READ_NUM = 4; //program的读取位宽(指令数,4条指令)
    localparam DATA_MEM_DATA_READ_NUM = 4; //data的读取位宽(数据数,4个数据)
    localparam PROGRAM_CACHE_SIZE = 16;     // Instruction cache size in bytes
    localparam PROGRAM_CACHE_LINE_SIZE = 4;        // Instruction cache line size in bytes
    localparam DATA_CACHE_SIZE = 32;     // Instruction cache size in bytes
    localparam DATA_CACHE_LINE_SIZE = 4;        // Instruction cache line size in bytes
    
    // 时钟和复位信号
    reg clk;
    reg reset;
    
    // 内核执行控制信号
    reg start;
    wire done;
    
    // 设备控制寄存器接号
    reg device_control_write_enable;
    reg [7:0] device_control_data [NUM_CORES-1:0];
    
    // 程序内存接口
    wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_valid;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address [PROGRAM_MEM_NUM_CHANNELS-1:0];
    reg [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_ready;
    reg [PROGRAM_MEM_DATA_READ_NUM * PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data [PROGRAM_MEM_NUM_CHANNELS-1:0];
    
    // 数据内存接口
    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [DATA_MEM_NUM_CHANNELS-1:0];
    reg [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_ready;
    reg [DATA_MEM_DATA_READ_NUM * DATA_MEM_DATA_BITS-1:0] data_mem_read_data [DATA_MEM_NUM_CHANNELS-1:0];
    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [DATA_MEM_NUM_CHANNELS-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [DATA_MEM_NUM_CHANNELS-1:0];
    reg [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_ready;
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // DUT实例
    gpu #(
        .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
        .DATA_MEM_NUM_CHANNELS(DATA_MEM_NUM_CHANNELS),
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .PROGRAM_MEM_NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS),
        .NUM_CORES(NUM_CORES),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .PROGRAM_CACHE_SIZE(PROGRAM_CACHE_SIZE),
        .PROGRAM_CACHE_LINE_SIZE(PROGRAM_CACHE_LINE_SIZE),
        .DATA_CACHE_SIZE(DATA_CACHE_SIZE),
        .DATA_CACHE_LINE_SIZE(DATA_CACHE_LINE_SIZE),
        .PROGRAM_MEM_DATA_READ_NUM(PROGRAM_MEM_DATA_READ_NUM),
        .DATA_MEM_DATA_READ_NUM(DATA_MEM_DATA_READ_NUM)
    ) dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .done(done),
        .device_control_write_enable(device_control_write_enable),
        .device_control_data(device_control_data),
        .program_mem_read_valid(program_mem_read_valid),
        .program_mem_read_address(program_mem_read_address),
        .program_mem_read_ready(program_mem_read_ready),
        .program_mem_read_data(program_mem_read_data),
        .data_mem_read_valid(data_mem_read_valid),
        .data_mem_read_address(data_mem_read_address),
        .data_mem_read_ready(data_mem_read_ready),
        .data_mem_read_data(data_mem_read_data),
        .data_mem_write_valid(data_mem_write_valid),
        .data_mem_write_address(data_mem_write_address),
        .data_mem_write_data(data_mem_write_data),
        .data_mem_write_ready(data_mem_write_ready)
    );
    
    // 测试程序内存数据
    reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem [64:0];
    initial begin
        // 矩阵乘测试程??
        program_mem = {default: 'h0};
        program_mem[0]  = {4'b0101, 4'd0, 4'd14, 4'd13};    //MUL R0, R14, R13      blockDim * blockIdx
        program_mem[1]  = {4'b0011, 4'd0, 4'd0, 4'd15};     //ADD R0, R0, R15       x = blockDim * blockIdx + threadIdx
        program_mem[2]  = {4'b1001, 4'd1, 8'd0};            //CONST R1, 0           baseA
        program_mem[3]  = {4'b1001, 4'd2, 8'd8};            //CONST R2, 8           baseB
        program_mem[4]  = {4'b1001, 4'd3, 8'd20};           //CONST R3, 20          baseC
        program_mem[5]  = {4'b1001, 4'd4, 8'd4};            //CONST R4, 4           A_coldim
        program_mem[6]  = {4'b1001, 4'd5, 8'd3};            //CONST R5, 3           C_coldim
        program_mem[7]  = {4'b0110, 4'd6, 4'd0, 4'd5};      //DIV R6, R0, R5        A_rows/C_rows = x / C_coldim
        program_mem[8]  = {4'b0101, 4'd7, 4'd6, 4'd5};      //MUL R7, R6, R5        C_rows *  C_coldim
        program_mem[9]  = {4'b0100, 4'd7, 4'd0, 4'd7};      //SUB R7, R0, R7        B_rows/C_cols = x - C_rows * C_coldim
        program_mem[10] = {4'b1001, 4'd8, 8'd0};            //CONST R8, 0           i = 0
        program_mem[11] = {4'b1001, 4'd9, 8'd0};            //CONST R9, 0           sum = 0 
        program_mem[12] = {4'b1001, 4'd5, 8'd1};            //CONST R5, 1           i + 1
        program_mem[13] = {4'b0101, 4'd10, 4'd6, 4'd4};     //MUL R10, R6, R4       A_rows * A_coldim
        program_mem[14] = {4'b0011, 4'd1, 4'd10, 4'd1};     //ADD R1, R10, R1       A_rows * A_coldim + baseA
        program_mem[15] = {4'b0101, 4'd11, 4'd7, 4'd4};     //MUL R11, R7, R4       B_rows * B_coldim
        program_mem[16] = {4'b0011, 4'd2, 4'd11, 4'd2};     //ADD R2, R11, R2       B_rows * B_coldim + baseB
        program_mem[17] = {4'b0011, 4'd3, 4'd3, 4'd0};      //ADD R3, R3, R0        baseC + x
        // LOOP:
        program_mem[18] = {4'b0011, 4'd10, 4'd8, 4'd1};     //ADD R10, R8, R1       i + A_rows * A_coldim + baseA
        program_mem[19] = {4'b0111, 4'd10, 4'd10, 4'd0};    //LDR R10, R10          A[i + A_rows * A_coldim + baseA]
        program_mem[20] = {4'b0011, 4'd11, 4'd8, 4'd2};     //ADD R11, R8, R2       i + B_rows * B_coldim + baseB
        program_mem[21] = {4'b0111, 4'd11, 4'd11, 4'd0};    //LDR R11, R11          B[i + B_rows * B_coldim + baseB]
        program_mem[22] = {4'b0101, 4'd12, 4'd10, 4'd11};   //MUL R12, R10, R11     A[i] * B[i]
        program_mem[23] = {4'b0011, 4'd9, 4'd9, 4'd12};     //ADD R9, R9, R12       sum += A[i] * B[i]
        program_mem[24] = {4'b0011, 4'd8, 4'd5, 4'd8};      //ADD R8, R5, R8        i + 1
        program_mem[25] = {4'b0010, 4'd0, 4'd8, 4'd4};      //CMP R8, R4            i < 4
        program_mem[26] = {4'b0001, 4'b0010, 8'd18};        //BRnzp LT LOOP         if i < 4, next_pc = 18
        program_mem[27] = {4'b1000, 4'd0, 4'd3, 4'd9};      //STR R9, R3            store sum
        program_mem[28] = {4'b1111, 4'b0, 4'd0, 4'd0};      //RET

    end
    
    reg [DATA_MEM_DATA_BITS-1:0] data_mem [64:0];
    // A:
    // [0. 1. 2. 3.]
    // [1. 2. 3. 4.]
    // B:
    // [2. 3. 4. 5.]
    // [3. 4. 5. 6.]
    // [4. 5. 6. 7.]
    // C:
    // [26. 32. 38.]
    // [40. 50. 60.]
    initial begin
        data_mem = {default: 'h0};
        for(int i=0; i<5; i++) begin
            for(int j=0; j<4; j++) begin
                data_mem[i*4 + j] = j+i;
            end
        end
    end
    // 测试过程
    initial begin
        // 初始化信号
        reset = 1;
        start = 0;
        device_control_write_enable = 0;
        for (int i = 0; i < NUM_CORES; i++) begin
            device_control_data[i] = 0;
        end
        program_mem_read_ready = 0;
        data_mem_read_ready = 0;
        data_mem_write_ready = 0;
        
        // 等待几个时钟周期后释放复??
        repeat(5) @(posedge clk);
        reset = 0;
        
        // 配置线程??
        @(posedge clk);
        device_control_write_enable = 1;
        device_control_data[0] = 3;
        device_control_data[1] = 3;
        @(posedge clk);
        device_control_write_enable = 0;
        
        // 启动内核执行
        @(posedge clk);
        start = 1;
        
        // 模拟程序内存和数据内存的响应
        fork
            // 程序内存响应
            begin
                forever begin
                    @(posedge clk);
                    if(program_mem_read_valid[0]) begin
                        repeat(5) @(posedge clk);  // 等待5个时钟周??
                        program_mem_read_ready[0] <= 1;
                        for(int i=0; i<PROGRAM_MEM_DATA_READ_NUM; i++) begin
                            program_mem_read_data[0][i*PROGRAM_MEM_DATA_BITS +: PROGRAM_MEM_DATA_BITS] <= program_mem[program_mem_read_address[0] + i];
                        end
                        @(posedge clk);
                        program_mem_read_ready[0] <= 0;
                    end
                end
            end
            
            // 数据内存读响应
            begin
                forever begin
                    @(posedge clk);
                    for(int i=0; i<DATA_MEM_NUM_CHANNELS; i++) begin
                        if(data_mem_read_valid[i]) begin
                            data_mem_read_ready[i] <= 0;  // 先拉低ready信号
                            repeat(5) @(posedge clk);  // 等待5个时钟周??
                            data_mem_read_ready[i] <= 1;
                            for(int j=0; j<DATA_MEM_DATA_READ_NUM; j++) begin
                                data_mem_read_data[i][j*DATA_MEM_DATA_BITS +: DATA_MEM_DATA_BITS] <= data_mem[data_mem_read_address[i] + j];
                            end
                            @(posedge clk);
                            data_mem_read_ready[i] <= 0;
                        end
                    end
                end
            end
            
            // 数据内存写响应
            begin
                forever begin
                    @(posedge clk);
                    for(int i=0; i<DATA_MEM_NUM_CHANNELS; i++) begin
                        if(data_mem_write_valid[i]) begin
                            data_mem_write_ready[i] <= 0;  // 先拉低ready信号
                            repeat(5) @(posedge clk);  // 等待5个时钟周??
                            data_mem_write_ready[i] <= 1;
                            data_mem[data_mem_write_address[i]] <= data_mem_write_data[i];
                            @(posedge clk);
                            data_mem_write_ready[i] <= 0;
                        end
                    end
                end
            end
        join_none
        
        // 等待内核执行完成
        wait(done);
        repeat(10) @(posedge clk);

        // 显示结果数据
        $display("\n=== 矩阵乘法结果 ===");
        $display("C矩阵结果 (地址20-25):");
        for(int i=0; i<6; i++) begin
            $display("data_mem[%0d] = %0d", 20+i, data_mem[20+i]);
        end
        $display("==================\n");

        $display("Test completed!");
        $finish;
    end
    
    // 监控关键信号
    initial begin
        $monitor("Time=%0t reset=%0b start=%0b done=%0b", 
                 $time, reset, start, done);
    end
    
endmodule 