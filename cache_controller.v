`timescale 1ns/1ps

module cache_controller (
    input clk,
    input reset,
    input read,
    input write,
    input [31:0] address,     
    input [63:0] write_data,
    output reg [63:0] read_data,
    output reg hit,
    output reg miss
);

    localparam BLOCK_SIZE = 64;            
    localparam NUM_SETS = 128;             
    localparam ASSOCIATIVITY = 4;          
    localparam TAG_WIDTH = 19;             

    // Address breakdown
    wire [5:0] offset = address[5:0];      // 6 bits for offset
    wire [6:0] index = address[12:6];      // 7 bits for index 
  	wire [TAG_WIDTH-1:0] tag = address[31:13]; // 19 bits for tag

    // Cache arrays
    reg valid [0:ASSOCIATIVITY-1][0:NUM_SETS-1];
    reg dirty [0:ASSOCIATIVITY-1][0:NUM_SETS-1];
    reg [TAG_WIDTH-1:0] tags [0:ASSOCIATIVITY-1][0:NUM_SETS-1];
    reg [63:0] data_mem [0:ASSOCIATIVITY-1][0:NUM_SETS-1];
    reg [1:0] latched_hit_way;

    // LRU tracking: 2-bit counters per way per set
    reg [1:0] lru_counters [0:ASSOCIATIVITY-1][0:NUM_SETS-1];

    integer i, j;

    // FSM satates
    parameter IDLE=4'b0000;
    parameter CHECK_HIT=4'b0001;
    parameter READ_HIT=4'b0010;
    parameter WRITE_HIT=4'b0011;
    parameter READ_MISS=4'b0100;
    parameter WRITE_MISS=4'b0101;
    parameter EVICT=4'b0110;
    parameter ALLOCATE=4'b0111;
    parameter UPDATE_LRU=4'b1000;

    reg [3:0] state;
    reg [3:0] next_state;

    // Variables for hit detection and chosen way
    reg hit_detected;
    reg next_hit;
    reg next_miss;
    reg [1:0] hit_way;
    reg [1:0] lru_way; // way to evict

    initial begin
        for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
            for (j = 0; j < NUM_SETS; j = j + 1) begin
                valid[i][j] = 0;
                dirty[i][j] = 0;
                tags[i][j] = 0;
                data_mem[i][j] = 0;
                lru_counters[i][j] = i; // initial LRU state (0..3)
            end
        end
        state = IDLE;
        read_data = 64'b0;
        hit = 0;
        miss = 0;
        latched_hit_way = 0;
        hit_detected = 0;
        next_hit = 0;
        next_miss = 0;
    end

    //state transitions
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            hit <= 0;
            miss <= 0;
            read_data <= 64'b0;
            latched_hit_way <= 0;
            hit_detected <= 0;
        end else begin
            state <= next_state;
        end
    end

    // FSM combinational logic
    always @(*) begin
        next_state = state;
        next_hit = 0;
        next_miss = 0;
      
        case(state)
            IDLE: begin
                if (read || write)
                    next_state = CHECK_HIT;
            end

            CHECK_HIT: begin
                hit_detected = 0;
                hit_way = 0;
                for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                    if (valid[i][index] && tags[i][index] == tag) begin
                        hit_detected = 1;
                        hit_way = i[1:0];
                    end
                end
                if (hit_detected) begin
                    next_hit = 1;
                    if (read)
                        next_state = READ_HIT;
                    else
                        next_state = WRITE_HIT;
                end else begin
                    next_miss = 1;
                    if (read)
                        next_state = READ_MISS;
                    else
                        next_state = WRITE_MISS;
                end
            end

            READ_HIT: begin
                next_hit = 1;
                next_state = UPDATE_LRU;
            end

            WRITE_HIT: begin
                next_hit = 1;
                next_state = UPDATE_LRU;
            end

            READ_MISS: begin
                next_miss = 1;
                next_state = EVICT;
            end

            WRITE_MISS: begin
                next_miss = 1;
                next_state = EVICT;
            end

            EVICT: begin
                next_state = ALLOCATE;
            end

            ALLOCATE: begin
                if (write)
                    next_state = UPDATE_LRU;
              if(read) next_state=IDLE;
            end

            UPDATE_LRU: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // Register hit and miss outputs from next_hit and next_miss
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            hit <= 0;
            miss <= 0;
        end else begin
            hit <= next_hit;
            miss <= next_miss;
        end
    end

    // Latch hit_way and hit_detected at CHECK_HIT state on clock edge
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            latched_hit_way <= 0;
            hit_detected <= 0;
        end 
      	else if (state == CHECK_HIT) begin
            latched_hit_way <= hit_way;
        end
    end

    // Main FSM sequential actions
    always @(posedge clk) begin
        if (reset) begin
            // reset done above
        end else begin
            case(state)
                READ_HIT: begin
                    read_data <= data_mem[latched_hit_way][index];
                end

                WRITE_HIT: begin
                    data_mem[latched_hit_way][index] <= write_data;
                    dirty[latched_hit_way][index] <= 1;
                end

                READ_MISS, WRITE_MISS: begin
                    // Find LRU way (max lru counter)
                    lru_way = 0;
                    for (i = 1; i < ASSOCIATIVITY; i = i + 1) begin
                        if (lru_counters[i][index] > lru_counters[lru_way][index])
                            lru_way = i[1:0];
                    end
                end

                EVICT: begin
                    if (dirty[lru_way][index]) begin
                        dirty[lru_way][index] <= 0;
                    end
                end

                ALLOCATE: begin
                    valid[lru_way][index] <= 1;
                    tags[lru_way][index] <= tag;
                    dirty[lru_way][index] <= (write) ? 1 : 0;
                    if (write)
                        data_mem[lru_way][index] <= write_data;
                    else
                        data_mem[lru_way][index] <= 64'b0; // simulate loading from memory
                end

                UPDATE_LRU: begin
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                        if (i == latched_hit_way)
                            lru_counters[i][index] <= 0;
                        else if (lru_counters[i][index] < lru_counters[latched_hit_way][index])
                            lru_counters[i][index] <= lru_counters[i][index] + 1;
                    end
                end
            endcase
        end
    end

endmodule