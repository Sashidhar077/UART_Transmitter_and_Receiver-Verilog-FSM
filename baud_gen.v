// =============================================================
//  baud_gen.v  -  Baud Rate Generator (16x oversampling tick)
//  CLK_FREQ  : system clock in Hz   (default 50 MHz)
//  BAUD_RATE : desired baud rate    (default 115200)
//
//  Outputs a single-cycle pulse "tick" at 16 x baud rate.
//  TX counts 16 ticks per bit; RX samples at tick 7/8/9.
// =============================================================
module baud_gen #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire clk,
    input  wire rst_n,
    output reg  tick
);
    localparam integer DIVISOR = CLK_FREQ / (BAUD_RATE * 16);
    localparam integer CTR_W   = $clog2(DIVISOR);

    reg [CTR_W-1:0] counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
            tick    <= 1'b0;
        end else if (counter == DIVISOR - 1) begin
            counter <= 0;
            tick    <= 1'b1;
        end else begin
            counter <= counter + 1;
            tick    <= 1'b0;
        end
    end
endmodule
