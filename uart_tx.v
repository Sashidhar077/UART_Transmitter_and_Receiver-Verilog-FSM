// =============================================================
//  uart_tx.v  -  UART Transmitter
//
//  Parameters
//    DATA_BITS : 7 or 8  (default 8)
//    PARITY    : 0=none  1=odd  2=even
//    STOP_BITS : 1 or 2  (default 1)
//
//  Interface
//    baud_tick : 16x oversampling tick from baud_gen
//    tx_start  : pulse high for 1 clk to begin transmission
//    tx_data   : parallel data byte to transmit
//    tx_busy   : high while frame is being sent
//    tx        : serial output line (idle = 1)
//
//  FSM states: IDLE -> START -> DATA -> PARITY -> STOP -> IDLE
// =============================================================
module uart_tx #(
    parameter DATA_BITS = 8,
    parameter PARITY    = 0,
    parameter STOP_BITS = 1
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             baud_tick,   // 16x tick
    input  wire             tx_start,
    input  wire [DATA_BITS-1:0] tx_data,
    output reg              tx_busy,
    output reg              tx
);
    // FSM state encoding
    localparam [2:0]
        IDLE   = 3'd0,
        START  = 3'd1,
        DATA   = 3'd2,
        PARITY_ST = 3'd3,
        STOP   = 3'd4;

    reg [2:0] state;
    reg [3:0] tick_cnt;   // counts 0-15 (one full bit = 16 ticks)
    reg [3:0] bit_idx;    // which data bit we are sending
    reg [DATA_BITS-1:0] shift_reg;
    reg [3:0] stop_cnt;   // counts stop bits

    // Parity computation
    wire parity_bit;
    generate
        if (PARITY == 1)       // odd parity
            assign parity_bit = ~^tx_data;
        else if (PARITY == 2)  // even parity
            assign parity_bit = ^tx_data;
        else
            assign parity_bit = 1'b0;
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            tx        <= 1'b1;
            tx_busy   <= 1'b0;
            tick_cnt  <= 0;
            bit_idx   <= 0;
            shift_reg <= 0;
            stop_cnt  <= 0;
        end else begin
            case (state)
                // -------------------------------------------------
                IDLE: begin
                    tx      <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        tx_busy   <= 1'b1;
                        tick_cnt  <= 0;
                        bit_idx   <= 0;
                        state     <= START;
                    end
                end

                // -------------------------------------------------
                START: begin
                    tx <= 1'b0;          // start bit
                    if (baud_tick) begin
                        if (tick_cnt == 15) begin
                            tick_cnt <= 0;
                            state    <= DATA;
                        end else
                            tick_cnt <= tick_cnt + 1;
                    end
                end

                // -------------------------------------------------
                DATA: begin
                    tx <= shift_reg[0];  // LSB first
                    if (baud_tick) begin
                        if (tick_cnt == 15) begin
                            tick_cnt  <= 0;
                            shift_reg <= shift_reg >> 1;
                            if (bit_idx == DATA_BITS - 1) begin
                                bit_idx <= 0;
                                state   <= (PARITY != 0) ? PARITY_ST : STOP;
                                stop_cnt<= 0;
                            end else
                                bit_idx <= bit_idx + 1;
                        end else
                            tick_cnt <= tick_cnt + 1;
                    end
                end

                // -------------------------------------------------
                PARITY_ST: begin
                    tx <= parity_bit;
                    if (baud_tick) begin
                        if (tick_cnt == 15) begin
                            tick_cnt <= 0;
                            stop_cnt <= 0;
                            state    <= STOP;
                        end else
                            tick_cnt <= tick_cnt + 1;
                    end
                end

                // -------------------------------------------------
                STOP: begin
                    tx <= 1'b1;          // stop bit(s)
                    if (baud_tick) begin
                        if (tick_cnt == 15) begin
                            tick_cnt <= 0;
                            if (stop_cnt == STOP_BITS - 1)
                                state <= IDLE;
                            else
                                stop_cnt <= stop_cnt + 1;
                        end else
                            tick_cnt <= tick_cnt + 1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
