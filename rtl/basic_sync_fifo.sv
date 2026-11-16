// ============================================================================
// File        : basic_sync_fifo.sv
// Author      : Vijay Kumar
// Description : Baseline Parameterized Synchronous FIFO (Standard Mode)
//
// Key Architectural Characteristics (Baseline Reference):
//   1. 1-Cycle Read Latency: rd_data is registered inside always_ff, meaning
//      valid data appears one clock edge after rd_en is asserted.
//   2. Static Thresholds: almost_full (DEPTH - 2) and almost_empty (2) are
//      fixed at synthesis time rather than dynamically configurable.
//   3. Combinational Flags: full, empty, almost_full, and almost_empty are
//      evaluated combinationally from the occupancy counter (count).
//   4. No Fault Telemetry: Illegal writes when full or reads when empty are
//      silently ignored without overflow/underflow error reporting.
// ============================================================================

`timescale 1ns / 1ps

module basic_sync_fifo #(
    parameter int DATA_WIDTH = 32,              // Width of each data word in bits
    parameter int DEPTH      = 16               // Total number of FIFO storage slots (power of 2)
) (
    // Global Clock and Active-Low Asynchronous Reset
    input  logic                   clk,         // System clock
    input  logic                   rst_n,       // Active-low reset

    // Write Interface (Producer Side)
    input  logic                   wr_en,       // Write enable strobe
    input  logic [DATA_WIDTH-1:0]  wr_data,     // Data word to push into FIFO

    // Read Interface (Consumer Side)
    input  logic                   rd_en,       // Read enable strobe
    output logic [DATA_WIDTH-1:0]  rd_data,     // Registered output data (1-cycle latency)

    // Status Flags
    output logic                   full,        // High when FIFO reaches maximum capacity (DEPTH)
    output logic                   empty,       // High when FIFO contains zero valid entries
    output logic                   almost_full, // High when remaining free slots <= 2
    output logic                   almost_empty // High when stored entries <= 2
);

    // Address width derived automatically from DEPTH (e.g., 4 bits for DEPTH = 16)
    localparam int ADDR_WIDTH = $clog2(DEPTH);

    // Internal storage array, read/write pointers, and occupancy counter
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];     // Distributed register/LUT memory array
    logic [ADDR_WIDTH-1:0] wr_ptr;              // Points to next slot to write
    logic [ADDR_WIDTH-1:0] rd_ptr;              // Points to next slot to read
    logic [ADDR_WIDTH:0]   count;               // Tracks live occupancy from 0 to DEPTH (5 bits for 16)

    // ------------------------------------------------------------------------
    // Combinational Status Flag Generation
    // Note: Directly comparing 'count' adds comparator logic delay onto the
    //       output flag paths and uses static thresholds.
    // ------------------------------------------------------------------------
    assign full         = (count == DEPTH);
    assign empty        = (count == 0);
    assign almost_full  = (count >= DEPTH - 2); // Fixed threshold at 14 for DEPTH = 16
    assign almost_empty = (count <= 2);         // Fixed threshold at 2

    // ------------------------------------------------------------------------
    // Synchronous Write, Registered Read, and Occupancy Counter Logic
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset pointers, counter, and output data register
            wr_ptr  <= '0;
            rd_ptr  <= '0;
            count   <= '0;
            rd_data <= '0;
        end else begin
            // Write Operation: Store incoming data only when FIFO is not full
            if (wr_en && !full) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr      <= wr_ptr + 1'b1;
            end

            // Read Operation: Register memory output onto rd_data (introduces 1-cycle latency)
            if (rd_en && !empty) begin
                rd_data <= mem[rd_ptr];
                rd_ptr  <= rd_ptr + 1'b1;
            end

            // Occupancy Counter Update:
            //   2'b10 -> Valid write only   : increment count
            //   2'b01 -> Valid read only    : decrement count
            //   2'b11 / 2'b00 -> Simultaneous or idle : hold count steady
            case ({(wr_en && !full), (rd_en && !empty)})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule