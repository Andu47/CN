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

//Partea asta nu cred ca are sens
// module registers (
//     input wire clk,
//     input wire rst,
//     input wire load_a,
//     input wire load_b,
//     input wire load_res,
//     input wire [7:0] data_a,
//     input wire [7:0] data_b,
//     input wire [7:0] data_res,
//     output wire [7:0] reg_a,
//     output wire [7:0] reg_b,
//     output wire [7:0] reg_res
// );
//     register_8 u_regA (
//         .clk (clk),  .rst(rst),
//         .load(load_a),
//         .d   (data_a), .q(reg_a)
//     );

//     register_8 u_regB (
//         .clk (clk),  .rst(rst),
//         .load(load_b),
//         .d   (data_b), .q(reg_b)
//     );

//     register_8 u_regRes (
//         .clk (clk),  .rst(rst),
//         .load(load_res),
//         .d   (data_res), .q(reg_res)
//     );
// endmodule