`timescale 1ns / 1ps

module tb_adder_sub;

    // Intrările (reg pentru a le putea schimba valoarea)
    reg [7:0] a;
    reg [7:0] b;
    reg mode;

    // Ieșirile (wire pentru a le citi din modul)
    wire [7:0] sum;
    wire cout;

    // Instanțierea modulului
    adder_sub DUT (
        .a(a),
        .b(b),
        .mode(mode),
        .sum(sum),
        .cout(cout)
    );

    initial begin
        // Generarea formelor de undă în folderul sim/ pe care tocmai l-ai creat
        $dumpfile("adder_sub_waves.vcd");
        $dumpvars(0, tb_adder_sub);

        // Header pentru consolă
        $display("Timp | Mod |  A  |  B  | Sum/Dif | Cout | Suma (Binar)");
        $display("---------------------------------------------------------");
        
        // Folosim %d pentru a afișa valorile în format zecimal, e mult mai ușor de citit!
        $monitor("%4t |  %b  | %3d | %3d |   %3d   |   %b  | %8b", 
                 $time, mode, a, b, sum, cout, sum);

        // ==========================================
        // 1. TESTE DE ADUNARE (mode = 0)
        // ==========================================
        $display("\n--- Incepere Teste Adunare ---");
        mode = 0;
        
        a = 8'd10;  b = 8'd15;  #10;  // Test normal: 10 + 15 = 25
        a = 8'd100; b = 8'd50;  #10;  // Test normal: 100 + 50 = 150
        a = 8'd255; b = 8'd1;   #10;  // Test Overflow: 255 + 1 = 0 (Cout trebuie să devină 1)

        // ==========================================
        // 2. TESTE DE SCĂDERE (mode = 1)
        // ==========================================
        $display("\n--- Incepere Teste Scadere ---");
        mode = 1;
        
        a = 8'd20;  b = 8'd5;   #10;  // Test normal: 20 - 5 = 15
        a = 8'd50;  b = 8'd50;  #10;  // Test zero: 50 - 50 = 0
        a = 8'd5;   b = 8'd10;  #10;  // Test negativ: 5 - 10 = -5 (În binar va apărea ca 251, Complement de 2)
        a = 8'd0;   b = 8'd1;   #10;  // Test Underflow: 0 - 1 = -1 (Suma binară va fi 11111111)

        $display("\nSimulare completa!");
        $finish;
    end

endmodule