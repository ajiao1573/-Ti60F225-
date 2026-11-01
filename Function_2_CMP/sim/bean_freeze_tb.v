`timescale 1ns/1ps
// Two independent clocks and four model DDR banks. Camera writes continue
// throughout freeze. Each bank contains a scene with either 1 or 3 targets.
module bean_freeze_tb #(parameter DENOISE_ENABLE=0,parameter FAULT_TEST=0,parameter HOLD_FRAMES=3);
    reg clk=0,axi_clk=0;
    always #5 clk=~clk;
    always #7 axi_clk=~axi_clk;
    reg rst_n=0,request=0,vs=1,de=0,hs=1;
    reg [23:0] rgb=24'hffffff;
    wire [1:0] wb,rb;
    wire frozen_axi;
    reg frozen_meta=0,frozen=0;
    reg vs_meta=1,vs_axi=1,vs_prev=1;
    reg wd=0;
    integer writer_clocks=0,camera_scene=1;
    integer scene[0:3];
    video_frame_banks banks(.clk(axi_clk),.rst_n(rst_n),.write_done_i(wd),
        .read_start_i(!vs_prev && vs_axi),.freeze_request_i(request),
        .write_bank_o(wb),.read_bank_o(rb),.frozen_o(frozen_axi));
    always @(posedge axi_clk) begin
        vs_meta<=vs; vs_axi<=vs_meta; vs_prev<=vs_axi;
        wd<=0;
        if(rst_n) begin
            writer_clocks<=writer_clocks+1;
            if(writer_clocks%150==149) wd<=1;
            if(wd) scene[wb]<=camera_scene;
        end
    end
    always @(posedge clk) begin frozen_meta<=frozen_axi; frozen<=frozen_meta; end
    reg source_error=0,source_ready=1;
    wire [15:0] count;
    wire valid,error,busy;
    wire [23:0] out_rgb;
    wire out_de,out_hs,out_vs;
    bean_counter_video #(.IMAGE_WIDTH(64),.IMAGE_HEIGHT(48),.LABEL_BITS(5),.LINE_TOTAL(74),
        .DENOISE_ENABLE(DENOISE_ENABLE),
        .ROI_X0(0),.ROI_Y0(0),.ROI_X1(64),.ROI_Y1(48),
        .MIN_AREA(3),.MAX_AREA(120),.MIN_WIDTH(2),.MIN_HEIGHT(2),.MAX_WIDTH(20),.MAX_HEIGHT(20)) dut(
        .clk(clk),.rst_n(rst_n),.rgb_i(rgb),.de_i(de),.hs_i(hs),.vs_i(vs),.source_error_i(source_error),.source_ready_i(source_ready),.frozen_i(frozen),
        .rgb_o(out_rgb),.de_o(out_de),.hs_o(out_hs),.vs_o(out_vs),
        .count_o(count),.result_valid_o(valid),.overflow_o(error),.busy_o(busy));
    integer frame_results=0,frozen_results=0,xx,yy,i,snapshot_scene,results_before_hold;
    reg [1:0] snapshot_bank;
    always @(posedge clk) begin
        if(rst_n && dut.done) begin
            frame_results=frame_results+1;
            if(frozen) frozen_results=frozen_results+1;
        end
        #1;
        if(rst_n && frozen && dut.frozen_count_done && valid && count!=snapshot_scene)
            $fatal(1,"count does not describe frozen DDR scene: count=%0d scene=%0d",count,snapshot_scene);
    end
    always @(posedge clk) begin
        if(rst_n && dut.restart_analysis) begin
            #1;
            if(valid || dut.osd.displayed_valid)
                $fatal(1,"old count was not hidden on freeze/resume acknowledgement");
        end
    end
    task video_frame;
        input press_in_frame;
        begin
            vs=0; de=0; repeat(6) @(negedge clk);
            vs=1; repeat(15) @(negedge clk);
            if(frozen && !dut.frozen_count_done) begin snapshot_scene=scene[rb]; snapshot_bank=rb; end
            for(yy=0;yy<48;yy=yy+1) begin
                for(xx=0;xx<64;xx=xx+1) begin
                    de=1; rgb=24'hffffff;
                    if((xx>=8 && xx<18 && yy>=8 && yy<18) ||
                       (scene[rb]==3 && ((xx>=28 && xx<38 && yy>=8 && yy<18) ||
                                       (xx>=44 && xx<54 && yy>=28 && yy<38)))) rgb=0;
                    if(press_in_frame && yy==12 && xx==10) request=1;
                    @(negedge clk);
                end
                de=0; rgb=24'hffffff; hs=0;
                repeat(3) @(negedge clk); hs=1; repeat(7) @(negedge clk);
            end
        end
    endtask
    initial begin
        scene[0]=0;scene[1]=0;scene[2]=0;scene[3]=0;snapshot_scene=0;snapshot_bank=0;
        repeat(5) @(negedge clk); rst_n=1;
        for(i=0;i<5;i=i+1) video_frame(0);
        if(!valid || count!=1) $fatal(1,"live startup did not count one target");
        // Let a newer 3-target bank be selected while a 1-target result is old.
        camera_scene=3; video_frame(0); video_frame(1);
        for(i=0;i<5;i=i+1) video_frame(0);
        if(!frozen || !valid || error || count!=3 || !dut.frozen_count_done)
            $fatal(1,"frozen capture did not count three targets");
        if(frozen_results!=1) $fatal(1,"must analyze frozen scene exactly once: %0d",frozen_results);
        if(FAULT_TEST) begin
            source_error=1;video_frame(0);video_frame(0);
            if(valid || !dut.osd.displayed_error || dut.osd.displayed_valid)
                $fatal(1,"transport fault left stale frozen count visible");
            source_error=0;source_ready=0;video_frame(0);
            if(valid) $fatal(1,"published a count before a complete source frame was ready");
            source_ready=1;
            for(i=0;i<5;i=i+1) video_frame(0);
            if(!valid || count!=3 || !dut.frozen_count_done || dut.osd.displayed_error)
                $fatal(1,"source fault did not recover and recount pinned frame");
        end
        results_before_hold=frame_results;
        camera_scene=1;
        for(i=0;i<HOLD_FRAMES;i=i+1) begin
            video_frame(0);
            if(rb!=snapshot_bank || scene[rb]!=3 || count!=3 || busy)
                $fatal(1,"held scene/count changed while camera kept writing");
        end
        if(frame_results!=results_before_hold || !dut.osd.displayed_frozen || dut.osd.displayed_bcd!=16'h0003)
            $fatal(1,"OSD HOLD/count or one-shot capture failed");
        request=0;
        for(i=0;i<6;i=i+1) video_frame(0);
        if(frozen || !valid || error || count!=1 || dut.osd.displayed_frozen)
            $fatal(1,"live video/count failed to resume");
        $display("PASS source_fault_test=%0d hold_frames=%0d",FAULT_TEST,HOLD_FRAMES);
        $display("PASS freeze/resume with asynchronous clocks, ongoing camera writes, matching frozen count and HOLD overlay");
        $finish;
    end
    initial begin #20000000; $fatal(1,"freeze timeout"); end
endmodule
