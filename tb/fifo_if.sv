`timescale 1ns / 1ps

interface fifo_if #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH      = 16
) (
    input logic clk,
    input logic rst_n
);
    logic                        wr_en;
    logic [DATA_WIDTH-1:0]       wr_data;
    logic                        rd_en;
    logic [DATA_WIDTH-1:0]       rd_data;
    logic [$clog2(DEPTH):0]      prog_full_thresh;
    logic [$clog2(DEPTH):0]      prog_empty_thresh;
    logic                        full;
    logic                        empty;
    logic                        almost_full;
    logic                        almost_empty;
    logic                        overflow;
    logic                        underflow;
    logic [$clog2(DEPTH):0]      data_count;

    // Driver clocking block (eliminates hold-time race conditions)
    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        output wr_en, wr_data, rd_en, prog_full_thresh, prog_empty_thresh;
        input  full, empty, almost_full, almost_empty, overflow, underflow, data_count;
    endclocking

    // Monitor clocking block (samples stable post-clock values)
    clocking mon_cb @(posedge clk);
        default input #1step;
        input wr_en, wr_data, rd_en, rd_data, prog_full_thresh, prog_empty_thresh;
        input full, empty, almost_full, almost_empty, overflow, underflow, data_count;
    endclocking

    //-------------------------------------------------------------------------
    // EMBEDDED SYSTEMVERILOG ASSERTIONS (SVA)
    //-------------------------------------------------------------------------
    // 1. Mutual Exclusion: FIFO must never report both full and empty
    property p_never_full_and_empty;
        @(posedge clk) disable iff (!rst_n)
        !(full && empty);
    endproperty
    assert property (p_never_full_and_empty)
        else $error("[SVA FAIL] FIFO asserted FULL and EMPTY simultaneously!");

    // 2. Cut-Through Bypass Latency Check:
    // When empty & wr_en is asserted, rd_data must immediately reflect wr_data
    property p_fwft_bypass_latency;
        @(posedge clk) disable iff (!rst_n)
        (empty && wr_en) |-> (rd_data == wr_data);
    endproperty
    assert property (p_fwft_bypass_latency)
        else $error("[SVA FAIL] FWFT/Bypass failed: rd_data (%0h) != wr_data (%0h)", rd_data, wr_data);

    // 3. Operand Isolation Power Check:
    // When idle empty (empty && !wr_en), rd_data must clamp to 0
    property p_operand_isolation;
        @(posedge clk) disable iff (!rst_n)
        (empty && !wr_en) |-> (rd_data == '0);
    endproperty
    assert property (p_operand_isolation)
        else $error("[SVA FAIL] Operand Isolation failed: rd_data != 0 while idle empty!");

    // 4. Legal Bypass Must Not Trigger Underflow:
    property p_no_false_underflow_on_bypass;
        @(posedge clk) disable iff (!rst_n)
        (empty && wr_en && rd_en) |=> !underflow;
    endproperty
    assert property (p_no_false_underflow_on_bypass)
        else $error("[SVA FAIL] False underflow triggered during legal cut-through bypass!");

endinterface