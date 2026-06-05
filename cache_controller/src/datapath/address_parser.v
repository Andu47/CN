// =============================================================================
// address_parser.v
// Combinational Address Splitter
//
// Splits the 32-bit CPU address into the three cache address fields:
//
//   Bit layout (32-bit address):
//   ┌──────────────────────┬─────────────┬──────────────┐
//   │  Tag  [31:13]  19b   │ Index [12:6] 7b │ Offset [5:0] 6b │
//   └──────────────────────┴─────────────┴──────────────┘
//
//   Offset : 6 bits → addresses 1 of 64 bytes within a block  (2^6 = 64)
//   Index  : 7 bits → selects 1 of 128 sets                   (2^7 = 128)
//   Tag    : 19 bits → the remaining high bits used for comparison
//
// This is purely combinational — no clock, no state.
//
// Author : Floarea Alexandru
// Project: Cache Controller — Computer Architecture HDL Project
// =============================================================================

`timescale 1ns / 1ps

module address_parser (
    input  wire [31:0] cpu_addr,   // Full 32-bit address from CPU

    output wire [18:0] tag,        // Bits [31:13] — compared against stored tags
    output wire [6:0]  index,      // Bits [12:6]  — selects the cache set
    output wire [5:0]  offset      // Bits [5:0]   — byte offset within the block
);

    assign offset = cpu_addr[5:0];
    assign index  = cpu_addr[12:6];
    assign tag    = cpu_addr[31:13];

endmodule