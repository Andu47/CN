`timescale 1ns / 1ps

module tb_multiplier;

    // 1. Declararea semnalelor (reg pentru intrări, wire pentru ieșiri)
    reg [7:0] a;
    reg [7:0] b;
    reg clk;
    reg rst;
    reg start;

    wire [15:0] prod;
    wire done;

    // 2. Instanțierea Multiplicatorului (UUT - Unit Under Test)
    multiplier uut (
        .a(a),
        .b(b),
        .clk(clk),
        .rst(rst),
        .start(start),
        .prod(prod),
        .done(done)
    );

    // 3. Generarea semnalului de ceas (Isi schimba starea la fiecare 5ns -> Perioada 10ns)
    always #5 clk = ~clk;

    // 4. Blocul de stimulare
    initial begin
        // Pregatirea fisierului pentru forme de unda
        $dumpfile("multiplier_waves.vcd");
        $dumpvars(0, tb_multiplier);

        // ==========================================
        // INITIALIZARE
        // ==========================================
        clk = 0;
        rst = 1;       // Tinem sistemul in reset
        start = 0;
        a = 0;
        b = 0;

        #20 rst = 0;   // Scoatem resetul dupa 20ns
        #10;

        // ==========================================
        // TEST 1: Numere pozitive (3 * 5 = 15)
        // ==========================================
        $display("\n--- Incepere Test 1 ---");
        a = 8'd3;  
        b = 8'd5;  
        
        // Dam un impuls de 'start' de durata unui ciclu de ceas
        start = 1; 
        #10;       
        start = 0;

        // Comanda magica: oprim executia testbench-ului pana cand semnalul done devine 1
        wait(done == 1); 
        
        // Folosim $signed() pentru a forta afisarea ca numere cu semn (Complement de 2)
        $display("Timp: %0t | Calcul terminat: %d * %d = %d", $time, $signed(a), $signed(b), $signed(prod));

        #35; // Pauza intre teste

        // ==========================================
        // TEST 2: Numar pozitiv * Numar negativ (7 * -4 = -28)
        // ==========================================
        $display("\n--- Incepere Test 2 (Complement de 2) ---");
        a = 8'd7;
        b = 8'b11111100; // Compilatorul transforma automat asta in complement de 2 pe 8 biti
        start = 1;
        #10;
        start = 0;

        wait(done == 1);
        $display("Timp: %0t | Calcul terminat: %d * %d = %d", $time, $signed(a), $signed(b), $signed(prod));

        #20;
        $display("\nSimulare completa!");
        $finish;
    end
endmodule