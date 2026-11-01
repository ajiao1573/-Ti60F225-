`timescale 1ns/1ps
// Default-size RAM/address and continuous-video regression.
module bean_720p_tb;
    parameter FRAMES=4; // -Pbean_720p_tb.FRAMES=2 for the native-size smoke run
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,de=0,hs=1,vs=1;
    reg [23:0] rgb=24'hffffff;
    wire [23:0] out_rgb;
    wire out_de,out_hs,out_vs,valid,error,busy;
    wire [15:0] count;
    bean_counter_video dut(
        .clk(clk),.rst_n(rst_n),.rgb_i(rgb),.de_i(de),.hs_i(hs),.vs_i(vs),
        .frozen_i(1'b0),.rgb_o(out_rgb),.de_o(out_de),.hs_o(out_hs),.vs_o(out_vs),
        .count_o(count),.result_valid_o(valid),.overflow_o(error),.busy_o(busy));
    integer frame,line,pixel,results=0,clock_count=0,capture_finish=0,contour_checks=0;
    always @(posedge clk) begin
        #1;
        if(rst_n && dut.contour_de && dut.contour_y==120 && dut.contour_x>=199 && dut.contour_x<=203) begin
            if(dut.contour_rgb !== ((dut.contour_x==199)?24'hffffff:
                (dut.contour_x==200 || dut.contour_x==201)?24'hff0000:24'h000000))
                $fatal(1,"720p contour alignment/thickness failed at x=%0d RGB=%h",dut.contour_x,dut.contour_rgb);
            contour_checks=contour_checks+1;
        end
    end
    always @(posedge clk) begin
        clock_count=clock_count+1;
        if(rst_n && dut.cca.state==2 && dut.cca.clear_x==0) capture_finish=clock_count;
        if(rst_n && dut.done) begin
            if(!valid || error || count!=3) $fatal(1,"720p count failed: %0d valid=%b error=%b",count,valid,error);
            results=results+1;
            $display("PASS 720p result %0d, CCA cycles after capture=%0d",results,clock_count-capture_finish);
        end
    end
    initial begin
        repeat(5) @(negedge clk); rst_n=1;
        // Four frames allow a second capture after two skipped frame starts.
        for(frame=0;frame<FRAMES;frame=frame+1) begin
            for(line=0;line<750;line=line+1) begin
                for(pixel=0;pixel<1650;pixel=pixel+1) begin
                    vs=line>=5; hs=pixel>=40;
                    de=line>=25 && line<745 && pixel>=260 && pixel<1540;
                    rgb=24'hffffff;
                    if(de && (
                        (pixel>=460 && pixel<500 && line>=125 && line<165) ||
                        (pixel>=860 && pixel<910 && line>=325 && line<375) ||
                        (pixel>=1160 && pixel<1200 && line>=525 && line<565)))
                        rgb=0;
                    @(negedge clk);
                end
            end
        end
        de=0; vs=1; hs=1;
        while(busy) @(negedge clk);
        // PUBLISH releases busy and raises done on the same edge; allow the
        // monitor to observe that done pulse before checking the result total.
        repeat(2) @(negedge clk);
        if(results<FRAMES/2) $fatal(1,"not enough completed 720p results: %0d",results);
        if(contour_checks!=5*FRAMES) $fatal(1,"720p contour checks incomplete: %0d",contour_checks);
        $display("PASS full-size continuous video: frames=%0d, results=%0d, count=%0d, native contour checks=%0d",FRAMES,results,count,contour_checks);
        $finish;
    end
    initial begin #80000000; $fatal(1,"720p timeout"); end
endmodule
