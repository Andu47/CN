module flags(
    input wire [7:0] A,
    input wire [7:0] B,
    input wire [7:0] result,
    input wire c_out,
    output wire Z,
    output wire N,
    output wire C,
    output wire V
);

    assign Z = ~|result;
    assign N = result[7];
    assign C = c_out;
    assign V = (~A[7] ^ B[7]) & (A[7] ^ result[7]);

endmodule