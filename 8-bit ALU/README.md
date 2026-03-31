8bit-ALU/
├── src/
│   ├── alu_top.v           # Wrapper-ul structural care instanțiază toate modulele
│   ├── arithmetic_unit.v   # Sub-wrapper pentru operații matematice
│   │   ├── adder_sub.v     # Adunător/Scăzător combinat (2's complement)
│   │   ├── multiplier.v    # Algoritm Booth Radix-2 (iterativ)
│   │   └── divider.v       # Algoritm Restoring Division
│   ├── logic_unit.v        # Modul separat pentru AND, OR, XOR, NOT
│   ├── control_unit.v      # FSM care gestionează semnalele "start" și "done"
│   ├── mux.v               # Selector pentru rezultatul final bazat pe opcode
│   ├── flags.v             # Logică combinatorială pentru indicatori (Z, N, C, V)
│   └── registers.v         # Registre de intrare și pentru rezultate intermediare
├── tb/
│   ├── tb_adder_sub.v      # Testare individuală pentru adunare/scădere
│   ├── tb_multiplier.v     # Testare pentru logica Booth
│   ├── tb_divider.v        # Testare pentru logica de împărțire
│   └── tb_alu_top.v        # Testbench global pentru verificarea întregului ALU
├── sim/                    # Fisiere rezultate din simulare (Icarus Verilog/ModelSim)
├── docs/                   # Schemele blocurilor și raportul final obligatoriu
└── README.md


MOD DE RULARE:
1. Compilarea proiectului
Deschideți un terminal în VS Code și rulați următoarea comandă pentru a compila toate fișierele sursă împreună cu testbench-ul:

iverilog -o alu_sim src/*.v tb/tb_alu_top.v

2. Executarea simulării
Rulați executabilul generat pentru a efectua testele definite în testbench. Această comandă va genera fișierul de date pentru forme de undă (de obicei .vcd):

vvp alu_sim

3. Vizualizarea în GTKWave
Pentru a verifica corectitudinea operațiilor (ex: transportul la adunare, shiftările în algoritmul Booth sau restaurarea restului la împărțire), deschideți formele de undă rezultate:

gtkwave sim/alu_wave.vcd

Notă: Asigurați-vă că testbench-ul conține apelurile $dumpfile și $dumpvars pentru a genera fișierul VCD.