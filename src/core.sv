`default_nettype none
`timescale 1ns/1ns

// COMPUTE CORE
// > Handles processing 1 block at a time
// > The core also has it's own scheduler to manage control flow
// > Each core contains 1 fetcher & decoder, and register files, ALUs, LSUs, PC for each thread
module core #(
    parameter DATA_MEM_ADDR_BITS     = 8,
    parameter DATA_MEM_DATA_BITS     = 8,
    parameter PROGRAM_MEM_ADDR_BITS  = 8,
    parameter PROGRAM_MEM_DATA_BITS  = 16,
    parameter THREADS_PER_BLOCK      = 4,
    parameter CACHE_SIZE             = 16,
    parameter LINE_SIZE              = 4,
    parameter PROGRAM_MEM_DATA_READ_NUM = 4
) (
    // Clock and Reset
    input  wire clk,
    input  wire reset,

    // Kernel Execution
    input  wire start,
    output wire done,

    // Block Metadata
    input  wire [7:0]                           block_id,
    input  wire [$clog2(THREADS_PER_BLOCK):0]   thread_count,

    // Program Memory
    output reg                             program_mem_read_valid,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address,
    input  reg                             program_mem_read_ready,
    input  reg [PROGRAM_MEM_DATA_READ_NUM * PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data,

    // Data Memory
    output reg                              data_mem_read_valid,
    output reg [DATA_MEM_ADDR_BITS-1:0]     data_mem_read_address,
    input  reg                              data_mem_read_ready,
    input  reg [DATA_MEM_DATA_BITS-1:0]     data_mem_read_data,
    output reg                              data_mem_write_valid,
    output reg [DATA_MEM_ADDR_BITS-1:0]     data_mem_write_address,
    output reg [DATA_MEM_DATA_BITS-1:0]     data_mem_write_data,
    input  reg                              data_mem_write_ready
);
    //[modify] change reg to wire
    // State
    wire [3:0]  core_state;
    wire [15:0] instruction;

    // Intermediate Signals
    //[modify] add thread_mask
    reg  [THREADS_PER_BLOCK-1:0] thread_mask;
    wire [THREADS_PER_BLOCK-1:0] branch_thread_mask;
    wire [7:0]  current_pc   ;
    wire [7:0]  next_pc      ;
    wire [7:0]  rs       [THREADS_PER_BLOCK-1:0];
    wire [7:0]  rt       [THREADS_PER_BLOCK-1:0];
    wire [1:0]  lsu_state[THREADS_PER_BLOCK-1:0];
    wire [7:0]  lsu_out  [THREADS_PER_BLOCK-1:0];
    wire [7:0]  alu_out  [THREADS_PER_BLOCK-1:0];
    wire [2:0]  nzp      [THREADS_PER_BLOCK-1:0];
    //[modify] add request_ready
    wire        request_ready;

    // Decoded Instruction Signals
    wire [3:0]  decoded_rd_address;
    wire [3:0]  decoded_rs_address;
    wire [3:0]  decoded_rt_address;
    wire [2:0]  decoded_nzp;
    wire [7:0]  decoded_immediate;

    // Decoded Control Signals
    wire        decoded_reg_write_enable;           // Enable writing to a register
    wire        decoded_mem_read_enable;            // Enable reading from memory
    wire        decoded_mem_write_enable;           // Enable writing to memory
    wire        decoded_nzp_write_enable;           // Enable writing to NZP register
    wire [1:0]  decoded_reg_input_mux;             // Select input to register
    wire [1:0]  decoded_alu_arithmetic_mux;        // Select arithmetic operation
    wire        decoded_alu_output_mux;             // Select operation in ALU
    wire        decoded_pc_mux;                     // Select source of next PC
    //[modify] add decoded_jump
    wire        decoded_jump;                       // instruction == JUMP
    wire        decoded_ret;
    //[modify] add decoded_sync, decoded_ssy
    wire        decoded_sync;                       // instruction == SYNC
    wire        decoded_ssy;                        // instruction == SSY

    // LSU访存请求信号
    wire [THREADS_PER_BLOCK-1:0] lsu_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] lsu_read_address [THREADS_PER_BLOCK-1:0];
    wire [THREADS_PER_BLOCK-1:0] lsu_read_ready;
    wire [DATA_MEM_DATA_BITS-1:0] lsu_read_data [THREADS_PER_BLOCK-1:0];
    wire [THREADS_PER_BLOCK-1:0] lsu_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] lsu_write_address [THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] lsu_write_data [THREADS_PER_BLOCK-1:0];
    wire [THREADS_PER_BLOCK-1:0] lsu_write_ready;

    // Data Accessor实例
    data_accessor #(
        .THREADS_PER_BLOCK (THREADS_PER_BLOCK),
        .DATA_MEM_ADDR_BITS (DATA_MEM_ADDR_BITS),
        .DATA_MEM_DATA_BITS (DATA_MEM_DATA_BITS)
    ) data_accessor_instance (
        .clk (clk),
        .reset (reset),

        .thread_mask    (thread_mask),
        // LSU接口
        .lsu_read_valid     (lsu_read_valid             ),
        .lsu_read_address   (lsu_read_address           ),
        .lsu_read_ready     (lsu_read_ready             ),
        .lsu_read_data      (lsu_read_data              ),
        .lsu_write_valid    (lsu_write_valid            ),
        .lsu_write_address  (lsu_write_address          ),
        .lsu_write_data     (lsu_write_data             ),
        .lsu_write_ready    (lsu_write_ready            ),

        // 外部存储器接口
        .mem_read_valid     (data_mem_read_valid        ),
        .mem_read_address   (data_mem_read_address      ), // 只使用第一个地址，因为data_accessor已经处理了多线程
        .mem_read_ready     (data_mem_read_ready        ),
        .mem_read_data      (data_mem_read_data         ),
        .mem_write_valid    (data_mem_write_valid       ),
        .mem_write_address  (data_mem_write_address     ),
        .mem_write_data     (data_mem_write_data        ),
        .mem_write_ready    (data_mem_write_ready       )
    );

    // Fetcher
    fetcher #(
        .PROGRAM_MEM_ADDR_BITS  (PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS  (PROGRAM_MEM_DATA_BITS),
        .CACHE_SIZE             (CACHE_SIZE),
        .LINE_SIZE              (LINE_SIZE),
        .PROGRAM_MEM_DATA_READ_NUM (PROGRAM_MEM_DATA_READ_NUM)
    ) fetcher_instance (
        .clk                    (clk                    ),
        .reset                  (reset                  ),
        .core_state             (core_state             ),
        .current_pc             (current_pc             ),
        .mem_read_valid         (program_mem_read_valid ),
        .mem_read_address       (program_mem_read_address),
        .mem_read_ready         (program_mem_read_ready ),
        .mem_read_data          (program_mem_read_data  ),
        .request_ready          (request_ready          ),
        .instruction            (instruction            ) 
    );

    // Decoder
    decoder decoder_instance (
        .clk                        (clk                        ),
        .reset                      (reset                      ),
        .core_state                 (core_state                 ),
        .instruction                (instruction                ),
        .decoded_rd_address         (decoded_rd_address         ),
        .decoded_rs_address         (decoded_rs_address         ),
        .decoded_rt_address         (decoded_rt_address         ),
        .decoded_nzp                (decoded_nzp                ),
        .decoded_immediate          (decoded_immediate          ),
        .decoded_reg_write_enable   (decoded_reg_write_enable   ),
        .decoded_mem_read_enable    (decoded_mem_read_enable    ),
        .decoded_mem_write_enable   (decoded_mem_write_enable   ),
        .decoded_nzp_write_enable   (decoded_nzp_write_enable   ),
        //[modify] add decoded_sync, decoded_ssy
        .decoded_sync               (decoded_sync               ),
        .decoded_ssy                (decoded_ssy                ),
        .decoded_reg_input_mux      (decoded_reg_input_mux      ),
        .decoded_alu_arithmetic_mux (decoded_alu_arithmetic_mux ),
        .decoded_alu_output_mux     (decoded_alu_output_mux     ),
        .decoded_pc_mux             (decoded_pc_mux             ),
        //[modify] add decoded_jump
        .decoded_jump               (decoded_jump               ),
        .decoded_ret                (decoded_ret                )
    );

    // Scheduler
    scheduler #(
        .THREADS_PER_BLOCK      (THREADS_PER_BLOCK)
    ) scheduler_instance (
        .clk                        (clk                    ),
        .reset                      (reset                  ),
        .start                      (start                  ),
        .request_ready              (request_ready          ),
        .core_state                 (core_state             ),
        .decoded_mem_read_enable    (decoded_mem_read_enable),
        .decoded_mem_write_enable   (decoded_mem_write_enable),
        .decoded_ret                (decoded_ret            ),
        .lsu_state                  (lsu_state              ),
        //[modify] delete current_pc, next_pc
        .done                       (done                   )
    );

    //[modify] change pc module to be shared in a core
    pc #(
        //[modify] add thread_per_block
        .THREADS_PER_BLOCK          (THREADS_PER_BLOCK      ),
        .DATA_MEM_DATA_BITS         (DATA_MEM_DATA_BITS     ),
        .PROGRAM_MEM_ADDR_BITS      (PROGRAM_MEM_ADDR_BITS  )
    ) pc_instance ( 
        //[modify] change nzp to input, delete alu_out, delete decoded_nzp_write_enable
        .clk                        (clk                    ),
        .reset                      (reset                  ),
        //[modify] delete enable
        .core_state                 (core_state             ),
        .decoded_nzp                (decoded_nzp            ),
        .decoded_immediate          (decoded_immediate      ),
        //[modify] add decoded_ssy, decoded_sync
        .decoded_ssy                (decoded_ssy            ),
        .decoded_sync               (decoded_sync           ),
        .decoded_pc_mux             (decoded_pc_mux         ),
        //[modify] add decoded_jump
        .decoded_jump               (decoded_jump           ),
        .nzp                        (nzp                    ),
        //[modify] add thread_mask output
        .thread_mask                (branch_thread_mask     ),
        .current_pc                 (current_pc             ),
        .next_pc                    (next_pc                )
    );

    always @ (*) begin
        for (int i = 0; i < THREADS_PER_BLOCK; i++) begin
            thread_mask[i] = (i < thread_count) && branch_thread_mask[i];
        end
    end

    // Dedicated ALU, LSU, registers, & PC unit for each thread this core has capacity for
    genvar i;
    generate
        for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin : threads
            // ALU
            alu alu_instance (
                .clk                        (clk                            ),
                .reset                      (reset                          ),
                //[modify] change enable to be controlled by thread_mask
                .enable                     (thread_mask[i]                 ),
                .core_state                 (core_state                     ),
                .decoded_alu_arithmetic_mux (decoded_alu_arithmetic_mux     ),
                .decoded_alu_output_mux     (decoded_alu_output_mux         ),
                .rs                         (rs[i]                          ),
                .rt                         (rt[i]                          ),
                .alu_out                    (alu_out[i]                     )
            );

            // LSU
            lsu lsu_instance (
                .clk                        (clk                        ),
                .reset                      (reset                      ),
                .enable                     (thread_mask[i]             ),
                .core_state                 (core_state                 ),
                .decoded_mem_read_enable    (decoded_mem_read_enable    ),
                .decoded_mem_write_enable   (decoded_mem_write_enable   ),
                .mem_read_valid             (lsu_read_valid[i]          ),
                .mem_read_address           (lsu_read_address[i]        ),
                .mem_read_ready             (lsu_read_ready[i]          ),
                .mem_read_data              (lsu_read_data[i]           ),
                .mem_write_valid            (lsu_write_valid[i]         ),
                .mem_write_address          (lsu_write_address[i]       ),
                .mem_write_data             (lsu_write_data[i]          ),
                .mem_write_ready            (lsu_write_ready[i]         ),
                .rs                         (rs[i]                      ),
                .rt                         (rt[i]                      ),
                .lsu_state                  (lsu_state[i]               ),
                .lsu_out                    (lsu_out[i]                 )
            );

            // Register File
            registers #(
                .THREADS_PER_BLOCK          (THREADS_PER_BLOCK  ),
                .THREAD_ID                  (i                  ),
                .DATA_BITS                  (DATA_MEM_DATA_BITS )
            ) register_instance (   
                //[modify] add nzp to output, add decoded_nzp_write_enable to input
                .clk                        (clk                    ),
                .reset                      (reset                  ),
                //[modify] change enable to be controlled by thread_mask
                .enable                     (thread_mask[i]         ),
                .block_id                   (block_id               ),
                .core_state                 (core_state             ),
                .decoded_reg_write_enable   (decoded_reg_write_enable),
                .decoded_nzp_write_enable   (decoded_nzp_write_enable),
                .decoded_nzp                (decoded_nzp            ),
                .decoded_reg_input_mux      (decoded_reg_input_mux  ),
                .decoded_rd_address         (decoded_rd_address     ),
                .decoded_rs_address         (decoded_rs_address     ),
                .decoded_rt_address         (decoded_rt_address     ),
                .decoded_immediate          (decoded_immediate      ),
                .alu_out                    (alu_out[i]             ),
                .lsu_out                    (lsu_out[i]             ),
                .thread_count               (thread_count           ),
                .nzp                        (nzp[i]                 ),
                .rs                         (rs[i]                  ),
                .rt                         (rt[i]                  )
            );

            // Program Counter
            //[modify] change pc module to be shared in a core
        end
    endgenerate
endmodule