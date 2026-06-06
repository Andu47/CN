// =============================================================================
// cache_controller_fsm.v
// Cache Controller Finite State Machine
// 4-way Set-Associative, Write-Back + Write-Allocate, Pseudo-LRU replacement
//
// Author : Golovatai Alexandru
// Project: Cache Controller — Computer Architecture HDL Project
// =============================================================================

`timescale 1ns / 1ps

module cache_controller_fsm (
    // -------------------------------------------------------------------------
    // Global Signals
    // -------------------------------------------------------------------------
    input  wire        clk,
    input  wire        rst_n,          // Active-low synchronous reset

    // -------------------------------------------------------------------------
    // CPU Interface
    // -------------------------------------------------------------------------
    input  wire        cpu_req,         // High when CPU issues a read or write
    input  wire        cpu_write_en,    // 1 = write, 0 = read
    output reg         cpu_ready,       // Asserted for 1 cycle when request done
                                        // (de-asserted = CPU is stalled)

    // -------------------------------------------------------------------------
    // Datapath Interface (Floarea & Popa)
    // -------------------------------------------------------------------------
    input  wire        cache_hit,       // High when tag comparison finds a match
    input  wire [1:0]  hit_way,         // Which of the 4 ways matched (valid only
                                        //   when cache_hit == 1)
    input  wire [1:0]  lru_way,         // Way selected by the LRU engine for
                                        //   eviction / allocation
    input  wire        is_dirty,        // Dirty bit of lru_way in the current set
                                        //   (valid during CHECK_HIT / EVICT)

    // Control outputs to storage arrays (tag_array, data_array, status_array)
    output reg         tag_we,          // Write-enable to tag_array
    output reg         data_we,         // Write-enable to data_array
    output reg         valid_we,        // Write-enable to valid bit in status_array
    output reg         dirty_we,        // Write-enable to dirty bit in status_array
    output reg         dirty_din,       // Value to write into dirty bit
    output reg         lru_update_en,   // Pulse: trigger LRU age recalculation
    output reg [1:0]   way_sel,         // Which way the FSM is operating on

    // -------------------------------------------------------------------------
    // Main Memory Interface
    // -------------------------------------------------------------------------
    output reg         mem_req,         // Assert to initiate a memory transaction
    output reg         mem_write_en,    // 1 = write (evict), 0 = read (fetch)
    input  wire        mem_ready        // Memory asserts when transaction complete
);

    // =========================================================================
    // State Encoding (one-hot for glitch-free outputs on FPGA)
    // =========================================================================
    localparam [6:0]
        IDLE           = 7'b000_0001,
        CHECK_HIT      = 7'b000_0010,
        READ_HIT       = 7'b000_0100,
        WRITE_HIT      = 7'b000_1000,
        EVICT          = 7'b001_0000,
        ALLOCATE_FETCH = 7'b010_0000,
        COMPLETE       = 7'b100_0000;   // Shared completion state after fetch

    // =========================================================================
    // Process 1 — Sequential: state register (+ capture cpu_write_en at entry)
    // =========================================================================
    reg [6:0] state, next_state;
    reg       pending_write;    // Remember operation type across stall cycles
    reg [1:0] allocated_way;   // Latch of lru_way captured when mem_ready fires
                                // in ALLOCATE_FETCH; used by COMPLETE so the
                                // correct way is updated even after lru_way has
                                // combinationally moved on.

    always @(posedge clk) begin
        if (!rst_n) begin
            state         <= IDLE;
            pending_write <= 1'b0;
            allocated_way <= 2'b00;
        end else begin
            state <= next_state;
            // Latch the write-enable the moment a new request is accepted
            if (state == IDLE && cpu_req)
                pending_write <= cpu_write_en;
            // Capture lru_way the cycle mem_ready fires during ALLOCATE_FETCH.
            // At this exact moment lru_way still points to the victim way BEFORE
            // valid_we has propagated, so it is the correct installation target.
            if (state == ALLOCATE_FETCH && mem_ready)
                allocated_way <= lru_way;
        end
    end

    // =========================================================================
    // Process 2 — Combinational: next-state logic + output generation
    //
    //   Rule: outputs are FULLY defined inside every branch so that synthesis
    //         produces no latches.
    // =========================================================================
    always @(*) begin
        // --- Default (safe) output values -----------------------------------
        cpu_ready    = 1'b0;
        mem_req      = 1'b0;
        mem_write_en = 1'b0;
        tag_we       = 1'b0;
        data_we      = 1'b0;
        valid_we     = 1'b0;
        dirty_we     = 1'b0;
        dirty_din    = 1'b0;
        lru_update_en= 1'b0;
        way_sel      = lru_way;    // Default: operate on the LRU way
        next_state   = state;      // Default: stay in current state

        case (state)

            // -----------------------------------------------------------------
            // IDLE
            //   Wait for the CPU to issue a request.  Transition immediately to
            //   CHECK_HIT so the tag comparison result is available next cycle.
            // -----------------------------------------------------------------
            IDLE: begin
                if (cpu_req)
                    next_state = CHECK_HIT;
                // else remain IDLE — all outputs already low
            end

            // -----------------------------------------------------------------
            // CHECK_HIT
            //   The tag comparators (hit_detector.v) have had one full clock
            //   cycle to stabilise.  Inspect cache_hit to decide the next step.
            //
            //   Hit  → read/write hit path
            //   Miss → dirty lru_way? must EVICT first, else go straight to FETCH
            // -----------------------------------------------------------------
            CHECK_HIT: begin
                if (cache_hit) begin
                    // Hit: choose path based on the operation type
                    if (pending_write)
                        next_state = WRITE_HIT;
                    else
                        next_state = READ_HIT;
                end else begin
                    // Miss: check if the victim block is dirty
                    if (is_dirty)
                        next_state = EVICT;
                    else
                        next_state = ALLOCATE_FETCH;
                end
            end

            // -----------------------------------------------------------------
            // READ_HIT
            //   Data is already steered to the CPU bus by data_steer_mux.v.
            //   Assert cpu_ready for one cycle, update LRU, return to IDLE.
            // -----------------------------------------------------------------
            READ_HIT: begin
                way_sel       = hit_way;    // Read from the matched way
                cpu_ready     = 1'b1;       // Un-stall the CPU
                lru_update_en = 1'b1;       // Notify LRU engine of the access
                next_state    = IDLE;
            end

            // -----------------------------------------------------------------
            // WRITE_HIT
            //   Enable write path into the data array and set the dirty bit.
            //   Assert cpu_ready for one cycle, update LRU, return to IDLE.
            // -----------------------------------------------------------------
            WRITE_HIT: begin
                way_sel       = hit_way;    // Write into the matched way
                data_we       = 1'b1;       // Write CPU data into cache block
                dirty_we      = 1'b1;       // Update dirty bit
                dirty_din     = 1'b1;       // Mark block as dirty
                cpu_ready     = 1'b1;       // Un-stall the CPU
                lru_update_en = 1'b1;       // Notify LRU engine of the access
                next_state    = IDLE;
            end

            // -----------------------------------------------------------------
            // EVICT
            //   The victim block (lru_way) is dirty — write it back to memory.
            //   Hold in this state while mem_ready is low (memory wait-states).
            //   On mem_ready: clear the dirty bit, proceed to ALLOCATE_FETCH.
            // -----------------------------------------------------------------
            EVICT: begin
                way_sel      = lru_way;
                mem_req      = 1'b1;        // Request a memory transaction
                mem_write_en = 1'b1;        // This is a write-back (evict)

                if (mem_ready) begin
                    // Write-back complete: clear dirty bit for the evicted way
                    dirty_we   = 1'b1;
                    dirty_din  = 1'b0;
                    next_state = ALLOCATE_FETCH;
                end
                // else: stay in EVICT and keep asserting mem_req / mem_write_en
            end

            // -----------------------------------------------------------------
            // ALLOCATE_FETCH
            //   Pull the missing block from main memory into the cache.
            //   Hold here until mem_ready, then write the fetched block in and
            //   transition to COMPLETE so the CPU request can be serviced.
            // -----------------------------------------------------------------
            ALLOCATE_FETCH: begin
                way_sel      = lru_way;
                mem_req      = 1'b1;        // Request a memory transaction
                mem_write_en = 1'b0;        // This is a read (fetch)

                if (mem_ready) begin
                    // Block received from memory: install it in the cache arrays
                    tag_we     = 1'b1;      // Write new tag
                    data_we    = 1'b1;      // Write fetched data block
                    valid_we   = 1'b1;      // Mark way as valid
                    dirty_we   = 1'b1;
                    dirty_din  = 1'b0;      // Freshly fetched block is clean

                    // Now re-service the original CPU request via COMPLETE
                    next_state = COMPLETE;
                end
                // else: stay in ALLOCATE_FETCH, hold memory handshake signals
            end

            // -----------------------------------------------------------------
            // COMPLETE
            //   The missing block is now in the cache.  Service the original CPU
            //   request (read or write) in exactly one cycle, then return to IDLE.
            //
            //   Use allocated_way (latched at the ALLOCATE_FETCH→COMPLETE edge)
            //   rather than the live lru_way signal.  By the time COMPLETE runs,
            //   valid_we has already set the new way as valid, which shifts the
            //   combinational lru_way to the next invalid/oldest slot — using
            //   the live signal would corrupt the LRU age update.
            // -----------------------------------------------------------------
            COMPLETE: begin
                way_sel       = allocated_way;
                lru_update_en = 1'b1;

                if (pending_write) begin
                    // Write-allocate: write CPU data into the newly fetched block
                    data_we   = 1'b1;
                    dirty_we  = 1'b1;
                    dirty_din = 1'b1;       // This write makes the block dirty
                end
                // For a read miss: data_steer_mux.v already presents the correct
                //   word; just assert cpu_ready.

                cpu_ready  = 1'b1;
                next_state = IDLE;
            end

            // -----------------------------------------------------------------
            // Default: recover from illegal state encoding (fault tolerance)
            // -----------------------------------------------------------------
            default: begin
                next_state = IDLE;
            end

        endcase
    end

endmodule