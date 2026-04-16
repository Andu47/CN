module tb_divider;
    reg clk;
    reg rst;
    reg start;
    reg [7:0] a;
    reg [7:0] b;
    wire [15:0] result; // [15:8] rest, [7:0] cat
    wire done;

    divider uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .a(a),
        .b(b),
        .result(result),
        .done(done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("divider.vcd");
        $dumpvars(0, tb_divider);

        rst = 1; start = 0; a = 0; b = 0;
        #15 rst = 0;

        // Test 1: 15 / 3
        @(posedge clk);
        a = 15; b = 3; start = 1;
        @(posedge clk);
        start = 0;
        
        wait(done);
        $display("Test 1: 15 / 3 = Cat: %d, Rest: %d", result[7:0], result[15:8]);

        #20 $finish;
    end
endmodule