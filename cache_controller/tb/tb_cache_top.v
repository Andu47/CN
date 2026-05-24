// =============================================================================
// tb_cache_controller.v  —  Testbench for Cache Controller
// =============================================================================
// Covers:
//   TC1  – Read Miss  → MEM_FETCH → Read Hit
//   TC2  – Write Miss → MEM_FETCH → Write Hit
//   TC3  – Write Hit  (dirty block)
//   TC4  – Evict      (dirty block forced out by conflict)
//   TC5  – LRU eviction ordering (4 ways filled, 5th access forces evict)
// =============================================================================

`timescale 1ns/1ps

module tb_cache_controller;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg         clk, rst_n;
    reg         cpu_req, cpu_we;
    reg  [31:0] cpu_addr, cpu_wdata;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;
    wire        mem_req, mem_we;
    wire [31:0] mem_addr, mem_wdata;
    reg  [31:0] mem_rdata;
    reg         mem_ready;

    // -------------------------------------------------------------------------
    // Performance counters
    // -------------------------------------------------------------------------
    integer total_accesses, hit_count, miss_count;

    // -------------------------------------------------------------------------
    // Instantiate DUT
    // -------------------------------------------------------------------------
    cache_controller dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .cpu_req   (cpu_req),
        .cpu_we    (cpu_we),
        .cpu_addr  (cpu_addr),
        .cpu_wdata (cpu_wdata),
        .cpu_rdata (cpu_rdata),
        .cpu_ready (cpu_ready),
        .mem_req   (mem_req),
        .mem_we    (mem_we),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_rdata (mem_rdata),
        .mem_ready (mem_ready)
    );

    // -------------------------------------------------------------------------
    // Clock — 10 ns period
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Simple memory model (latency = 3 cycles)
    // -------------------------------------------------------------------------
    reg [31:0] main_mem [0:4095];
    reg [1:0]  mem_delay_cnt;

    initial begin : mem_init
        integer m;
        for (m = 0; m < 4096; m = m + 1)
            main_mem[m] = m * 4 + 32'hA000_0000;
    end

    always @(posedge clk) begin
        mem_ready <= 1'b0;
        if (mem_req && !mem_we) begin          // read request
            if (mem_delay_cnt == 2) begin
                mem_rdata     <= main_mem[mem_addr[13:2]];
                mem_ready     <= 1'b1;
                mem_delay_cnt <= 0;
            end else begin
                mem_delay_cnt <= mem_delay_cnt + 1;
            end
        end else if (mem_req && mem_we) begin  // write-back request
            if (mem_delay_cnt == 2) begin
                main_mem[mem_addr[13:2]] <= mem_wdata;
                mem_ready     <= 1'b1;
                mem_delay_cnt <= 0;
            end else begin
                mem_delay_cnt <= mem_delay_cnt + 1;
            end
        end else begin
            mem_delay_cnt <= 0;
        end
    end

    // -------------------------------------------------------------------------
    // VCD dump for GTKWave / ModelSim
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("sim/dump.vcd");
        $dumpvars(0, tb_cache_controller);
    end

    // -------------------------------------------------------------------------
    // Task: issue a CPU request and wait for completion
    // -------------------------------------------------------------------------
    task cpu_access;
        input        is_write;
        input [31:0] addr;
        input [31:0] wdata;
        begin
            @(posedge clk);
            cpu_req   <= 1'b1;
            cpu_we    <= is_write;
            cpu_addr  <= addr;
            cpu_wdata <= wdata;

            total_accesses = total_accesses + 1;

            // Wait for ready
            @(posedge clk);
            while (!cpu_ready) @(posedge clk);

            if (cpu_ready && !dut.u_cache_mem.hit)
                miss_count = miss_count + 1;
            else
                hit_count  = hit_count  + 1;

            cpu_req <= 1'b0;
            @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    initial begin
        $display("=== Cache Controller Testbench Start ===");
        total_accesses = 0; hit_count = 0; miss_count = 0;

        // Reset
        rst_n = 0; cpu_req = 0; cpu_we = 0;
        cpu_addr = 0; cpu_wdata = 0;
        mem_rdata = 0; mem_ready = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // -----------------------------------------------------------------
        // TC1: Read Miss — address maps to set 0, should miss then fill
        // -----------------------------------------------------------------
        $display("[TC1] Read Miss + subsequent Read Hit");
        cpu_access(0, 32'h0000_0040, 32'h0);   // READ — set 0, expect miss
        cpu_access(0, 32'h0000_0040, 32'h0);   // READ — same addr, expect hit

        // -----------------------------------------------------------------
        // TC2: Write Miss → Write-allocate → Write Hit
        // -----------------------------------------------------------------
        $display("[TC2] Write Miss + Write Hit");
        cpu_access(1, 32'h0000_0500, 32'hDEAD_BEEF);  // WRITE miss → allocate
        cpu_access(1, 32'h0000_0500, 32'hCAFE_BABE);  // WRITE hit

        // -----------------------------------------------------------------
        // TC3: Read after write (dirty hit)
        // -----------------------------------------------------------------
        $display("[TC3] Read after Write (dirty hit)");
        cpu_access(0, 32'h0000_0500, 32'h0);   // READ — should be hit (dirty)

        // -----------------------------------------------------------------
        // TC4: Fill all 4 ways in one set, then conflict → evict dirty
        // -----------------------------------------------------------------
        $display("[TC4] Eviction of dirty block");
        // Each address below maps to set 5 (bits [12:6] = 7'b000_0101)
        // Tag changes every 8KB (2^13 bytes)
        cpu_access(1, 32'h0000_01C0, 32'h1111_1111);  // way 0 – miss + allocate
        cpu_access(1, 32'h0020_01C0, 32'h2222_2222);  // way 1 – miss + allocate
        cpu_access(1, 32'h0040_01C0, 32'h3333_3333);  // way 2 – miss + allocate
        cpu_access(1, 32'h0060_01C0, 32'h4444_4444);  // way 3 – miss + allocate
        // 5th unique tag → LRU way is dirty → EVICT state triggered
        cpu_access(0, 32'h0080_01C0, 32'h0);          // should evict LRU way

        // -----------------------------------------------------------------
        // TC5: Sequential scan (stress test, mostly misses)
        // -----------------------------------------------------------------
        $display("[TC5] Sequential scan (16 unique lines)");
        begin : scan
            integer s;
            for (s = 0; s < 16; s = s + 1)
                cpu_access(0, s * 32'h0000_0040, 32'h0);
        end

        // -----------------------------------------------------------------
        // Results
        // -----------------------------------------------------------------
        $display("=== Simulation Complete ===");
        $display("  Total accesses : %0d", total_accesses);
        $display("  Hits           : %0d", hit_count);
        $display("  Misses         : %0d", miss_count);
        $display("  Hit rate       : %0d%%",
                 (total_accesses > 0) ? (hit_count * 100 / total_accesses) : 0);

        #50;
        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog — prevents infinite hang
    // -------------------------------------------------------------------------
    initial begin
        #500000;
        $display("TIMEOUT — simulation exceeded limit");
        $finish;
    end

endmodule
