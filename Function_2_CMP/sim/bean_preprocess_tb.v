`timescale 1ns/1ps
module bean_preprocess_tb;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,de=0,hs=1,vs=1;
    reg [23:0] rgb=0;
    reg [11:0] x=0,y=0;
    wire [23:0] rgb_dark,rgb_light;
    wire de_o,hs_o,vs_o,sample_valid,mask_dark,mask_light;
    wire [11:0] xo,yo,sx,sy;
    bean_preprocess #(.THRESHOLD(112),.DEBUG_BINARY(1),.ROI_X0(2),.ROI_Y0(2),.ROI_X1(8),.ROI_Y1(8)) dark (
        .clk(clk),.rst_n(rst_n),.rgb_i(rgb),.de_i(de),.hs_i(hs),.vs_i(vs),.x_i(x),.y_i(y),
        .rgb_o(rgb_dark),.de_o(de_o),.hs_o(hs_o),.vs_o(vs_o),.x_o(xo),.y_o(yo),
        .sample_valid_o(sample_valid),.sample_mask_o(mask_dark),.sample_x_o(sx),.sample_y_o(sy));
    bean_preprocess #(.THRESHOLD(112),.DARK_OBJECT(0),.DEBUG_BINARY(1),.ROI_X0(2),.ROI_Y0(2),.ROI_X1(8),.ROI_Y1(8)) light (
        .clk(clk),.rst_n(rst_n),.rgb_i(rgb),.de_i(de),.hs_i(hs),.vs_i(vs),.x_i(x),.y_i(y),
        .rgb_o(rgb_light),.sample_mask_o(mask_light));
    integer i,expected_luma;
    reg expected_dark,expected_light;
    task check;
        input [23:0] color;
        input [11:0] px,py;
        begin
            @(negedge clk); de=1; rgb=color; x=px; y=py;
            repeat(2) @(negedge clk);
            expected_luma=(77*color[23:16]+150*color[15:8]+29*color[7:0])>>8;
            expected_dark=expected_luma<112 && px>=2 && px<8 && py>=2 && py<8;
            expected_light=expected_luma>112 && px>=2 && px<8 && py>=2 && py<8;
            if(mask_dark!==expected_dark || mask_light!==expected_light ||
               rgb_dark!=={24{expected_dark}} || rgb_light!=={24{expected_light}})
                $fatal(1,"threshold/ROI mismatch color=%h luma=%0d",color,expected_luma);
            if(sample_valid !== (!px[0] && !py[0]) || sx!=px/2 || sy!=py/2 || xo!=px || yo!=py)
                $fatal(1,"decimation/coordinate mismatch");
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        check(24'h000000,2,2); check(24'hffffff,2,2);
        check(24'h6f6f6f,2,2); check(24'h707070,2,2); check(24'h717171,2,2);
        check(24'hff0000,2,2); check(24'h00ff00,2,2); check(24'h0000ff,2,2);
        check(24'h000000,0,2); check(24'h000000,8,2); check(24'h000000,2,8);
        check(24'h000000,3,3); check(24'h000000,7,7);
        @(negedge clk); de=0;
        repeat(3) @(negedge clk);
        if(sample_valid || de_o || rgb_dark!=0) $fatal(1,"blanking not suppressed");
        $display("PASS preprocess threshold boundaries, RGB weighting, polarity, ROI and debug pixels");
        $finish;
    end
endmodule
