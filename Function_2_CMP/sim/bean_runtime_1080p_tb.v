`timescale 1ns/1ps
`include "bean/bean_config.vh"
// Actual default raster and final runtime-enabled, denoised, annotated path.
module bean_runtime_1080p_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;
    wire de,hs,vs;
    wire [23:0] unused;
    lcd_driver #(.DATA_WIDTH(24)) raster(.clk(clk),.rst_n(rst_n),.lcd_dclk(),.lcd_blank(),.lcd_sync(),
        .lcd_hs(hs),.lcd_vs(vs),.lcd_en(de),.lcd_rgb(unused),.lcd_request(),.lcd_xpos(),.lcd_ypos(),.lcd_data(24'd0));
    reg [23:0] source=24'hffffff;
    wire [146:0] cfg={12'd240,12'd240,12'd5,12'd5,20'd11250,20'd36,
        12'd1008,12'd1824,12'd72,12'd96,2'd2,1'b1,8'd112};
    wire [15:0] count;
    wire valid,error,busy;
    bean_counter_video #(.RUNTIME_ENABLE(1),.OBJECTS_ENABLE(1),.MAX_OBJECTS(128),
        .IMAGE_WIDTH(1920),.IMAGE_HEIGHT(1080),.LINE_TOTAL(2200),.DENOISE_ENABLE(1),.CONTOUR_ENABLE(1),
        .ROI_X0(96),.ROI_Y0(72),.ROI_X1(1824),.ROI_Y1(1008),
        .MIN_AREA(36),.MAX_AREA(11250),.MIN_WIDTH(5),.MIN_HEIGHT(5),.MAX_WIDTH(240),.MAX_HEIGHT(240)) dut(
        .clk(clk),.rst_n(rst_n),.rgb_i(source),.de_i(de),.hs_i(hs),.vs_i(vs),
        .source_error_i(1'b0),.source_ready_i(1'b1),.frozen_i(1'b1),.config_i(cfg),
        .menu_i(1'b0),.field_i(4'd1),.step_i(2'd0),.rgb_o(),.de_o(),.hs_o(),.vs_o(),
        .count_o(count),.result_valid_o(valid),.overflow_o(error),.busy_o(busy));
    function rect;
        input integer x,y,x0,y0,size;
        begin rect=x>=x0 && x<x0+size && y>=y0 && y<y0+size;end
    endfunction
    reg [23:0] ref40[0:1599],ref50[0:2499],expected;
    integer inputs=0,sx,sy,checked=0,cx,cy;
    reg annotated_vs_d=1,checking=0;
    integer overlay_pixels=0,green_samples=0,label_pixels=0;
    always @(negedge clk) if(rst_n) begin
        if(de) begin
            sx=inputs%1920;sy=(inputs/1920)%1080;
            source=(rect(sx,sy,200,100,40)||rect(sx,sy,900,500,50)||rect(sx,sy,1720,950,40))?0:24'hffffff;
            if(sx%127==31 && sy%101==25 && source!=0) source=0;
            inputs=inputs+1;
        end else source=24'hffffff;
    end
    always @(posedge clk) if(rst_n) begin
        #1;
        if(error) $fatal(1,"native runtime analysis error");
        if(dut.contour_de && checked<4147200) begin
            cx=checked%1920;cy=(checked/1920)%1080;
            if(rect(cx,cy,200,100,40)) expected=ref40[(cy-100)*40+cx-200];
            else if(rect(cx,cy,900,500,50)) expected=ref50[(cy-500)*50+cx-900];
            else if(rect(cx,cy,1720,950,40)) expected=ref40[(cy-950)*40+cx-1720];
            else expected=24'hf8fcf8;
            if(dut.contour_rgb!==expected || dut.contour_x!=cx || dut.contour_y!=cy)
                $fatal(1,"native runtime contour reference mismatch at %0d,%0d",cx,cy);
            checked=checked+1;
        end
        if(annotated_vs_d && !dut.annotated_vs && dut.boxes_visible==3) checking=1;
        annotated_vs_d=dut.annotated_vs;
        if(checking && dut.annotated_de) begin
            overlay_pixels=overlay_pixels+1;
            if(dut.annotated_rgb==24'h80ff00) label_pixels=label_pixels+1;
            if((dut.annotated_x==200 && dut.annotated_y==120) ||
               (dut.annotated_x==900 && dut.annotated_y==520) ||
               (dut.annotated_x==1720 && dut.annotated_y==970)) begin
                if(dut.annotated_rgb!=24'h00ff00) $fatal(1,"native accepted-box alignment");
                green_samples=green_samples+1;
            end
            if(count!=3 || !valid) $fatal(1,"count/box mismatch in held output frame");
            if(overlay_pixels==2073600) begin
                if(checked!=4147200 || green_samples!=3 || label_pixels==0 || dut.osd.displayed_bcd!=16'h0003)
                    $fatal(1,"native runtime coverage incomplete");
                $display("PASS runtime 1080p: 4147200 contour pixels vs independent reference; complete held frame of 2073600 annotated pixels; 3 matching accepted boxes, IDs, count and 5x5 denoise");
                $finish;
            end
        end
    end
    initial begin
        $readmemh("build/sim/native_denoise_rect40.hex",ref40);
        $readmemh("build/sim/native_denoise_rect50.hex",ref50);
        repeat(5) @(negedge clk);rst_n=1;
    end
    initial begin #250000000;$fatal(1,"runtime 1080p timeout");end
endmodule
