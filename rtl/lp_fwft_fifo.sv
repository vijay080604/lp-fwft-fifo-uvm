// ============================================================================
// File        : lp_fwft_fifo.sv
// Author      : Vijay Kumar
// Description : Low-Power First-Word Fall-Through (LP-FWFT) Synchronous FIFO
//
// Key Architectural Upgrades over Baseline (basic_sync_fifo):
//   1. 0-Cycle First-Word Fall-Through (FWFT): Eliminates the 32-bit output
//      flip-flop stage (-24 net FFs), presenting the head of the queue
//      immediately on rd_data as soon as empty == 0 (before rd_en rises).
//   2. Cut-Through Empty Bypass: When empty && wr_en && rd_en occur together,
//      wr_data routes combinationally to rd_data in the same cycle while
//      gating off memory writes (mem_wr_en = 0) and freezing pointers.
//   3. Operand Isolation Power Clamping: Forces rd_data to '0 whenever the
//      FIFO is idle and empty (empty && !wr_en), preventing downstream bus
//      toggling and dynamic switching power.
//   4. Runtime-Programmable Thresholds: Dynamic prog_full_thresh and
//      prog_empty_thresh inputs replace fixed compile-time thresholds.
//   5. Registered Look-Ahead Status & Fault Telemetry: Registers full, empty,
//      almost_full, almost_empty, overflow, underflow, and data_count for
//      clean output timing and protocol error detection.
// ============================================================================

`timescale 1ns / 1ps

module lp_fwft_fifo #(
    parameter int DATA_WIDTH = 32,                  // Width of each data word in bits
    parameter int DEPTH      = 16                   // Total storage slots (must be a power of 2)
) (
    // Global Clock and Active-Low Asynchronous Reset
    input  logic                        clk,               // System clock (200 MHz / 5.000 ns target)
    input  logic                        rst_n,             // Active-low asynchronous reset

    // Write Interface (Producer Side)
    input  logic                        wr_en,             // Write enable strobe
    input  logic [DATA_WIDTH-1:0]       wr_data,           // Incoming data word

    // Read Interface (Consumer Side: FWFT + 0-Cycle Empty Bypass)
    input  logic                        rd_en,             // Read acknowledge / pop strobe
    output logic [DATA_WIDTH-1:0]       rd_data,           // Combinational FWFT / bypass / zero-clamped data

    // Runtime-Programmable Thresholds (1 to DEPTH-1)
    input  logic [$clog2(DEPTH):0]      prog_full_thresh,  // Dynamic threshold for almost_full assertion
    input  logic [$clog2(DEPTH):0]      prog_empty_thresh, // Dynamic threshold for almost_empty assertion

    // Registered Look-Ahead Status, Error, and Occupancy Flags
    output logic                        full,              // High when FIFO occupancy reaches DEPTH
    output logic                        empty,             // High when FIFO occupancy is 0
    output logic                        almost_full,       // High when next_count >= prog_full_thresh
    output logic                        almost_empty,      // High when next_count <= prog_empty_thresh
    output logic                        overflow,          // Pulses high if wr_en asserts while full
    output logic                        underflow,         // Pulses high if rd_en asserts while empty && !wr_en
    output logic [$clog2(DEPTH):0]      data_count         // Live word occupancy count (0 to DEPTH)
);

    // Address width derived from DEPTH (e.g., 4 bits for DEPTH = 16)
    localparam int ADDR_WIDTH = $clog2(DEPTH);

    // Storage array (synthesizes cleanly into LUTRAM / Distributed RAM with Clock Enable)
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Extra-MSB wrap-around pointers (ADDR_WIDTH+1 bits) and look-ahead count
    logic [ADDR_WIDTH:0] wr_ptr, wr_ptr_next;       // Current and next write pointers
    logic [ADDR_WIDTH:0] rd_ptr, rd_ptr_next;       // Current and next read pointers
    logic [ADDR_WIDTH:0] next_count;                // Next-cycle occupancy count

    // Internal control qualifiers for bypass and clock-enable gating
    logic bypass_en;                                // High during simultaneous read/write on empty FIFO
    logic mem_wr_en;                                // Gated write enable sent to memory array
    logic mem_rd_en;                                // Valid memory read qualifier

    // ------------------------------------------------------------------------
    // CONCEPT 1: Cut-Through Empty Bypass Detection
    // When the FIFO is empty and both wr_en & rd_en arrive simultaneously,
    // wr_data passes straight to rd_data without touching mem or pointers.
    // ------------------------------------------------------------------------
    assign bypass_en = empty && wr_en && rd_en;

    // ------------------------------------------------------------------------
    // CONCEPT 2: Fine-Grained Clock-Enable Gating (Dynamic Power Reduction)
    // Memory write clock-enable only toggles when an actual store is needed
    // (i.e., valid write that is NOT bypassed directly to the output).
    // ------------------------------------------------------------------------
    assign mem_wr_en = wr_en && !full && !bypass_en;
    assign mem_rd_en = rd_en && !empty;

    // ------------------------------------------------------------------------
    // CONCEPT 3: Look-Ahead Pointer & Occupancy Calculation
    // Computes next-state pointers and word count combinationally so status
    // flags can be registered cleanly on the rising clock edge.
    // ------------------------------------------------------------------------
    always_comb begin
        wr_ptr_next = mem_wr_en ? (wr_ptr + 1'b1) : wr_ptr;
        rd_ptr_next = mem_rd_en ? (rd_ptr + 1'b1) : rd_ptr;

        // Occupancy delta:
        //   2'b10 -> Stored write only : increment occupancy
        //   2'b01 -> Memory read only  : decrement occupancy
        //   2'b11 / 2'b00 -> Simultaneous or bypass/idle : hold occupancy
        case ({mem_wr_en, mem_rd_en})
            2'b10:   next_count = data_count + 1'b1;
            2'b01:   next_count = data_count - 1'b1;
            default: next_count = data_count;
        endcase
    end

    // ------------------------------------------------------------------------
    // Sequential Logic: Gated Memory Write + Registered Look-Ahead Flags
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize pointers, occupancy, and registered status/error flags
            wr_ptr       <= '0;
            rd_ptr       <= '0;
            data_count   <= '0;
            full         <= 1'b0;
            empty        <= 1'b1;
            almost_full  <= 1'b0;
            almost_empty <= 1'b1;
            overflow     <= 1'b0;
            underflow    <= 1'b0;
        end else begin
            // Clock-enabled write: Vivado maps 'mem_wr_en' directly to slice CE pin
            if (mem_wr_en) begin
                mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
            end

            // Update pointers and live occupancy count
            wr_ptr     <= wr_ptr_next;
            rd_ptr     <= rd_ptr_next;
            data_count <= next_count;

            // CONCEPT 4: Registered Status Flags (Output Timing Optimization)
            // Evaluated from next-state pointers/count so flag outputs have zero
            // combinational comparator delay after the clock edge.
            full         <= (wr_ptr_next[ADDR_WIDTH] != rd_ptr_next[ADDR_WIDTH]) &&
                            (wr_ptr_next[ADDR_WIDTH-1:0] == rd_ptr_next[ADDR_WIDTH-1:0]);
            empty        <= (wr_ptr_next == rd_ptr_next);
            almost_full  <= (next_count >= prog_full_thresh);
            almost_empty <= (next_count <= prog_empty_thresh);

            // Registered single-cycle protocol fault flags:
            // Note: rd_en while empty is valid ONLY when wr_en is also high (bypass)
            overflow     <= (wr_en && full);
            underflow    <= (rd_en && empty && !wr_en);
        end
    end

    // ------------------------------------------------------------------------
    // CONCEPT 5: FWFT + Cut-Through Mux + Operand Isolation (Power Saving)
    //   - If empty & wr_en  : 0-cycle cut-through directly from wr_data
    //   - If empty & !wr_en : Clamp rd_data to '0 to stop downstream toggling
    //   - If !empty         : Present head of queue immediately (FWFT)
    // ------------------------------------------------------------------------
    always_comb begin
        if (empty) begin
            rd_data = wr_en ? wr_data : '0;        // Zero-cycle cut-through OR low-power isolation clamp
        end else begin
            rd_data = mem[rd_ptr[ADDR_WIDTH-1:0]]; // First-Word Fall-Through (0-cycle read latency)
        end
    end

endmodule