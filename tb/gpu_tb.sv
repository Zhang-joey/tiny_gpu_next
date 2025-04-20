`default_nettype none
`timescale 1ns/1ns

module gpu_tb;
    // ��������
    localparam DATA_MEM_ADDR_BITS = 8;
    localparam DATA_MEM_DATA_BITS = 8;
    localparam DATA_MEM_NUM_CHANNELS = 4;
    localparam PROGRAM_MEM_ADDR_BITS = 8;
    localparam PROGRAM_MEM_DATA_BITS = 16;
    localparam PROGRAM_MEM_NUM_CHANNELS = 1;
    localparam NUM_CORES = 2;
    localparam THREADS_PER_BLOCK = 4;
    
    // ʱ�Ӻ͸�λ�ź�
    reg clk;
    reg reset;
    
    // �ں�ִ�п����ź�
    reg start;
    wire done;
    
    // �豸���ƼĴ����ӿ�
    reg device_control_write_enable;
    reg [7:0] device_control_data;
    
    // �����ڴ�ӿ�
    wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_valid;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address [PROGRAM_MEM_NUM_CHANNELS-1:0];
    reg [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_ready;
    reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data [PROGRAM_MEM_NUM_CHANNELS-1:0];
    
    // �����ڴ�ӿ�
    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [DATA_MEM_NUM_CHANNELS-1:0];
    reg [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_ready;
    reg [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [DATA_MEM_NUM_CHANNELS-1:0];
    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [DATA_MEM_NUM_CHANNELS-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [DATA_MEM_NUM_CHANNELS-1:0];
    reg [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_ready;
    
    // ʱ������
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // DUTʵ����
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
    
    // ���Գ����ڴ�����
    reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem [16:0];
    initial begin
        // �򵥵Ĳ��Գ���:
        // 1. CONST R0, 5      - ������5���ص�R0
        // 2. CONST R1, 3      - ������3���ص�R1
        // 3. ADD R2, R0, R1   - R2 = R0 + R1
        // 4. STR R2, R0       - ��R2�洢���ڴ��ַR0
        // 5. LDR R3, R0       - ���ڴ��ַR0���ص�R3
        // 6. CMP R2, R3       - �Ƚ�R2��R3
        // 7. BRnzp 0          - ����������ת����ַ0
        // 8. RET              - ����
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
    // ���Թ���
    initial begin
        // ��ʼ���ź�
        reset = 1;
        start = 0;
        device_control_write_enable = 0;
        device_control_data = 0;
        program_mem_read_ready = 0;
        data_mem_read_ready = 0;
        data_mem_write_ready = 0;
        
        // �ȴ�����ʱ�����ں��ͷŸ�λ
        repeat(5) @(posedge clk);
        reset = 0;
        
        // �����߳���
        @(posedge clk);
        device_control_write_enable = 1;
        device_control_data = 6;
        @(posedge clk);
        device_control_write_enable = 0;
        
        // �����ں�ִ��
        @(posedge clk);
        start = 1;
        
        // ģ������ڴ�������ڴ����Ӧ
        fork
            // �����ڴ���Ӧ
            begin
                forever begin
                    @(posedge clk);
                    if(program_mem_read_valid[0]) begin
                        repeat(5) @(posedge clk);  // �ȴ�5��ʱ������
                        program_mem_read_ready[0] <= 1;
                        program_mem_read_data[0] <= program_mem[program_mem_read_address[0]];
                        @(posedge clk);
                        program_mem_read_ready[0] <= 0;
                    end
                end
            end
            
            // �����ڴ����Ӧ
            begin
                forever begin
                    @(posedge clk);
                    for(int i=0; i<DATA_MEM_NUM_CHANNELS; i++) begin
                        if(data_mem_read_valid[i]) begin
                            data_mem_read_ready[i] <= 0;  // ������ready�ź�
                            repeat(5) @(posedge clk);  // �ȴ�5��ʱ������
                            data_mem_read_ready[i] <= 1;
                            data_mem_read_data[i] <= data_mem[data_mem_read_address[i]];
                            @(posedge clk);
                            data_mem_read_ready[i] <= 0;
                        end
                    end
                end
            end
            
            // �����ڴ�д��Ӧ
            begin
                forever begin
                    @(posedge clk);
                    for(int i=0; i<DATA_MEM_NUM_CHANNELS; i++) begin
                        if(data_mem_write_valid[i]) begin
                            data_mem_write_ready[i] <= 0;  // ������ready�ź�
                            repeat(5) @(posedge clk);  // �ȴ�5��ʱ������
                            data_mem_write_ready[i] <= 1;
                            data_mem[data_mem_write_address[i]] <= data_mem_write_data[i];
                            @(posedge clk);
                            data_mem_write_ready[i] <= 0;
                        end
                    end
                end
            end
        join_none
        
        // �ȴ��ں�ִ�����
        wait(done);
        repeat(10) @(posedge clk);
        $display("Test completed!");
        $finish;
    end
    
    // ��عؼ��ź�
    initial begin
        $monitor("Time=%0t reset=%0b start=%0b done=%0b", 
                 $time, reset, start, done);
    end
    
endmodule 