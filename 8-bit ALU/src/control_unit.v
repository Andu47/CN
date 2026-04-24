module control_unit(
    input wire [1:0] alu_op,
    input wire start,
    output wire mode,       
    output wire start_mul,  
    output wire start_div   
);

    // mode 0 pt add, 1 pt sub (luam doar bitul cel mai putin semnificativ)
    assign mode = alu_op[0];

    // dam startul mai departe doar daca am primit opcode-ul corect
    assign start_mul = start & (alu_op == 2'b10);
    assign start_div = start & (alu_op == 2'b11);

endmodule