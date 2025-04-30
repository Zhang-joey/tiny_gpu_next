`default_nettype none
`timescale 1ns/1ns

// GPU
// > Built to use an external async memory with multi-channel read/write
// > Assumes that the program is loaded into program memory, data into data memory, and threads into
//   the device control register before the start signal is triggered
// > Has memory controllers to interface between external memory and its multiple cores
// > Configurable number of cores and thread capacity per core
module gpu #(
    parameter DATA_MEM_ADDR_BITS        = 8,        // Number of bits in data memory address (256 rows)
    parameter DATA_MEM_DATA_BITS        = 8,        // Number of bits in data memory value (8 bit data)
    parameter DATA_MEM_NUM_CHANNELS     = 2,        // Number of concurrent channels for sending requests to data memory
    parameter PROGRAM_MEM_ADDR_BITS     = 8,        // Number of bits in program memory address (256 rows)
    parameter PROGRAM_MEM_DATA_BITS     = 16,       // Number of bits in program memory value (16 bit instruction)
    parameter PROGRAM_MEM_NUM_CHANNELS  = 1,        // Number of concurrent channels for sending requests to program memory
    parameter NUM_CORES                 = 2,        // Number of cores to include in this GPU
    parameter THREADS_PER_BLOCK         = 4,        // Number of threads to handle per block (determines the compute resources of each core)
    parameter CACHE_SIZE                = 16,     // Instruction cache size in bytes
    parameter LINE_SIZE                 = 4,        // Instruction cache line size in bytes
    parameter PROGRAM_MEM_DATA_READ_NUM = 4        // Number of instructions to read from program memory per cycle
) (
    input  wire                                     clk,
    input  wire                                     reset,

    // Kernel Execution
    input  wire                                     start,
    output wire                                     done,

    // Device Control Register
    input  wire                                     device_control_write_enable,
    input  wire [7:0]                               device_control_data [NUM_CORES-1:0],

    // Program Memory
    output wire [PROGRAM_MEM_NUM_CHANNELS-1:0]      program_mem_read_valid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0]         program_mem_read_address [PROGRAM_MEM_NUM_CHANNELS-1:0],
    input  wire [PROGRAM_MEM_NUM_CHANNELS-1:0]      program_mem_read_ready,
    input  wire [PROGRAM_MEM_DATA_READ_NUM * PROGRAM_MEM_DATA_BITS-1:0]         program_mem_read_data [PROGRAM_MEM_NUM_CHANNELS-1:0],

    // Data Memory  
    output wire [DATA_MEM_NUM_CHANNELS-1:0]         data_mem_read_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0]            data_mem_read_address [DATA_MEM_NUM_CHANNELS-1:0],
    input  wire [DATA_MEM_NUM_CHANNELS-1:0]         data_mem_read_ready,
    input  wire [DATA_MEM_DATA_BITS-1:0]            data_mem_read_data [DATA_MEM_NUM_CHANNELS-1:0],
    output wire [DATA_MEM_NUM_CHANNELS-1:0]         data_mem_write_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0]            data_mem_write_address [DATA_MEM_NUM_CHANNELS-1:0],
    output wire [DATA_MEM_DATA_BITS-1:0]            data_mem_write_data [DATA_MEM_NUM_CHANNELS-1:0],
    input  wire [DATA_MEM_NUM_CHANNELS-1:0]         data_mem_write_ready
);
    // Control
    wire [7:0]                                      thread_count [NUM_CORES-1:0];

    // Compute Core State
    reg  [NUM_CORES-1:0]                            core_start;
    reg  [NUM_CORES-1:0]                            core_reset;
    reg  [NUM_CORES-1:0]                            core_done;
    reg  [7:0]                                      core_block_id [NUM_CORES-1:0];
    reg  [$clog2(THREADS_PER_BLOCK):0]              core_thread_count [NUM_CORES-1:0];

    // core <> Data Memory Controller Channels
    reg  [NUM_CORES-1:0]                            core_read_valid;
    reg  [DATA_MEM_ADDR_BITS-1:0]                   core_read_address [NUM_CORES-1:0];
    reg  [NUM_CORES-1:0]                            core_read_ready;
    reg  [DATA_MEM_DATA_BITS-1:0]                   core_read_data [NUM_CORES-1:0];
    reg  [NUM_CORES-1:0]                            core_write_valid;
    reg  [DATA_MEM_ADDR_BITS-1:0]                   core_write_address [NUM_CORES-1:0];
    reg  [DATA_MEM_DATA_BITS-1:0]                   core_write_data [NUM_CORES-1:0];
    reg  [NUM_CORES-1:0]                            core_write_ready;

    // Fetcher <> Program Memory Controller Channels
    localparam NUM_FETCHERS = NUM_CORES;
    reg  [NUM_FETCHERS-1:0]                       fetcher_read_valid;
    reg  [PROGRAM_MEM_ADDR_BITS-1:0]              fetcher_read_address [NUM_FETCHERS-1:0];
    reg  [NUM_FETCHERS-1:0]                       fetcher_read_ready;
    reg  [PROGRAM_MEM_DATA_READ_NUM * PROGRAM_MEM_DATA_BITS-1:0]              fetcher_read_data [NUM_FETCHERS-1:0];
    
    // Device Control Register
    dcr #(
        .NUM_CORES(NUM_CORES)
    ) dcr_instance (
        .clk                        (clk                        ),
        .reset                      (reset                      ),

        .device_control_write_enable(device_control_write_enable),
        .device_control_data        (device_control_data        ),
        .thread_count               (thread_count               )
    );

    // Data Memory Controller
    controller #(
        .ADDR_BITS                  (DATA_MEM_ADDR_BITS         ),
        .DATA_BITS                  (DATA_MEM_DATA_BITS         ),
        .NUM_CONSUMERS              (NUM_CORES                   ),
        .NUM_CHANNELS               (DATA_MEM_NUM_CHANNELS      ),
        .WRITE_ENABLE               (1                          ),
        .DATA_READ_NUM              (1                          )
    ) data_memory_controller (
        .clk                    (clk                        ),
        .reset                  (reset                      ),

        .consumer_read_valid    (core_read_valid             ),
        .consumer_read_address  (core_read_address           ),
        .consumer_read_ready    (core_read_ready             ),
        .consumer_read_data     (core_read_data              ),
        .consumer_write_valid   (core_write_valid            ),
        .consumer_write_address (core_write_address          ),
        .consumer_write_data    (core_write_data             ),
        .consumer_write_ready   (core_write_ready            ),

        .mem_read_valid         (data_mem_read_valid        ),
        .mem_read_address       (data_mem_read_address      ),
        .mem_read_ready         (data_mem_read_ready        ),
        .mem_read_data          (data_mem_read_data         ),
        .mem_write_valid        (data_mem_write_valid       ),
        .mem_write_address      (data_mem_write_address     ),
        .mem_write_data         (data_mem_write_data        ),
        .mem_write_ready        (data_mem_write_ready       )
    );

    // Program Memory Controller
    controller #(
        .ADDR_BITS              (PROGRAM_MEM_ADDR_BITS      ),
        .DATA_BITS              (PROGRAM_MEM_DATA_BITS      ),
        .NUM_CONSUMERS          (NUM_FETCHERS               ),
        .NUM_CHANNELS           (PROGRAM_MEM_NUM_CHANNELS   ),
        .WRITE_ENABLE           (0                          ),
        .DATA_READ_NUM          (PROGRAM_MEM_DATA_READ_NUM  )
    ) program_memory_controller (
        .clk                    (clk                        ),
        .reset                  (reset                      ),

        .consumer_read_valid    (fetcher_read_valid         ),
        .consumer_read_address  (fetcher_read_address       ),
        .consumer_read_ready    (fetcher_read_ready         ),
        .consumer_read_data     (fetcher_read_data          ),

        .mem_read_valid         (program_mem_read_valid     ),
        .mem_read_address       (program_mem_read_address   ),
        .mem_read_ready         (program_mem_read_ready     ),
        .mem_read_data          (program_mem_read_data      )
    );

    // Dispatcher
    dispatch #(
        .NUM_CORES              (NUM_CORES                  ),
        .THREADS_PER_BLOCK      (THREADS_PER_BLOCK          )
    ) dispatch_instance (   
        .clk                    (clk                        ),
        .reset                  (reset                      ),
        .start                  (start                      ),
        .thread_count           (thread_count               ),
        .core_done              (core_done                  ),
        .core_start             (core_start                 ),
        .core_reset             (core_reset                 ),
        .core_block_id          (core_block_id              ),
        .core_thread_count      (core_thread_count          ),
        .done                   (done                       )
    );

    // Compute Cores
    genvar i;
    generate
        for (i = 0; i < NUM_CORES; i = i + 1) begin : cores
            // EDA: We create separate signals here to pass to cores because of a requirement
            // by the OpenLane EDA flow (uses Verilog 2005) that prevents slicing the top-level signals
            reg                             single_core_read_valid;
            reg [DATA_MEM_ADDR_BITS-1:0]    single_core_read_address;
            reg                             single_core_read_ready;
            reg [DATA_MEM_DATA_BITS-1:0]    single_core_read_data;
            reg                             single_core_write_valid;
            reg [DATA_MEM_ADDR_BITS-1:0]    single_core_write_address;
            reg [DATA_MEM_DATA_BITS-1:0]    single_core_write_data;
            reg                             single_core_write_ready;

            // Pass through signals between core and data memory controller
            // [modify] cancel the relay cycle
            assign core_read_valid  [i]     = single_core_read_valid;
            assign core_read_address[i]     = single_core_read_address;
            assign core_write_valid [i]     = single_core_write_valid;
            assign core_write_address[i]    = single_core_write_address;
            assign core_write_data  [i]     = single_core_write_data;
            
            assign single_core_read_ready   = core_read_ready[i];
            assign single_core_read_data    = core_read_data[i];
            assign single_core_write_ready  = core_write_ready[i];

            // Compute Core
            core #(
                .DATA_MEM_ADDR_BITS         (DATA_MEM_ADDR_BITS     ),
                .DATA_MEM_DATA_BITS         (DATA_MEM_DATA_BITS     ),
                .PROGRAM_MEM_ADDR_BITS      (PROGRAM_MEM_ADDR_BITS  ),
                .PROGRAM_MEM_DATA_BITS      (PROGRAM_MEM_DATA_BITS  ),
                .THREADS_PER_BLOCK          (THREADS_PER_BLOCK      ),
                .CACHE_SIZE                 (CACHE_SIZE             ),
                .LINE_SIZE                  (LINE_SIZE              )
            ) core_instance (
                .clk                        (clk),
                .reset                      (core_reset[i]          ),
                .start                      (core_start[i]          ),
                .done                       (core_done[i]           ),
                .block_id                   (core_block_id[i]       ),
                .thread_count               (core_thread_count[i]   ),
                
                .program_mem_read_valid     (fetcher_read_valid[i]  ),
                .program_mem_read_address   (fetcher_read_address[i]),
                .program_mem_read_ready     (fetcher_read_ready[i]  ),
                .program_mem_read_data      (fetcher_read_data[i]   ),

                .data_mem_read_valid        (single_core_read_valid    ),
                .data_mem_read_address      (single_core_read_address  ),
                .data_mem_read_ready        (single_core_read_ready    ),
                .data_mem_read_data         (single_core_read_data     ),
                .data_mem_write_valid       (single_core_write_valid   ),
                .data_mem_write_address     (single_core_write_address ),
                .data_mem_write_data        (single_core_write_data    ),
                .data_mem_write_ready       (single_core_write_ready   )
            );
        end
    endgenerate
endmodule
