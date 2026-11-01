`timescale 1ns/1ps
// Exact per-channel 3x3 median, one pixel/clock. The DDR source is RGB565;
// retain that precision in two line RAMs instead of storing redundant zeros.
// Full-raster delay = LINE_TOTAL+5 cycles. Borders pass the center unchanged.
module bean_rgb_median #(
    parameter IMAGE_WIDTH=1920, IMAGE_HEIGHT=1080, LINE_TOTAL=2200
)(
    input clk,rst_n,
    input [23:0] rgb_i, input de_i,hs_i,vs_i,
    output [23:0] rgb_o, output de_o,hs_o,vs_o
);
    wire [143:0] pixels;
    wire [2:0] sync;
    bean_window #(.K(3),.BITS(16),.META_BITS(3),.LINE_TOTAL(LINE_TOTAL)) window3(
        .clk(clk),.rst_n(rst_n),
        .data_i({rgb_i[23:19],rgb_i[15:10],rgb_i[7:3]}),
        .meta_i({de_i,hs_i,vs_i}),.window_o(pixels),.meta_o(sync));
    wire [11:0] x,y;
    bean_raster_coords coords(.clk(clk),.rst_n(rst_n),.de_i(sync[2]),
        .vs_i(sync[0]),.x_o(x),.y_o(y));
    wire interior=sync[2] && x>0 && x<IMAGE_WIDTH-1 && y>0 && y<IMAGE_HEIGHT-1;
    reg [19:0] meta1,meta2,meta3;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin meta1<=20'd3;meta2<=20'd3;meta3<=20'd3;end
        else begin
            meta1<={pixels[64+:16],interior,sync};
            meta2<=meta1;meta3<=meta2;
        end
    end
    wire [15:0] median_pixel;
    genvar channel;
    generate for(channel=0;channel<3;channel=channel+1) begin: color
        localparam B=(channel==1)?6:5;
        localparam O=(channel==0)?0:((channel==1)?5:11);
        function [B-1:0] lo;
            input [B-1:0] a,b,c;
            begin lo=(a<b)?((a<c)?a:c):((b<c)?b:c);end
        endfunction
        function [B-1:0] hi;
            input [B-1:0] a,b,c;
            begin hi=(a>b)?((a>c)?a:c):((b>c)?b:c);end
        endfunction
        function [B-1:0] mid;
            input [B-1:0] a,b,c;
            begin mid=(a<b)?((b<c)?b:((a<c)?c:a)):
                             ((a<c)?a:((b<c)?c:b));end
        endfunction
        reg [B-1:0] row_lo[0:2],row_mid[0:2],row_hi[0:2];
        reg [B-1:0] max_lo,mid_mid,min_hi,result;
        integer r;
        always @(posedge clk) begin
            for(r=0;r<3;r=r+1) begin
                row_lo[r]<=lo(pixels[(r*3)*16+O+:B],pixels[(r*3+1)*16+O+:B],pixels[(r*3+2)*16+O+:B]);
                row_mid[r]<=mid(pixels[(r*3)*16+O+:B],pixels[(r*3+1)*16+O+:B],pixels[(r*3+2)*16+O+:B]);
                row_hi[r]<=hi(pixels[(r*3)*16+O+:B],pixels[(r*3+1)*16+O+:B],pixels[(r*3+2)*16+O+:B]);
            end
            // Median9 = median(max(row minima), median(row medians), min(row maxima)).
            max_lo<=hi(row_lo[0],row_lo[1],row_lo[2]);
            mid_mid<=mid(row_mid[0],row_mid[1],row_mid[2]);
            min_hi<=lo(row_hi[0],row_hi[1],row_hi[2]);
            result<=mid(max_lo,mid_mid,min_hi);
        end
        assign median_pixel[O+:B]=result;
    end endgenerate
    wire [15:0] selected=meta3[3]?median_pixel:meta3[19:4];
    assign {de_o,hs_o,vs_o}=meta3[2:0];
    assign rgb_o=!de_o?24'b0:{selected[15:11],3'b0,selected[10:5],2'b0,selected[4:0],3'b0};
endmodule
