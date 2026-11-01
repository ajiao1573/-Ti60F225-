`timescale 1ns/1ps
module bean_osd_tb;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,vs=1,valid=0,error=0,busy=0,done=0;
    reg [15:0] count=0;
    wire [23:0] rgb;
    wire de,hs,vs_o;
    bean_osd dut(.clk(clk),.rst_n(rst_n),.rgb_i(24'h123456),.de_i(1'b1),.hs_i(1'b1),.vs_i(vs),
        .x_i(12'd400),.y_i(12'd400),.count_i(count),.result_valid_i(valid),.error_i(error),.busy_i(busy),.done_i(done),
        .frozen_i(1'b0),.invalidate_i(1'b0),.rgb_o(rgb),.de_o(de),.hs_o(hs),.vs_o(vs_o));
    task latch_frame;
        begin vs=0; repeat(3) @(negedge clk); vs=1; repeat(3) @(negedge clk); end
    endtask
    task publish;
        input [15:0] value;
        input [15:0] expected_bcd;
        reg [15:0] old_bcd;
        begin
            old_bcd=dut.displayed_bcd;
            count=value; valid=1; done=1;
            @(negedge clk); done=0;
            repeat(20) @(negedge clk);
            if(dut.displayed_bcd!==old_bcd) $fatal(1,"OSD changed within frame");
            latch_frame;
            if(!dut.displayed_valid || dut.displayed_bcd!==expected_bcd)
                $fatal(1,"BCD conversion failed: %0d -> %h",value,dut.displayed_bcd);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        repeat(3) @(negedge clk); latch_frame;
        if(dut.displayed_valid || dut.displayed_error) $fatal(1,"startup status wrong");
        publish(0,16'h0000); publish(7,16'h0007); publish(42,16'h0042);
        publish(999,16'h0999); publish(1023,16'h1023);
        valid=0; error=1; done=1; @(negedge clk); done=0;
        latch_frame;
        if(dut.displayed_valid || !dut.displayed_error) $fatal(1,"OSD error status failed");
        error=0; publish(3,16'h0003);
        if(dut.displayed_error) $fatal(1,"OSD error did not recover");
        if(rgb!==24'h123456 || !de || !hs) $fatal(1,"video passthrough failed");
        $display("PASS OSD decimal values, frame-stable count, invalid result and recovery");
        $finish;
    end
endmodule
