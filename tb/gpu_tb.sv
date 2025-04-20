`default_nettype none
`timescale 1ns/1ns

module gpu_tb;
    // 参数定义
    localparam DATA_MEM_ADDR_BITS = 8;
    localparam DATA_MEM_DATA_BITS = 8;
    localparam DATA_MEM_NUM_CHANNELS = 4;
    localparam PROGRAM_MEM_ADDR_BITS = 8;
    localparam PROGRAM_MEM_DATA_BITS = 16;
    localparam PROGRAM_MEM_NUM_CHANNELS = 1;
    localparam NUM_CORES = 2;
    localparam THREADS_PER_BLOCK = 4;
    
    // 时钟和复位信号
    reg clk;
    reg reset;
    
    // 内核执行控制信号
    reg start;
    wire done;
    
    // 设备控制寄存器接口
    reg device_control_write_enable;
    reg [7:0] device_control_data;
    
    // 程序内存接口
    wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_valid;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address [PROGRAM_MEM_NUM_CHANNELS-1:0];
    reg [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_ready;
    reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data [PROGRAM_MEM_NUM_CHANNELS-1:0];
    
    // 数据内存接口
    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [DATA_MEM_NUM_CHANNELS-1:0];
    reg [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_ready;
    reg [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [DATA_MEM_NUM_CHANNELS-1:0];
    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [DATA_MEM_NUM_CHANNELS-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [DATA_MEM_NUM_CHANNELS-1:0];
    reg [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_ready;
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // DUT实例化
    gpu #(
        .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
        .DATA_MEM_NUM_CHANNELS(DATA_MEM_NUM_CHANNELS),
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .PROGRAM_MEM_NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS),
        .NUM_CORES(NUM_CORES),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK)
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
    reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem [16:0];
    initial begin
        // 简单的测试程序:
        // 1. CONST R0, 5      - 将常数5加载到R0
        // 2. CONST R1, 3      - 将常数3加载到R1
        // 3. ADD R2, R0, R1   - R2 = R0 + R1
        // 4. STR R2, R0       - 将R2存储到内存地址R0
        // 5. LDR R3, R0       - 从内存地址R0加载到R3
        // 6. CMP R2, R3       - 比较R2和R3
        // 7. BRnzp 0          - 如果相等则跳转到地址0
        // 8. RET              - 返回
        program_mem = {default: 'h0};
        program_mem[0] = {4'b1001, 4'd0, 8'd3};    // CONST R0, 3
        program_mem[1] = {4'b0101, 4'd1, 4'd14, 4'd13}; // MUL R1, R14, R13
        program_mem[2] = {4'b0011, 4'd2, 4'd15, 4'd1}; // ADD R2, R15, R1
        program_mem[3] = {4'b1000, 4'd0, 4'd2, 4'd0}; // STR R2, R0
        program_mem[4] = {4'b0111, 4'd0, 4'd2, 4'd0}; // LDR R3, R0
        program_mem[5] = {4'b0010, 4'd0, 4'd2, 4'd3}; // CMP R2, R3
        program_mem[6] = {4'b0001, 3'b010, 5'd0};     // BRnzp 0
        program_mem[7] = {4'b1111, 12'd0};            // RET
    end
    
    reg [DATA_MEM_DATA_BITS-1:0] data_mem [16:0];
    initial begin
        data_mem = {default: 'h0};
    end
    // 测试过程
    initial begin
        // 初始化信号
        reset = 1;
        start = 0;
        device_control_write_enable = 0;
        device_control_data = 0;
        program_mem_read_ready = 0;
        data_mem_read_ready = 0;
        data_mem_write_ready = 0;
        
        // 等待几个时钟周期后释放复位
        repeat(5) @(posedge clk);
        reset = 0;
        
        // 配置线程数
        @(posedge clk);
        device_control_write_enable = 1;
        device_control_data = 6;
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
                        repeat(5) @(posedge clk);  // 等待5个时钟周期
                        program_mem_read_ready[0] <= 1;
                        program_mem_read_data[0] <= program_mem[program_mem_read_address[0]];
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
                            repeat(5) @(posedge clk);  // 等待5个时钟周期
                            data_mem_read_ready[i] <= 1;
                            data_mem_read_data[i] <= data_mem[data_mem_read_address[i]];
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
                            repeat(5) @(posedge clk);  // 等待5个时钟周期
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
        $display("Test completed!");
        $finish;
    end
    
    // 监控关键信号
    initial begin
        $monitor("Time=%0t reset=%0b start=%0b done=%0b", 
                 $time, reset, start, done);
    end
    
endmodule 