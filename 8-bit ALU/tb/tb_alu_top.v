`timescale 1ns / 1ps

module tb_alu_top;

    // ==========================================
    // 1. Declararea semnalelor
    // ==========================================
    reg clk;
    reg rst;
    reg start;
    reg [7:0] a;
    reg [7:0] b;
    reg [1:0] alu_op;

    wire [15:0] result;
    wire done;

    // ==========================================
    // 2. Instanțierea modulului (Unit Under Test)
    // ==========================================
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

    // ==========================================
    // 3. Generarea semnalului de ceas (Clock)
    // Perioada = 10ns (5ns High, 5ns Low)
    // ==========================================
    always #5 clk = ~clk;

    // ==========================================
    // 4. Scenariul de testare
    // ==========================================
    initial begin
        // Configurare pentru generarea fisierului VCD (pentru Waveforms)
        $dumpfile("sim_alu_top.vcd");
        $dumpvars(0, tb_alu_top);

        // Initializare semnale
        clk = 0;
        rst = 1;
        start = 0;
        a = 0;
        b = 0;
        alu_op = 0;

        // Resetare sistem
        #15 rst = 0; // Scoatem din reset dupa 15ns

        $display("==================================================");
        $display("   Incepere Simulare ALU 8-bit Structural");
        $display("==================================================\n");

        // --------------------------------------------------
        // TEST 1: ADUNARE (ADD - Opcode 00)
        // --------------------------------------------------
        $display("-> TEST 1: Adunare (ADD)");
        alu_op = 2'b00;
        a = 8'd25;   // 25
        b = 8'd15;   // + 15
        #10;         // Asteptam 1 ciclu (operatie combinationala)
        $display("Timpul %0t | %0d + %0d = %0d (Rezultat brut hex: %h)", $time, a, b, result[7:0], result);

        // --------------------------------------------------
        // TEST 2: SCADERE (SUB - Opcode 01)
        // --------------------------------------------------
        $display("\n-> TEST 2: Scadere (SUB)");
        alu_op = 2'b01;
        a = 8'd50;   // 50
        b = 8'd20;   // - 20
        #10;
        $display("Timpul %0t | %0d - %0d = %0d (Rezultat brut hex: %h)", $time, a, b, result[7:0], result);

        // Test cu rezultat negativ (Complement fata de 2)
        a = 8'd10;
        b = 8'd30;
        #10;
        // 10 - 30 = -20. In complement de 2 pe 8 biti: 236
        $display("Timpul %0t | %0d - %0d = %0d (Asteptat: -20 in C2 / 236)", $time, a, b, result[7:0]);

        // TEST 3: INMULTIRE (MUL - Opcode 10)
        // --------------------------------------------------
        $display("\n-> TEST 3: Inmultire Booth (MUL)");
        alu_op = 2'b10;
        a = 8'd12;   // 12
        b = 8'd5;    // * 5 = 60
        
        // Dam pulsul de start
        start = 1; 
        #10 start = 0; 

        // Asteptam ca FSM-ul sa ridice semnalul "done"
        @(posedge done); 
        @(negedge done); // <--- FIX: Asteptam ca FSM-ul sa revina in IDLE
        #10;             // <--- FIX: Pauza de siguranta
        $display("Timpul %0t | %0d * %0d = %0d (Rezultat brut hex: %h)", $time, a, b, result, result);

        // Test Inmultire cu numere negative
        a = 8'b1111_1110; // -2 in complement de 2
        b = 8'd15;        // 15
        start = 1;
        #10 start = 0;
        
        @(posedge done);
        @(negedge done); // <--- FIX
        #10;             // <--- FIX
        // -2 * 15 = -30. In complement de 2 pe 16 biti: FFE2
        $display("Timpul %0t | -2 * 15 = %0d (Asteptat: -30, Hex: %h)", $time, $signed(result), result);

        // --------------------------------------------------
        // TEST 4: IMPARTIRE (DIV - Opcode 11)
        // --------------------------------------------------
        $display("\n-> TEST 4: Impartire Restoring (DIV)");
        alu_op = 2'b11;
        a = 8'd45;   // Deimpartit: 45
        b = 8'd7;    // Impartitor: 7
                     // Asteptat: Cat(Quotient) = 6, Rest(Remainder) = 3
        
        start = 1;
        #10 start = 0;

        @(posedge done);
        @(negedge done); 
        #10;             
        
        // Din divider.v, rezultatul este concatenat: result = {remainder[7:0], quotient[7:0]}
        $display("Timpul %0t | %0d / %0d -> Cat = %0d, Rest = %0d", 
                 $time, a, b, result[7:0], result[15:8]);

        // --------------------------------------------------
        // Incheiere Simulare
        // --------------------------------------------------
        $display("\n==================================================");
        $display("   Simulare Finalizata");
        $display("==================================================");
        $finish;
    end
endmodule