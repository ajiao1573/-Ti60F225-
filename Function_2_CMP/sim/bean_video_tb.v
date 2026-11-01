`timescale 1ns/1ps
module bean_video_tb;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,de=0,hs=1,vs=1;
    reg [23:0] rgb=0;
    wire [23:0] rgb_o;
    wire de_o,hs_o,vs_o;
    wire [15:0] count;
    wire valid,error,busy;
    bean_counter_video #(.IMAGE_WIDTH(64),.IMAGE_HEIGHT(48),.LABEL_BITS(5),.CONTOUR_ENABLE(0),
        .ROI_X0(0),.ROI_Y0(0),.ROI_X1(64),.ROI_Y1(48),
        .MIN_AREA(3),.MAX_AREA(120),.MIN_WIDTH(2),.MIN_HEIGHT(2),
        .MAX_WIDTH(20),.MAX_HEIGHT(20)) dut (
        .clk(clk),.rst_n(rst_n),.rgb_i(rgb),.de_i(de),.hs_i(hs),.vs_i(vs),
        .source_error_i(1'b0),.source_ready_i(1'b1),.frozen_i(1'b0),.rgb_o(rgb_o),.de_o(de_o),.hs_o(hs_o),.vs_o(vs_o),
        .count_o(count),.result_valid_o(valid),.overflow_o(error),.busy_o(busy));
    reg [2:0] de_pipe=0,hs_pipe=7,vs_pipe=7;
    integer filter_pixels=0,exmask,frc,ff;
    always @(posedge clk) begin
        if(!rst_n) begin de_pipe<=0; hs_pipe<=7; vs_pipe<=7; end
        else begin de_pipe<={de_pipe[1:0],de}; hs_pipe<={hs_pipe[1:0],hs}; vs_pipe<={vs_pipe[1:0],vs}; end
        #1;
        if(rst_n && {de_o,hs_o,vs_o} !== {de_pipe[2],hs_pipe[2],vs_pipe[2]})
            $fatal(1,"video pipeline timing mismatch");
        if(rst_n && dut.filter_valid) begin
            frc=$fscanf(ff,"%d",exmask);
            if(frc!=1 || dut.filter_mask !== exmask[0])
                $fatal(1,"majority filter mismatch pixel %0d",filter_pixels);
            if(dut.filter_x != filter_pixels%32 || dut.filter_y != filter_pixels/32)
                $fatal(1,"sample coordinate mismatch");
            filter_pixels=filter_pixels+1;
        end
    end
    integer fd,rc,expected,xx,yy,value,cycles;
    initial begin
        fd=$fopen("build/sim/video_vectors.txt","r");
        ff=$fopen("build/sim/filtered_expected.txt","r");
        if(!fd || !ff) $fatal(1,"missing vectors");
        rc=$fscanf(fd,"%d",expected);
        repeat(4) @(negedge clk); rst_n=1;
        @(negedge clk); vs=0;
        repeat(5) @(negedge clk); vs=1;
        repeat(5) @(negedge clk);
        for(yy=0;yy<48;yy=yy+1) begin
            for(xx=0;xx<64;xx=xx+1) begin
                rc=$fscanf(fd,"%d",value);
                if(rc != 1) $fatal(1,"bad video vector");
                de=1; rgb={value[7:0],value[7:0],value[7:0]};
                @(negedge clk);
            end
            de=0; rgb=0; hs=0;
            repeat(4) @(negedge clk); hs=1;
            repeat(6) @(negedge clk);
        end
        cycles=0;
        while(!valid && !error && cycles<100000) begin @(negedge clk); cycles=cycles+1; end
        if(!valid || error || count!=expected || filter_pixels!=768)
            $fatal(1,"video result count=%0d expected=%0d valid=%b error=%b samples=%0d",count,expected,valid,error,filter_pixels);
        // Wait for decimal conversion, then latch overlay on a frame boundary.
        repeat(25) @(negedge clk); vs=0;
        repeat(8) @(negedge clk); vs=1;
        if(!dut.osd.displayed_valid || dut.osd.displayed_bcd!=16'h0002)
            $fatal(1,"OSD decimal/frame latch failed");
        $display("PASS video, all filtered pixels, 2x decimation, sync alignment and OSD: count=%0d",count);
        $finish;
    end
    initial begin #20000000; $fatal(1,"video timeout"); end
endmodule
