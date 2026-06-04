# Cache Controller — HDL Project

4-way set-associative cache controller in Verilog, FSM-based.

| Spec          | Value                       |
| ------------- | --------------------------- |
| Cache size    | 32 KB                       |
| Block size    | 64 bytes                    |
| Sets          | 128                         |
| Associativity | 4-way                       |
| Replacement   | LRU (pseudo-LRU tree)       |
| Write policy  | Write-back + Write-allocate |

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

| State        | Description                                |
| ------------ | ------------------------------------------ |
| `IDLE`       | Waiting for CPU request                    |
| `READ_HIT`   | Tag match on read — return data in 1 cycle |
| `READ_MISS`  | No match — check if eviction needed        |
| `WRITE_HIT`  | Tag match on write — mark dirty            |
| `WRITE_MISS` | No match — allocate block                  |
| `EVICT`      | Write dirty block back to memory           |
| `MEM_FETCH`  | Fill cache block from main memory          |

---

## Address breakdown (32-bit)

```
 31      13 | 12     6 | 5      0
 [tag 19b]  | [idx 7b] | [off 6b]
```

---

## Task allocation

### Floarea Alexandru

Implement `address_parser.v` to split the CPU address into `Tag` (19 bits), `Index` (7 bits), and `Offset` (6 bits).

Implement `hit_detector.v` (instantiating 4 parallel digital comparators to check all 4 ways simultaneously).

Implement `data_steer_mux.v` to handle multiplexing the 64-byte blocks down to 4-byte words for the CPU.

Develop the global testbench (`tb_cache_top.v`) and write the simulation scripts for ModelSim.

### Golovatai Alexandru

Implement `cache_controller_fsm.v`

Design the core FSM states: `IDLE`, `READ_HIT`, `READ_MISS`, `WRITE_HIT`, `WRITE_MISS`, and `EVICT`.

Manage the complex control handshake with the CPU (e.g., handling ready/stall signals) and Main Memory (e.g., handling memory wait-states during eviction or allocation).

## FSM

| STATE          | INPUT                      | NEXT STATE     | DESCRIPTION                                                                                                   |
| -------------- | -------------------------- | -------------- | ------------------------------------------------------------------------------------------------------------- |
| IDLE           | -                          | CHECK_HIT      | If there is a request from the CPU, the Cache is checked.                                                     |
| WRITE_HIT      | pending_write & cache_hit  | IDLE           | If there is data to write and hit is found, data will be written.                                             |
| READ_HIT       | !pending_write & cahce_hit | IDLE           | If there is no data to write and a hit is found, data will be read.                                           |
| EVICT          | !cache_hit & is_dirty      | ALLOCATE_FETCH | Intermediary step to write back to memory before going to ALLOCATE_FETCH (clears the is_dirty flag)           |
| ALLOCATE_FETCH | !cache_hit & !is_dirty     | COMPLETE       | If there is a miss, but the way is not dirty, the missing block is pulled from memory.                        |
| COMPLETE       | mem_ready                  | IDLE           | After the block is brought from the memory, we set the necessary bits to show a finished cycle (cpu_ready=1). |

### Popa Lucian

Implement `tag_array.v` and `data_array.v` (handling 128 sets 4 ways).

Implement `status_array.v` to hold the `Valid` and `Dirty` bits.

Design the LRU (Least Recently Used) replacement policy engine. For a 4-way cache, this requires maintaining an age counter or a pseudo-LRU matrix for each set that updates on every hit or miss.

## Interface

```
               ┌─────────────────────────────────────────┐
               │                cache_top                │
               │                                         │
CPU_Addr   ───►│ ┌─────────────────┐   ┌───────────────┐ │───► Mem_Addr
CPU_DataIn ◄──►│ │ Team 3: Datapath│   │ Team 1: FSM   │ │◄──► Mem_Data
CPU_Req    ───►│ └────────┬────────┘   └───────┬───────┘ │───► Mem_Req
CPU_Ready  ◄───│          │                    │         │◄─── Mem_Ready
               │          ▼                    ▼         │
               │ ┌─────────────────────────────────────┐ │
               │ │         Team 2: Storage & LRU       │ │
               │ └─────────────────────────────────────┘ │
               └─────────────────────────────────────────┘
```
