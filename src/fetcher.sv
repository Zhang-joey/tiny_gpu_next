`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION FETCHER
// > 使用指令缓存从程序内存中获取指令
// > 每个核心都有自己的fetcher和指令缓存
module fetcher #(
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter CACHE_SIZE = 16,
    parameter LINE_SIZE = 4,
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
    localparam  IDLE        = 3'b000, 
                FETCHING    = 3'b001, 
                FETCHED     = 3'b010;
    
    // 指令缓存接口信号
    
    // 实例化指令缓存
    instruction_cache #(
        .CACHE_SIZE(CACHE_SIZE),
        .LINE_SIZE(LINE_SIZE),
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .PROGRAM_MEM_DATA_READ_NUM(PROGRAM_MEM_DATA_READ_NUM)
    ) icache (
        .clk(clk),
        .reset(reset),
        .pc(current_pc),
        .request_valid(core_state == 4'b0001),  // 当core_state为FETCH时请求有效
        .request_ready(request_ready),
        .instruction(instruction),
        .mem_read_valid(mem_read_valid),
        .mem_read_address(mem_read_address),
        .mem_read_ready(mem_read_ready),
        .mem_read_data(mem_read_data)
    );
    
    // always @(posedge clk) begin
    //     if (reset) begin
    //         fetcher_state    <= IDLE;
    //         instruction <= {PROGRAM_MEM_DATA_BITS{1'b0}};
    //     end else begin
    //         case (fetcher_state)
    //             IDLE: begin
    //                 // 当core_state为FETCH时开始获取指令
    //                 if (core_state == 4'b0001) begin
    //                     fetcher_state <= FETCHING;
    //                 end
    //             end
    //             FETCHING: begin
    //                 // 等待缓存准备好指令
    //                 if (cache_request_ready) begin
    //                     fetcher_state <= FETCHED;
    //                     instruction <= cache_instruction;
    //                 end
    //             end
    //             FETCHED: begin
    //                 // 当core_state为DECODE时重置状态
    //                 if (core_state == 4'b0010) begin 
    //                     fetcher_state <= IDLE;
    //                 end
    //             end
    //         endcase
    //     end
    // end
endmodule
