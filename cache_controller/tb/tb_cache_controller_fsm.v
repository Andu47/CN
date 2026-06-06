// =============================================================================
// tb_cache_controller_fsm.v  —  Cache Controller FSM Testbench
//
// FSM timing (verified by waveform trace):
//   - Inputs are applied at negedge (setup before next posedge)
//   - State register updates on posedge
//   - Combinational outputs settle and are readable at the following negedge
//
// Sequence per state hop:
//   apply inputs @negedge → @posedge (state latches) → @negedge (outputs valid)
//
// Test cases
//   TC1  Read  Hit
//   TC2  Write Hit
//   TC3  Read  Miss, clean victim → ALLOCATE_FETCH → COMPLETE
//   TC4  Write Miss, clean victim → ALLOCATE_FETCH → COMPLETE (write-allocate)
//   TC5  Read  Miss, dirty victim → EVICT → ALLOCATE_FETCH → COMPLETE
//   TC6  Write Miss, dirty victim → EVICT → ALLOCATE_FETCH → COMPLETE
//   TC7  Back-to-back Read Hits (x4, pipeline stress)
// =============================================================================
`timescale 1ns / 1ps

module tb_cache_controller_fsm;

    // ── DUT ports ─────────────────────────────────────────────────────────────
    reg        clk, rst_n;
    reg        cpu_req, cpu_write_en;
    wire       cpu_ready;
    reg        cache_hit;
    reg  [1:0] hit_way, lru_way;
    reg        is_dirty;
    wire       tag_we, data_we, valid_we, dirty_we, dirty_din, lru_update_en;
    wire [1:0] way_sel;
    wire       mem_req, mem_write_en;
    reg        mem_ready;

    cache_controller_fsm dut (
        .clk(clk),             .rst_n(rst_n),
        .cpu_req(cpu_req),     .cpu_write_en(cpu_write_en), .cpu_ready(cpu_ready),
        .cache_hit(cache_hit), .hit_way(hit_way),
        .lru_way(lru_way),     .is_dirty(is_dirty),
        .tag_we(tag_we),       .data_we(data_we),
        .valid_we(valid_we),   .dirty_we(dirty_we),
        .dirty_din(dirty_din), .lru_update_en(lru_update_en),
        .way_sel(way_sel),
        .mem_req(mem_req),     .mem_write_en(mem_write_en), .mem_ready(mem_ready)
    );

    // ── Clock: 10 ns period ───────────────────────────────────────────────────
    initial clk = 0;
    always  #5 clk = ~clk;

    // ── Scoreboard ────────────────────────────────────────────────────────────
    integer pass_count = 0, fail_count = 0;

    task chk;
        input        exp, got;
        input [239:0] lbl;
        begin
            if (exp === got) begin
                $display("    [PASS] %0s", lbl);
                pass_count = pass_count + 1;
            end else begin
                $display("    [FAIL] %0s  expected=%b  got=%b", lbl, exp, got);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ── Helpers ───────────────────────────────────────────────────────────────

    // Reset the DUT and all stimulus
    task do_reset;
        begin
            rst_n = 0; cpu_req = 0; cpu_write_en = 0;
            cache_hit = 0; hit_way = 0; lru_way = 0; is_dirty = 0; mem_ready = 0;
            @(posedge clk); @(posedge clk); rst_n = 1; @(posedge clk);
        end
    endtask

    // Acknowledge memory after 'n' wait posedges, then withdraw
    // Call this AFTER the FSM has entered the memory-handshake state.
    task mem_ack;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i+1) @(posedge clk);
            @(negedge clk); mem_ready = 1;
            @(posedge clk);          // FSM latches mem_ready=1, advances state
            @(negedge clk);          // outputs now stable in new state
            mem_ready = 0;
        end
    endtask

    // ── Timing shorthand ──────────────────────────────────────────────────────
    // "advance N state hops and land at a negedge where outputs are readable"
    task hop;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i+1) begin
                @(posedge clk);
            end
            @(negedge clk);
        end
    endtask

    // ── Main sequence ─────────────────────────────────────────────────────────
    initial begin
        $dumpfile("tb_cache_controller_fsm_sim.vcd");
        $dumpvars(0, tb_cache_controller_fsm);

        $display("============================================================");
        $display("  Cache Controller FSM — Testbench");
        $display("============================================================");

        do_reset;

        // =====================================================================
        // TC1: Read Hit
        //   Path: IDLE -1-> CHECK_HIT -1-> READ_HIT  (outputs valid @negedge)
        // =====================================================================
        $display("\n--- TC1: Read Hit ---");
        @(negedge clk);
        cpu_req = 1; cpu_write_en = 0; cache_hit = 1; hit_way = 2'b10;
        hop(2);   // land at negedge after READ_HIT is entered
        chk(1, cpu_ready,     "TC1  cpu_ready");
        chk(1, lru_update_en, "TC1  lru_update_en");
        chk(0, data_we,       "TC1  data_we==0 (read, no write)");
        chk(0, mem_req,       "TC1  mem_req==0");
        @(posedge clk);  // READ_HIT → IDLE
        cpu_req = 0; cache_hit = 0;
        @(posedge clk);

        // =====================================================================
        // TC2: Write Hit
        //   Path: IDLE -1-> CHECK_HIT -1-> WRITE_HIT
        // =====================================================================
        $display("\n--- TC2: Write Hit ---");
        @(negedge clk);
        cpu_req = 1; cpu_write_en = 1; cache_hit = 1; hit_way = 2'b00;
        hop(2);
        chk(1, cpu_ready,     "TC2  cpu_ready");
        chk(1, data_we,       "TC2  data_we");
        chk(1, dirty_we,      "TC2  dirty_we");
        chk(1, dirty_din,     "TC2  dirty_din=1 (mark dirty)");
        chk(1, lru_update_en, "TC2  lru_update_en");
        chk(0, mem_req,       "TC2  mem_req==0");
        @(posedge clk); cpu_req = 0; cpu_write_en = 0; cache_hit = 0;
        @(posedge clk);

        // =====================================================================
        // TC3: Read Miss, clean victim
        //   Path: IDLE → CHECK_HIT → ALLOCATE_FETCH → (mem_ack) → COMPLETE
        // =====================================================================
        $display("\n--- TC3: Read Miss, clean victim ---");
        @(negedge clk);
        cpu_req = 1; cpu_write_en = 0; cache_hit = 0; lru_way = 2'b01; is_dirty = 0;
        hop(2);  // land in ALLOCATE_FETCH
        chk(1, mem_req,      "TC3  mem_req (fetch)");
        chk(0, mem_write_en, "TC3  mem_write_en=0 (read)");
        // Respond after 2 wait states; mem_ack ends at negedge with new outputs
        mem_ack(2);  // FSM moves ALLOCATE_FETCH → COMPLETE; we're at negedge
        chk(1, cpu_ready,    "TC3  cpu_ready (COMPLETE)");
        chk(0, data_we,      "TC3  data_we=0 (read, no CPU write)");
        chk(1, lru_update_en,"TC3  lru_update_en");
        @(posedge clk); cpu_req = 0;
        @(posedge clk);

        // =====================================================================
        // TC4: Write Miss, clean victim  (write-allocate)
        //   Path: IDLE → CHECK_HIT → ALLOCATE_FETCH → COMPLETE
        // =====================================================================
        $display("\n--- TC4: Write Miss, clean victim (write-allocate) ---");
        @(negedge clk);
        cpu_req = 1; cpu_write_en = 1; cache_hit = 0; lru_way = 2'b11; is_dirty = 0;
        hop(2);
        chk(1, mem_req,      "TC4  mem_req (fetch)");
        chk(0, mem_write_en, "TC4  mem_write_en=0");
        mem_ack(2);
        chk(1, cpu_ready,    "TC4  cpu_ready (COMPLETE)");
        chk(1, data_we,      "TC4  data_we (write-allocate CPU write)");
        chk(1, dirty_din,    "TC4  dirty_din=1");
        chk(1, lru_update_en,"TC4  lru_update_en");
        @(posedge clk); cpu_req = 0; cpu_write_en = 0;
        @(posedge clk);

        // =====================================================================
        // TC5: Read Miss, dirty victim  (EVICT then FETCH)
        //   Path: IDLE → CHECK_HIT → EVICT → (mem_ack) → ALLOCATE_FETCH → (mem_ack) → COMPLETE
        // =====================================================================
        $display("\n--- TC5: Read Miss, dirty victim ---");
        @(negedge clk);
        cpu_req = 1; cpu_write_en = 0; cache_hit = 0; lru_way = 2'b10; is_dirty = 1;
        hop(2);  // land in EVICT
        chk(1, mem_req,      "TC5  evict mem_req");
        chk(1, mem_write_en, "TC5  evict mem_write_en=1");
        // Write-back completes; mem_ack lands us in ALLOCATE_FETCH at negedge
        mem_ack(2);
        is_dirty = 0;  // block has been written out; victim is now clean
        chk(1, mem_req,      "TC5  fetch mem_req");
        chk(0, mem_write_en, "TC5  fetch mem_write_en=0");
        mem_ack(2);   // fetch completes; land in COMPLETE
        chk(1, cpu_ready,    "TC5  cpu_ready (COMPLETE)");
        chk(0, data_we,      "TC5  data_we=0 (read miss)");
        @(posedge clk); cpu_req = 0;
        @(posedge clk);

        // =====================================================================
        // TC6: Write Miss, dirty victim  (EVICT + write-allocate)
        // =====================================================================
        $display("\n--- TC6: Write Miss, dirty victim ---");
        @(negedge clk);
        cpu_req = 1; cpu_write_en = 1; cache_hit = 0; lru_way = 2'b00; is_dirty = 1;
        hop(2);  // EVICT
        chk(1, mem_req,      "TC6  evict mem_req");
        chk(1, mem_write_en, "TC6  evict mem_write_en=1");
        mem_ack(2); is_dirty = 0;  // → ALLOCATE_FETCH
        chk(1, mem_req,      "TC6  fetch mem_req");
        chk(0, mem_write_en, "TC6  fetch mem_write_en=0");
        mem_ack(1);   // → COMPLETE
        chk(1, cpu_ready,    "TC6  cpu_ready");
        chk(1, data_we,      "TC6  write-allocate data_we");
        chk(1, dirty_din,    "TC6  dirty_din=1 after write");
        @(posedge clk); cpu_req = 0; cpu_write_en = 0;
        @(posedge clk);

        // =====================================================================
        // TC7: Back-to-back Read Hits (x4)
        // =====================================================================
        $display("\n--- TC7: Back-to-back Read Hits (x4) ---");
        cache_hit = 1; hit_way = 2'b01;
        repeat (4) begin
            @(negedge clk); cpu_req = 1;
            hop(2);
            chk(1, cpu_ready,    "TC7  cpu_ready");
            chk(1, lru_update_en,"TC7  lru_update_en");
            @(posedge clk); cpu_req = 0;
            @(posedge clk);
        end
        cache_hit = 0;

        // =====================================================================
        // Summary
        // =====================================================================
        $display("\n============================================================");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** FAILURES DETECTED — check sim/tb_cache_controller_fsm.vcd ***");
        $display("============================================================");

        $finish;
    end

endmodule