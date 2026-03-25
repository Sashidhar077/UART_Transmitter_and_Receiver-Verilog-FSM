// =============================================================
//  uart_tb.v  -  Self-Checking UART Testbench
//
//  Compatible with: Icarus Verilog (iverilog + vvp)
//                   ModelSim / Questa
//
//  Waveform dump: uart_wave.vcd  (open with GTKWave)
//
//  Test plan
//    1. Single byte 8'hA5  – basic loopback
//    2. All-zeros  8'h00
//    3. All-ones   8'hFF
//    4. Sweep 8'h00..8'hFF (256 bytes)
//    5. Back-to-back two bytes
//    Reports PASS / FAIL per test and a final summary.
// =============================================================
`timescale 1ns/1ps

module uart_tb;

    // ---------------------------------------------------------
    //  Parameters – must match DUT parameters
    // ---------------------------------------------------------
    localparam CLK_FREQ  = 50_000_000;
    localparam BAUD_RATE = 115_200;
    localparam DATA_BITS = 8;
    localparam PARITY    = 0;
    localparam STOP_BITS = 1;

    localparam CLK_PERIOD = 1_000_000_000 / CLK_FREQ; // ns

    // One bit period in ns (for timeout calculations)
    localparam BIT_PERIOD_NS = 1_000_000_000 / BAUD_RATE;
    // Full frame: start + data + stop bits
    localparam FRAME_NS  = BIT_PERIOD_NS * (1 + DATA_BITS + STOP_BITS + 10);

    // ---------------------------------------------------------
    //  DUT signals
    // ---------------------------------------------------------
    reg  clk, rst_n;
    wire baud_tick;
    reg  tx_start;
    reg  [DATA_BITS-1:0] tx_data;
    wire tx_busy, tx_serial;
    wire [DATA_BITS-1:0] rx_data;
    wire rx_done, frame_error, parity_error;

    // ---------------------------------------------------------
    //  Instantiate DUT chain:  baud_gen -> uart_tx -> uart_rx
    //  TX serial output wired directly to RX input (loopback)
    // ---------------------------------------------------------
    baud_gen #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_baud (
        .clk  (clk),
        .rst_n(rst_n),
        .tick (baud_tick)
    );

    uart_tx #(
        .DATA_BITS(DATA_BITS),
        .PARITY   (PARITY),
        .STOP_BITS(STOP_BITS)
    ) u_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .baud_tick(baud_tick),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx_busy  (tx_busy),
        .tx       (tx_serial)
    );

    uart_rx #(
        .DATA_BITS(DATA_BITS),
        .PARITY   (PARITY),
        .STOP_BITS(STOP_BITS)
    ) u_rx (
        .clk         (clk),
        .rst_n       (rst_n),
        .baud_tick   (baud_tick),
        .rx          (tx_serial),   // loopback
        .rx_data     (rx_data),
        .rx_done     (rx_done),
        .frame_error (frame_error),
        .parity_error(parity_error)
    );

    // ---------------------------------------------------------
    //  Clock generation  (50 MHz -> 20 ns period)
    // ---------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---------------------------------------------------------
    //  Waveform dump for GTKWave
    // ---------------------------------------------------------
    initial begin
        $dumpfile("uart_wave.vcd");
        $dumpvars(0, uart_tb);
    end

    // ---------------------------------------------------------
    //  Test counters
    // ---------------------------------------------------------
    integer pass_cnt, fail_cnt;

    // ---------------------------------------------------------
    //  Task: send one byte and check received value
    // ---------------------------------------------------------
    task send_and_check;
        input [DATA_BITS-1:0] byte_in;
        input [63:0]          test_num;
        integer timeout;
        begin
            // Apply stimulus
            @(posedge clk);
            tx_data  <= byte_in;
            tx_start <= 1'b1;
            @(posedge clk);
            tx_start <= 1'b0;

            // Wait for rx_done with timeout
            timeout = 0;
            while (!rx_done && timeout < FRAME_NS) begin
                #(CLK_PERIOD);
                timeout = timeout + CLK_PERIOD;
            end

            // Evaluate
            if (timeout >= FRAME_NS) begin
                $display("[FAIL] Test %0d: TIMEOUT waiting for rx_done  (sent 0x%02X)",
                         test_num, byte_in);
                fail_cnt = fail_cnt + 1;
            end else if (frame_error) begin
                $display("[FAIL] Test %0d: FRAME ERROR  (sent 0x%02X)", test_num, byte_in);
                fail_cnt = fail_cnt + 1;
            end else if (parity_error) begin
                $display("[FAIL] Test %0d: PARITY ERROR (sent 0x%02X)", test_num, byte_in);
                fail_cnt = fail_cnt + 1;
            end else if (rx_data !== byte_in) begin
                $display("[FAIL] Test %0d: DATA MISMATCH sent=0x%02X  got=0x%02X",
                         test_num, byte_in, rx_data);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("[PASS] Test %0d: sent=0x%02X  received=0x%02X", test_num, byte_in, rx_data);
                pass_cnt = pass_cnt + 1;
            end

            // Wait for line to go idle before next frame
            @(posedge clk);
            wait (!tx_busy);
            #(BIT_PERIOD_NS * 2);
        end
    endtask

    // ---------------------------------------------------------
    //  Main test sequence
    // ---------------------------------------------------------
    initial begin
        pass_cnt = 0;
        fail_cnt = 0;

        // -- Reset --
        rst_n    = 0;
        tx_start = 0;
        tx_data  = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5)  @(posedge clk);

        $display("============================================");
        $display("  UART Loopback Testbench  (%0d baud)", BAUD_RATE);
        $display("============================================");

        // Test 1 – walking pattern
        $display("\n--- Test Group 1: Key bytes ---");
        send_and_check(8'hA5, 1);
        send_and_check(8'h00, 2);
        send_and_check(8'hFF, 3);
        send_and_check(8'h55, 4);
        send_and_check(8'hAA, 5);

        // Test 2 – full sweep
        $display("\n--- Test Group 2: Full 0x00-0xFF sweep ---");
        begin : sweep
            integer i;
            for (i = 0; i < 256; i = i + 1)
                send_and_check(i[7:0], 100 + i);
        end

        // Test 3 – back-to-back (minimal gap)
        $display("\n--- Test Group 3: Back-to-back ---");
        send_and_check(8'h12, 400);
        send_and_check(8'h34, 401);
        send_and_check(8'h56, 402);

        // ----- Summary -----
        $display("\n============================================");
        $display("  Results:  %0d PASSED  |  %0d FAILED", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** SOME TESTS FAILED - check log above ***");
        $display("============================================\n");

        $finish;
    end

    // ---------------------------------------------------------
    //  Safety watchdog – kills sim if it hangs
    // ---------------------------------------------------------
    initial begin
        #500_000_000;   // 500 ms sim time limit
        $display("[WATCHDOG] Simulation exceeded time limit – aborting.");
        $finish;
    end

endmodule
