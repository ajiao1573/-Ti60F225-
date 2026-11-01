`timescale 1ns/1ps
`include "bean/bean_config.vh"
module bean_dualkey_tick_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,k1=1,k2=1;
    wire [146:0] cfg;
    wire menu;
    bean_runtime_controls #(.CLOCK_HZ(1000),.DEBOUNCE_CYCLES(3)) dut(
        .clk(clk),.rst_n(rst_n),.key1_n_i(k1),.key2_n_i(k2),.config_o(cfg),
        .menu_o(menu),.field_o(),.step_o(),.freeze_toggle_o(),.freeze_set_o());
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        k2=0;repeat(20) @(negedge clk);k2=1;repeat(20) @(negedge clk);
        if(!menu) $fatal(1,"tick test menu entry");
        k1=0;repeat(480) @(negedge clk);
        if(cfg[`BC_THRESHOLD]!=112) $fatal(1,"hold fired early");
        repeat(45) @(negedge clk);
        if(cfg[`BC_THRESHOLD]!=111) $fatal(1,"0.5s hold failed");
        repeat(120) @(negedge clk);
        if(cfg[`BC_THRESHOLD]!=110) $fatal(1,"0.12s repeat failed");
        k1=1;repeat(20) @(negedge clk);
        if(cfg[`BC_THRESHOLD]!=110) $fatal(1,"release added after tick repeat");
        k2=0;repeat(980) @(negedge clk);if(!menu) $fatal(1,"exit fired early");
        repeat(40) @(negedge clk);if(menu) $fatal(1,"1s exit failed");
        k2=1;repeat(20) @(negedge clk);if(menu) $fatal(1,"exit release reentered");
        $display("PASS shared tick: prescaled 0.5s subtract, 0.12s repeat, 1s exit and release suppression");
        $finish;
    end
    initial begin #100000;$fatal(1,"tick timeout");end
endmodule
