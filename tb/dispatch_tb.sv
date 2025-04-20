`default_nettype none
`timescale 1ns/1ns

module dispatch_tb;
    // ��������
    localparam NUM_CORES = 2;
    localparam THREADS_PER_BLOCK = 4;

    // ʱ�����ڶ���
    localparam CLK_PERIOD = 10;

    // �źŶ���
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

    // ʵ��������ģ��
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

    // ʱ������
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ���Թ���
    initial begin
        // ��ʼ���ź�
        reset = 1;
        thread_count = 0;
        core_done = 0;

        // �ȴ�100ns���ͷŸ�λ
        #100;
        reset = 0;

        // ��������1��8���̣߳�2�����ģ�ÿ����4���߳�
        thread_count = 4;
        #10;

        // ģ�����0��ɵ�һ����
        #20;
        core_done[0] = 1;

        // ģ�����1��ɵڶ�����
        #20;
        core_done[1] = 1;

        // �ȴ�done�ź�
        #100;

        // ��������2��6���̣߳�2�����ģ�ÿ����4���߳�
//        reset = 1;
        #20;
        reset = 0;
        thread_count = 6;
        // ģ�����0��ɵ�һ����
        #20;
        core_done[0] = 1;

        // ģ�����1��ɵڶ�����
        #20;
        core_done[1] = 1;

        // �ȴ�done�ź�
        #100;

        // ��������
        $finish;
    end
    
    always @ (posedge clk) begin
        if (reset) start <= 0;
        else if (done != 1) start <= 1;
        else start <= 0;
    end
    
    // ������
    initial begin
        $monitor("Time=%0t reset=%b start=%b thread_count=%0d done=%b core_start=%b core_done=%b",
                 $time, reset, start, thread_count, done, core_start, core_done);
    end

endmodule 