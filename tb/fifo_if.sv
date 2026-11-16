// ============================================================================
// File        : fifo_if.sv
// Author      : Vijay Kumar
// Description : SystemVerilog Verification Interface & Embedded SVA Suite
//               for LP-FWFT Synchronous FIFO
//
// Key Verification Features:
//   1. Race-Free Clocking Blocks:
//      - drv_cb: Applies #1ns output skew after posedge clk to prevent hold-time
//        race conditions between the UVM driver and DUT inputs.
//      - mon_cb: Samples stable pre-clock (#1step) bus states for accurate
//        scoreboard and functional coverage capture.
//   2. Concurrent SystemVerilog Assertions (SVA):
//      - p_never_full_and_empty        : Ensures mutual exclusion of boundary flags.
//      - p_fwft_bypass_latency         : Verifies 0-cycle pass-through when empty && wr_en.
//      - p_operand_isolation           : Confirms rd_data clamps to '0 when idle empty.
//      - p_no_false_underflow_on_bypass: Ensures simultaneous R/W on empty never flags underflow.
// ============================================================================

`timescale 1ns / 1ps

interface fifo_if #(
    parameter int DATA_WIDTH = 32,              // Data word width in bits
    parameter int DEPTH      = 16               // FIFO depth (must match DUT parameter)
) (
    input logic clk,                            // System clock from tb_top
    input logic rst_n                           // Active-low asynchronous reset from tb_top
);

    // ------------------------------------------------------------------------
    // DUT Interface Signals
    // ------------------------------------------------------------------------
    // Producer (Write) Channel
    logic                        wr_en;             // Write enable strobe
    logic [DATA_WIDTH-1:0]       wr_data;           // Write data payload

    // Consumer (Read) Channel
    logic                        rd_en;             // Read acknowledge / pop strobe
    logic [DATA_WIDTH-1:0]       rd_data;           // Combinational FWFT / bypass / clamped output

    // Runtime-Programmable Thresholds
    logic [$clog2(DEPTH):0]      prog_full_thresh;  // Dynamic almost_full threshold
    logic [$clog2(DEPTH):0]      prog_empty_thresh; // Dynamic almost_empty threshold

    // Status, Fault & Occupancy Telemetry
    logic                        full;              // High when occupancy == DEPTH
    logic                        empty;             // High when occupancy == 0
    logic                        almost_full;       // High when occupancy >= prog_full_thresh
    logic                        almost_empty;      // High when occupancy <= prog_empty_thresh
    logic                        overflow;          // High when wr_en asserts while full
    logic                        underflow;         // High when rd_en asserts while empty && !wr_en
    logic [$clog2(DEPTH):0]      data_count;        // Live stored word count (0 to DEPTH)

    // ------------------------------------------------------------------------
    // Driver Clocking Block (Active Stimulus)
    // Drives DUT inputs #1ns after posedge clk to eliminate setup/hold races.
    // ------------------------------------------------------------------------
    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        output wr_en, wr_data, rd_en, prog_full_thresh, prog_empty_thresh;
        input  full, empty, almost_full, almost_empty, overflow, underflow, data_count;
    endclocking

    // ------------------------------------------------------------------------
    // Monitor Clocking Block (Passive Observation)
    // Samples all bus signals #1step before posedge clk for clean UVM capture.
    // ------------------------------------------------------------------------
    clocking mon_cb @(posedge clk);
        default input #1step;
        input wr_en, wr_data, rd_en, rd_data, prog_full_thresh, prog_empty_thresh;
        input full, empty, almost_full, almost_empty, overflow, underflow, data_count;
    endclocking

    // ========================================================================
    // EMBEDDED SYSTEMVERILOG ASSERTIONS (SVA)
    // Continuously checks protocol invariants and low-power features at runtime
    // ========================================================================

    // 1. Boundary Mutual Exclusion: FIFO can never be both full and empty
    property p_never_full_and_empty;
        @(posedge clk) disable iff (!rst_n)
        !(full && empty);
    endproperty
    assert property (p_never_full_and_empty)
        else $error("[SVA FAIL] FIFO asserted FULL and EMPTY simultaneously!");

    // 2. Zero-Cycle FWFT / Cut-Through Bypass Latency Check:
    //    When empty and wr_en is high, rd_data must immediately equal wr_data
    //    on the exact same clock cycle (0-cycle latency).
    property p_fwft_bypass_latency;
        @(posedge clk) disable iff (!rst_n)
        (empty && wr_en) |-> (rd_data == wr_data);
    endproperty
    assert property (p_fwft_bypass_latency)
        else $error("[SVA FAIL] FWFT/Bypass failed: rd_data (%0h) != wr_data (%0h)", rd_data, wr_data);

    // 3. Operand Isolation Low-Power Clamping Check:
    //    When the FIFO is idle and empty (empty && !wr_en), rd_data must stay
    //    clamped to 0 to prevent unnecessary downstream bus toggling.
    property p_operand_isolation;
        @(posedge clk) disable iff (!rst_n)
        (empty && !wr_en) |-> (rd_data == '0);
    endproperty
    assert property (p_operand_isolation)
        else $error("[SVA FAIL] Operand Isolation failed: rd_data != 0 while idle empty!");

    // 4. Cut-Through Bypass Underflow Immunity Check:
    //    Simultaneous read and write on an empty FIFO is a legal cut-through
    //    transfer and must NOT trigger underflow on the following cycle.
    property p_no_false_underflow_on_bypass;
        @(posedge clk) disable iff (!rst_n)
        (empty && wr_en && rd_en) |=> !underflow;
    endproperty
    assert property (p_no_false_underflow_on_bypass)
        else $error("[SVA FAIL] False underflow triggered during legal cut-through bypass!");

endinterface