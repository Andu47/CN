module adder_sub(
    input wire [7:0] a,
    input wire [7:0] b,
    input wire mode, // 0 pentru add, 1 pentru sub
    output wire [7:0] sum,
    output wire cout
);

    wire [7:0] b_xor;
    wire [8:0] carry;

    assign carry[0] = mode; // adauga 1 la inceput pt C2

    assign b_xor = b ^ {8{mode}}; // la scadere, inversam bitii lui b

    genvar i;
    generate 
        for(i = 0; i < 8; i = i + 1) begin : fac_loop
            fac fac (
                .a(a[i]),
                .b(b_xor[i]),
                .cin(carry[i]),
                .sum(sum[i]),
                .cout(carry[i+1])
            );
        end
    endgenerate

    assign cout = carry[8];

endmodule