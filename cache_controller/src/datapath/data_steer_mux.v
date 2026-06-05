// =============================================================================
// data_steer_mux.v
// Data Width Steering MUX
//
// Bridges the mismatch between the 512-bit (64-byte) cache block width and
// the 32-bit (4-byte) CPU word width.
//
// READ path  (block → CPU word):
//   Uses the 6-bit byte offset from address_parser to extract the single
//   32-bit word the CPU requested.  offset[5:2] selects one of 16 words
//   (word index); offset[1:0] are ignored — the CPU is word-aligned.
//
//   word_index = offset[5:2]           (4 bits → 0..15)
//   bit_base   = word_index × 32       (bit position in the 512-bit block)
//   cpu_data_out = cache_block[bit_base +: 32]
//
// WRITE path  (CPU word → block):
//   Injects the 32-bit CPU word into a copy of the 512-bit block at the
//   correct offset position, producing a full updated block ready to be
//   written back into the data_array.
//
//   merged_block = cache_block with [bit_base +: 32] replaced by cpu_data_in
//
// Both paths are purely combinational.
//
// Author : Floarea Alexandru
// Project: Cache Controller — Computer Architecture HDL Project
// =============================================================================

`timescale 1ns / 1ps

module data_steer_mux (
    // From data_array — the full 64-byte cache block of the target way
    input  wire [511:0] cache_block,

    // From address_parser
    input  wire [5:0]   offset,         // Byte offset within the block

    // From CPU (write path)
    input  wire [31:0]  cpu_data_in,    // Word to inject into the block

    // ── READ path output ────────────────────────────────────────────────────
    output wire [31:0]  cpu_data_out,   // Extracted 32-bit word → CPU

    // ── WRITE path output ───────────────────────────────────────────────────
    // Full 512-bit block with the CPU word merged in — feed to data_array
    // write port on a WRITE_HIT or after ALLOCATE_FETCH for a write miss.
    output wire [511:0] merged_block    // Updated block → data_array.cpu_data_in
);

    // ── Bit base address (word-aligned) ────────────────────────────────────
    // offset[5:2] gives the 32-bit word index (0..15) inside the 64-byte block.
    // Multiply by 32 to get the LSB bit position.
    wire [8:0] bit_base = {offset[5:2], 5'b0_0000};  // 9 bits: max = 15*32 = 480

    // ── READ: extract 32-bit word ───────────────────────────────────────────
    assign cpu_data_out = cache_block[bit_base +: 32];

    // ── WRITE: splice CPU word into a copy of the block ─────────────────────
    // Build a 512-bit mask: 32 ones at bit_base, zeros elsewhere.
    // merged = (cache_block & ~mask) | (cpu_data_in << bit_base)
    wire [511:0] mask        = {{480{1'b0}}, {32{1'b1}}} << bit_base;
    wire [511:0] word_placed = {{480{1'b0}}, cpu_data_in} << bit_base;
    assign merged_block = (cache_block & ~mask) | word_placed;

endmodule