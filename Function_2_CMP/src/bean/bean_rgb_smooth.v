`timescale 1ns/1ps
// Rounded binomial 3x3 RGB average in low-contrast regions after median.
// High-contrast windows pass their center, protecting silhouettes and lines.
module bean_rgb_smooth #(
    parameter IMAGE_WIDTH=1920,IMAGE_HEIGHT=1080,LINE_TOTAL=2200,EDGE_THRESHOLD=48
)(
    input clk,rst_n,
    input [23:0] rgb_i,input de_i,hs_i,vs_i,
    output [23:0] rgb_o,output de_o,hs_o,vs_o
);
    wire [143:0] pixels;
    wire [2:0] sync;
    bean_window #(.K(3),.BITS(16),.META_BITS(3),.LINE_TOTAL(LINE_TOTAL)) window3(
        .clk(clk),.rst_n(rst_n),.data_i({rgb_i[23:19],rgb_i[15:10],rgb_i[7:3]}),
        .meta_i({de_i,hs_i,vs_i}),.window_o(pixels),.meta_o(sync));
    wire [11:0] x,y;
    bean_raster_coords coords(.clk(clk),.rst_n(rst_n),.de_i(sync[2]),.vs_i(sync[0]),.x_o(x),.y_o(y));
    wire interior=sync[2] && x>0 && x<IMAGE_WIDTH-1 && y>0 && y<IMAGE_HEIGHT-1;
    reg [19:0] meta1,meta2;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin meta1<=20'd3;meta2<=20'd3;end
        else begin meta1<={pixels[64+:16],interior,sync};meta2<=meta1;end
    end
    wire [2:0] low_contrast;
    wire [15:0] filtered;
    genvar ch;
    generate for(ch=0;ch<3;ch=ch+1) begin: color
        localparam B=(ch==1)?6:5;
        localparam O=(ch==0)?0:((ch==1)?5:11);
        localparam LIMIT=(ch==1)?EDGE_THRESHOLD/4:EDGE_THRESHOLD/8;
        wire [B-1:0] p[0:8];
        genvar n;
        for(n=0;n<9;n=n+1) begin: unpack_pixel
            assign p[n]=pixels[n*16+O+:B];
        end
        function [B-1:0] lo;
            input [B-1:0] a,b,c;
            begin lo=(a<b)?((a<c)?a:c):((b<c)?b:c);end
        endfunction
        function [B-1:0] hi;
            input [B-1:0] a,b,c;
            begin hi=(a>b)?((a>c)?a:c):((b>c)?b:c);end
        endfunction
        wire [B+3:0] sum=
            {{4{1'b0}},p[0]}+({{4{1'b0}},p[1]}<<1)+{{4{1'b0}},p[2]}+
            ({{4{1'b0}},p[3]}<<1)+({{4{1'b0}},p[4]}<<2)+({{4{1'b0}},p[5]}<<1)+
            {{4{1'b0}},p[6]}+({{4{1'b0}},p[7]}<<1)+{{4{1'b0}},p[8]}+8;
        reg [B-1:0] local_min,local_max,average,result;
        always @(posedge clk) begin
            local_min<=lo(lo(p[0],p[1],p[2]),lo(p[3],p[4],p[5]),lo(p[6],p[7],p[8]));
            local_max<=hi(hi(p[0],p[1],p[2]),hi(p[3],p[4],p[5]),hi(p[6],p[7],p[8]));
            average<=sum[B+3:4];
            result<=(&low_contrast)?average:meta1[4+O+:B];
        end
        assign low_contrast[ch]=(local_max-local_min)<=LIMIT;
        assign filtered[O+:B]=result;
    end endgenerate
    wire [15:0] selected=meta2[3]?filtered:meta2[19:4];
    assign {de_o,hs_o,vs_o}=meta2[2:0];
    assign rgb_o=!de_o?24'b0:{selected[15:11],3'b0,selected[10:5],2'b0,selected[4:0],3'b0};
endmodule
