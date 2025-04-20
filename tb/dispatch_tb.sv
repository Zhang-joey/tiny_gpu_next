`default_nettype none
`timescale 1ns/1ns

module dispatch_tb;
    // 参数定义
    localparam NUM_CORES = 2;
    localparam THREADS_PER_BLOCK = 4;

    // 时钟周期定义
    localparam CLK_PERIOD = 10;

    // 信号定义
    reg clk;
    reg reset;
    reg start;
    reg [7:0] thread_count;
    reg [NUM_CORES-1:0] core_done;
    wire [NUM_CORES-1:0] core_start;
    wire [NUM_CORES-1:0] core_reset;
    wire [7:0] core_block_id [NUM_CORES-1:0];
    wire [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES-1:0];
    wire done;

    // 实例化被测模块
    dispatch #(
        .NUM_CORES(NUM_CORES),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK)
    ) dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .thread_count(thread_count),
        .core_done(core_done),
        .core_start(core_start),
        .core_reset(core_reset),
        .core_block_id(core_block_id),
        .core_thread_count(core_thread_count),
        .done(done)
    );

    // 时钟生成
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // 测试过程
    initial begin
        // 初始化信号
        reset = 1;
        thread_count = 0;
        core_done = 0;

        // 等待100ns后释放复位
        #100;
        reset = 0;

        // 测试用例1：8个线程，2个核心，每个块4个线程
        thread_count = 4;
        #10;

        // 模拟核心0完成第一个块
        #20;
        core_done[0] = 1;

        // 模拟核心1完成第二个块
        #20;
        core_done[1] = 1;

        // 等待done信号
        #100;

        // 测试用例2：6个线程，2个核心，每个块4个线程
//        reset = 1;
        #20;
        reset = 0;
        thread_count = 6;
        // 模拟核心0完成第一个块
        #20;
        core_done[0] = 1;

        // 模拟核心1完成第二个块
        #20;
        core_done[1] = 1;

        // 等待done信号
        #100;

        // 结束仿真
        $finish;
    end
    
    always @ (posedge clk) begin
        if (reset) start <= 0;
        else if (done != 1) start <= 1;
        else start <= 0;
    end
    
    // 监控输出
    initial begin
        $monitor("Time=%0t reset=%b start=%b thread_count=%0d done=%b core_start=%b core_done=%b",
                 $time, reset, start, thread_count, done, core_start, core_done);
    end

endmodule 