`timescale 1ns/1ps
`include "bean/bean_config.vh"
// Causal 3x3 majority filter. Output coordinates retain the bottom-right
// window position (object masks shift about one analysis pixel down/right).
// The first two rows/columns are zero; ROI clipping also follows filtering.
module binary_filter_3x3 #(
    parameter RUNTIME_ENABLE=0,
    parameter WIDTH = 640,
    parameter ROI_X0 = 32, ROI_Y0 = 24,
    parameter ROI_X1 = 608, ROI_Y1 = 336
)(
    input [`BEAN_CFG_BITS-1:0] config_i,
    input clk, input rst_n,
    input valid_i, input mask_i,
    input [11:0] x_i, input [11:0] y_i,
    output reg valid_o, output reg mask_o,
    output reg [11:0] x_o, output reg [11:0] y_o
);
    wire [11:0] cfg_roi_x0=RUNTIME_ENABLE ? (config_i[`BC_X0]>>1) : ROI_X0;
    wire [11:0] cfg_roi_y0=RUNTIME_ENABLE ? (config_i[`BC_Y0]>>1) : ROI_Y0;
    wire [11:0] cfg_roi_x1=RUNTIME_ENABLE ? (config_i[`BC_X1]>>1) : ROI_X1;
    wire [11:0] cfg_roi_y1=RUNTIME_ENABLE ? (config_i[`BC_Y1]>>1) : ROI_Y1;
    reg row1 [0:WIDTH-1];
    reg row2 [0:WIDTH-1];
    reg q1, q2, mask_d, valid_d;
    reg [11:0] x_d, y_d;
    reg [1:0] top_shift, mid_shift, bot_shift;
    wire top = y_d >= 2 ? q2 : 1'b0;
    wire mid = y_d >= 1 ? q1 : 1'b0;
    wire [1:0] ts = x_d == 0 ? 2'b0 : top_shift;
    wire [1:0] ms = x_d == 0 ? 2'b0 : mid_shift;
    wire [1:0] bs = x_d == 0 ? 2'b0 : bot_shift;
    wire [3:0] population = {3'b0,top} + {3'b0,mid} + {3'b0,mask_d} +
                            {3'b0,ts[0]} + {3'b0,ts[1]} +
                            {3'b0,ms[0]} + {3'b0,ms[1]} +
                            {3'b0,bs[0]} + {3'b0,bs[1]};
    // Memories intentionally have no reset, allowing block RAM inference.
    // Row coordinates suppress stale data at every new frame.
    always @(posedge clk) begin
        if (valid_i) begin
            q1 <= row1[x_i]; q2 <= row2[x_i];
            row1[x_i] <= mask_i;
        end
        if (valid_d) row2[x_d] <= q1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_d <= 0; mask_d <= 0; x_d <= 0; y_d <= 0;
            top_shift <= 0; mid_shift <= 0; bot_shift <= 0;
            valid_o <= 0; mask_o <= 0; x_o <= 0; y_o <= 0;
        end else begin
            valid_d <= valid_i;
            if (valid_i) begin mask_d <= mask_i; x_d <= x_i; y_d <= y_i; end
            valid_o <= valid_d;
            if (valid_d) begin
                top_shift <= {ts[0],top}; mid_shift <= {ms[0],mid};
                bot_shift <= {bs[0],mask_d};
                x_o <= x_d; y_o <= y_d;
                mask_o <= x_d >= 2 && y_d >= 2 && population >= 5 &&
                          x_d >= cfg_roi_x0 && x_d < cfg_roi_x1 &&
                          y_d >= cfg_roi_y0 && y_d < cfg_roi_y1;
            end
        end
    end
endmodule
