## 📁 Structura Proiectului

Arhitectura proiectului este modulară, separând clar designul structural, unitatea de control și mediul de testare:

```text
8bit-ALU/
├── src/                    # Codul sursă Verilog (Design Structural)
│   ├── alu_top.v           # Wrapper-ul principal care conectează toate modulele
│   ├── arithmetic_unit.v   # Sub-wrapper pentru operații matematice
│   │   ├── adder_sub.v     # Adunător/Scăzător (Complement de 2)
│   │   ├── multiplier.v    # Implementare algoritm Booth Radix-2
│   │   └── divider.v       # Implementare Restoring Division
│   ├── logic_unit.v        # Operații logice bit-cu-bit (AND, OR, XOR, NOT)
│   ├── control_unit.v      # FSM pentru gestionarea operațiilor iterative
│   ├── mux.v               # Multiplexor pentru selecția rezultatului final
│   ├── flags.v             # Logică pentru indicatori de stare (Z, N, C, V)
│   └── registers.v         # Registre de intrare și stocare intermediară
├── tb/                     # Testbenches pentru verificarea funcționalității
│   ├── tb_alu_top.v        # Testbench global pentru întregul ALU
│   └── tb_multiplier.v     # Teste specifice pentru logica Booth
├── sim/                    # Rezultatele simulărilor (VCD, logs)
├── docs/                   # Schemele arhitecturale și raportul tehnic
└── README.md
```

## MOD DE RULARE:

# 1. Compilarea proiectului

Deschideți un terminal în VS Code și rulați următoarea comandă pentru a compila toate fișierele sursă împreună cu testbench-ul:

iverilog -o alu_sim src/\*.v tb/tb_alu_top.v

# 2. Executarea simulării

Rulați executabilul generat pentru a efectua testele definite în testbench. Această comandă va genera fișierul de date pentru forme de undă (de obicei .vcd):

vvp alu_sim

# 3. Vizualizarea în GTKWave

Pentru a verifica corectitudinea operațiilor (ex: transportul la adunare, shiftările în algoritmul Booth sau restaurarea restului la împărțire), deschideți formele de undă rezultate:

gtkwave sim/alu_wave.vcd

Notă: Asigurați-vă că testbench-ul conține apelurile $dumpfile și $dumpvars pentru a genera fișierul VCD.
