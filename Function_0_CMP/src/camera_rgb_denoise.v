`ifndef CAMERA_RGB_DENOISE_V
`define CAMERA_RGB_DENOISE_V
`include "src/camera_rgb_smooth.v"
// Same-source preprocessor for grayscale, RGB and all algorithms.
// Existing3x3 smoothing plus a second pass only in locally flat regions.
module camera_rgb_denoise #(parameter WIDTH=960,HEIGHT=720,FLAT_RANGE=24)(
 input clk,rst_n,in_frame,in_valid,input [23:0] in_rgb,
 output out_frame,out_valid,output [23:0] out_rgb
);
 wire f,v;wire [23:0] rgb;
 camera_rgb_smooth #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) first_pass(
  .clk(clk),.rst_n(rst_n),.in_frame(in_frame),.in_valid(in_valid),.in_rgb(in_rgb),
  .out_frame(f),.out_valid(v),.out_rgb(rgb));
 camera_rgb_smooth #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.EDGE_AWARE(1),.FLAT_RANGE(FLAT_RANGE)) flat_pass(
  .clk(clk),.rst_n(rst_n),.in_frame(f),.in_valid(v),.in_rgb(rgb),
  .out_frame(out_frame),.out_valid(out_valid),.out_rgb(out_rgb));
endmodule
`endif
