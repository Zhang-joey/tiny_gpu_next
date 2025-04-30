`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION FETCHER
// > 使用指令缓存从程序内存中获取指令
// > 每个核心都有自己的fetcher和指令缓存
module fetcher #(
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter CACHE_SIZE = 16,
    parameter CACHE_LINE_SIZE = 4,
    parameter PROGRAM_MEM_DATA_READ_NUM = 4
) (
    input wire clk,
    input wire reset,
    
    // Execution State
    input reg [3:0] core_state,
    input reg [7:0] current_pc,

    // Program Memory
    output  reg                             mem_read_valid,
    output  reg [PROGRAM_MEM_ADDR_BITS-1:0] mem_read_address,
    input   reg                             mem_read_ready,
    input   reg [PROGRAM_MEM_DATA_READ_NUM * PROGRAM_MEM_DATA_BITS-1:0] mem_read_data,

    // Fetcher Output
    // [modify] delete fetcher_state
    // [modify] add request_ready
    output  reg                             request_ready,
    output  reg [PROGRAM_MEM_DATA_BITS-1:0] instruction
);
    
    // 实例化指令缓存
    cache #(
        .CACHE_SIZE(CACHE_SIZE),
        .LINE_SIZE(CACHE_LINE_SIZE),
        .MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .MEM_DATA_READ_NUM(PROGRAM_MEM_DATA_READ_NUM)
    ) icache (
        .clk(clk),
        .reset(reset),
        .addr(current_pc),
        .request_valid(core_state == 4'b0001),  // 当core_state为FETCH时请求有效
        .request_ready(request_ready),
        .instruction(instruction),
        .mem_read_valid(mem_read_valid),
        .mem_read_address(mem_read_address),
        .mem_read_ready(mem_read_ready),
        .mem_read_data(mem_read_data)
    );
    
endmodule
