module dff ( //D Flip-Flop
    input  wire clk,
    input  wire rst,
    input  wire d,
    output reg q
);
    always @(posedge clk) begin
        if (rst)
            q <= 1'b0;
        else
            q <= d;
    end
endmodule


module register_8 ( //load cu prioritate
    input wire clk,
    input wire rst,
    input wire load,
    input wire [7:0] d,
    input wire shift, shift_in, 
    output wire [7:0] q
);
    wire [7:0] d_next;

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : bit
            if(i==7) begin //bitul 7 devine shift_in
                assign d_next[7] = load? d[7] : (shift? shift_in: q[7]);
            end else begin
                assign d_next[i] = load? d[i] : (shift? q[i+1] : q[i]); 
            end
            dff g_dff (.clk(clk), .rst(rst), .d(d_next[i]), .q(q[i]));
        end
    endgenerate

endmodule

module register_8_left ( // La fel ca celalalt, dar face SHIFT LA STANGA
    input wire clk,
    input wire rst,
    input wire load,
    input wire [7:0] d,
    input wire shift, shift_in, 
    output wire [7:0] q
);
    wire [7:0] d_next;
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : bit_left
            if (i == 0) begin // LSB-ul (bitul 0) primeste shift_in
                assign d_next[0] = load ? d[0] : (shift ? shift_in : q[0]);
            end else begin    // Restul primesc bitul din dreapta lor (i-1)
                assign d_next[i] = load ? d[i] : (shift ? q[i-1] : q[i]); 
            end
            dff g_dff (.clk(clk), .rst(rst), .d(d_next[i]), .q(q[i]));
        end
    endgenerate
endmodule