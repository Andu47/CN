// =============================================================================
// hit_detector.v
// Parallel Tag Comparator — 4-Way Set-Associative Hit Detection
//
// Instantiates four independent combinational comparators, one per way.
// Each comparator checks: (valid_wayN == 1) AND (tag_wayN == addr_tag)
//
// All four run in parallel; the result is available within the same clock
// cycle that the tag_array presents its read outputs, so the FSM can
// evaluate cache_hit in CHECK_HIT with zero added latency.
//
// Priority encoding: way 0 > way 1 > way 2 > way 3.
// In a correctly-operating cache only one way can ever hit at a time
// (tags are unique per set), so priority is a safety net, not a design choice.
//
// Author : Floarea Alexandru
// Project: Cache Controller — Computer Architecture HDL Project
// =============================================================================

`timescale 1ns / 1ps

module hit_detector (
    // Tag from the incoming CPU address (address_parser output)
    input  wire [18:0] addr_tag,

    // Tags and valid bits read from tag_array for the current set (all 4 ways)
    input  wire [18:0] tag_way0,
    input  wire [18:0] tag_way1,
    input  wire [18:0] tag_way2,
    input  wire [18:0] tag_way3,
    input  wire        valid_way0,
    input  wire        valid_way1,
    input  wire        valid_way2,
    input  wire        valid_way3,

    // Hit outputs → FSM (cache_controller_fsm)
    output reg         cache_hit,   // 1 = at least one way matched
    output reg  [1:0]  hit_way      // Which way matched (valid only when cache_hit=1)
);

    // ── Per-way combinational hit signals ──────────────────────────────────
    wire hit0 = valid_way0 && (tag_way0 == addr_tag);
    wire hit1 = valid_way1 && (tag_way1 == addr_tag);
    wire hit2 = valid_way2 && (tag_way2 == addr_tag);
    wire hit3 = valid_way3 && (tag_way3 == addr_tag);

    // ── Priority mux: combine into a single hit + way indicator ────────────
    // If multiple ways somehow match (should never happen in a correct cache),
    // the lowest-numbered way wins. This prevents X-propagation on hit_way.
    always @(*) begin
        casex ({hit3, hit2, hit1, hit0})
            4'bxxx1: begin cache_hit = 1'b1; hit_way = 2'b00; end  // way 0
            4'bxx10: begin cache_hit = 1'b1; hit_way = 2'b01; end  // way 1
            4'bx100: begin cache_hit = 1'b1; hit_way = 2'b10; end  // way 2
            4'b1000: begin cache_hit = 1'b1; hit_way = 2'b11; end  // way 3
            default: begin cache_hit = 1'b0; hit_way = 2'b00; end  // miss
        endcase
    end

endmodule