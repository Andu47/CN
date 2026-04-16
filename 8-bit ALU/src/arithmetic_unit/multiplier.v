//Booth Radix-2

module multiplier(
    input wire [7:0] a,
    input wire [7:0] b,
    input wire clk, rst, start,

    output wire [15:0] prod,
    output wire done
);

    wire init, add_sub_enable, mode, shift_enable;

    wire [7:0] adder_sum; // suma/diferenta de la adder_sub
    wire [7:0] A_out, M_out, Q_out; //iesirea registrilor

    wire q_minus_1;
    wire q_m1_next = shift_enable? Q_out[0] : q_minus_1;

    register_8 A (
        .clk(clk),
        .rst(rst | init), //A trebuie "curatat" la initializare
        .load(add_sub_enable), //in A se da load doar daca acceptam operatia facuta sau daca de abia am initializat modulul
        .d(adder_sum),
        .shift(shift_enable),
        .shift_in(A_out[7]),
        .q(A_out)
    );

    register_8 M (
        .clk(clk),
        .rst(rst),
        .load(init),
        .d(a),
        .shift(1'b0),
        .shift_in(1'b0),
        .q(M_out)
    );

    register_8 Q (
        .clk(clk),
        .rst(rst),
        .load(init),
        .d(b),
        .shift(shift_enable),
        .shift_in(A_out[0]),
        .q(Q_out)
    );

    dff Q_minus_1 (
        .clk(clk),
        .rst(rst | init),
        .d(q_m1_next),
        .q(q_minus_1)
    );

    adder_sub calc_unit (
        .a(A_out),
        .b(M_out),
        .mode(mode),
        .sum(adder_sum),
        .cout() //nu conteaza (pt Booth Radix-2)
    );

    FSM_multiplier control_unit (
        .clk(clk),
        .rst(rst),
        .start(start),
        .q0(Q_out[0]),
        .q_minus_1(q_minus_1),
        
        .init(init),
        .add_sub_enable(add_sub_enable),
        .mode(mode),
        .shift_enable(shift_enable),
        .done(done)
    );

    assign prod = {A_out, Q_out};

endmodule

module FSM_multiplier(
    input wire clk, 
    input wire rst,
    input wire start,
    input wire q0,
    input wire q_minus_1,

    output reg init,//incepe 
    output reg add_sub_enable, //permite adunarea/scaderea din A
    output reg mode, //adunare = 0, scadere = 1
    output reg shift_enable, //permite shiftarea
    output reg done //anunta finalul algoritmului
);

    parameter IDLE = 2'b00; //asteptam sa primim start
    parameter CALC = 2'b01; //decizia in functie de Q0Q-1
    parameter SHIFT = 2'b10; //asteptam sa primim shift_enable
    parameter DONE = 2'b11; //gata

    reg [1:0] state, next_state;
    reg [2:0] count;

    //se ocupa de reset si counter
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            count <= 0;
        end else begin

            state <= next_state;

            if (state == IDLE && start) begin //reseteaza counter 
                count <= 0;
            end
            else if (state == SHIFT) begin //incrementeaza la fiecare shiftare
                count <= count + 1;
            end
        end
    end

    always @(*) begin
        //safety
        next_state = state;
        init = 0;
        add_sub_enable = 0;
        mode = 0;
        shift_enable = 0;
        done = 0;

        case(state)

            IDLE: begin
                if(start) begin
                    init = 1'b1;
                    next_state = CALC;
                end
            end

            CALC: begin
                if (q0 == 1'b1 && q_minus_1 == 1'b0) begin
                    add_sub_enable = 1'b1;
                    mode = 1'b1; //scadere
                end 
                if (q0 == 1'b0 && q_minus_1 == 1'b1) begin
                    add_sub_enable = 1'b1;
                    mode = 1'b0; //adunare
                end
                //pt celelalte 2 cazuri (00 si 11) nu trebuie facut nimic
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
                    next_state = IDLE; //ne intoarcem in IDLE doar daca start e dezactivat
            end
        endcase
    end
endmodule