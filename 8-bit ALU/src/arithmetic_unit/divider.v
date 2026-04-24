module divider(
    input wire clk, rst, start,
    input wire [7:0] a, b,
    output wire [15:0] result,
    output wire done
);
    wire init, sub_enable, shift_enable;
    wire [7:0] adder_out;
    wire [7:0] A_out, M_out, Q_out;

    // A si Q folosesc noul registru de SHIFT LA STANGA
    register_8_left A (
        .clk(clk), .rst(rst | init), .load(sub_enable),
        .d(adder_out), .shift(shift_enable), .shift_in(Q_out[7]), .q(A_out)
    );

    // M ramane fix (nu ne intereseaza shiftarea la el)
    register_8 M (
        .clk(clk), .rst(rst), .load(init),
        .d(b), .shift(1'b0), .shift_in(1'b0), .q(M_out)
    );

    register_8_left Q (
        .clk(clk), .rst(rst), .load(init),
        .d(a), .shift(shift_enable), .shift_in(q_bit), .q(Q_out)
    );

    wire q_bit;

    // TRUC STRUCTURAL: Pre-shiftam combinational A-ul pentru adunator!
    wire [7:0] A_shifted = {A_out[6:0], Q_out[7]};

    // Scadem M din A_shifted
    adder_sub calc_unit (
        .a    (A_shifted), 
        .b    (M_out),
        .mode (1'b1), // mereu scadere
        .sum  (adder_out),
        .cout ()
    );

    FSM_divider control_unit (
        .clk(clk), .rst(rst), .start(start),
        .a_msb(adder_out[7]), // ATENTIE: Verificam semnul DUPA scadere!
        .init(init), .sub_enable(sub_enable),
        .shift_enable(shift_enable), .q_bit(q_bit), .done(done)
    );

    assign result = {A_out, Q_out};
endmodule

module FSM_divider(
    input wire clk, rst, start,
    input wire a_msb, // Semnul rezultatului de la adder
    output reg init, sub_enable, shift_enable, q_bit, done
);
    parameter IDLE = 2'b00;
    parameter CALC = 2'b01; // Nu mai avem nevoie de starea SHIFT separata!
    parameter DONE = 2'b10;

    reg [1:0] state, next_state;
    reg [2:0] count;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            count <= 0;
        end else begin
            state <= next_state;
            if (state == IDLE && start) count <= 0;
            else if (state == CALC) count <= count + 1;
        end
    end

    always @(*) begin
        // default
        next_state = state;
        init = 0; sub_enable = 0; shift_enable = 0; q_bit = 0; done = 0;

        case(state)
            IDLE: begin
                if (start) begin
                    init = 1'b1;
                    next_state = CALC;
                end
            end

            CALC: begin
                shift_enable = 1'b1; // Q shifteaza mereu 
                
                if (a_msb == 1'b0) begin
                    // A_shifted - M >= 0 (Succes, nu restauram)
                    sub_enable = 1'b1; // Incarcam in A diferenta (suprascrie shift-ul din A)
                    q_bit = 1'b1;      // Catul primeste 1
                end else begin
                    // A_shifted - M < 0 (Esueaza, trebuie restaurat)
                    sub_enable = 1'b0; // A isi face shiftarea normala (este perfect echivalent cu A_shifted!)
                    q_bit = 1'b0;      // Catul primeste 0
                end

                if (count == 7) next_state = DONE;
            end

            DONE: begin
                done = 1'b1;
                if (~start) next_state = IDLE;
            end
        endcase
    end
endmodule
