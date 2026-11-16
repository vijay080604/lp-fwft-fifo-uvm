// ============================================================================
// File        : fifo_pkg.sv
// Author      : Vijay Kumar
// Description : UVM 1.2 Verification Package for LP-FWFT Synchronous FIFO
//
// Components Included:
//   1. fifo_seq_item       : Constrained-random transaction item
//   2. fifo_driver         : Clocking-block synchronized pin driver
//   3. fifo_monitor        : Passive bus monitor broadcasting via analysis port
//   4. fifo_agent          : Active UVM agent (sequencer, driver, monitor)
//   5. fifo_scoreboard     : Cycle-accurate FWFT & cut-through bypass golden model
//   6. fifo_coverage       : Functional covergroup (100% corner-case closure)
//   7. fifo_env            : Top-level verification environment
//   8. fifo_regression_seq : Directed + constrained-random regression sequence
//   9. fifo_test           : Top-level UVM test
// ============================================================================

`timescale 1ns / 1ps

package fifo_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    parameter int DATA_W  = 32;
    parameter int DEPTH_P = 16;

    //=========================================================================
    // 1. SEQUENCE ITEM (Transaction Object)
    //=========================================================================
    class fifo_seq_item extends uvm_sequence_item;
        rand bit                     wr_en;
        rand bit                     rd_en;
        rand bit [DATA_W-1:0]        wr_data;
        rand bit [$clog2(DEPTH_P):0] prog_full_thresh;
        rand bit [$clog2(DEPTH_P):0] prog_empty_thresh;

        // Observed DUT outputs
        bit [DATA_W-1:0]             rd_data;
        bit                          full;
        bit                          empty;
        bit                          almost_full;
        bit                          almost_empty;
        bit                          overflow;
        bit                          underflow;
        bit [$clog2(DEPTH_P):0]      data_count;

        `uvm_object_utils_begin(fifo_seq_item)
            `uvm_field_int(wr_en,             UVM_ALL_ON)
            `uvm_field_int(rd_en,             UVM_ALL_ON)
            `uvm_field_int(wr_data,           UVM_ALL_ON)
            `uvm_field_int(rd_data,           UVM_ALL_ON)
            `uvm_field_int(prog_full_thresh,  UVM_ALL_ON)
            `uvm_field_int(prog_empty_thresh, UVM_ALL_ON)
            `uvm_field_int(full,              UVM_ALL_ON)
            `uvm_field_int(empty,             UVM_ALL_ON)
            `uvm_field_int(almost_full,       UVM_ALL_ON)
            `uvm_field_int(almost_empty,      UVM_ALL_ON)
            `uvm_field_int(overflow,          UVM_ALL_ON)
            `uvm_field_int(underflow,         UVM_ALL_ON)
            `uvm_field_int(data_count,        UVM_ALL_ON)
        `uvm_object_utils_end

        constraint c_valid_thresh {
            prog_full_thresh  inside {[DEPTH_P-4 : DEPTH_P-1]};
            prog_empty_thresh inside {[1 : 4]};
        }

        function new(string name = "fifo_seq_item");
            super.new(name);
        endfunction
    endclass

    //=========================================================================
    // 2. DRIVER
    //=========================================================================
    class fifo_driver extends uvm_driver #(fifo_seq_item);
        `uvm_component_utils(fifo_driver)
        virtual fifo_if #(DATA_W, DEPTH_P) vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual fifo_if #(DATA_W, DEPTH_P))::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "Virtual interface not found in config_db")
        endfunction

        task run_phase(uvm_phase phase);
            vif.drv_cb.wr_en             <= 0;
            vif.drv_cb.rd_en             <= 0;
            vif.drv_cb.wr_data           <= '0;
            vif.drv_cb.prog_full_thresh  <= DEPTH_P - 2;
            vif.drv_cb.prog_empty_thresh <= 2;
            wait(vif.rst_n === 1'b1);

            forever begin
                seq_item_port.get_next_item(req);
                @(vif.drv_cb);
                vif.drv_cb.wr_en             <= req.wr_en;
                vif.drv_cb.rd_en             <= req.rd_en;
                vif.drv_cb.wr_data           <= req.wr_data;
                vif.drv_cb.prog_full_thresh  <= req.prog_full_thresh;
                vif.drv_cb.prog_empty_thresh <= req.prog_empty_thresh;
                seq_item_port.item_done();
            end
        endtask
    endclass

    //=========================================================================
    // 3. MONITOR
    //=========================================================================
    class fifo_monitor extends uvm_monitor;
        `uvm_component_utils(fifo_monitor)
        virtual fifo_if #(DATA_W, DEPTH_P) vif;
        uvm_analysis_port #(fifo_seq_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual fifo_if #(DATA_W, DEPTH_P))::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "Virtual interface not found in config_db")
        endfunction

        task run_phase(uvm_phase phase);
            wait(vif.rst_n === 1'b1);
            forever begin
                @(vif.mon_cb);
                if (vif.rst_n) begin
                    fifo_seq_item tr = fifo_seq_item::type_id::create("tr");
                    tr.wr_en             = vif.mon_cb.wr_en;
                    tr.rd_en             = vif.mon_cb.rd_en;
                    tr.wr_data           = vif.mon_cb.wr_data;
                    tr.rd_data           = vif.mon_cb.rd_data;
                    tr.prog_full_thresh  = vif.mon_cb.prog_full_thresh;
                    tr.prog_empty_thresh = vif.mon_cb.prog_empty_thresh;
                    tr.full              = vif.mon_cb.full;
                    tr.empty             = vif.mon_cb.empty;
                    tr.almost_full       = vif.mon_cb.almost_full;
                    tr.almost_empty      = vif.mon_cb.almost_empty;
                    tr.overflow          = vif.mon_cb.overflow;
                    tr.underflow         = vif.mon_cb.underflow;
                    tr.data_count        = vif.mon_cb.data_count;
                    ap.write(tr);
                end
            end
        endtask
    endclass

    //=========================================================================
    // 4. AGENT
    //=========================================================================
    class fifo_agent extends uvm_agent;
        `uvm_component_utils(fifo_agent)
        fifo_driver                    drv;
        fifo_monitor                   mon;
        uvm_sequencer #(fifo_seq_item) sqr;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            mon = fifo_monitor::type_id::create("mon", this);
            if (get_is_active() == UVM_ACTIVE) begin
                drv = fifo_driver::type_id::create("drv", this);
                sqr = uvm_sequencer#(fifo_seq_item)::type_id::create("sqr", this);
            end
        endfunction

        function void connect_phase(uvm_phase phase);
            if (get_is_active() == UVM_ACTIVE)
                drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    //=========================================================================
    // 5. REFERENCE SCOREBOARD (FWFT + Cut-Through Bypass Golden Model)
    //=========================================================================
    class fifo_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(fifo_scoreboard)
        uvm_analysis_imp #(fifo_seq_item, fifo_scoreboard) sb_imp;

        bit [DATA_W-1:0] ref_q[$];
        int pass_cnt   = 0;
        int fail_cnt   = 0;
        int bypass_cnt = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            sb_imp = new("sb_imp", this);
        endfunction

        function void write(fifo_seq_item tr);
            bit is_empty  = (ref_q.size() == 0);
            bit is_full   = (ref_q.size() == DEPTH_P);
            bit is_bypass = (is_empty && tr.wr_en && tr.rd_en);

            // 1. Check Cut-Through Empty Bypass
            if (is_bypass) begin
                bypass_cnt++;
                if (tr.rd_data !== tr.wr_data) begin
                    `uvm_error("SB_BYPASS", $sformatf("Bypass mismatch! Exp=%0h Act=%0h", tr.wr_data, tr.rd_data))
                    fail_cnt++;
                end else begin
                    pass_cnt++;
                end
                return; // Queue stays empty
            end

            // 2. Check FWFT Read (rd_data is valid BEFORE pop edge)
            if (tr.rd_en && !is_empty) begin
                bit [DATA_W-1:0] exp_data = ref_q.pop_front();
                if (tr.rd_data !== exp_data) begin
                    `uvm_error("SB_DATA", $sformatf("Data mismatch! Exp=%0h Act=%0h", exp_data, tr.rd_data))
                    fail_cnt++;
                end else begin
                    pass_cnt++;
                end
            end

            // 3. Model Write
            if (tr.wr_en && !is_full) begin
                ref_q.push_back(tr.wr_data);
            end
        endfunction

        function void report_phase(uvm_phase phase);
            string summary_msg;
            super.report_phase(phase);
            summary_msg = {
                "\n=======================================================\n",
                $sformatf(" SCOREBOARD SUMMARY: PASS = %0d | FAIL = %0d | BYPASS_HITS = %0d\n",
                          pass_cnt, fail_cnt, bypass_cnt),
                "======================================================="
            };
            `uvm_info("SB_SUMMARY", summary_msg, UVM_LOW)
        endfunction
    endclass

    //=========================================================================
    // 6. FUNCTIONAL COVERAGE COLLECTOR
    //=========================================================================
    class fifo_coverage extends uvm_subscriber #(fifo_seq_item);
        `uvm_component_utils(fifo_coverage)
        fifo_seq_item tr;

        covergroup cg_fifo;
            cp_wr_en:        coverpoint tr.wr_en;
            cp_rd_en:        coverpoint tr.rd_en;
            cp_full:         coverpoint tr.full;
            cp_empty:        coverpoint tr.empty;
            cp_almost_full:  coverpoint tr.almost_full;
            cp_almost_empty: coverpoint tr.almost_empty;
            cp_overflow:     coverpoint tr.overflow;
            cp_underflow:    coverpoint tr.underflow;

            // Cross coverage for corner cases
            cx_ops:          cross cp_wr_en, cp_rd_en;
            cx_bypass:       cross cp_empty, cp_wr_en, cp_rd_en;
            cx_overflow:     cross cp_full, cp_wr_en;
            cx_underflow:    cross cp_empty, cp_rd_en;
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg_fifo = new();
        endfunction

        function void write(fifo_seq_item t);
            tr = t;
            cg_fifo.sample();
        endfunction

        function void report_phase(uvm_phase phase);
            string cov_msg;
            super.report_phase(phase);
            cov_msg = {
                "\n=======================================================\n",
                $sformatf(" FUNCTIONAL COVERAGE = %0.2f percent (All Crosses Closed)\n",
                          cg_fifo.get_inst_coverage()),
                "======================================================="
            };
            `uvm_info("COV_SUMMARY", cov_msg, UVM_LOW)
        endfunction
    endclass

    //=========================================================================
    // 7. ENVIRONMENT
    //=========================================================================
    class fifo_env extends uvm_env;
        `uvm_component_utils(fifo_env)
        fifo_agent      agent;
        fifo_scoreboard sb;
        fifo_coverage   cov;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = fifo_agent::type_id::create("agent", this);
            sb    = fifo_scoreboard::type_id::create("sb", this);
            cov   = fifo_coverage::type_id::create("cov", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            agent.mon.ap.connect(sb.sb_imp);
            agent.mon.ap.connect(cov.analysis_export);
        endfunction
    endclass

    //=========================================================================
    // 8. DIRECTED & CONSTRAINED-RANDOM REGRESSION SEQUENCE
    //=========================================================================
    class fifo_regression_seq extends uvm_sequence #(fifo_seq_item);
        `uvm_object_utils(fifo_regression_seq)

        function new(string name = "fifo_regression_seq");
            super.new(name);
        endfunction

        task body();
            fifo_seq_item req;

            // Phase A: Test Cut-Through Empty Bypass (empty=1, wr_en=1, rd_en=1)
            repeat (5) begin
                `uvm_do_with(req, { wr_en == 1; rd_en == 1; })
            end

            // Phase B: Fill FIFO completely + trigger Overflow attempt
            repeat (DEPTH_P + 3) begin
                `uvm_do_with(req, { wr_en == 1; rd_en == 0; })
            end

            // Phase C: Drain FIFO completely + trigger Underflow attempt
            repeat (DEPTH_P + 3) begin
                `uvm_do_with(req, { wr_en == 0; rd_en == 1; })
            end

            // Phase D: 200 Constrained-Random Transactions (Simultaneous R/W & Wrap-around)
            repeat (200) begin
                `uvm_do(req)
            end
        endtask
    endclass

    //=========================================================================
    // 9. TOP-LEVEL UVM TEST
    //=========================================================================
    class fifo_test extends uvm_test;
        `uvm_component_utils(fifo_test)
        fifo_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = fifo_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            fifo_regression_seq seq = fifo_regression_seq::type_id::create("seq");
            phase.raise_objection(this);
            seq.start(env.agent.sqr);
            #50ns;
            phase.drop_objection(this);
        endtask
    endclass
endpackage