`timescale 1ns/1ps
`include "bean/bean_config.vh"
// Exercise real debounced buttons through frame commits, recount and overlays.
module bean_dualkey_video_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,key1=1,key2=1,frozen=0;
    reg de=0,hs=1,vs=1;
    reg [23:0] rgb=24'hf0f0f0;
    wire [`BEAN_CFG_BITS-1:0] cfg;
    wire menu,toggle,set_freeze;
    wire [3:0] field;
    wire [1:0] step;
    bean_runtime_controls #(.CLOCK_HZ(100),.DEBOUNCE_CYCLES(3),
        .IMAGE_WIDTH(320),.IMAGE_HEIGHT(160),.ROI_X0(0),.ROI_Y0(0),.ROI_X1(320),.ROI_Y1(160),
        .MIN_AREA(36),.MAX_AREA(500),.MIN_WIDTH(3),.MIN_HEIGHT(3),.MAX_WIDTH(80),.MAX_HEIGHT(80)) controls(
        .clk(clk),.rst_n(rst_n),.key1_n_i(key1),.key2_n_i(key2),.config_o(cfg),
        .menu_o(menu),.field_o(field),.step_o(step),.freeze_toggle_o(toggle),.freeze_set_o(set_freeze));
    // Same set-before-toggle priority as example_top; DDR acknowledgement is
    // modeled immediately here (the existing freeze/AXI tests cover that CDC).
    always @(posedge clk) begin
        if(!rst_n) frozen<=0;
        else if(set_freeze) frozen<=1;
        else if(toggle) frozen<=~frozen;
    end
    wire [15:0] count;
    wire valid,error;
    bean_counter_video #(.RUNTIME_ENABLE(1),.OBJECTS_ENABLE(1),.MAX_OBJECTS(128),
        .IMAGE_WIDTH(320),.IMAGE_HEIGHT(160),.LINE_TOTAL(340),.CONTOUR_ENABLE(0),
        .ROI_X0(0),.ROI_Y0(0),.ROI_X1(320),.ROI_Y1(160),
        .MIN_AREA(36),.MAX_AREA(500),.MIN_WIDTH(3),.MIN_HEIGHT(3),.MAX_WIDTH(80),.MAX_HEIGHT(80)) dut(
        .clk(clk),.rst_n(rst_n),.config_i(cfg),.menu_i(menu),.field_i(field),.step_i(step),
        .source_error_i(1'b0),.source_ready_i(1'b1),.frozen_i(frozen),
        .rgb_i(rgb),.de_i(de),.hs_i(hs),.vs_i(vs),.rgb_o(),.de_o(),.hs_o(),.vs_o(),
        .count_o(count),.result_valid_o(valid),.overflow_o(error),.busy_o());
    integer x,y,frames=0,green=0,labels=0;
    always @(posedge clk) begin
        #1;
        if(rst_n && error) $fatal(1,"dual-key count error");
        if(dut.annotated_de && dut.annotated_rgb==24'h00ff00) green=green+1;
        if(dut.annotated_de && dut.annotated_rgb==24'h80ff00) labels=labels+1;
    end
    initial begin
        wait(rst_n);
        forever begin
            de=0;vs=0;repeat(10) @(negedge clk);vs=1;repeat(680) @(negedge clk);
            for(y=0;y<160;y=y+1) begin
                for(x=0;x<320;x=x+1) begin
                    de=1;rgb=24'hf0f0f0;
                    if((x>=80 && x<100 && y>=80 && y<100) ||
                       (x>=160 && x<184 && y>=92 && y<116)) rgb=24'h505050;
                    @(negedge clk);
                end
                de=0;hs=0;repeat(4) @(negedge clk);hs=1;repeat(16) @(negedge clk);
            end
            repeat(680) @(negedge clk);frames=frames+1;
        end
    end
    task gesture;
        input integer key,cycles;
        begin
            if(key==1) key1=0;else key2=0;
            repeat(cycles) @(negedge clk);
            if(key==1) key1=1;else key2=1;
            repeat(12) @(negedge clk);
        end
    endtask
    task select_field;
        input integer target;
        begin while(field!=target) gesture(2,15);end
    endtask
    task settle;
        input integer n;
        integer target;
        begin target=frames+n;wait(frames>=target);@(negedge clk);end
    endtask
    initial begin
        repeat(5) @(negedge clk);rst_n=1;settle(4);
        if(!valid || count!=2 || frozen || dut.boxes_visible) $fatal(1,"initial live count");
        gesture(1,15);settle(7);
        if(!frozen || !valid || count!=2 || dut.boxes_visible!=2 || !green || !labels)
            $fatal(1,"K1 freeze and accepted boxes");
        gesture(2,15);settle(2);
        if(!menu || !frozen || field!=1 || !dut.osd.runtime_menu) $fatal(1,"K2 menu not propagated");
        select_field(13);gesture(1,15);gesture(1,15);gesture(1,15);
        if(step!=3) $fatal(1,"step 256 selection");
        select_field(1);
        wait(de && y==84 && x==83);@(negedge clk);
        gesture(1,55);
        if(cfg[`BC_THRESHOLD]!=0 || dut.active_config[`BC_THRESHOLD]!=112)
            $fatal(1,"button change leaked into current frame");
        wait(dut.active_config[`BC_THRESHOLD]==0);repeat(8) @(negedge clk);
        if(valid || dut.boxes_visible) $fatal(1,"new button configuration did not invalidate old result");
        settle(7);
        if(!valid || count!=0 || dut.boxes_visible || dut.osd.param_bcd!=0) $fatal(1,"button threshold recount/readback");
        select_field(13);gesture(1,55);
        if(step!=2) $fatal(1,"reverse step 32 selection");
        select_field(1);gesture(1,15);gesture(1,15);gesture(1,15);settle(7);
        if(cfg[`BC_THRESHOLD]!=96 || count!=2 || dut.boxes_visible!=2 || dut.osd.param_bcd!=24'h000096)
            $fatal(1,"buttons did not restore count/boxes/readback");
        gesture(2,120);settle(2);
        if(menu || !frozen || dut.osd.runtime_menu || count!=2) $fatal(1,"K2 exit must preserve frozen result");
        gesture(1,15);settle(3);green=0;labels=0;settle(1);
        if(frozen || dut.boxes_visible || green || labels) $fatal(1,"K1 resume left old boxes");
        gesture(2,15);settle(7);
        if(!menu || !frozen || count!=2 || dut.boxes_visible!=2) $fatal(1,"menu entry from live must request freeze");
        $display("PASS dual-key video: real button freeze/menu/next/step/edit/exit/resume, frame-atomic configuration, invalidation/recount, threshold readback and matching frozen boxes/IDs");
        $finish;
    end
    initial begin #100000000;$fatal(1,"dual-key video timeout");end
endmodule
