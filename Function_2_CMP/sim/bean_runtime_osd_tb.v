`timescale 1ns/1ps
`include "bean/bean_config.vh"
module bean_runtime_osd_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,vs=1,de=0,menu=1;
    reg [11:0] x=200,y=72;
    reg [3:0] field=1;
    reg [146:0] cfg=0;
    wire [23:0] rgb;
    bean_osd #(.RUNTIME_ENABLE(1)) dut(
        .clk(clk),.rst_n(rst_n),.config_i(cfg),.menu_i(menu),.field_i(field),.step_i(2'd3),.box_limit_i(1'b0),
        .rgb_i(24'h123456),.de_i(de),.hs_i(1'b1),.vs_i(vs),.x_i(x),.y_i(y),
        .count_i(16'd0),.result_valid_i(1'b0),.error_i(1'b0),.busy_i(1'b0),.done_i(1'b0),
        .frozen_i(1'b0),.invalidate_i(1'b0),.rgb_o(rgb),.de_o(),.hs_o(),.vs_o(),.display_ready_o());
    task frame;
        begin de=0;vs=0;repeat(4) @(negedge clk);vs=1;repeat(30) @(negedge clk);de=1;repeat(3) @(negedge clk);end
    endtask
    initial begin
        cfg[`BC_THRESHOLD]=112;cfg[`BC_X1]=1920;cfg[`BC_Y1]=1080;
        repeat(5) @(negedge clk);rst_n=1;frame;
        if(dut.param_bcd!=24'h000112 || rgb!=24'h123456) $fatal(1,"initial runtime OSD");
        cfg[`BC_THRESHOLD]=255;cfg[`BC_X0]=200;cfg[`BC_Y0]=72;
        repeat(30) @(negedge clk);
        if(dut.param_bcd!=24'h000112 || rgb!=24'h123456) $fatal(1,"OSD/ROI changed inside a frame");
        frame;
        if(dut.param_bcd!=24'h000255 || rgb!=24'h00ff00) $fatal(1,"frame-latched parameter/ROI display");
        field=7;cfg[`BC_MIN_AREA]=518400;frame;
        if(dut.param_bcd!=24'h518400) $fatal(1,"six-digit native area readback truncated");
        field=13;frame;if(dut.param_bcd!=24'h000256) $fatal(1,"step readback");
        x=288;y=30;@(negedge clk);
        if(dut.hint!="K1:+ HOLD:- K2:NEXT 1S:EXIT     " || dut.ch!="K" || !dut.glyph)
            $fatal(1,"dual-key menu hint truncated or missing");
        menu=0;repeat(4) @(negedge clk);
        if(!dut.runtime_menu) $fatal(1,"menu changed inside output frame");
        frame;
        if(dut.hint!="K1:FREEZE K2:MENU               " || dut.ch!="K" || !dut.glyph)
            $fatal(1,"dual-key normal hint truncated or missing");
        $display("PASS runtime OSD: frame-stable configuration/ROI/menu, threshold readback, six-digit native area, step size and complete dual-key hints");
        $finish;
    end
    initial begin #100000;$fatal(1,"runtime OSD timeout");end
endmodule
