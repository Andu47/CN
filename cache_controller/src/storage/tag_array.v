// =============================================================================
// tag_array.v
// Tag Storage Array — 128 sets × 4 ways × 19 bits
//
// Synchronous write, combinational (async) read.
// All four way-tags for the indexed set are read out in parallel every cycle
// so hit_detector.v can run its four comparators simultaneously.
//
// Author : Popa Lucian
// Project: Cache Controller — Computer Architecture HDL Project
// =============================================================================

`timescale 1ns / 1ps

module tag_array (
    input  wire        clk,

    // Set index — selects one of 128 sets
    input  wire [6:0]  index,

    // Write port — FSM drives these during ALLOCATE_FETCH
    input  wire [1:0]  way_sel,     // Which of the 4 ways to write
    input  wire [18:0] tag_in,      // New tag value (bits [31:13] of CPU address)
    input  wire        we,          // Write-enable (active high)

    // Read port — all four ways exposed simultaneously (combinational)
    output wire [18:0] tag_out0,    // Tag stored in way 0 of the selected set
    output wire [18:0] tag_out1,    // Tag stored in way 1
    output wire [18:0] tag_out2,    // Tag stored in way 2
    output wire [18:0] tag_out3     // Tag stored in way 3
);

    // =========================================================================
    // Storage — 4 separate arrays, one per way
    // Synthesis maps each to a simple dual-port SRAM or register file.
    // =========================================================================
    reg [18:0] tags_way0 [0:127];
    reg [18:0] tags_way1 [0:127];
    reg [18:0] tags_way2 [0:127];
    reg [18:0] tags_way3 [0:127];

    // =========================================================================
    // Synchronous Write
    // Only the selected way is updated; the other three are untouched.
    // =========================================================================
    always @(posedge clk) begin
        if (we) begin
            case (way_sel)
                2'b00: tags_way0[index] <= tag_in;
                2'b01: tags_way1[index] <= tag_in;
                2'b10: tags_way2[index] <= tag_in;
                2'b11: tags_way3[index] <= tag_in;
            endcase
        end
    end

    // =========================================================================
    // Combinational Read — all four ways, every cycle
    // hit_detector.v compares all four tags against addr_tag in parallel.
    // =========================================================================
    assign tag_out0 = tags_way0[index];
    assign tag_out1 = tags_way1[index];
    assign tag_out2 = tags_way2[index];
    assign tag_out3 = tags_way3[index];

endmodule