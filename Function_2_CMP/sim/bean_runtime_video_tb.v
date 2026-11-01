`timescale 1ns/1ps
`include "bean/bean_config.vh"
module bean_runtime_video_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,de=0,hs=1,vs=1,frozen=1;
    reg [23:0] rgb=24'hf0f0f0;
    reg [`BEAN_CFG_BITS-1:0] cfg={12'd80,12'd80,12'd3,12'd3,20'd500,20'd36,
        12'd160,12'd320,12'd0,12'd0,2'd2,1'b1,8'd112};
    wire [15:0] count;
    wire valid,error,busy;
    bean_counter_video #(.RUNTIME_ENABLE(1),.OBJECTS_ENABLE(1),.MAX_OBJECTS(128),
        .IMAGE_WIDTH(320),.IMAGE_HEIGHT(160),.LINE_TOTAL(340),.CONTOUR_ENABLE(0),
        .ROI_X0(0),.ROI_Y0(0),.ROI_X1(320),.ROI_Y1(160),
        .MIN_AREA(36),.MAX_AREA(500),.MIN_WIDTH(3),.MIN_HEIGHT(3),.MAX_WIDTH(80),.MAX_HEIGHT(80)) dut(
        .clk(clk),.rst_n(rst_n),.config_i(cfg),.menu_i(1'b1),.field_i(4'd1),.step_i(2'd0),
        .source_error_i(1'b0),.source_ready_i(1'b1),.frozen_i(frozen),
        .rgb_i(rgb),.de_i(de),.hs_i(hs),.vs_i(vs),.rgb_o(),.de_o(),.hs_o(),.vs_o(),
        .count_o(count),.result_valid_o(valid),.overflow_o(error),.busy_o(busy));
    integer xx,yy,i,phase=0,green=0,labels=0,binary_fg=0,binary_bg=0,raw_fg=0;
    always @(posedge clk) begin
        #1;
        if(rst_n && error) $fatal(1,"runtime analysis failed");
        if(dut.annotated_de) begin
            if(dut.annotated_rgb==24'h00ff00) green=green+1;
            if(dut.annotated_rgb==24'h80ff00) labels=labels+1;
            if(phase==2 && dut.annotated_x==90 && dut.annotated_y==90 && dut.annotated_rgb==24'hffffff) binary_fg=binary_fg+1;
            if(phase==2 && dut.annotated_x==200 && dut.annotated_y==90 && dut.annotated_rgb==24'h000000) binary_bg=binary_bg+1;
            if(phase==3 && dut.annotated_x==90 && dut.annotated_y==90 && dut.annotated_rgb==24'h505050) raw_fg=raw_fg+1;
        end
    end
    task frame;
        input change_midframe;
        begin
            de=0;vs=0;repeat(10) @(negedge clk);vs=1;repeat(680) @(negedge clk);
            for(yy=0;yy<160;yy=yy+1) begin
                for(xx=0;xx<320;xx=xx+1) begin
                    de=1;rgb=24'hf0f0f0;
                    if((xx>=80 && xx<100 && yy>=80 && yy<100) ||
                       (xx>=160 && xx<184 && yy>=92 && yy<116) ||
                       (xx>=240 && xx<244 && yy>=120 && yy<124)) rgb=24'h505050;
                    if(change_midframe && xx==83 && yy==84) begin
                        cfg[`BC_THRESHOLD]=10;cfg[`BC_MIN_AREA]=100;cfg[`BC_MAX_AREA]=200;
                        if(dut.active_config[`BC_THRESHOLD]!=112 || dut.active_config[`BC_MIN_AREA]!=36)
                            $fatal(1,"configuration changed inside source frame");
                    end
                    @(negedge clk);
                end
                de=0;hs=0;repeat(4) @(negedge clk);hs=1;repeat(16) @(negedge clk);
            end
            repeat(680) @(negedge clk);
        end
    endtask
    task settle;
        input integer n;
        begin for(i=0;i<n;i=i+1) frame(0);end
    endtask
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        settle(7);
        if(!valid || count!=2 || dut.boxes_visible!=2 || !green || !labels)
            $fatal(1,"accepted-box correspondence count=%0d boxes=%0d green=%0d labels=%0d",count,dut.boxes_visible,green,labels);
        if(dut.osd.param_bcd!=24'h000112) $fatal(1,"runtime value readback");
        frame(1);
        if(dut.active_config[`BC_THRESHOLD]!=112) $fatal(1,"mid-frame pending configuration leaked");
        settle(6);
        if(!valid || count!=0 || dut.boxes_visible!=0 || dut.active_config[`BC_MIN_AREA]!=100)
            $fatal(1,"atomic update/recount failed");
        cfg[`BC_THRESHOLD]=112;cfg[`BC_MIN_AREA]=36;cfg[`BC_MAX_AREA]=500;cfg[`BC_X1]=140;
        settle(7);
        if(!valid || count!=1 || dut.boxes_visible!=1) $fatal(1,"runtime ROI not shared by count and boxes");
        cfg[`BC_MIN_W]=20;cfg[`BC_MIN_H]=20;settle(6);
        if(!valid || count!=0 || dut.boxes_visible) $fatal(1,"runtime minimum size filtering failed");
        cfg[`BC_MIN_W]=3;cfg[`BC_MIN_H]=3;cfg[`BC_MAX_W]=8;settle(6);
        if(!valid || count!=0 || dut.boxes_visible) $fatal(1,"runtime maximum size filtering failed");
        cfg[`BC_MAX_W]=80;cfg[`BC_VIEW]=1;phase=2;settle(6);
        if(!binary_fg || !binary_bg || dut.boxes_visible) $fatal(1,"binary view mismatch");
        cfg[`BC_DARK]=0;phase=5;settle(6);
        if(count!=0 || dut.boxes_visible) $fatal(1,"runtime polarity filtering failed");
        cfg[`BC_DARK]=1;cfg[`BC_VIEW]=0;phase=3;settle(6);
        if(!raw_fg || dut.boxes_visible) $fatal(1,"raw view mismatch");
        cfg[`BC_VIEW]=2;phase=4;settle(6);
        if(count!=1 || dut.boxes_visible!=1) $fatal(1,"result view did not restore exact accepted set");
        frozen=0;settle(3);green=0;labels=0;settle(1);
        if(green || labels || dut.boxes_visible) $fatal(1,"stale boxes overlaid on live scene");
        $display("PASS runtime video: frame-atomic threshold/area/ROI/size/polarity, invalidation/recount while frozen, shared accepted boxes, IDs, raw/binary/result views, readback and no stale live boxes");
        $finish;
    end
    initial begin #100000000;$fatal(1,"runtime video timeout");end
endmodule
