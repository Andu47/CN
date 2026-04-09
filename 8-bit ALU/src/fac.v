module fac (
    input wire a,
    input wire b,
    input wire cin,
    output wire sum,
    output wire cout
);

    // Ecuatiile logice pentru Suma si Transport (Carry Out)
    assign sum = a ^ b ^ cin; 
    assign cout = (a & b) | (cin & (a ^ b));

endmodule