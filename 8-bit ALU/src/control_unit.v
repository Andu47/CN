module control_unit(
    input wire [1:0] alu_op,
    input wire start,
    
    output wire mode,        // 0 pentru ADD, 1 pentru SUB
    output wire start_mul,   // Activeaza multiplicatorul
    output wire start_div    // Activeaza divizorul
);

    // Modul de adunare/scadere este dictat direct de bitul LSB al opcode-ului
    // 00 -> mod 0 (add) | 01 -> mod 1 (sub)
    assign mode = alu_op[0];

    // Pornim MUL doar daca opcode-ul este 10 si avem semnal de start
    assign start_mul = start & (alu_op == 2'b10);

    // Pornim DIV doar daca opcode-ul este 11 si avem semnal de start
    assign start_div = start & (alu_op == 2'b11);

endmodule