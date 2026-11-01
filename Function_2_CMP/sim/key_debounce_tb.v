`timescale 1ns/1ps
module key_debounce_tb;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,key_n=1;
    wire press;
    integer pulses=0;
    key_debounce #(.DEBOUNCE_CYCLES(5)) dut(.clk(clk),.rst_n(rst_n),.key_n_i(key_n),.press_o(press));
    always @(posedge clk) if(rst_n && press) pulses=pulses+1;
    task level;
        input value;
        input integer clocks;
        begin key_n=value; repeat(clocks) @(negedge clk); end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        level(0,2); level(1,2); level(0,1); level(1,10);
        if(pulses!=0) $fatal(1,"bounce generated a press");
        level(0,30);
        if(pulses!=1) $fatal(1,"held key retriggered");
        level(1,2); level(0,15);
        if(pulses!=1) $fatal(1,"release bounce rearmed key");
        level(1,10); level(0,12);
        if(pulses!=2) $fatal(1,"second press lost");
        rst_n=0; level(1,3); rst_n=1; level(1,10);
        if(press) $fatal(1,"reset generated a press");
        $display("PASS key synchronization, press/release bounce, held key and second press");
        $finish;
    end
endmodule
