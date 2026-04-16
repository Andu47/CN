//----------------------------------
//NU CRED CA NE TREBUIE MODULUL ASTA
//----------------------------------

module logic_unit (
    input wire [7:0] A,
    input wire [7:0] B,
    input wire [1:0] op,
    output wire [7:0] result
);
    wire [7:0] and_result, or_result, xor_result, not_result;

    assign and_result = A & B; // 00
    assign or_result = A | B; // 01
    assign xor_result = A ^ B; // 10
    assign not_result = ~A; // 11

    assign result = (op == 2'b00) ? and_result :
                     (op == 2'b01) ? or_result :
                     (op == 2'b10) ? xor_result :
                     not_result;

endmodule