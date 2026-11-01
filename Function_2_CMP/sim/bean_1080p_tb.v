`timescale 1ns/1ps
// Actual default lcd_driver raster, every native contour pixel checked.
// CCA runs on its unchanged analysis branch; stop only the contour simulation
// clock after its complete output frame, while offline CCA finishes normally.
module bean_1080p_tb #(parameter DENOISE_ENABLE=1,parameter FRAMES=2);
    localparam W=1920,H=1080,TOTAL=W*H,EXPECTED_PIXELS=TOTAL*FRAMES;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,capture=1,contour_run=1;
    wire cc=clk & contour_run;
    wire de,hs,vs,req;
    wire [11:0] unused_x,unused_y;
    wire [23:0] unused_rgb;
    lcd_driver #(.DATA_WIDTH(24)) timing(.clk(clk),.rst_n(rst_n),
        .lcd_dclk(),.lcd_blank(),.lcd_sync(),.lcd_hs(hs),.lcd_vs(vs),.lcd_en(de),
        .lcd_rgb(unused_rgb),.lcd_request(req),.lcd_xpos(unused_x),.lcd_ypos(unused_y),.lcd_data(24'b0));
    reg [23:0] source=24'hffffff;
    wire input_de=de && capture;
    // The legacy driver does not assign VS until the first line ends.
    // Treat its startup X as inactive blanking, then use its actual raster.
    wire video_vs=(vs===1'b0)?1'b0:1'b1;
    wire [23:0] rgb;
    wire ode,ohs,ovs;
    wire [11:0] ox,oy;
    wire [23:0] smooth_rgb,median_rgb;
    wire smooth_de,smooth_hs,smooth_vs;
    wire median_de,median_hs,median_vs;
    generate if(DENOISE_ENABLE) begin: filtered
        bean_rgb_median5 #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.LINE_TOTAL(2200)) median(
            .clk(cc),.rst_n(rst_n),.rgb_i(source),.de_i(input_de),.hs_i(hs),.vs_i(video_vs),
            .rgb_o(median_rgb),.de_o(median_de),.hs_o(median_hs),.vs_o(median_vs));
        bean_rgb_smooth #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.LINE_TOTAL(2200)) smooth(
            .clk(cc),.rst_n(rst_n),.rgb_i(median_rgb),.de_i(median_de),.hs_i(median_hs),.vs_i(median_vs),
            .rgb_o(smooth_rgb),.de_o(smooth_de),.hs_o(smooth_hs),.vs_o(smooth_vs));
    end else begin
        assign {smooth_rgb,smooth_de,smooth_hs,smooth_vs}={source,input_de,hs,video_vs};
    end endgenerate
    bean_contour #(.LINE_TOTAL(2200),.INPUT_DENOISED(DENOISE_ENABLE),
        .ROI_X0(96),.ROI_Y0(72),.ROI_X1(1824),.ROI_Y1(1008)) contour(
        .clk(cc),.rst_n(rst_n),.rgb_i(smooth_rgb),.de_i(smooth_de),.hs_i(smooth_hs),.vs_i(smooth_vs),
        .x_i(12'b0),.y_i(12'b0),.rgb_o(rgb),.de_o(ode),.hs_o(ohs),.vs_o(ovs),.x_o(ox),.y_o(oy));
    wire [15:0] count;
    wire valid,error,busy;
    bean_counter_video #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.CONTOUR_ENABLE(0),
        .LINE_TOTAL(2200),.DENOISE_ENABLE(0),
        .ROI_X0(96),.ROI_Y0(72),.ROI_X1(1824),.ROI_Y1(1008),
        .MIN_AREA(36),.MAX_AREA(11250),.MIN_WIDTH(5),.MIN_HEIGHT(5),.MAX_WIDTH(240),.MAX_HEIGHT(240)) counter(
        // Share the full-resolution denoised stream, as the actual top does.
        // Keep CCA running while the verified image pipeline clock is stopped.
        .clk(clk),.rst_n(rst_n),.rgb_i(smooth_rgb),.de_i(smooth_de),.hs_i(smooth_hs),.vs_i(smooth_vs),.source_error_i(1'b0),.source_ready_i(1'b1),.frozen_i(1'b0),
        .rgb_o(),.de_o(),.hs_o(),.vs_o(),.count_o(count),.result_valid_o(valid),.overflow_o(error),.busy_o(busy));
    function in_rect;
        input integer x,y,x0,y0,size;
        begin in_rect=x>=x0 && x<x0+size && y>=y0 && y<y0+size;end
    endfunction
    function rounded_rect;
        input integer x,y,x0,y0,size,r;
        begin
            rounded_rect=in_rect(x,y,x0+r,y0+r,size-2*r) &&
                !((x==x0+r || x==x0+size-1-r) && (y==y0+r || y==y0+size-1-r));
        end
    endfunction
    function is_object;
        input integer x,y;
        begin is_object=in_rect(x,y,200,100,40) || in_rect(x,y,900,500,50) || in_rect(x,y,1720,950,40);end
    endfunction
    function is_edge;
        input integer x,y;
        begin is_edge=(rounded_rect(x,y,200,100,40,0) && !rounded_rect(x,y,200,100,40,2)) ||
            (rounded_rect(x,y,900,500,50,0) && !rounded_rect(x,y,900,500,50,2)) ||
            (rounded_rect(x,y,1720,950,40,0) && !rounded_rect(x,y,1720,950,40,2));end
    endfunction
    function median_object;
        input integer x,y;
        begin median_object=rounded_rect(x,y,200,100,40,0) ||
            rounded_rect(x,y,900,500,50,0) || rounded_rect(x,y,1720,950,40,0);end
    endfunction
    integer inputs=0,outputs=0,red=0,sx,sy,ex,ey,cycles=0;
    reg [23:0] rect40[0:1599],rect50[0:2499];
    integer expected_red=992,ref_fd,ref_rc;
    reg [23:0] expected;
    reg last_hs=1,last_vs=1,last_de=0;
    integer hs_start=-1,vs_start=-1,low_start=-1,active_start=-1,frame_pixels=0,frame_requests=0,frames_checked=0,lines_checked=0;
    always @(negedge clk) if(rst_n) begin
        if(inputs==EXPECTED_PIXELS) capture=0;
        if(input_de) begin
            sx=inputs%W;sy=(inputs/W)%H;
            source=is_object(sx,sy)?24'h000000:24'hffffff;
            // Sparse isolated impulse noise in the background must disappear
            // before both full-resolution contouring and downsampled counting.
            if(DENOISE_ENABLE && sx%127==31 && sy%101==25 && !is_object(sx,sy)) source=0;
            inputs=inputs+1;
        end else source=24'hffffff;
        if(outputs==EXPECTED_PIXELS) contour_run=0;
    end
    always @(posedge clk) if(rst_n) begin
        cycles=cycles+1;
        #1;
        if(last_hs && !hs) begin
            if(hs_start>=0 && cycles-hs_start!=2200) $fatal(1,"1080p line period");
            hs_start=cycles;low_start=cycles;
        end
        if(!last_hs && hs && low_start>=0) begin
            if(cycles-low_start!=44) $fatal(1,"1080p HSync width");
            lines_checked=lines_checked+1;
        end
        if(last_vs && !video_vs) begin
            if(vs_start>=0) begin
                if(cycles-vs_start!=2475000 || frame_pixels!=TOTAL || frame_requests!=TOTAL)
                    $fatal(1,"1080p frame period/active/request count: %0d %0d %0d",cycles-vs_start,frame_pixels,frame_requests);
                frames_checked=frames_checked+1;
            end
            vs_start=cycles;frame_pixels=0;frame_requests=0;
        end
        if(de) frame_pixels=frame_pixels+1;
        if(req) frame_requests=frame_requests+1;
        if(!last_de && de) active_start=cycles;
        if(last_de && !de && cycles-active_start!=1920) $fatal(1,"1080p active line width");
        last_hs=hs;last_vs=video_vs;last_de=de;
        if(contour_run && ode) begin
            ex=outputs%W;ey=(outputs/W)%H;
            if(DENOISE_ENABLE) begin
                if(in_rect(ex,ey,200,100,40)) expected=rect40[(ey-100)*40+ex-200];
                else if(in_rect(ex,ey,900,500,50)) expected=rect50[(ey-500)*50+ex-900];
                else if(in_rect(ex,ey,1720,950,40)) expected=rect40[(ey-950)*40+ex-1720];
                else expected=24'hf8fcf8;
            end
            else expected=is_edge(ex,ey)?24'hff0000:is_object(ex,ey)?24'h000000:24'hffffff;
            if(rgb!==expected || ox!=ex || oy!=ey)
                $fatal(1,"1080p native contour pixel %0d,%0d: got %h (%0d,%0d) expected %h",ex,ey,rgb,ox,oy,expected);
            if(rgb==24'hff0000) red=red+1;
            outputs=outputs+1;
            if(outputs%(W*270)==0) $display("1080p progress: %0d/%0d denoised pixels checked",outputs,EXPECTED_PIXELS);
        end
        if(error) $fatal(1,"1080p count overflow/incomplete capture");
    end
    initial begin
        if(DENOISE_ENABLE) begin
            $readmemh("build/sim/native_denoise_rect40.hex",rect40);
            $readmemh("build/sim/native_denoise_rect50.hex",rect50);
            ref_fd=$fopen("build/sim/native_denoise_red_total.txt","r");
            ref_rc=$fscanf(ref_fd,"%d",expected_red);
            if(ref_rc!=1) $fatal(1,"missing native median5 reference");
            $fclose(ref_fd);
        end
        repeat(5) @(negedge clk);rst_n=1;
        wait(outputs==EXPECTED_PIXELS && valid && frames_checked>=FRAMES);
        repeat(3) @(negedge clk);
        if(count!=3 || inputs!=EXPECTED_PIXELS || frames_checked<FRAMES || lines_checked<1125*FRAMES || red!=expected_red*FRAMES)
            $fatal(1,"1080p incomplete verification: count=%0d in=%0d out=%0d frames=%0d red=%0d",count,inputs,outputs,frames_checked,red);
        $display("PASS 1080p: %0d native contour pixels, median=%0d, impulse removal, 2px borders incl bottom-right object, RGB/XY alignment",outputs,DENOISE_ENABLE);
        $display("PASS actual 2200x1125 raster, 1920x1080 DE/request, HSync=44, full 960x540 count=%0d",count);
        $finish;
    end
    initial begin #150000000;$fatal(1,"1080p simulation timeout");end
endmodule
