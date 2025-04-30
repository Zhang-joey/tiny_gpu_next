`default_nettype none
`timescale 1ns/1ns

// DEVICE CONTROL REGISTER
// > Used to configure high-level settings
// > In this minimal example, the DCR is used to configure the number of threads to run for the kernel
module dcr #(
    parameter NUM_CORES = 2
) (
    input wire clk,
    input wire reset,

    input wire device_control_write_enable,
    input wire [7:0] device_control_data [NUM_CORES-1:0],
    output reg [7:0] thread_count [NUM_CORES-1:0]
);
    // Store device control data in dedicated register

    always @(posedge clk) begin
        if (reset) begin
            for (int i = 0; i < NUM_CORES; i++) begin
                thread_count[i] <= 8'b0;
            end
        end else begin
            if (device_control_write_enable) begin 
                thread_count <= device_control_data;
            end
        end
    end
endmodule