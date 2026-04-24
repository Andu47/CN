module mux(
    input wire [7:0] res_adder_sub,
    input wire [15:0] res_multiplier,
    input wire [15:0] res_divider,
    input wire [1:0] sel, 
    output wire [15:0] result
);

    // umplem rezultatul de 8 biti cu zerouri ca sa incapa pe magistrala
    wire [15:0] ext_adder_sub = {8'b0, res_adder_sub};

    // decodificam operatiile cu porti logice ca sa nu folosim if
    wire sel_add_sub = ~sel[1];                  
    wire sel_mul = sel[1] & ~sel[0];             
    wire sel_div = sel[1] & sel[0];              

    // cream niste masti aplicand bitul de pe firele de mai sus peste 16 biti
    wire [15:0] mask_add_sub = {16{sel_add_sub}};
    wire [15:0] mask_mul     = {16{sel_mul}};
    wire [15:0] mask_div     = {16{sel_div}};

    // doar rezultatul corect va trece prin AND, restul devin 0
    assign result = (ext_adder_sub & mask_add_sub) | 
                    (res_multiplier & mask_mul) | 
                    (res_divider & mask_div);

endmodule