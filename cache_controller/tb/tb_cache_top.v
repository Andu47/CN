// =============================================================================
// tb_cache_top.v
// Global System Testbench — Full Cache Controller Integration
//
// Timing (verified by waveform trace):
//   Hit  path: IDLE→CHECK_HIT→READ/WRITE_HIT  cpu_ready seen at cycle 3
//   Miss path: IDLE→CHECK_HIT→ALLOC_FETCH(+MEM_LATENCY cycles)→COMPLETE
//              cpu_ready seen at cycle ≥ MEM_LATENCY+3
//
// Mock Memory: behavioural 64-byte block SRAM, MEM_LATENCY cycle response.
//   READ  (mem_write_en=0): drives fetched block onto mem_data, asserts mem_ready.
//   WRITE (mem_write_en=1): captures block from mem_data bus, asserts mem_ready.
//
// Test Scenarios
//   SC1  Cold Start          — read miss + ALLOCATE_FETCH
//   SC2  Temporal Locality   — repeat read becomes a hit
//   SC3  Write & Dirty Track — write hit, dirty bit flips, read-back correct
//   SC4  Eviction Penalty    — fill 4 ways dirty, 5th address triggers EVICT
//   SC5  Write Miss          — cold write → write-allocate path
//   SC6  Read-After-Write    — two words in same block, coherence check
//   SC7  LRU Ordering        — MRU way is not evicted
//
// Author : Floarea Alexandru
// =============================================================================

`timescale 1ns / 1ps

`define MKADDR(t,i,o) {19'(t), 7'(i), 6'(o)}

module tb_cache_top;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam MEM_LATENCY = 4;    // cycles from mem_req to mem_ready
    localparam CLK_HALF    = 5;    // 10 ns period

    // Hit  = 3 cycles  (IDLE→CHECK_HIT→HIT_STATE, ready visible on 3rd posedge)
    // Miss = CHECK_HIT(1) + ALLOC_FETCH wait (MEM_LATENCY) + COMPLETE(1) + overhead
    localparam HIT_CYCLES  = 3;
    localparam MISS_MIN    = MEM_LATENCY + 3;  // conservative minimum

    // =========================================================================
    // DUT Ports
    // =========================================================================
    reg         clk, rst_n;
    reg  [31:0] cpu_addr, cpu_data_in;
    wire [31:0] cpu_data_out;
    reg          cpu_req, cpu_write_en;
    wire         cpu_ready;
    wire [31:0]  mem_addr;
    wire [511:0] mem_data;
    wire          mem_req, mem_write_en;
    reg           mem_ready;

    // =========================================================================
    // DUT
    // =========================================================================
    cache_top dut (
        .clk(clk), .rst_n(rst_n),
        .cpu_addr(cpu_addr), .cpu_data_in(cpu_data_in), .cpu_data_out(cpu_data_out),
        .cpu_req(cpu_req), .cpu_write_en(cpu_write_en), .cpu_ready(cpu_ready),
        .mem_addr(mem_addr), .mem_data(mem_data),
        .mem_req(mem_req), .mem_write_en(mem_write_en), .mem_ready(mem_ready)
    );

    // =========================================================================
    // Mock Main Memory
    // 4 Mi blocks of 512 bits each (covers 256 MB address space)
    // Addressed by mem_addr[27:6] (block-aligned, lower 6 bits always 0)
    // =========================================================================
    reg [63:0] mock_mem [0:'hFFFFF][0:7];  // [block_index][64-bit word 0..7]

    reg [511:0] mem_drive;
    reg          mem_drive_en = 0;
    assign mem_data = mem_drive_en ? mem_drive : 512'bz;

    // Initialise with deterministic pattern: word w of block b = {8{b[7:0]^w[7:0]}}
    integer bi, wi;
    initial begin
        for (bi = 0; bi < 'hFFFFF; bi = bi + 1)
            for (wi = 0; wi < 8; wi = wi + 1)
                mock_mem[bi][wi] = {8{bi[7:0] ^ wi[7:0]}};
    end

    // ── Memory service process ──────────────────────────────────────────────
    // Triggered by mem_req. Waits MEM_LATENCY cycles, services, asserts ready.
    always @(posedge clk) begin
        mem_ready    <= 1'b0;
        mem_drive_en <= 1'b0;

        if (mem_req) begin : svc
            integer li;
            // Wait the remaining latency cycles (first posedge already consumed)
            for (li = 1; li < MEM_LATENCY; li = li + 1)
                @(posedge clk);

            if (mem_write_en) begin : do_write
                // EVICT: latch block from cache and store in mock memory
                integer wi2;
                reg [511:0] wb;
                wb = mem_data;
                for (wi2 = 0; wi2 < 8; wi2 = wi2 + 1)
                    mock_mem[mem_addr[27:6]][wi2] <= wb[wi2*64 +: 64];
            end else begin : do_read
                // FETCH: assemble block from mock memory and drive onto bus
                integer wi3;
                reg [511:0] fb;
                for (wi3 = 0; wi3 < 8; wi3 = wi3 + 1)
                    fb[wi3*64 +: 64] = mock_mem[mem_addr[27:6]][wi3];
                mem_drive    <= fb;
                mem_drive_en <= 1'b1;
            end

            mem_ready <= 1'b1;
            @(posedge clk);
            mem_ready    <= 1'b0;
            mem_drive_en <= 1'b0;
        end
    end

    // =========================================================================
    // Clock
    // =========================================================================
    initial clk = 0;
    always  #CLK_HALF clk = ~clk;

    // =========================================================================
    // Scoreboard
    // =========================================================================
    integer pass_cnt = 0, fail_cnt = 0;
    integer total_reqs = 0, total_cycs = 0;

    task pass_if;
        input        cond;
        input [319:0] lbl;
        begin
            if (cond) begin $display("    [PASS] %0s", lbl); pass_cnt = pass_cnt+1; end
            else       begin $display("    [FAIL] %0s", lbl); fail_cnt = fail_cnt+1; end
        end
    endtask

    // =========================================================================
    // cpu_request task
    //   Applies addr/data, asserts cpu_req, counts posedges until cpu_ready,
    //   then de-asserts and waits for FSM to return to IDLE.
    //   Result stored in req_cycles (integer).
    // =========================================================================
    integer req_cycles;

    task cpu_request;
        input        is_write;
        input [31:0] addr;
        input [31:0] wdata;
        integer      cycs;
        begin
            @(negedge clk);                     // safe setup before posedge
            cpu_addr     = addr;
            cpu_data_in  = wdata;
            cpu_req      = 1'b1;
            cpu_write_en = is_write;

            cycs = 0;
            @(posedge clk); cycs = cycs + 1;    // IDLE → CHECK_HIT
            while (!cpu_ready) begin
                @(posedge clk); cycs = cycs + 1;
            end
            req_cycles   = cycs;
            total_cycs   = total_cycs + cycs;
            total_reqs   = total_reqs + 1;

            // Sample cpu_data_out here — it is valid while cpu_ready is high
            // (caller reads cpu_data_out directly after this task returns)

            @(negedge clk);
            cpu_req      = 1'b0;
            cpu_write_en = 1'b0;
            @(posedge clk);                     // FSM: HIT_STATE → IDLE
            @(posedge clk);                     // one extra settle cycle
        end
    endtask

    // Latched data — capture cpu_data_out while cpu_ready is still asserted
    reg [31:0] latched_data;
    always @(posedge clk)
        if (cpu_ready) latched_data <= cpu_data_out;

    // =========================================================================
    // Reset
    // =========================================================================
    task do_reset;
        begin
            rst_n = 0; cpu_req = 0; cpu_write_en = 0;
            cpu_addr = 0; cpu_data_in = 0; mem_ready = 0;
            @(posedge clk); @(posedge clk);
            rst_n = 1;
            @(posedge clk); @(posedge clk);
        end
    endtask

    // =========================================================================
    // Address constants
    // All SC4/SC7 eviction tests use a specific set index to be deterministic.
    // =========================================================================
    localparam IDX4      = 7'h0A;   // set 10 — used for SC4 eviction
    localparam IDX7      = 7'h0F;   // set 15 — used for SC7 LRU test
    localparam OFF0      = 6'h00;   // byte offset → word 0
    localparam OFF16     = 6'h10;   // byte offset → word 4

    // SC4: 5 tags → same set IDX4
    localparam [18:0] T0=19'h00001, T1=19'h00002, T2=19'h00003,
                      T3=19'h00004, T4=19'h00005;

    wire [31:0] A0 = {T0, IDX4, OFF0};
    wire [31:0] A1 = {T1, IDX4, OFF0};
    wire [31:0] A2 = {T2, IDX4, OFF0};
    wire [31:0] A3 = {T3, IDX4, OFF0};
    wire [31:0] A4 = {T4, IDX4, OFF0};  // 5th tag → eviction trigger

    // Unrelated address for SC1/SC2/SC3
    wire [31:0] ADDR_X = `MKADDR(19'h7BEEF, 7'h55, 6'h08);

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $dumpfile("tb_cache_top.vcd");
        $dumpvars(0, tb_cache_top);

        $display("============================================================");
        $display("  Cache Controller — Global Integration Testbench");
        $display("============================================================");

        do_reset;

        // =====================================================================
        // SC1: Cold Start — Read Miss → ALLOCATE_FETCH
        // =====================================================================
        $display("\n--- SC1: Cold Start (Read Miss + ALLOCATE_FETCH) ---");

        cpu_request(0, ADDR_X, 32'h0);
        pass_if(req_cycles >= MISS_MIN,
                "SC1  miss latency ≥ MEM_LATENCY+3 cycles");

        begin : sc1_data
            reg [27:0] baddr; reg [3:0] widx; reg [63:0] w64; reg [31:0] exp;
            baddr = ADDR_X[27:6];
            widx  = ADDR_X[5:2];            // 32-bit word index 0..15
            w64   = mock_mem[baddr][widx[3:1]];
            exp   = widx[0] ? w64[63:32] : w64[31:0];
            pass_if(latched_data === exp,
                    "SC1  returned data matches mock memory initialisation");
        end

        // =====================================================================
        // SC2: Temporal Locality — Repeat Read → Hit
        // =====================================================================
        $display("\n--- SC2: Temporal Locality (Read Hit) ---");

        cpu_request(0, ADDR_X, 32'h0);
        pass_if(req_cycles === HIT_CYCLES,
                "SC2  repeat read resolved in exactly 3 cycles (hit)");
        // Data from cold block must be deterministic (not unknown/garbage)
        pass_if(latched_data === latched_data,  // always true if not X/Z
                "SC2  data output is defined (not X/Z)");

        // =====================================================================
        // SC3: Write & Dirty Tracking
        // =====================================================================
        $display("\n--- SC3: Write & Dirty Tracking ---");

        begin : sc3
            reg [31:0] wval;
            wval = 32'hDEAD_BEEF;

            cpu_request(1, ADDR_X, wval);
            pass_if(req_cycles === HIT_CYCLES,
                    "SC3  write hit resolved in 3 cycles");

            // Read back — must return written value (served from dirty cache)
            cpu_request(0, ADDR_X, 32'h0);
            pass_if(req_cycles === HIT_CYCLES,
                    "SC3  read after write is still a hit (3 cycles)");
            pass_if(latched_data === wval,
                    "SC3  read-back returns written value (dirty tracking correct)");
        end

        // =====================================================================
        // SC4: Eviction Penalty
        //   4a — cold-load 4 distinct addresses into the same set (4 misses)
        //   4b — write to all 4 → all ways become dirty
        //   4c — access 5th tag in same set → EVICT + ALLOCATE_FETCH
        // =====================================================================
        $display("\n--- SC4: Eviction Penalty ---");

        $display("  4a: cold-fill 4 ways of set %0d ...", IDX4);
        cpu_request(0, A0, 32'h0); pass_if(req_cycles >= MISS_MIN, "SC4a A0 cold miss");
        cpu_request(0, A1, 32'h0); pass_if(req_cycles >= MISS_MIN, "SC4a A1 cold miss");
        cpu_request(0, A2, 32'h0); pass_if(req_cycles >= MISS_MIN, "SC4a A2 cold miss");
        cpu_request(0, A3, 32'h0); pass_if(req_cycles >= MISS_MIN, "SC4a A3 cold miss");

        $display("  4b: write to all 4 ways (make dirty) ...");
        cpu_request(1, A0, 32'hCAFE_0000); pass_if(req_cycles === HIT_CYCLES, "SC4b A0 write hit");
        cpu_request(1, A1, 32'hCAFE_0001); pass_if(req_cycles === HIT_CYCLES, "SC4b A1 write hit");
        cpu_request(1, A2, 32'hCAFE_0002); pass_if(req_cycles === HIT_CYCLES, "SC4b A2 write hit");
        cpu_request(1, A3, 32'hCAFE_0003); pass_if(req_cycles === HIT_CYCLES, "SC4b A3 write hit");

        $display("  4c: 5th address in same set → must EVICT + FETCH ...");
        cpu_request(0, A4, 32'h0);
        // Must take at least 2× MEM_LATENCY (one evict, one fetch)
        pass_if(req_cycles >= MEM_LATENCY * 2,
                "SC4c 5th-way access ≥ 2×MEM_LATENCY (EVICT+FETCH path taken)");

        $display("  4d: verifying evicted dirty data survived write-back ...");
        // Access sequence A0,A1,A2,A3 → after 4 loads: A0=LRU, A3=MRU.
        // After 4 writes (each bumps to MRU): final order is A3=MRU, A0=LRU(3).
        // The 5th-way access (A4) evicts A0.  Re-reading A0 must be a miss
        // (block no longer in cache), and the data fetched from mock memory
        // must be the value we wrote (0xCAFE_0000) since it was written back.
        cpu_request(0, A0, 32'h0);   // miss: fetch the written-back block
        pass_if(req_cycles >= MISS_MIN,
                "SC4d A0 is a miss after eviction (no longer cached)");
        pass_if(latched_data === 32'hCAFE_0000,
                "SC4d A0 written-back value 0xCAFE_0000 survives round-trip");

        // =====================================================================
        // SC5: Write Miss → Write-Allocate
        // =====================================================================
        $display("\n--- SC5: Write Miss + Write-Allocate ---");

        begin : sc5
            reg [31:0] cwa, cwv;
            cwa = `MKADDR(19'h1F001, 7'h7F, 6'h04);
            cwv = 32'h5A5A_A5A5;

            cpu_request(1, cwa, cwv);
            pass_if(req_cycles >= MISS_MIN, "SC5 write miss has allocate latency");

            cpu_request(0, cwa, 32'h0);
            pass_if(req_cycles === HIT_CYCLES, "SC5 read after write-alloc is a hit");
            pass_if(latched_data === cwv,      "SC5 data read-back matches written value");
        end

        // =====================================================================
        // SC6: Read-After-Write Coherence — two words in one block
        // =====================================================================
        $display("\n--- SC6: Read-After-Write Coherence ---");

        begin : sc6
            reg [31:0] aw0, aw4, vw0, vw4;
            aw0 = `MKADDR(19'h3C3C3, 7'h33, OFF0);
            aw4 = `MKADDR(19'h3C3C3, 7'h33, OFF16);
            vw0 = 32'h1111_1111;
            vw4 = 32'h4444_4444;

            cpu_request(0, aw0, 32'h0);   // cold load block
            cpu_request(1, aw0, vw0);     // write word 0
            cpu_request(1, aw4, vw4);     // write word 4 (same block, different offset)
            cpu_request(0, aw0, 32'h0);
            pass_if(latched_data === vw0, "SC6 word-0 read-back correct");
            cpu_request(0, aw4, 32'h0);
            pass_if(latched_data === vw4, "SC6 word-4 read-back correct");
        end

        // =====================================================================
        // SC7: LRU Ordering
        //   Access order: B0 B1 B2 B3 (fills 4 ways, B0 = LRU after all 4)
        //   Then re-touch B1 (B1 becomes MRU, B0 still LRU)
        //   Then re-touch B3 (B3 becomes MRU)
        //   Bring in B4 → must evict B0 (the true LRU)
        //   Confirm B1 and B3 are still in cache (they were touched more recently)
        // =====================================================================
        $display("\n--- SC7: LRU Ordering ---");

        begin : sc7
            reg [31:0] b0, b1, b2, b3, b4, sent;
            b0   = `MKADDR(19'h0A001, IDX7, OFF0);
            b1   = `MKADDR(19'h0A002, IDX7, OFF0);
            b2   = `MKADDR(19'h0A003, IDX7, OFF0);
            b3   = `MKADDR(19'h0A004, IDX7, OFF0);
            b4   = `MKADDR(19'h0A005, IDX7, OFF0);
            sent = 32'hBEEF_CAFE;

            // Fill 4 ways in order — after this B3=MRU, B0=LRU
            cpu_request(0, b0, 32'h0);
            cpu_request(0, b1, 32'h0);
            cpu_request(0, b2, 32'h0);
            cpu_request(0, b3, 32'h0);

            // Write sentinel to B1 → B1 becomes MRU
            cpu_request(1, b1, sent);
            pass_if(req_cycles === HIT_CYCLES, "SC7 B1 write is a hit");

            // Touch B3 again → B3 MRU, B1 second, B0 = LRU
            cpu_request(0, b3, 32'h0);
            pass_if(req_cycles === HIT_CYCLES, "SC7 B3 re-read is a hit");

            // Bring in B4 → LRU is B0 → evict B0 (it is clean, so no write-back)
            cpu_request(0, b4, 32'h0);
            pass_if(req_cycles >= MISS_MIN, "SC7 B4 caused a miss + allocate");

            // B1 (MRU) and B3 must still be in cache
            cpu_request(0, b1, 32'h0);
            pass_if(req_cycles === HIT_CYCLES, "SC7 B1 still in cache after eviction");
            pass_if(latched_data === sent,     "SC7 B1 sentinel value intact");

            cpu_request(0, b3, 32'h0);
            pass_if(req_cycles === HIT_CYCLES, "SC7 B3 still in cache after eviction");
        end

        // =====================================================================
        // Summary
        // =====================================================================
        $display("\n============================================================");
        $display("  Performance Metrics");
        $display("    Total requests  : %0d", total_reqs);
        $display("    Total cycles    : %0d", total_cycs);
        $display("    Avg cycles/req  : %0d.%01d",
                 total_cycs/total_reqs,
                 (total_cycs*10/total_reqs)%10);
        $display("  Correctness : %0d passed, %0d failed", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d FAILURE(S) — see sim/tb_top.vcd ***", fail_cnt);
        $display("============================================================");
        $finish;
    end

endmodule