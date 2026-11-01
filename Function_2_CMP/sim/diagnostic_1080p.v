`timescale 1ns/1ps
// Temporary board diagnostic: known RGB565 bytes into the normal DDR path,
// plus the actual camera's last HREF length and completed-frame line count.
module diagnostic_1080p(
    input clk,rst_n,cam_clk,cam_href,cam_vs,
    output frame_vs,output frame_en,output [7:0] frame_data,
    output [15:0] measured_bytes,measured_lines
);
    reg [1:0] phase=0;
    reg [12:0] byte_x=0;
    reg [10:0] line_y=0;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin phase<=0;byte_x<=0;line_y<=0;end
        else begin
            phase<=phase+1'b1;
            if(phase==3) begin
                if(byte_x==4999) begin
                    byte_x<=0;
                    line_y<=line_y==1119 ? 0 : line_y+1'b1;
                end else byte_x<=byte_x+1'b1;
            end
        end
    end
    reg [15:0] pixel;
    always @* begin
        if(byte_x<480) pixel=16'hffff;
        else if(byte_x<960) pixel=16'hffe0;
        else if(byte_x<1440) pixel=16'h07ff;
        else if(byte_x<1920) pixel=16'h07e0;
        else if(byte_x<2400) pixel=16'hf81f;
        else if(byte_x<2880) pixel=16'hf800;
        else if(byte_x<3360) pixel=16'h001f;
        else pixel=16'h0000;
    end
    assign frame_vs=line_y<1080;
    assign frame_en=phase==3 && byte_x<3840 && line_y<1080;
    assign frame_data=byte_x[0] ? pixel[7:0] : pixel[15:8];
    reg href_d=0,vs_d=0;
    reg [15:0] byte_count=0,line_count=0,last_bytes=0,last_lines=0;
    always @(posedge cam_clk or negedge rst_n) begin
        if(!rst_n) begin
            href_d<=0;vs_d<=0;byte_count<=0;line_count<=0;
            last_bytes<=0;last_lines<=0;
        end else begin
            href_d<=cam_href;vs_d<=cam_vs;
            if(cam_href) byte_count<=byte_count+1'b1;
            else begin
                byte_count<=0;
                if(href_d) begin last_bytes<=byte_count;line_count<=line_count+1'b1;end
            end
            if(cam_vs&&!vs_d) begin last_lines<=line_count;line_count<=0;end
        end
    end
    // Frame-level diagnostics only; these values remain stable between frames.
    (* async_reg="true" *) reg [15:0] bytes_meta=0,bytes_sync=0,lines_meta=0,lines_sync=0;
    always @(posedge clk) begin
        bytes_meta<=last_bytes;bytes_sync<=bytes_meta;
        lines_meta<=last_lines;lines_sync<=lines_meta;
    end
    assign measured_bytes=bytes_sync;
    assign measured_lines=lines_sync;
endmodule
