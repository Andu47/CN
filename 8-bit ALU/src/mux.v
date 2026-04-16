module mux(
    input wire [7:0] res_adder_sub, // 00
    input wire [7:0] res_multiplier, // 01
    input wire [7:0] res_divider, // 10
    input wire [1:0] sel, 
    output wire [7:0] result
);

    assign result = (sel == 2'b00) ? res_adder_sub :
                    (sel == 2'b01) ? res_multiplier :
                    (sel == 2'b10) ? res_divider :
                    8'b0;

endmodule