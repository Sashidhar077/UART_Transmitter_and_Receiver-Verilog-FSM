// =============================================================
//  uart_rx.v  -  UART Receiver  (16x oversampling)
//
//  Parameters match uart_tx.v
//
//  Interface
//    baud_tick    : 16x oversampling tick
//    rx           : serial input line
//    rx_data      : received parallel byte (valid when rx_done=1)
//    rx_done      : 1-cycle pulse when a full frame is received
//    frame_error  : high if stop bit is 0  (framing error)
//    parity_error : high if parity mismatch (only when PARITY!=0)
//
//  Oversampling strategy
//    - On falling edge of rx (start bit detected), reset tick counter
//    - Sample DATA bits at tick 7, 8, 9 and majority-vote
//    - This centres the sample window in the middle of each bit
// =============================================================
module uart_rx #(
    parameter DATA_BITS = 8,
    parameter PARITY    = 0,
    parameter STOP_BITS = 1
)(
    input  wire clk,
    input  wire rst_n,
    input  wire baud_tick,
    input  wire rx,
    output reg  [DATA_BITS-1:0] rx_data,
    output reg  rx_done,
    output reg  frame_error,
    output reg  parity_error
);
    localparam [2:0]
        IDLE      = 3'd0,
        START     = 3'd1,
        DATA      = 3'd2,
        PARITY_ST = 3'd3,
        STOP      = 3'd4;

    reg [2:0] state;
    reg [3:0] tick_cnt;
    reg [3:0] bit_idx;
    reg [DATA_BITS-1:0] shift_reg;

    // Majority vote sample registers (ticks 7,8,9)
    reg s7, s8, s9;

    // Majority vote function
    function majority;
        input a, b, c;
        majority = (a & b) | (b & c) | (a & c);
    endfunction

    // Expected parity
    wire expected_parity;
    generate
        if (PARITY == 1)
            assign expected_parity = ~^shift_reg;
        else if (PARITY == 2)
            assign expected_parity = ^shift_reg;
        else
            assign expected_parity = 1'b0;
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            tick_cnt     <= 0;
            bit_idx      <= 0;
            shift_reg    <= 0;
            rx_data      <= 0;
            rx_done      <= 1'b0;
            frame_error  <= 1'b0;
            parity_error <= 1'b0;
            s7 <= 0; s8 <= 0; s9 <= 0;
        end else begin
            rx_done      <= 1'b0;
            frame_error  <= 1'b0;
            parity_error <= 1'b0;

            case (state)
                // -------------------------------------------------
                IDLE: begin
                    if (!rx) begin       // falling edge = start bit
                        tick_cnt <= 0;
                        state    <= START;
                    end
                end

                // -------------------------------------------------
                //  Wait 8 ticks to hit the centre of the start bit
                //  and confirm it is still 0 (not a glitch).
                // -------------------------------------------------
                START: begin
                    if (baud_tick) begin
                        if (tick_cnt == 7) begin
                            if (!rx) begin
                                tick_cnt <= 0;
                                bit_idx  <= 0;
                                state    <= DATA;
                            end else
                                state <= IDLE;  // glitch, abort
                        end else
                            tick_cnt <= tick_cnt + 1;
                    end
                end

                // -------------------------------------------------
                DATA: begin
                    if (baud_tick) begin
                        tick_cnt <= tick_cnt + 1;
                        // Capture three samples around the bit centre
                        if (tick_cnt == 7)  s7 <= rx;
                        if (tick_cnt == 8)  s8 <= rx;
                        if (tick_cnt == 9)  s9 <= rx;

                        if (tick_cnt == 15) begin
                            tick_cnt  <= 0;
                            // Shift majority-voted bit in from MSB side, then reverse
                            shift_reg <= {majority(s7,s8,s9), shift_reg[DATA_BITS-1:1]};
                            if (bit_idx == DATA_BITS - 1) begin
                                bit_idx <= 0;
                                state   <= (PARITY != 0) ? PARITY_ST : STOP;
                            end else
                                bit_idx <= bit_idx + 1;
                        end
                    end
                end

                // -------------------------------------------------
                PARITY_ST: begin
                    if (baud_tick) begin
                        tick_cnt <= tick_cnt + 1;
                        if (tick_cnt == 7)  s7 <= rx;
                        if (tick_cnt == 8)  s8 <= rx;
                        if (tick_cnt == 9)  s9 <= rx;
                        if (tick_cnt == 15) begin
                            tick_cnt <= 0;
                            // Check parity after DATA bits are locked
                            if (majority(s7,s8,s9) !== expected_parity)
                                parity_error <= 1'b1;
                            state <= STOP;
                        end
                    end
                end

                // -------------------------------------------------
                STOP: begin
                    if (baud_tick) begin
                        tick_cnt <= tick_cnt + 1;
                        if (tick_cnt == 15) begin
                            tick_cnt <= 0;
                            if (!rx)
                                frame_error <= 1'b1;
                            else begin
                                rx_data <= shift_reg;
                                rx_done <= 1'b1;
                            end
                            state <= IDLE;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
