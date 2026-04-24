module alu_top(
    input wire clk,
    input wire rst,
    input wire start,         // Apasat pentru a porni Mul/Div
    input wire [7:0] a,
    input wire [7:0] b,
    input wire [1:0] alu_op,  // 00=ADD, 01=SUB, 10=MUL, 11=DIV
    
    output wire [15:0] result,
    output wire done          // Devine 1 cand rezultatul este gata
);

    // ==========================================
    // Semnale interne de legatura
    // ==========================================
    
    // Semnale de control generate de Control Unit
    wire ctrl_mode;
    wire ctrl_start_mul;
    wire ctrl_start_div;

    // Iesiri din unitatile aritmetice
    wire [7:0]  add_sub_res;
    wire [15:0] mul_res;
    wire [15:0] div_res;
    
    // Semnale "done" de la Mul si Div
    wire mul_done;
    wire div_done;

    // ==========================================
    // Instantierea Modulelor
    // ==========================================

    // 1. Control Unit
    control_unit cu (
        .alu_op(alu_op),
        .start(start),
        .mode(ctrl_mode),
        .start_mul(ctrl_start_mul),
        .start_div(ctrl_start_div)
    );

    // 2. Unitatea de Adunare / Scadere Combinationala
    adder_sub top_adder_sub (
        .a(a),
        .b(b),
        .mode(ctrl_mode), 
        .sum(add_sub_res),
        .cout() // Ignoram Carry-ul din cerinta strict aritmetica
    );

    // 3. Multiplicatorul Booth Radix-2
    multiplier top_multiplier (
        .clk(clk),
        .rst(rst),
        .start(ctrl_start_mul),
        .a(a),
        .b(b),
        .prod(mul_res),
        .done(mul_done)
    );

    // 4. Impartitorul Restoring
    divider top_divider (
        .clk(clk),
        .rst(rst),
        .start(ctrl_start_div),
        .a(a),
        .b(b),
        .result(div_res),
        .done(div_done)
    );

    // 5. Multiplexorul de iesire
    mux top_mux (
        .res_adder_sub(add_sub_res),
        .res_multiplier(mul_res),
        .res_divider(div_res),
        .sel(alu_op),
        .result(result)
    );

    // ==========================================
    // Logica pentru semnalul DONE general
    // ==========================================
    
    // Daca este ADD (00) sau SUB (01), operatia este combinationala si e gata instant
    // Daca este MUL (10) sau DIV (11), asteptam dupa FSM-urile respective
    assign done = (alu_op == 2'b00 || alu_op == 2'b01) ? 1'b1 :
                  (alu_op == 2'b10) ? mul_done :
                  (alu_op == 2'b11) ? div_done : 1'b0;

endmodule