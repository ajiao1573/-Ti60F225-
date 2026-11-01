`timescale 1ns/1ps
module banked_ram_case #(parameter WIDTH=16,DEPTH=2200)(output reg done=0);
    reg clk=0;always #5 clk=~clk;
    reg re=0,we=0;
    reg [31:0] ra=0,wa=0,wd=0;
    wire [WIDTH-1:0] rd;
    reg [WIDTH-1:0] reference[0:DEPTH-1];
    reg [WIDTH-1:0] expected;
    reg expected_valid=0;
    reg [31:0] random_state=32'h56401920;
    integer i,checked=0;
    bean_banked_ram #(.WIDTH(WIDTH),.DEPTH(DEPTH)) dut(
        .clk(clk),.read_en(re),.write_en(we),.read_addr(ra),.write_addr(wa),
        .write_data(wd[WIDTH-1:0]),.read_data(rd));
    always @(posedge clk) begin
        // Independent storage oracle: capture old word before any write.
        if(re) begin expected=reference[ra];expected_valid=1;end
        if(we) reference[wa]=wd[WIDTH-1:0];
        #1;
        if(expected_valid && rd!==expected)
            $fatal(1,"banked RAM width=%0d depth=%0d address=%0d got=%h expected=%h",WIDTH,DEPTH,ra,rd,expected);
        if(expected_valid) checked=checked+1;
    end
    initial begin
        for(i=0;i<DEPTH;i=i+1) begin
            @(negedge clk);we=1;wa=i;wd=i*32'h12345;
        end
        for(i=0;i<DEPTH;i=i+1) begin
            @(negedge clk);re=1;we=1;ra=i;wa=i;wd=~(i*32'h12345);
        end
        for(i=0;i<12000;i=i+1) begin
            @(negedge clk);
            random_state=random_state^(random_state<<13);
            random_state=random_state^(random_state>>17);
            random_state=random_state^(random_state<<5);
            re=random_state[0];we=random_state[1];
            ra=(random_state>>2)%DEPTH;wa=(random_state>>15)%DEPTH;wd=random_state;
        end
        @(negedge clk);re=0;we=0;
        repeat(4) @(negedge clk);
        $display("PASS banked RAM width=%0d depth=%0d: %0d reads/holds, collisions, every bank boundary and partial last bank",WIDTH,DEPTH,checked);
        done=1;
    end
endmodule
module bean_banked_ram_tb;
    wire a,b,c,d;
    banked_ram_case #(.WIDTH(16),.DEPTH(2200)) c0(a);
    banked_ram_case #(.WIDTH(19),.DEPTH(4403)) c1(b);
    banked_ram_case #(.WIDTH(3),.DEPTH(4403)) c2(c);
    banked_ram_case #(.WIDTH(16),.DEPTH(513)) c3(d);
    initial begin wait(a&&b&&c&&d);$display("PASS banked RAM regression");$finish;end
    initial begin #1000000;$fatal(1,"banked RAM timeout");end
endmodule
