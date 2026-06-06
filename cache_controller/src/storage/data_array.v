// =============================================================================
// data_array.v
// Data Storage Array — 128 sets × 4 ways × 512 bits (64 bytes per block)
//
// Two write modes controlled by is_alloc:
//   is_alloc = 0  →  Word write (WRITE_HIT): write only the 32-bit CPU word
//                    addressed by 'offset' into the selected block.
//   is_alloc = 1  →  Block write (ALLOCATE_FETCH): overwrite the entire
//                    512-bit block with the data fetched from main memory.
//
// Combinational read: the full 512-bit block of the selected way is presented
// every cycle to data_steer_mux.v, which extracts the requested 32-bit word.
// The evict_block_out port always presents the LRU-way block so the FSM can
// drive it onto the memory bus during EVICT without an extra read cycle.
//
// Author : Popa Lucian
// Project: Cache Controller — Computer Architecture HDL Project
// =============================================================================

`timescale 1ns / 1ps

module data_array (
    input  wire         clk,

    // Address
    input  wire [6:0]   index,       // Set select (7 bits → 128 sets)
    input  wire [1:0]   way_sel,     // Way select (from FSM)
    input  wire [5:0]   offset,      // Byte offset within block (from address_parser)

    // Write port
    input  wire         we,          // Write-enable (asserted by FSM)
    input  wire         is_alloc,    // 1 = full block write, 0 = single-word write
    input  wire [31:0]  cpu_data_in, // 32-bit word from CPU (used when is_alloc=0)
    input  wire [511:0] mem_data_in, // 512-bit block from memory (used when is_alloc=1)

    // Read ports
    output wire [511:0] block_out,       // Full block of way_sel → data_steer_mux
    output wire [511:0] evict_block_out  // Full block of lru_way → memory bus (EVICT)
);

    // =========================================================================
    // Storage — four flat arrays, one per way
    // =========================================================================
    reg [511:0] data_way0 [0:127];
    reg [511:0] data_way1 [0:127];
    reg [511:0] data_way2 [0:127];
    reg [511:0] data_way3 [0:127];

    // =========================================================================
    // Byte offset → bit offset conversion
    // The offset field addresses bytes; we need the LSB bit position of the
    // target 32-bit word inside the 512-bit block.
    // offset[5:2] selects one of 16 words (bits [5:2]); bits [1:0] are ignored
    // because the CPU always issues word-aligned accesses.
    // =========================================================================
    wire [8:0] bit_offset = {offset[5:2], 5'b0};  // multiply word-index by 32

    // =========================================================================
    // Synchronous Write
    // =========================================================================
    always @(posedge clk) begin
        if (we) begin
            if (is_alloc) begin
                // ── Full block install (ALLOCATE_FETCH) ──────────────────────
                case (way_sel)
                    2'b00: data_way0[index] <= mem_data_in;
                    2'b01: data_way1[index] <= mem_data_in;
                    2'b10: data_way2[index] <= mem_data_in;
                    2'b11: data_way3[index] <= mem_data_in;
                endcase
            end else begin
                // ── Single word update (WRITE_HIT / COMPLETE after write miss)
                // Perform a read-modify-write: copy the existing block and
                // splice in the 32-bit CPU word at the correct bit position.
                case (way_sel)
                    2'b00: data_way0[index][bit_offset +: 32] <= cpu_data_in;
                    2'b01: data_way1[index][bit_offset +: 32] <= cpu_data_in;
                    2'b10: data_way2[index][bit_offset +: 32] <= cpu_data_in;
                    2'b11: data_way3[index][bit_offset +: 32] <= cpu_data_in;
                endcase
            end
        end
    end

    // =========================================================================
    // Combinational Read — selected way block → data_steer_mux
    // Explicit sensitivity list avoids the "sensitive to all N words" warning.
    // =========================================================================
    reg [511:0] block_read;
    always @(way_sel or index
             or data_way0[index] or data_way1[index]
             or data_way2[index] or data_way3[index]) begin
        case (way_sel)
            2'b00: block_read = data_way0[index];
            2'b01: block_read = data_way1[index];
            2'b10: block_read = data_way2[index];
            2'b11: block_read = data_way3[index];
        endcase
    end
    assign block_out = block_read;

    // =========================================================================
    // Eviction Read — always exposes way_sel block on evict port
    // The FSM sets way_sel = lru_way during EVICT so the correct dirty block
    // is presented on this port for the memory write-back.
    // =========================================================================
    assign evict_block_out = block_read;

endmodule