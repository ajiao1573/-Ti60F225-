`timescale 1ns/1ps
`include "bean/bean_config.vh"
// Two-cycle video pipeline. Coordinates refer to active source pixels.
module bean_preprocess #(
    parameter RUNTIME_ENABLE=0,
    parameter THRESHOLD = 112,
    parameter DARK_OBJECT = 1,
    parameter DEBUG_BINARY = 0,
    parameter ROI_X0 = 64, ROI_Y0 = 48,
    parameter ROI_X1 = 1216, ROI_Y1 = 672
)(
    input [`BEAN_CFG_BITS-1:0] config_i,
    input clk, input rst_n,
    input [23:0] rgb_i,
    input de_i, input hs_i, input vs_i,
    input [11:0] x_i, input [11:0] y_i,
    output reg [23:0] rgb_o,
    output reg de_o, output reg hs_o, output reg vs_o,
    output reg [11:0] x_o, output reg [11:0] y_o,
    output reg sample_valid_o, output reg sample_mask_o,
    output reg [11:0] sample_x_o, output reg [11:0] sample_y_o
);
    wire [11:0] cfg_roi_x0=RUNTIME_ENABLE ? config_i[`BC_X0] : ROI_X0;
    wire [11:0] cfg_roi_y0=RUNTIME_ENABLE ? config_i[`BC_Y0] : ROI_Y0;
    wire [11:0] cfg_roi_x1=RUNTIME_ENABLE ? config_i[`BC_X1] : ROI_X1;
    wire [11:0] cfg_roi_y1=RUNTIME_ENABLE ? config_i[`BC_Y1] : ROI_Y1;
    wire [7:0] cfg_threshold=RUNTIME_ENABLE ? config_i[`BC_THRESHOLD] : THRESHOLD;
    wire [0:0] cfg_dark_object=RUNTIME_ENABLE ? config_i[`BC_DARK] : DARK_OBJECT;
    reg [15:0] luma_sum;
    reg [23:0] rgb_d;
    reg de_d, hs_d, vs_d;
    reg [11:0] x_d, y_d;
    wire in_roi = x_d >= cfg_roi_x0 && x_d < cfg_roi_x1 &&
                  y_d >= cfg_roi_y0 && y_d < cfg_roi_y1;
    wire foreground = in_roi && (cfg_dark_object ?
                      (luma_sum[15:8] < cfg_threshold) :
                      (luma_sum[15:8] > cfg_threshold));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            luma_sum <= 0; rgb_d <= 0;
            de_d <= 0; hs_d <= 1; vs_d <= 1; x_d <= 0; y_d <= 0;
            rgb_o <= 0; de_o <= 0; hs_o <= 1; vs_o <= 1;
            x_o <= 0; y_o <= 0;
            sample_valid_o <= 0; sample_mask_o <= 0;
            sample_x_o <= 0; sample_y_o <= 0;
        end else begin
            // Explicitly widen operands before arithmetic (max sum = 65280).
            luma_sum <= {8'b0,rgb_i[23:16]} * 16'd77 +
                        {8'b0,rgb_i[15:8]} * 16'd150 +
                        {8'b0,rgb_i[7:0]} * 16'd29;
            rgb_d <= rgb_i; de_d <= de_i; hs_d <= hs_i; vs_d <= vs_i;
            x_d <= x_i; y_d <= y_i;
            rgb_o <= de_d ? ((RUNTIME_ENABLE ? config_i[`BC_VIEW]==1 : DEBUG_BINARY) ? {24{foreground}} : rgb_d) : 24'b0;
            de_o <= de_d; hs_o <= hs_d; vs_o <= vs_d;
            x_o <= x_d; y_o <= y_d;
            // Keep one pixel from each 2x2 source block; display stays 720p.
            sample_valid_o <= de_d && !x_d[0] && !y_d[0];
            sample_mask_o <= foreground;
            sample_x_o <= x_d >> 1; sample_y_o <= y_d >> 1;
        end
    end
endmodule
