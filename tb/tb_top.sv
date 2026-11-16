`timescale 1ns / 1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import fifo_pkg::*;

module tb_top;
    logic clk;
    logic rst_n;

    // 200 MHz Clock (5ns period)
    initial begin
        clk = 0;
        forever #2.5ns clk = ~clk;
    end

    // Active-Low Reset
    initial begin
        rst_n = 0;
        #20ns rst_n = 1;
    end

    // Instantiate Interface
    fifo_if #(.DATA_WIDTH(DATA_W), .DEPTH(DEPTH_P)) vif (.clk(clk), .rst_n(rst_n));

    // Instantiate Optimized Low-Power FWFT + Bypass DUT
    lp_fwft_fifo #(
        .DATA_WIDTH(DATA_W),
        .DEPTH(DEPTH_P)
    ) dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .wr_en             (vif.wr_en),
        .wr_data           (vif.wr_data),
        .rd_en             (vif.rd_en),
        .rd_data           (vif.rd_data),
        .prog_full_thresh  (vif.prog_full_thresh),
        .prog_empty_thresh (vif.prog_empty_thresh),
        .full              (vif.full),
        .empty             (vif.empty),
        .almost_full       (vif.almost_full),
        .almost_empty      (vif.almost_empty),
        .overflow          (vif.overflow),
        .underflow         (vif.underflow),
        .data_count        (vif.data_count)
    );

    // Start UVM Test
    initial begin
        uvm_config_db#(virtual fifo_if #(DATA_W, DEPTH_P))::set(null, "*", "vif", vif);
        run_test("fifo_test");
    end
endmodule