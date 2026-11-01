`timescale 1ns/1ps
module bean_median_tb #(parameter SMOOTH=0,K=3,NATIVE=0);
    localparam W=NATIVE?1920:64,H=NATIVE?16:56,L=NATIVE?2200:80,F=NATIVE?1:4;
    localparam PASSES=NATIVE?1:2,N=F*(H+16)*L;
    localparam MD=(K==5)?2*L+18:L+5,D=MD+(SMOOTH?L+5:0),C=D+6*L+16;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,de=0,hs=1,vs=1;
    reg [23:0] rgb=0;
    wire [23:0] med_rgb,out_rgb;
    wire med_de,med_hs,med_vs,out_de,out_hs,out_vs;
    wire [11:0] mx,my,ox,oy;
    wire [23:0] raw_median_rgb;
    wire raw_median_de,raw_median_hs,raw_median_vs;
    generate if(K==5) begin: median5_enabled
    bean_rgb_median5 #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.LINE_TOTAL(L)) dut(
        .clk(clk),.rst_n(rst_n),.rgb_i(rgb),.de_i(de),.hs_i(hs),.vs_i(vs),
        .rgb_o(raw_median_rgb),.de_o(raw_median_de),.hs_o(raw_median_hs),.vs_o(raw_median_vs));
    end else begin: median3_enabled
    bean_rgb_median #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.LINE_TOTAL(L)) dut(
        .clk(clk),.rst_n(rst_n),.rgb_i(rgb),.de_i(de),.hs_i(hs),.vs_i(vs),
        .rgb_o(raw_median_rgb),.de_o(raw_median_de),.hs_o(raw_median_hs),.vs_o(raw_median_vs));
    end endgenerate
    generate if(SMOOTH) begin: smooth_enabled
        bean_rgb_smooth #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.LINE_TOTAL(L)) smooth(
            .clk(clk),.rst_n(rst_n),.rgb_i(raw_median_rgb),.de_i(raw_median_de),.hs_i(raw_median_hs),.vs_i(raw_median_vs),
            .rgb_o(med_rgb),.de_o(med_de),.hs_o(med_hs),.vs_o(med_vs));
    end else begin
        assign {med_rgb,med_de,med_hs,med_vs}={raw_median_rgb,raw_median_de,raw_median_hs,raw_median_vs};
    end endgenerate
    bean_raster_coords coords(.clk(clk),.rst_n(rst_n),.de_i(med_de),.vs_i(med_vs),.x_o(mx),.y_o(my));
    bean_contour #(.LINE_TOTAL(L),.INPUT_DENOISED(1),
        .ROI_X0(4),.ROI_Y0(4),.ROI_X1(W-4),.ROI_Y1(H-4)) contour(
        .clk(clk),.rst_n(rst_n),.rgb_i(med_rgb),.de_i(med_de),.hs_i(med_hs),.vs_i(med_vs),
        .x_i(mx),.y_i(my),.rgb_o(out_rgb),.de_o(out_de),.hs_o(out_hs),.vs_o(out_vs),.x_o(ox),.y_o(oy));
    reg [23:0] images[0:N-1],expected[0:N-1],edges[0:N-1];
    integer des[0:N-1],hss[0:N-1],vss[0:N-1],xs[0:N-1],ys[0:N-1];
    integer fd,rc,i,idx=-1,checked=0,chain_checked=0,pass,j;
    always @(posedge clk) if(rst_n) begin
        #1;
        if(idx>=D && idx-D<N) begin
            j=idx-D;
            if({med_de,med_hs,med_vs} !== {des[j][0],hss[j][0],vss[j][0]})
                $fatal(1,"median sync alignment idx=%0d",j);
            if(med_de) begin
                if(med_rgb!==expected[j] || mx!=xs[j] || my!=ys[j])
                    $fatal(1,"median mismatch idx=%0d xy=%0d,%0d got=%h expected=%h outxy=%0d,%0d",
                        j,xs[j],ys[j],med_rgb,expected[j],mx,my);
                checked=checked+1;
            end else if(med_rgb!==0) $fatal(1,"median blanking");
        end
        if(idx>=C && idx-C<N) begin
            j=idx-C;
            if({out_de,out_hs,out_vs} !== {des[j][0],hss[j][0],vss[j][0]})
                $fatal(1,"denoised contour sync alignment idx=%0d",j);
            if(out_de) begin
                if(out_rgb!==edges[j] || ox!=xs[j] || oy!=ys[j])
                    $fatal(1,"denoised contour mismatch idx=%0d xy=%0d,%0d got=%h expected=%h outxy=%0d,%0d",
                        j,xs[j],ys[j],out_rgb,edges[j],ox,oy);
                chain_checked=chain_checked+1;
            end else if(out_rgb!==0) $fatal(1,"contour blanking");
        end
    end
    initial begin
        if(NATIVE) fd=$fopen("build/sim/native_median5_smooth_vectors.txt","r");
        else if(K==5) fd=SMOOTH?$fopen("build/sim/median5_smooth_vectors.txt","r"):$fopen("build/sim/median5_vectors.txt","r");
        else fd=SMOOTH?$fopen("build/sim/median_smooth_vectors.txt","r"):$fopen("build/sim/median_vectors.txt","r");
        if(!fd) $fatal(1,"missing median vectors");
        for(i=0;i<N;i=i+1) begin
            rc=$fscanf(fd,"%h %d %d %d %d %d %h %h",images[i],des[i],hss[i],vss[i],xs[i],ys[i],expected[i],edges[i]);
            if(rc!=8) $fatal(1,"bad median vector %0d",i);
        end
        $fclose(fd);
        for(pass=0;pass<PASSES;pass=pass+1) begin
            rst_n=0;idx=-1;
            repeat(4) @(negedge clk);
            rst_n=1;
            for(i=0;i<N+C;i=i+1) begin
                idx=i;
                if(i<N) begin rgb=images[i];de=des[i];hs=hss[i];vs=vss[i];end
                else begin rgb=0;de=0;hs=1;vs=1;end
                @(negedge clk);
            end
        end
        if(checked!=PASSES*F*W*H || chain_checked!=PASSES*F*W*H) $fatal(1,"incomplete median coverage");
        $display("PASS RGB median%0d/smooth=%0d native_width=%0d and contour: %0d pixels each, independent spatial reference, random/impulse/grain/moving/empty scenes, borders, sync, reset",K,SMOOTH,NATIVE,checked);
        $finish;
    end
endmodule
