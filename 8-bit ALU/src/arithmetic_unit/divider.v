module divider(
    input wire clk,
    input wire rst,
    input wire start,
    input wire [7:0] a,        // deimpartitul (dividend)
    input wire [7:0] b,        // impartitorul (divisor)
    output wire [15:0] result, // result[15:8] = remainder, result[7:0] = quotient
    output wire done
);
    wire init, sub_enable, shift_enable;
    wire [7:0] adder_out;
    wire [7:0] A_out, M_out, Q_out;

    // Registrul A - restul partial, incepe cu 0
    // shift la stanga: shift_in vine din MSB-ul lui A (arithmetic shift)
    register_8 A (
        .clk      (clk),
        .rst      (rst | init),   // reset la initializare
        .load     (sub_enable),   // incarca rezultatul scaderii
        .d        (adder_out),
        .shift    (shift_enable),
        .shift_in (Q_out[7]),     // MSB din Q intra in LSB-ul lui A
        .q        (A_out)
    );

    // Registrul M - impartitorul, ramane fix
    register_8 M (
        .clk      (clk),
        .rst      (rst),
        .load     (init),
        .d        (b),
        .shift    (1'b0),
        .shift_in (1'b0),
        .q        (M_out)
    );

    // Registrul Q - deimpartitul, se transforma treptat in cat
    // shift la stanga: LSB primeste bitul de cat (0 sau 1)
    wire q_bit; // bitul de cat generat de FSM
    register_8 Q (
        .clk      (clk),
        .rst      (rst),
        .load     (init),
        .d        (a),
        .shift    (shift_enable),
        .shift_in (q_bit),        // bitul de cat intra in LSB
        .q        (Q_out)
    );

    // Scadem M din A folosind adder_sub al colegului
    // mode=1 inseamna scadere
    adder_sub calc_unit (
        .a    (A_out),
        .b    (M_out),
        .mode (1'b1),       // intotdeauna scadere pentru restoring division
        .sum  (adder_out),
        .cout ()            // nu ne trebuie carry
    );

    // FSM-ul care coordoneaza toti pasii
    FSM_divider control_unit (
        .clk          (clk),
        .rst          (rst),
        .start        (start),
        .a_msb        (A_out[7]),  // semnul lui A dupa scadere
        .init         (init),
        .sub_enable   (sub_enable),
        .shift_enable (shift_enable),
        .q_bit        (q_bit),
        .done         (done)
    );

    assign result = {A_out, Q_out}; // remainder in sus, quotient in jos

endmodule


module FSM_divider(
    input wire clk,
    input wire rst,
    input wire start,
    input wire a_msb,        // MSB-ul lui A: 0 = pozitiv, 1 = negativ

    output reg init,         // initializeaza registrele
    output reg sub_enable,   // permite scrierea rezultatului scaderii in A
    output reg shift_enable, // permite shiftarea
    output reg q_bit,        // bitul de cat (0 sau 1)
    output reg done
);
    // Stari identice ca la multiplier pentru consistenta
    parameter IDLE  = 2'b00;
    parameter CALC  = 2'b01;
    parameter SHIFT = 2'b10;
    parameter DONE  = 2'b11;

    reg [1:0] state, next_state;
    reg [2:0] count;

    // Registru de stare + contor
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            count <= 0;
        end else begin
            state <= next_state;

            if (state == IDLE && start)
                count <= 0;
            else if (state == SHIFT)
                count <= count + 1;
        end
    end

    // Logica combinationala a FSM-ului
    always @(*) begin
        // valori default (safety)
        next_state  = state;
        init        = 0;
        sub_enable  = 0;
        shift_enable= 0;
        q_bit       = 0;
        done        = 0;

        case(state)

            IDLE: begin
                if (start) begin
                    init       = 1'b1;
                    next_state = CALC;
                end
            end

            CALC: begin
                // a_msb=0 → A-M >= 0 → acceptam scaderea, q_bit=1
                // a_msb=1 → A-M <  0 → restauram (nu scriem in A), q_bit=0
                if (a_msb == 1'b0) begin
                    sub_enable = 1'b1;  // scriem A_minus_M in A
                    q_bit      = 1'b1;
                end else begin
                    sub_enable = 1'b0;  // A ramane neschimbat (restaurare automata)
                    q_bit      = 1'b0;
                end
                next_state = SHIFT;
            end

            SHIFT: begin
                shift_enable = 1'b1;
                if (count == 7)
                    next_state = DONE;
                else
                    next_state = CALC;
            end

            DONE: begin
                done = 1'b1;
                if (~start)
                    next_state = IDLE;
            end

        endcase
    end

endmodule