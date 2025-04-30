`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION CACHE
// > Ϊÿ�������ṩָ��湦��
// > ʹ��ֱ��ӳ�仺��ṹ
// > ֧��ָ��Ԥȡ
module cache #(
    parameter CACHE_SIZE = 16,        // �����ܴ�С(ָ����)
    parameter LINE_SIZE = 4,           // �����д�С(ָ����, ÿ��4·ָ��)
    parameter MEM_ADDR_BITS = 8,
    parameter MEM_DATA_BITS = 16,
    parameter MEM_DATA_READ_NUM = 4 //program�Ķ�ȡλ��(ָ����,4��ָ��)
) (
    input wire clk,
    input wire reset,
    
    // ���Ժ��ĵ�����
    input wire [MEM_ADDR_BITS-1:0] addr,
    input wire request_valid,
    output reg request_ready,
    output reg [MEM_DATA_BITS-1:0] instruction,
    
    // �����洢���Ľӿ�
    output reg mem_read_valid,
    output reg [MEM_ADDR_BITS-1:0] mem_read_address,
    input wire mem_read_ready,
    input wire [MEM_DATA_READ_NUM * MEM_DATA_BITS-1:0] mem_read_data
);

    // �����������
    localparam NUM_LINES = CACHE_SIZE / LINE_SIZE;  //����
    localparam LINE_ADDR_BITS = $clog2(LINE_SIZE);  //offsetλ��(2bit)
    localparam INDEX_BITS = $clog2(NUM_LINES);      //indexλ��(2bit)
    localparam TAG_BITS = MEM_ADDR_BITS - INDEX_BITS - LINE_ADDR_BITS;//tagλ��(4bit)
    localparam DATA_WRITE_NUM = (MEM_DATA_READ_NUM > LINE_SIZE) ? LINE_SIZE : MEM_DATA_READ_NUM;//���mem�������LINE_SIZE,��һ��д��һ��cacheline
    
    // ����洢
    reg [MEM_DATA_BITS-1:0] cache_data [NUM_LINES-1:0][LINE_SIZE-1:0];
    reg [TAG_BITS-1:0] cache_tags [NUM_LINES-1:0];
    reg cache_valid [NUM_LINES-1:0];
    
    // ״̬��״̬
    localparam IDLE = 2'b00,
               LOOKUP = 2'b01,
               MISS = 2'b10,
               FILL = 2'b11;
    
    reg [1:0] state;
    
    // ������ʿ����ź�
    reg [INDEX_BITS-1:0] current_index;
    reg [TAG_BITS-1:0] current_tag;
    reg [LINE_ADDR_BITS-1:0] current_offset;
    reg [LINE_ADDR_BITS-1:0] fill_counter;
    
    // ��ַ����
    always @(*) begin
        current_tag     = addr[MEM_ADDR_BITS-1 : INDEX_BITS+LINE_ADDR_BITS];
        current_index   = addr[INDEX_BITS+LINE_ADDR_BITS-1 : LINE_ADDR_BITS];
        current_offset  = addr[LINE_ADDR_BITS-1 : 0];
    end
    
    // ״̬��
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            request_ready <= 0;
            mem_read_valid <= 0;
            fill_counter <= 0;
            mem_read_address <= 0;
            instruction <= 0;
            for (int i = 0; i < NUM_LINES; i++) begin
                cache_valid[i] <= 0;
                cache_tags[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (request_valid) begin
                        state <= LOOKUP;
                    end
                end
                
                LOOKUP: begin
                    if (cache_valid[current_index] && cache_tags[current_index] == current_tag) begin
                        // ��������
                        instruction <= cache_data[current_index][current_offset];
                        request_ready <= 1;
                        if (!request_valid) begin
                            state <= IDLE;
                            request_ready <= 0;
                        end
                    end else begin
                        // ����δ����
                        state <= MISS;
                        request_ready <= 0;
                    end
                end
                
                MISS: begin
                    mem_read_valid <= 1;
                    mem_read_address <= {current_tag, current_index, {LINE_ADDR_BITS{1'b0}}};
                    fill_counter <= 0;
                    state <= FILL;
                end
                
                FILL: begin
                    if (mem_read_ready) begin
                        for (int i = 0; i < DATA_WRITE_NUM; i++) begin
                            cache_data[current_index][i+fill_counter] <= mem_read_data[i * MEM_DATA_BITS +: MEM_DATA_BITS];
                        end
                        if (fill_counter == LINE_SIZE-DATA_WRITE_NUM) begin
                            cache_valid[current_index] <= 1;
                            cache_tags[current_index] <= current_tag;
                            mem_read_valid <= 0;
                            state <= LOOKUP;
                        end else begin
                            fill_counter <= fill_counter + DATA_WRITE_NUM;
                            mem_read_address <= mem_read_address + DATA_WRITE_NUM;
                            mem_read_valid <= 0;
                        end
                    end
                    else begin
                        mem_read_valid <= 1;
                    end
                end
            endcase
        end
    end
    
endmodule 