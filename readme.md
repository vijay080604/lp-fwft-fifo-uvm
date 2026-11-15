# Low-Power First-Word Fall-Through (LP-FWFT) Synchronous FIFO with UVM 1.2 Verification

![SystemVerilog](https://img.shields.io/badge/Language-SystemVerilog-blue)
![UVM](https://img.shields.io/badge/Verification-UVM%201.2-brightgreen)
![Target](https://img.shields.io/badge/FPGA-Xilinx%20Artix--7%20(200MHz)-orange)
![Coverage](https://img.shields.io/badge/Functional%20Coverage-100%25-success)

## Overview
This repository presents the RTL micro-architecture optimization, hardware Power-Performance-Area (PPA) benchmarking, and full **UVM 1.2 verification** of a parameterized **Low-Power First-Word Fall-Through Synchronous FIFO (`lp_fwft_fifo`)** compared against a traditional registered-output **Baseline Synchronous FIFO (`basic_sync_fifo`)**.

Synthesized and verified in **Vivado 2026.1** targeting the **Xilinx Artix-7 (`xc7a35tifgg484-1L`)** at **200 MHz (`5.000 ns`)**, the upgraded architecture cuts read latency from **1 clock cycle to 0 clock cycles**, reduces flip-flop utilization by **4.3% (`-24` FFs)**, and integrates runtime threshold programmability, cut-through empty bypass, operand-isolation power clamping, and protocol fault telemetry.

---

## Architectural Upgrades (`basic_sync_fifo` vs. `lp_fwft_fifo`)

1. **Zero-Cycle First-Word Fall-Through (FWFT):**
   * Eliminates the 32-bit registered `rd_data` output flip-flop stage (`-24` net Slice Registers), presenting the oldest queued word immediately on `rd_data` as soon as `empty == 0`—before `rd_en` is asserted.
2. **Cut-Through Empty Bypass (`empty && wr_en && rd_en`):**
   * When the FIFO is empty and simultaneous write/read requests arrive, `wr_data` routes directly to `rd_data` combinationally in the **same clock cycle** (`0` latency), while gating off memory writes (`mem_wr_en = 0`) and keeping pointers frozen to prevent unnecessary flip-flop switching.
3. **Operand Isolation Power Clamping:**
   * Forces `rd_data` to `32'h0000_0000` whenever `empty == 1` and `wr_en == 0`, eliminating downstream combinational switching activity during idle cycles.
4. **Dynamic Programmable Thresholds (`prog_full_thresh`, `prog_empty_thresh`):**
   * Replaces static thresholds with runtime-configurable 5-bit ports (`1` to `15`), preventing multi-cycle pipeline skid overflows and burst-read starvation without resynthesizing RTL.
5. **Protocol Fault & Occupancy Telemetry (`overflow`, `underflow`, `data_count`):**
   * Protects internal memory against illegal writes/reads while asserting registered `overflow` / `underflow` error flags and live buffer occupancy (`0` to `16`).

---
