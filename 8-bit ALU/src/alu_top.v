module alu_top(
    input wire clk,
    input wire rst,
    input wire start,         
    input wire [7:0] a,
    input wire [7:0] b,
    input wire [1:0] alu_op,  
    output wire [15:0] result,
    output wire done          
);

    // fire pentru legaturile interne
    wire ctrl_mode;
    wire ctrl_start_mul;
    wire ctrl_start_div;

    wire [7:0]  add_sub_res;
    wire [15:0] mul_res;
    wire [15:0] div_res;
    
    wire mul_done;
    wire div_done;

    // blocul care imparte comenzile
    control_unit cu (
        .alu_op(alu_op),
        .start(start),
        .mode(ctrl_mode),
        .start_mul(ctrl_start_mul),
        .start_div(ctrl_start_div)
    );

    // instantiem adunatorul/scazatorul
    adder_sub top_adder_sub (
        .a(a),
        .b(b),
        .mode(ctrl_mode), 
        .sum(add_sub_res),
        .cout() // nu folosim carry conform cerintei
    );

    multiplier top_multiplier (
        .clk(clk),
        .rst(rst),
        .start(ctrl_start_mul),
        .a(a),
        .b(b),
        .prod(mul_res),
        .done(mul_done)
    );

    divider top_divider (
        .clk(clk),
        .rst(rst),
        .start(ctrl_start_div),
        .a(a),
        .b(b),
        .result(div_res),
        .done(div_done)
    );

    mux top_mux (
        .res_adder_sub(add_sub_res),
        .res_multiplier(mul_res),
        .res_divider(div_res),
        .sel(alu_op),
        .result(result)
    );

    // done ramane in 1 pt add/sub (instant), altfel ia rezultatul din FSM-uri
    assign done = (alu_op == 2'b00 || alu_op == 2'b01) ? 1'b1 :
                  (alu_op == 2'b10) ? mul_done :
                  (alu_op == 2'b11) ? div_done : 1'b0;

endmodule