`timescale 1ns/1ps
// Recover active coordinates from delayed timing instead of storing 24
// coordinate bits per pixel in every line RAM. Internal VS is active low.
module bean_raster_coords(
    input clk,rst_n,de_i,vs_i,
    output reg [11:0] x_o,y_o
);
    reg de_d,vs_d;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin x_o<=0;y_o<=0;de_d<=0;vs_d<=1;end
        else begin
            de_d<=de_i;vs_d<=vs_i;
            if(vs_d && !vs_i) begin x_o<=0;y_o<=0;end
            else if(de_i) x_o<=x_o+12'd1;
            else begin x_o<=0; if(de_d) y_o<=y_o+12'd1;end
        end
    end
endmodule
