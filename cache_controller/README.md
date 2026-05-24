# Cache Controller — HDL Project

4-way set-associative cache controller in Verilog, FSM-based.

| Spec | Value |
|---|---|
| Cache size | 32 KB |
| Block size | 64 bytes |
| Sets | 128 |
| Associativity | 4-way |
| Replacement | LRU (pseudo-LRU tree) |
| Write policy | Write-back + Write-allocate |

## Project structure

```
cache-controller/
├── src/                        # Verilog source code (Structural & RTL Design)
│   ├── cache_top.v             # Main wrapper connecting CPU, Controller, and Memory Arrays
│   ├── cache_controller_fsm.v  # The core FSM (IDLE, HIT, MISS, EVICT states)
│   ├── datapath/               # Address parsing, hit detection, and data steering
│   │   ├── address_parser.v    # Splits CPU address into Tag, Index, and Offset
│   │   ├── hit_detector.v      # Parallel tag comparators for 4-way set associativity
│   │   └── data_steer_mux.v    # Selects correct word/way from cache to CPU or Memory
│   └── storage/                # Cache memory arrays (SRAM blocks or registers)
│       ├── tag_array.v         # Stores tags for all 4 ways across 128 sets
│       ├── data_array.v        # Stores 64-byte blocks for all 4 ways across 128 sets
│       └── status_array.v      # Tracks Valid, Dirty bits, and LRU age bits per set
├── tb/                         # Verification and Testbenches
│   ├── tb_cache_top.v          # Global testbench simulating CPU requests & Main Memory
│   └── tb_lru_logic.v          # Isolated testing for the LRU update scheme
├── sim/                        # Simulation configurations and wave files (ModelSim/vsim)
├── docs/                       # FSM state diagrams, block diagrams, and report drafts
└── README.md
```
---
## FSM States

| State | Description |
|---|---|
| `IDLE` | Waiting for CPU request |
| `READ_HIT` | Tag match on read — return data in 1 cycle |
| `READ_MISS` | No match — check if eviction needed |
| `WRITE_HIT` | Tag match on write — mark dirty |
| `WRITE_MISS` | No match — allocate block |
| `EVICT` | Write dirty block back to memory |
| `MEM_FETCH` | Fill cache block from main memory |

---

## Address breakdown (32-bit)

```
 31      13 | 12     6 | 5      0
 [tag 19b]  | [idx 7b] | [off 6b]
```

---