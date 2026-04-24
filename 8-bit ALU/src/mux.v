module mux(
    input wire [7:0] res_adder_sub,
    input wire [15:0] res_multiplier,
    input wire [15:0] res_divider,
    input wire [1:0] sel, 
    output wire [15:0] result
);

    // Daca e ADD (00) sau SUB (01), luam res_adder_sub si il extindem cu zerouri.
    // Daca e MUL (10) luam res_multiplier. Daca e DIV (11) luam res_divider.
    assign result = (sel == 2'b00 || sel == 2'b01) ? {8'b0, res_adder_sub} :
                    (sel == 2'b10) ? res_multiplier :
                    (sel == 2'b11) ? res_divider :
                    16'b0;

endmodule