`timescale 1ns / 1ps

module tb_fac;

    // Intrările sunt declarate ca 'reg' pentru a le putea atribui valori în blocul initial
    reg a;
    reg b;
    reg cin;

    // Ieșirile sunt declarate ca 'wire' pentru a capta rezultatele din modul
    wire sum;
    wire cout;

    // Instanțierea modulului Full Adder (Device Under Test)
    fac DUT (
        .a(a),
        .b(b),
        .cin(cin),
        .sum(sum),
        .cout(cout)
    );

    // Blocul de stimulare
    initial begin
        // (Opțional) Crearea unui fișier pentru a vedea formele de undă în GTKWave
        $dumpfile("fac_waves.vcd");
        $dumpvars(0, tb_fac);

        // Header pentru afișarea în consolă
        $display("Timp | a | b | cin | sum | cout");
        $display("--------------------------------");
        
        // $monitor afișează automat valorile ori de câte ori se schimbă o variabilă
        $monitor("%4t | %b | %b |  %b  |  %b  |  %b", $time, a, b, cin, sum, cout);

        // Testarea tuturor celor 8 combinații posibile cu o întârziere de 10 unități de timp
        a = 0; b = 0; cin = 0; #10;
        a = 0; b = 0; cin = 1; #10;
        a = 0; b = 1; cin = 0; #10;
        a = 0; b = 1; cin = 1; #10;
        a = 1; b = 0; cin = 0; #10;
        a = 1; b = 0; cin = 1; #10;
        a = 1; b = 1; cin = 0; #10;
        a = 1; b = 1; cin = 1; #10;

        // Încheierea simulării
        $finish;
    end

endmodule