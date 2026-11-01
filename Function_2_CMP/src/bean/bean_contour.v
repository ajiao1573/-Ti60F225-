`timescale 1ns/1ps
`include "bean/bean_config.vh"
// Native-resolution silhouette extraction: Gaussian -> threshold -> opening
// -> closing -> two-pixel INNER morphological boundary. All stages stream
// one pixel/clock; no frame-old mask is overlaid on a moving live image.
module bean_contour #(
    parameter RUNTIME_ENABLE=0,
    parameter LINE_TOTAL=1650, THRESHOLD=112, DARK_OBJECT=1, INPUT_DENOISED=0,
    parameter ROI_X0=64, ROI_Y0=48, ROI_X1=1216, ROI_Y1=672
)(
    input [`BEAN_CFG_BITS-1:0] config_i,
    input clk, input rst_n,
    input [23:0] rgb_i, input de_i,hs_i,vs_i,
    input [11:0] x_i,y_i,
    output [23:0] rgb_o, output de_o,hs_o,vs_o,
    output [11:0] x_o,y_o
);
    wire [11:0] cfg_roi_x0=RUNTIME_ENABLE ? config_i[`BC_X0] : ROI_X0;
    wire [11:0] cfg_roi_y0=RUNTIME_ENABLE ? config_i[`BC_Y0] : ROI_Y0;
    wire [11:0] cfg_roi_x1=RUNTIME_ENABLE ? config_i[`BC_X1] : ROI_X1;
    wire [11:0] cfg_roi_y1=RUNTIME_ENABLE ? config_i[`BC_Y1] : ROI_Y1;
    wire [7:0] cfg_threshold=RUNTIME_ENABLE ? config_i[`BC_THRESHOLD] : THRESHOLD;
    wire [0:0] cfg_dark_object=RUNTIME_ENABLE ? config_i[`BC_DARK] : DARK_OBJECT;
    wire [15:0] weighted_luma = {8'b0,rgb_i[23:16]}*16'd77+
        {8'b0,rgb_i[15:8]}*16'd150+{8'b0,rgb_i[7:0]}*16'd29;
    // Store only RGB and timing: coordinates are regenerated at the two
    // consumers. This keeps native 1080p within the Ti60 block-RAM budget.
    localparam M=INPUT_DENOISED?19:27;
    wire [M-1:0] meta[0:6];
    wire [11:0] smooth_x,smooth_y;
    generate if(INPUT_DENOISED) begin: pack_565
        assign meta[0]={rgb_i[23:19],rgb_i[15:10],rgb_i[7:3],de_i,hs_i,vs_i};
    end else begin: pack_888
        assign meta[0]={rgb_i,de_i,hs_i,vs_i};
    end endgenerate
    wire [7:0] smooth;
    generate if(INPUT_DENOISED) begin: median_input
        assign meta[1]=meta[0];
        assign smooth=weighted_luma[15:8];
    end else begin: gaussian_input
    wire [71:0] gray;
    bean_window #(.K(3),.BITS(8),.META_BITS(M),.LINE_TOTAL(LINE_TOTAL)) gaussian_window(
        .clk(clk),.rst_n(rst_n),.data_i(weighted_luma[15:8]),
        .meta_i(meta[0]),.window_o(gray),.meta_o(meta[1]));
    // Binomial Gaussian [1 2 1]'*[1 2 1]/16, rounded to nearest.
    wire [11:0] gaussian_sum =
        {4'b0,gray[7:0]}+({4'b0,gray[15:8]}<<1)+{4'b0,gray[23:16]}+
        ({4'b0,gray[31:24]}<<1)+({4'b0,gray[39:32]}<<2)+({4'b0,gray[47:40]}<<1)+
        {4'b0,gray[55:48]}+({4'b0,gray[63:56]}<<1)+{4'b0,gray[71:64]}+12'd8;
    assign smooth=gaussian_sum[11:4];
    end endgenerate
    bean_raster_coords smooth_coords(.clk(clk),.rst_n(rst_n),.de_i(meta[1][2]),
        .vs_i(meta[1][0]),.x_o(smooth_x),.y_o(smooth_y));
    wire in_roi=meta[1][2] && smooth_x>=cfg_roi_x0 && smooth_x<cfg_roi_x1 &&
        smooth_y>=cfg_roi_y0 && smooth_y<cfg_roi_y1;
    wire mask0=in_roi && (cfg_dark_object ? smooth<cfg_threshold : smooth>cfg_threshold);
    wire [8:0] w1,w2,w3,w4;
    wire [24:0] w5;
    bean_window #(.META_BITS(M),.LINE_TOTAL(LINE_TOTAL)) opening_erode(
        .clk(clk),.rst_n(rst_n),.data_i(mask0),.meta_i(meta[1]),.window_o(w1),.meta_o(meta[2]));
    bean_window #(.META_BITS(M),.LINE_TOTAL(LINE_TOTAL)) opening_dilate(
        .clk(clk),.rst_n(rst_n),.data_i(&w1),.meta_i(meta[2]),.window_o(w2),.meta_o(meta[3]));
    bean_window #(.META_BITS(M),.LINE_TOTAL(LINE_TOTAL)) closing_dilate(
        .clk(clk),.rst_n(rst_n),.data_i(|w2),.meta_i(meta[3]),.window_o(w3),.meta_o(meta[4]));
    bean_window #(.META_BITS(M),.LINE_TOTAL(LINE_TOTAL)) closing_erode(
        .clk(clk),.rst_n(rst_n),.data_i(|w3),.meta_i(meta[4]),.window_o(w4),.meta_o(meta[5]));
    bean_window #(.K(5),.META_BITS(M),.LINE_TOTAL(LINE_TOTAL)) inner_boundary(
        .clk(clk),.rst_n(rst_n),.data_i(&w4),.meta_i(meta[5]),.window_o(w5),.meta_o(meta[6]));
    assign {de_o,hs_o,vs_o}=meta[6][2:0];
    bean_raster_coords output_coords(.clk(clk),.rst_n(rst_n),.de_i(de_o),
        .vs_i(vs_o),.x_o(x_o),.y_o(y_o));
    wire edge_pixel=w5[12] && !(&w5);
    wire [23:0] delayed_rgb;
    generate if(INPUT_DENOISED) begin: unpack_565
        assign delayed_rgb={meta[6][18:14],3'b0,meta[6][13:8],2'b0,meta[6][7:3],3'b0};
    end else begin: unpack_888
        assign delayed_rgb=meta[6][26:3];
    end endgenerate
    reg vs_delayed;
    reg [1:0] display_view;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin vs_delayed<=1;display_view<=2;end
        else begin
            vs_delayed<=vs_o;
            if(vs_delayed && !vs_o) display_view<=config_i[`BC_VIEW];
        end
    end
    assign rgb_o=!de_o ? 24'b0 : (edge_pixel && (!RUNTIME_ENABLE || display_view==2)) ? 24'hff0000 : delayed_rgb;
endmodule
