`timescale 1ns / 1ps

module tb_alu_top;

    reg clk;
    reg rst;
    reg start;
    reg [7:0] a;
    reg [7:0] b;
    reg [1:0] alu_op;

    wire [15:0] result;
    wire done;

    alu_top uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .a(a),
        .b(b),
        .alu_op(alu_op),
        .result(result),
        .done(done)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim_alu.vcd");
        $dumpvars(0, tb_alu_top);

        clk = 0;
        rst = 1;
        start = 0;
        a = 0;
        b = 0;
        alu_op = 0;

        #15 rst = 0; 
        $display("Incepem simularea pt ALU...");

        // test add
        alu_op = 2'b00;
        a = 8'd25;   
        b = 8'd15;   
        #10;
        $display("ADD: %0d + %0d = %0d", a, b, result[7:0]);

        // test sub
        alu_op = 2'b01;
        a = 8'd50;   
        b = 8'd20;   
        #10;
        $display("SUB: %0d - %0d = %0d", a, b, result[7:0]);

        // test inmultire
        alu_op = 2'b10;
        a = 8'd12;   
        b = 8'd5;    
        
        start = 1; 
        #10 start = 0; 

        @(posedge done); 
        @(negedge done); // asteptam curatarea FSM-ului
        #10;
        $display("MUL: %0d * %0d = %0d", a, b, result);

        // inmultire numere negative (verificare Booth)
        a = 8'b1111_1110; // -2
        b = 8'd15;        // 15
        start = 1;
        #10 start = 0;
        
        @(posedge done);
        @(negedge done);
        #10;
        $display("MUL (negativ): -2 * 15 = %0d", $signed(result));

        // test impartire
        alu_op = 2'b11;
        a = 8'd45;   
        b = 8'd7;    
        
        start = 1;
        #10 start = 0;

        @(posedge done);
        @(negedge done); 
        #10;
        
        // impartim result in doua ca sa scoatem restul si catul
        $display("DIV: %0d / %0d -> Cat = %0d, Rest = %0d", a, b, result[7:0], result[15:8]);

        $finish;
    end

endmodule