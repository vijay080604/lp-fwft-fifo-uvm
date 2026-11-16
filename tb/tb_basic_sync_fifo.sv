`timescale 1ns / 1ps

module tb_basic_sync_fifo;

    localparam int DATA_WIDTH = 32;
    localparam int DEPTH      = 16;
    localparam real CLK_PERIOD = 5.0; // 200 MHz target clock for benchmarking

    logic                   clk;
    logic                   rst_n;
    logic                   wr_en;
    logic [DATA_WIDTH-1:0]  wr_data;
    logic                   rd_en;
    logic [DATA_WIDTH-1:0]  rd_data;
    logic                   full;
    logic                   empty;
    logic                   almost_full;
    logic                   almost_empty;

    // Reference model queue & tracking variables
    logic [DATA_WIDTH-1:0]  ref_q[$];
    logic [DATA_WIDTH-1:0]  expected_rd_data;
    logic                   check_rd_next_cycle;
    int                     pass_count = 0;
    int                     fail_count = 0;

    // Instantiate Baseline DUT
    basic_sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH     (DEPTH)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .wr_en       (wr_en),
        .wr_data     (wr_data),
        .rd_en       (rd_en),
        .rd_data     (rd_data),
        .full        (full),
        .empty       (empty),
        .almost_full (almost_full),
        .almost_empty(almost_empty)
    );

    // 200 MHz Clock Generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2.0) clk = ~clk;
    end

    // Scoreboard / Self-Checker (Models 1-Cycle Registered Read Latency)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ref_q.delete();
            check_rd_next_cycle <= 1'b0;
            expected_rd_data    <= '0;
        end else begin
            // 1. Verify data read from previous cycle (1-cycle latency)
            if (check_rd_next_cycle) begin
                if (rd_data === expected_rd_data) begin
                    pass_count++;
                end else begin
                    $error("[FAIL] Time=%0t | Expected rd_data=0x%08h, Got=0x%08h",
                           $time, expected_rd_data, rd_data);
                    fail_count++;
                end
            end

            // 2. Schedule read check if valid read occurs on this edge
            if (rd_en && !empty) begin
                expected_rd_data    <= ref_q.pop_front();
                check_rd_next_cycle <= 1'b1;
            end else begin
                check_rd_next_cycle <= 1'b0;
            end

            // 3. Push write data into golden queue if valid write occurs
            if (wr_en && !full) begin
                ref_q.push_back(wr_data);
            end
        end
    end

    // Helper task to apply stimulus cleanly before clock edge
    task drive_cycle(input logic w, input logic r, input logic [DATA_WIDTH-1:0] data);
        @(negedge clk);
        wr_en   = w;
        rd_en   = r;
        wr_data = data;
    endtask

    // Main Stimulus Sequence
    initial begin
        // Initialize & Reset
        rst_n   = 1'b0;
        wr_en   = 1'b0;
        rd_en   = 1'b0;
        wr_data = '0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;

        // Check Post-Reset Flags
        assert (empty && !full && almost_empty && !almost_full)
            else $error("[FAIL] Post-reset flags incorrect!");

        $display("--- Phase 1: Fill FIFO to FULL + Overflow Protection ---");
        for (int i = 0; i < DEPTH + 3; i++) begin
            drive_cycle(1'b1, 1'b0, 32'hA000_0000 + i);
        end
        drive_cycle(1'b0, 1'b0, '0);
        @(posedge clk); #1;
        assert (full && !empty && almost_full)
            else $error("[FAIL] FIFO should be FULL after %0d writes!", DEPTH);

        $display("--- Phase 2: Drain FIFO to EMPTY + Underflow Protection ---");
        for (int i = 0; i < DEPTH + 3; i++) begin
            drive_cycle(1'b0, 1'b1, '0);
        end
        drive_cycle(1'b0, 1'b0, '0);
        @(posedge clk); #1;
        assert (empty && !full && almost_empty)
            else $error("[FAIL] FIFO should be EMPTY after draining!");

        $display("--- Phase 3: 200 Constrained-Random Simultaneous R/W Cycles ---");
        for (int i = 0; i < 200; i++) begin
            drive_cycle($urandom_range(0, 1), $urandom_range(0, 1), $urandom());
        end
        drive_cycle(1'b0, 1'b0, '0);
        repeat (3) @(posedge clk);

        // Final Summary Report
        $display("\n=======================================================");
        $display(" BASELINE FIFO VERIFICATION COMPLETE");
        $display(" PASSED TRANSFERS: %0d | FAILED TRANSFERS: %0d", pass_count, fail_count);
        $display("=======================================================\n");
        $finish;
    end

endmodule