`default_nettype none
`timescale 1ns/1ns

// DATA ACCESSOR
// > 负责处理并合并core内所有线程的LSU访存请求
// > 实现相同地址请求的合并和不同地址请求的轮询发送
module data_accessor #(
    parameter THREADS_PER_BLOCK = 4,
    parameter DATA_MEM_ADDR_BITS = 8,
    parameter DATA_MEM_DATA_BITS = 8,
    parameter DATA_MEM_DATA_READ_NUM = 4,
    parameter CACHE_SIZE = 32,        // 新增：缓存总大小
    parameter CACHE_LINE_SIZE = 4     // 新增：缓存行大小
) (
    input wire clk,
    input wire reset,

    // 来自各个线程LSU的读请求
    input wire [THREADS_PER_BLOCK-1:0]     thread_mask,
    input wire [THREADS_PER_BLOCK-1:0]     lsu_read_valid,
    input wire [DATA_MEM_ADDR_BITS-1:0]    lsu_read_address [THREADS_PER_BLOCK-1:0],
    output reg [THREADS_PER_BLOCK-1:0]     lsu_read_ready,
    output reg [DATA_MEM_DATA_BITS-1:0]    lsu_read_data [THREADS_PER_BLOCK-1:0],

    // 来自各个线程LSU的写请求
    input wire [THREADS_PER_BLOCK-1:0]     lsu_write_valid,
    input wire [DATA_MEM_ADDR_BITS-1:0]    lsu_write_address [THREADS_PER_BLOCK-1:0],
    input wire [DATA_MEM_DATA_BITS-1:0]    lsu_write_data [THREADS_PER_BLOCK-1:0],
    output reg [THREADS_PER_BLOCK-1:0]     lsu_write_ready,

    // 对外部数据存储器的接口
    output reg                            mem_read_valid,
    output reg [DATA_MEM_ADDR_BITS-1:0]   mem_read_address,
    input wire                            mem_read_ready,
    input wire [DATA_MEM_DATA_READ_NUM * DATA_MEM_DATA_BITS-1:0]   mem_read_data,
    output reg                            mem_write_valid,
    output reg [DATA_MEM_ADDR_BITS-1:0]   mem_write_address,
    output reg [DATA_MEM_DATA_BITS-1:0]   mem_write_data,
    input wire                            mem_write_ready
);

    // 状态定义
    localparam IDLE = 3'b000;
    localparam READ_WAITING = 3'b001;
    localparam WRITE_WAITING = 3'b010;
    localparam READ_RELAYING = 3'b011;
    localparam WRITE_RELAYING = 3'b100;

    reg [2:0] state;
    reg [THREADS_PER_BLOCK-1:0] pending_read_threads;
    reg [THREADS_PER_BLOCK-1:0] pending_write_threads;
    reg [THREADS_PER_BLOCK-1:0] completed_read_threads;
    reg [THREADS_PER_BLOCK-1:0] completed_write_threads;
    reg [$clog2(THREADS_PER_BLOCK)-1:0] current_thread;

    // 新增：数据缓存接口信号
    reg request_valid;
    reg [DATA_MEM_ADDR_BITS-1:0] request_address;
    wire request_ready;
    wire [DATA_MEM_DATA_BITS-1:0] request_data;

    // 新增：数据缓存实例化
    cache #(
        .CACHE_SIZE(CACHE_SIZE),
        .LINE_SIZE(CACHE_LINE_SIZE),
        .MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
        .MEM_DATA_BITS(DATA_MEM_DATA_BITS),
        .MEM_DATA_READ_NUM(DATA_MEM_DATA_READ_NUM)
    ) dcache (
        .clk(clk),
        .reset(reset),
        .addr(request_address),
        .request_valid(request_valid),
        .request_ready(request_ready),
        .instruction(request_data),
        .mem_read_valid(mem_read_valid),
        .mem_read_address(mem_read_address),
        .mem_read_ready(mem_read_ready),
        .mem_read_data(mem_read_data)
    );

    // 检查是否有相同地址的请求
    function automatic [THREADS_PER_BLOCK-1:0] find_same_address;
        input [THREADS_PER_BLOCK-1:0]  valid;
        input [DATA_MEM_ADDR_BITS-1:0] addresses [THREADS_PER_BLOCK-1:0];
        input [DATA_MEM_ADDR_BITS-1:0] target_address;
        begin
            find_same_address = 0;
            for (int i = 0; i < THREADS_PER_BLOCK; i++) begin
                if (valid[i] && addresses[i] == target_address) begin
                    find_same_address[i] = 1;
                end
            end
        end
    endfunction

    // 轮询选择下一个请求
    function automatic [$clog2(THREADS_PER_BLOCK)-1:0] round_robin_select;
        input [THREADS_PER_BLOCK-1:0] valid;
        begin
            round_robin_select = 0;
            for (int i = 0; i < THREADS_PER_BLOCK; i++) begin
                if (valid[i]) begin
                    round_robin_select = i;
                    break;
                end
            end
        end
    endfunction

    assign current_thread = round_robin_select(lsu_read_valid | lsu_write_valid);
    
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            pending_read_threads <= 0;
            pending_write_threads <= 0;
            completed_read_threads <= 0;
            completed_write_threads <= 0;
            request_valid <= 0;
            request_address <= 0;
            lsu_read_ready <= 0;
            lsu_write_ready <= 0;
        end else begin
            case (state)
                IDLE: begin
                    // 检查是否有新的读请求
                    if (|lsu_read_valid) begin
                        state <= READ_WAITING;
                        // 找到所有相同地址的读请求
                        pending_read_threads <= find_same_address(lsu_read_valid, lsu_read_address, lsu_read_address[current_thread]);
                        completed_read_threads <= 0;
                        request_valid <= 1;
                        request_address <= lsu_read_address[current_thread];
                    end
                    // 检查是否有新的写请求
                    else if (|lsu_write_valid) begin
                        state <= WRITE_WAITING;
                        // 找到所有相同地址的写请求
                        pending_write_threads <= find_same_address(lsu_write_valid, lsu_write_address, lsu_write_address[current_thread]);
                        completed_write_threads <= 0;
                        mem_write_valid <= 1;
                        mem_write_address <= lsu_write_address[current_thread];
                        mem_write_data <= lsu_write_data[current_thread];
                    end
                end

                READ_WAITING: begin
                    if (request_ready) begin
                        request_valid <= 0;
                        // 将数据返回给所有等待相同地址的线程
                        for (int i = 0; i < THREADS_PER_BLOCK; i++) begin
                            if (pending_read_threads[i] && !completed_read_threads[i]) begin
                                lsu_read_data[i] <= request_data;
                                lsu_read_ready[i] <= 1;
                                completed_read_threads[i] <= 1;
                            end 
                        end
                    end
                    if (pending_read_threads == lsu_read_ready) begin                        
                        state <= READ_RELAYING;
                        lsu_read_ready <= 0;
                    end
                end

                WRITE_WAITING: begin
                    if (mem_write_ready) begin
                        mem_write_valid <= 0;
                        // 通知所有等待相同地址的线程写操作完成
                        for (int i = 0; i < THREADS_PER_BLOCK; i++) begin
                            if (pending_write_threads[i] && !completed_write_threads[i]) begin
                                lsu_write_ready[i] <= 1;
                                completed_write_threads[i] <= 1;
                            end
                        end
                    end
                    if (pending_write_threads == lsu_write_ready) begin                        
                        state <= WRITE_RELAYING;
                        lsu_write_ready <= 0;
                    end
                end

                READ_RELAYING: begin
                    // 等待所有线程确认接收数据
                    if (completed_read_threads == thread_mask) begin                                                    
                        state <= IDLE;                            
                    end
                    else begin      // 更新轮询指针到下一个请求
                        pending_read_threads <= find_same_address(lsu_read_valid, lsu_read_address, lsu_read_address[current_thread]);
                        request_valid <= 1;
                        request_address <= lsu_read_address[current_thread];
                        state <= READ_WAITING;
                    end
                end

                WRITE_RELAYING: begin
                    // 等待所有线程确认写操作完成
                    if (completed_write_threads == thread_mask) begin
                        state <= IDLE;
                    end
                    else begin
                        pending_write_threads <= find_same_address(lsu_write_valid, lsu_write_address, lsu_write_address[current_thread]);
                        mem_write_valid <= 1;
                        mem_write_address <= lsu_write_address[current_thread];
                        mem_write_data <= lsu_write_data[current_thread];
                        state <= WRITE_WAITING;
                    end
                end
            endcase
        end
    end

endmodule 