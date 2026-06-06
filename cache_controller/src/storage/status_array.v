// =============================================================================
// status_array.v
// Status Storage + LRU Logic — 128 sets × 4 ways
//
// Per-way, per-set state tracked:
//   valid  [1 bit]  — 1 = block holds live data
//   dirty  [1 bit]  — 1 = block has been written since it was fetched
//   age    [2 bits] — 0 = MRU (most recently used), 3 = LRU (evict candidate)
//
// ── LRU Age Counter Rules ────────────────────────────────────────────────────
//
//   On a Cache HIT  (lru_update_en=1, cache_hit=1):
//     • The hit way resets its age to 0 (it is now the MRU).
//     • Every OTHER way that was YOUNGER than the hit way (age < hit_age)
//       has its age incremented by 1 (it got relatively older).
//     • Ways that were already OLDER than the hit way are unchanged
//       (their relative order among themselves is preserved).
//
//     Example — 4 ways with ages [1, 0, 3, 2], hit on way 2 (age=3):
//       Way 0: age was 1 < 3  → increment → 2
//       Way 1: age was 0 < 3  → increment → 1
//       Way 2: hit            → reset     → 0   ← MRU
//       Way 3: age was 2 < 3  → increment → 3
//       Result: [2, 1, 0, 3]  — way 3 is still the LRU candidate.
//
//   On a Cache MISS / ALLOCATE  (lru_update_en=1, cache_hit=0):
//     • The allocated way (way_sel = lru_way from FSM) resets to age 0.
//     • All other three ways increment their age by 1.
//     • Because lru_way always had age 3 before allocation, the other
//       three ways (ages 0–2) become 1–3 — a clean, fully-ordered set.
//
// ── Outputs ──────────────────────────────────────────────────────────────────
//   lru_way  — index of the way currently holding age == 3 (eviction candidate)
//   is_dirty — dirty bit of lru_way (tells FSM whether an EVICT is needed)
//
// Author : Popa Lucian
// Project: Cache Controller — Computer Architecture HDL Project
// =============================================================================

`timescale 1ns / 1ps

module status_array (
    input  wire        clk,
    input  wire        rst_n,          // Active-low synchronous reset

    // Set index
    input  wire [6:0]  index,

    // Write controls (driven by FSM)
    input  wire [1:0]  way_sel,        // Way being operated on
    input  wire        valid_we,       // Write the valid bit of way_sel
    input  wire        dirty_we,       // Write the dirty bit of way_sel
    input  wire        dirty_din,      // Value to write into dirty bit

    // LRU update trigger (asserted by FSM on READ_HIT, WRITE_HIT, COMPLETE)
    input  wire        lru_update_en,
    input  wire        cache_hit,      // 1 = hit update rule, 0 = miss/alloc rule
    input  wire [1:0]  hit_way,        // Way that hit (used when cache_hit=1)

    // Status read-outs (combinational — used by hit_detector and FSM)
    output wire        valid_out0,
    output wire        valid_out1,
    output wire        valid_out2,
    output wire        valid_out3,

    // LRU eviction candidate and its dirty status
    output reg  [1:0]  lru_way,
    output reg         is_dirty
);

    // =========================================================================
    // Storage Arrays
    // =========================================================================
    reg        valid [0:127][0:3];     // valid[set][way]
    reg        dirty [0:127][0:3];     // dirty[set][way]
    reg [1:0]  age   [0:127][0:3];     // age[set][way]  0=MRU, 3=LRU

    // =========================================================================
    // Combinational Valid Read-out (all 4 ways of selected set)
    // =========================================================================
    assign valid_out0 = valid[index][0];
    assign valid_out1 = valid[index][1];
    assign valid_out2 = valid[index][2];
    assign valid_out3 = valid[index][3];

    // =========================================================================
    // LRU Way Lookup + Dirty Status (combinational)
    //
    // Priority:
    //   1. Any invalid way -> use the lowest-numbered invalid way (cold miss).
    //      is_dirty is forced 0 so the FSM skips EVICT and goes straight to
    //      ALLOCATE_FETCH.
    //   2. All ways valid -> use the way whose age == 3 (true LRU victim).
    //
    // Without this, the first 3 cold misses all write into way 0 because no
    // way reaches age==3 until the set is fully populated.
    // =========================================================================
    integer s;
    reg     found_invalid;

    always @(*) begin
        lru_way       = 2'b00;
        is_dirty      = 1'b0;
        found_invalid = 1'b0;

        // Pass 1: lowest-numbered invalid way (reverse scan so lowest wins)
        for (s = 3; s >= 0; s = s - 1) begin
            if (!valid[index][s]) begin
                lru_way       = s[1:0];
                is_dirty      = 1'b0;
                found_invalid = 1'b1;
            end
        end

        // Pass 2: all ways valid -- find the age==3 LRU victim
        if (!found_invalid) begin
            for (s = 0; s < 4; s = s + 1) begin
                if (age[index][s] == 2'b11) begin
                    lru_way  = s[1:0];
                    is_dirty = dirty[index][s];
                end
            end
        end
    end

    // =========================================================================
    // Synchronous Write — Valid, Dirty, and LRU Age
    // =========================================================================
    integer w;

    always @(posedge clk) begin
        if (!rst_n) begin
            // ── Reset: invalidate all blocks, clear dirty, age all to 0 ──────
            // (Using a nested loop; synthesis unrolls this completely.)
            for (w = 0; w < 128*4; w = w + 1) begin
                valid[w/4][w%4] <= 1'b0;
                dirty[w/4][w%4] <= 1'b0;
                age  [w/4][w%4] <= 2'b00;
            end

        end else begin

            // ── Valid bit write ───────────────────────────────────────────────
            if (valid_we)
                valid[index][way_sel] <= 1'b1;   // FSM only ever sets valid=1

            // ── Dirty bit write ───────────────────────────────────────────────
            if (dirty_we)
                dirty[index][way_sel] <= dirty_din;

            // ── LRU age update ────────────────────────────────────────────────
            if (lru_update_en) begin
                if (cache_hit) begin
                    // HIT UPDATE RULE
                    // Capture the age of the hit way before any modifications.
                    // We need it inside the loop to decide which other ways to age.
                    begin : hit_update_block
                        reg [1:0] hit_age;
                        hit_age = age[index][hit_way];

                        for (w = 0; w < 4; w = w + 1) begin
                            if (w[1:0] == hit_way) begin
                                // Hit way becomes the MRU
                                age[index][w] <= 2'b00;
                            end else if (age[index][w] < hit_age) begin
                                // Ways younger than the hit way get relatively older
                                age[index][w] <= age[index][w] + 2'b01;
                            end
                            // Ways already older than the hit way: unchanged
                        end
                    end

                end else begin
                    // MISS / ALLOCATE UPDATE RULE
                    // way_sel holds the newly installed way (lru_way from FSM).
                    for (w = 0; w < 4; w = w + 1) begin
                        if (w[1:0] == way_sel) begin
                            // Newly allocated block becomes the MRU
                            age[index][w] <= 2'b00;
                        end else begin
                            // All other ways age by 1
                            age[index][w] <= age[index][w] + 2'b01;
                        end
                    end
                end
            end // lru_update_en

        end // rst_n
    end // always

endmodule