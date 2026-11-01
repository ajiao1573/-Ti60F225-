`timescale 1ns/1ps
// Exact 25-sample median per RGB565 channel. A 32-input bitonic network
// pads seven inputs with the maximum value and selects sorted index 12.
// Fifteen registered compare/exchange layers sustain one pixel per clock.
module bean_rgb_median5 #(
    parameter IMAGE_WIDTH=1920,IMAGE_HEIGHT=1080,LINE_TOTAL=2200
)(
    input clk,rst_n,
    input [23:0] rgb_i,input de_i,hs_i,vs_i,
    output [23:0] rgb_o,output de_o,hs_o,vs_o
);
    wire [399:0] pixels;
    wire [2:0] sync;
    bean_window #(.K(5),.BITS(16),.META_BITS(3),.LINE_TOTAL(LINE_TOTAL)) window5(
        .clk(clk),.rst_n(rst_n),.data_i({rgb_i[23:19],rgb_i[15:10],rgb_i[7:3]}),
        .meta_i({de_i,hs_i,vs_i}),.window_o(pixels),.meta_o(sync));
    wire [11:0] x,y;
    bean_raster_coords coords(.clk(clk),.rst_n(rst_n),.de_i(sync[2]),.vs_i(sync[0]),.x_o(x),.y_o(y));
    wire interior=sync[2] && x>=2 && x<IMAGE_WIDTH-2 && y>=2 && y<IMAGE_HEIGHT-2;
    reg [19:0] meta[0:14];
    genvar m,ch,k,j,i;
    generate for(m=0;m<15;m=m+1) begin: timing_pipe
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) meta[m]<=20'd3;
            else if(m==0) meta[m]<={pixels[192+:16],interior,sync};
            else meta[m]<=meta[m-1];
        end
    end endgenerate
    wire [15:0] median_pixel;
    generate for(ch=0;ch<3;ch=ch+1) begin: color
        localparam B=(ch==1)?6:5;
        localparam O=(ch==0)?0:((ch==1)?5:11);
        wire [B-1:0] input_value[0:31];
        reg [B-1:0] sorted[0:479];
        for(i=0;i<32;i=i+1) begin: pad
            if(i<25) assign input_value[i]=pixels[i*16+O+:B];
            else assign input_value[i]={B{1'b1}};
        end
        for(k=1;k<=5;k=k+1) begin: group_size
            for(j=0;j<k;j=j+1) begin: compare_distance
                localparam S=k*(k-1)/2+j;
                localparam DIST=1<<(k-1-j);
                for(i=0;i<32;i=i+1) begin: exchange
                    localparam PARTNER=i^DIST;
                    localparam TAKE_MIN=((i&DIST)==0)==((i&(1<<k))==0);
                    wire [B-1:0] a,b;
                    if(S==0) begin
                        assign a=input_value[i];assign b=input_value[PARTNER];
                    end else begin
                        assign a=sorted[(S-1)*32+i];assign b=sorted[(S-1)*32+PARTNER];
                    end
                    always @(posedge clk)
                        sorted[S*32+i]<=TAKE_MIN?((a<b)?a:b):((a>b)?a:b);
                end
            end
        end
        assign median_pixel[O+:B]=sorted[14*32+12];
    end endgenerate
    wire [15:0] selected=meta[14][3]?median_pixel:meta[14][19:4];
    assign {de_o,hs_o,vs_o}=meta[14][2:0];
    assign rgb_o=!de_o?24'b0:{selected[15:11],3'b0,selected[10:5],2'b0,selected[4:0],3'b0};
endmodule
