// =============================================================================
// cache_top.v
// Top-Level Structural Wrapper — Cache Controller
//
// Instantiates and connects all three sub-teams' components:
//   • (Floarea Alexandru) : address_parser, hit_detector, data_steer_mux
//   • (Popa Lucian)       : tag_array, data_array, status_array (+ LRU)
//   • (Golovatai Alexandru): cache_controller_fsm
//
// =============================================================================

`timescale 1ns / 1ps

module cache_top (
    // -------------------------------------------------------------------------
    // Global
    // -------------------------------------------------------------------------
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // CPU-side ports
    // -------------------------------------------------------------------------
    input  wire [31:0] cpu_addr,        // Full 32-bit address from CPU
    input  wire [31:0] cpu_data_in,     // Write data from CPU
    output wire [31:0] cpu_data_out,    // Read data to CPU
    input  wire        cpu_req,         // CPU issues a request
    input  wire        cpu_write_en,    // 1 = write, 0 = read
    output wire        cpu_ready,       // De-asserted while cache is busy

    // -------------------------------------------------------------------------
    // Main Memory-side ports
    // -------------------------------------------------------------------------
    output wire [31:0] mem_addr,        // Address forwarded to main memory
    inout  wire [511:0] mem_data,       // 64-byte (512-bit) full-block bus
    output wire        mem_req,
    output wire        mem_write_en,
    input  wire        mem_ready
);

    // =========================================================================
    // Internal Wires
    // =========================================================================

    // --- Address fields (from address_parser → everyone) --------------------
    wire [18:0] addr_tag;               // Bits [31:13]
    wire [6:0]  addr_index;             // Bits [12:6]   → selects 1 of 128 sets
    wire [5:0]  addr_offset;            // Bits [5:0]    → byte offset within block

    // --- Hit detection (hit_detector → FSM) ---------------------------------
    wire        cache_hit;
    wire [1:0]  hit_way;

    // --- LRU / dirty status (status_array → FSM) ----------------------------
    wire [1:0]  lru_way;
    wire        is_dirty;

    // --- FSM control outputs ------------------------------------------------
    wire        tag_we;
    wire        data_we;
    wire        valid_we;
    wire        dirty_we;
    wire        dirty_din;
    wire        lru_update_en;
    wire [1:0]  way_sel;

    // --- Tag read-back from tag_array (hit_detector needs current tags) ------
    wire [18:0] tag_out_way0, tag_out_way1, tag_out_way2, tag_out_way3;
    wire        valid_out_way0, valid_out_way1,
                valid_out_way2, valid_out_way3;

    // --- Data read from cache (data_steer_mux → CPU) ------------------------
    wire [511:0] cache_block_out;       // Full block from the matched way

    // --- Memory data routing ------------------------------------------------
    // On a fetch  (mem_write_en=0): mem_data drives data into cache
    // On an evict (mem_write_en=1): cache drives mem_data
    wire [511:0] evict_block;           // Block to be written back

    // Tri-state: FSM drives evict block onto mem_data during EVICT
    assign mem_data = mem_write_en ? evict_block : 512'bz;

    // Memory address:
    //   EVICT (mem_write_en=1): must use the VICTIM block's tag (stored in the
    //     tag_array for the lru_way), not the incoming CPU tag.  If we used the
    //     CPU tag we would write the dirty block back to the WRONG memory address.
    //   FETCH (mem_write_en=0) / all other states: use the CPU address tag.
    //
    // The victim tag is read from the tag_array using the current index and
    // the lru_way selected by status_array.  A 4:1 mux picks it here.
    wire [18:0] victim_tag;
    assign victim_tag = (way_sel == 2'b00) ? tag_out_way0 :
                        (way_sel == 2'b01) ? tag_out_way1 :
                        (way_sel == 2'b10) ? tag_out_way2 :
                                             tag_out_way3;

    assign mem_addr = mem_write_en
                    ? {victim_tag, addr_index, 6'b0}   // EVICT:  victim's address
                    : {addr_tag,   addr_index, 6'b0};  // FETCH:  CPU's address

    // =========================================================================
    // Datapath Instantiations (Floarea Alexandru)
    // =========================================================================

    // --- 3a: Address Parser --------------------------------------------------
    // Splits the 32-bit CPU address into Tag (19 bits), Index (7 bits), Offset (6 bits)
    address_parser u_addr_parser (
        .cpu_addr   (cpu_addr),
        .tag        (addr_tag),
        .index      (addr_index),
        .offset     (addr_offset)
    );

    // --- 3b: Hit Detector ----------------------------------------------------
    // Four parallel comparators, one per way.
    // Inputs:  the four stored tags + valid bits read from tag_array this cycle
    // Outputs: cache_hit (any match) and hit_way (which way matched)
    hit_detector u_hit_detector (
        .addr_tag       (addr_tag),
        // Way tags and valid bits read from tag_array 
        .tag_way0       (tag_out_way0),
        .tag_way1       (tag_out_way1),
        .tag_way2       (tag_out_way2),
        .tag_way3       (tag_out_way3),
        .valid_way0     (valid_out_way0),
        .valid_way1     (valid_out_way1),
        .valid_way2     (valid_out_way2),
        .valid_way3     (valid_out_way3),
        // Outputs to FSM
        .cache_hit      (cache_hit),
        .hit_way        (hit_way)
    );

    // --- 3c: Data Steering MUX -----------------------------------------------
    // Selects the correct 4-byte word from the matched/allocated 64-byte block
    data_steer_mux u_data_mux (
        .cache_block    (cache_block_out),  // Full 64-byte block from data_array
        .offset         (addr_offset),      // Byte offset from address_parser
        .cpu_data_out   (cpu_data_out)      // 32-bit word to CPU
    );

    // =========================================================================
    // Storage Arrays & LRU (Popa Lucian)
    // =========================================================================

    // --- Tag Array -----------------------------------------------------------
    // 128 sets × 4 ways × 19-bit tags
    // Read  : every cycle (combinational read for hit detection)
    // Write : when FSM asserts tag_we (after a successful ALLOCATE_FETCH)
    tag_array u_tag_array (
        .clk        (clk),
        .index      (addr_index),       // Set select (from address_parser)
        .way_sel    (way_sel),          // Way select (from FSM)
        .tag_in     (addr_tag),         // New tag to write (from address_parser)
        .we         (tag_we),           // Write-enable from FSM
        // Read-out: all four ways in parallel (needed by hit_detector)
        .tag_out0   (tag_out_way0),
        .tag_out1   (tag_out_way1),
        .tag_out2   (tag_out_way2),
        .tag_out3   (tag_out_way3)
    );

    // --- Data Array ----------------------------------------------------------
    // 128 sets × 4 ways × 512-bit (64-byte) blocks
    // Read  : combinational; selected way output goes to data_steer_mux
    // Write : on WRITE_HIT (word-granule update) or ALLOCATE_FETCH (full block)
    data_array u_data_array (
        .clk            (clk),
        .index          (addr_index),
        .way_sel        (way_sel),
        .offset         (addr_offset),
        // Write ports
        .we             (data_we),
        .cpu_data_in    (cpu_data_in),  // Word from CPU (used on WRITE_HIT)
        .mem_data_in    (mem_data),     // Block from memory (used on ALLOCATE_FETCH)
        .is_alloc       (~mem_write_en & mem_ready), // Full-block write when fetching
        // Read ports
        .block_out      (cache_block_out),   // → data_steer_mux
        .evict_block_out(evict_block)        // → mem_data (during EVICT)
    );

    // --- Status Array (Valid, Dirty, LRU) ------------------------------------
    // Outputs lru_way (victim way) and is_dirty (dirty bit of lru_way)
    status_array u_status_array (
        .clk            (clk),
        .rst_n          (rst_n),
        .index          (addr_index),
        .way_sel        (way_sel),
        // Write controls from FSM
        .valid_we       (valid_we),
        .dirty_we       (dirty_we),
        .dirty_din      (dirty_din),
        .lru_update_en  (lru_update_en),
        .hit_way        (hit_way),      // Tells LRU engine which way was accessed
        // Outputs to FSM
        .valid_out0     (valid_out_way0),
        .valid_out1     (valid_out_way1),
        .valid_out2     (valid_out_way2),
        .valid_out3     (valid_out_way3),
        .lru_way        (lru_way),
        .is_dirty       (is_dirty)
    );

    // =========================================================================
    // Cache Controller FSM (Golovatai Alexandru)
    // =========================================================================
    cache_controller_fsm u_fsm (
        .clk            (clk),
        .rst_n          (rst_n),
        // CPU interface
        .cpu_req        (cpu_req),
        .cpu_write_en   (cpu_write_en),
        .cpu_ready      (cpu_ready),
        // Datapath interface
        .cache_hit      (cache_hit),
        .hit_way        (hit_way),
        .lru_way        (lru_way),
        .is_dirty       (is_dirty),
        // Storage control
        .tag_we         (tag_we),
        .data_we        (data_we),
        .valid_we       (valid_we),
        .dirty_we       (dirty_we),
        .dirty_din      (dirty_din),
        .lru_update_en  (lru_update_en),
        .way_sel        (way_sel),
        // Memory interface
        .mem_req        (mem_req),
        .mem_write_en   (mem_write_en),
        .mem_ready      (mem_ready)
    );

endmodule