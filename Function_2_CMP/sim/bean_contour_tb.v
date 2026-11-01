`timescale 1ns/1ps
module bean_contour_tb;
    localparam L=80, N=4*72*80, D=7*L+18;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,de=0,hs=1,vs=1;
    reg [23:0] rgb=0;
    reg [11:0] x=0,y=0;
    wire [23:0] out_rgb;
    wire out_de,out_hs,out_vs;
    wire [11:0] out_x,out_y;
    bean_contour #(.LINE_TOTAL(L),.ROI_X0(4),.ROI_Y0(4),.ROI_X1(60),.ROI_Y1(52)) dut(
        .clk(clk),.rst_n(rst_n),.rgb_i(rgb),.de_i(de),.hs_i(hs),.vs_i(vs),.x_i(x),.y_i(y),
        .rgb_o(out_rgb),.de_o(out_de),.hs_o(out_hs),.vs_o(out_vs),.x_o(out_x),.y_o(out_y));
    reg [23:0] images[0:N-1],expected[0:N-1];
    integer des[0:N-1],hss[0:N-1],vss[0:N-1],xs[0:N-1],ys[0:N-1];
    integer fd,rc,i,idx=-1,checked=0,red=0,pass,preview;
    always @(posedge clk) begin
        if(rst_n) begin
            #1;
            if(idx>=D && idx-D<N) begin
                if({out_de,out_hs,out_vs} !== {des[idx-D][0],hss[idx-D][0],vss[idx-D][0]})
                    $fatal(1,"contour sync alignment idx=%0d",idx-D);
                if(out_de) begin
                    if(out_rgb !== expected[idx-D] || out_x!=xs[idx-D] || out_y!=ys[idx-D])
                        $fatal(1,"contour mismatch idx=%0d xy=%0d,%0d got=%h expected=%h outxy=%0d,%0d",
                            idx-D,xs[idx-D],ys[idx-D],out_rgb,expected[idx-D],out_x,out_y);
                    checked=checked+1;
                    if(out_rgb==24'hff0000) red=red+1;
                    if(pass==0 && idx-D<72*80)
                        $fwrite(preview,"%c%c%c",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);
                end else if(out_rgb!==0) $fatal(1,"non-black blanking");
            end
        end
    end
    initial begin
        preview=$fopen("build/sim/contour_rtl.ppm","wb");
        $fwrite(preview,"P6\n64 56\n255\n");
        fd=$fopen("build/sim/contour_vectors.txt","r");
        if(!fd) $fatal(1,"missing contour vectors");
        for(i=0;i<N;i=i+1) begin
            rc=$fscanf(fd,"%h %d %d %d %d %d %h",images[i],des[i],hss[i],vss[i],xs[i],ys[i],expected[i]);
            if(rc!=7) $fatal(1,"bad vector %0d",i);
        end
        // Reset twice to prove stale line RAM cannot leak after restart.
        for(pass=0;pass<2;pass=pass+1) begin
            rst_n=0; idx=-1;
            repeat(4) @(negedge clk);
            rst_n=1;
            for(i=0;i<N+D;i=i+1) begin
                idx=i;
                if(i<N) begin rgb=images[i]; de=des[i]; hs=hss[i]; vs=vss[i]; x=xs[i]; y=ys[i]; end
                else begin rgb=0;de=0;hs=1;vs=1;x=0;y=0;end
                @(negedge clk);
            end
        end
        if(checked!=2*4*64*56 || red<1000) $fatal(1,"incomplete coverage %0d %0d",checked,red);
        $fclose(preview);
        $display("PASS contours: %0d pixels vs independent spatial reference, moving/empty frames, 2px thickness, RGB/sync/coordinates, warm reset",checked);
        $finish;
    end
endmodule

