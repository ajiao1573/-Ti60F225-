`timescale 1ns/1ps
// Accepted CCA roots only. Collect while frozen, hide partial/failed results,
// and reveal at a video boundary after OSD has published the matching count.
module bean_objects #(
    parameter MAX_OBJECTS=128,IMAGE_WIDTH=1920,IMAGE_HEIGHT=1080
)(input clk,rst_n,input restart_i,frozen_i,done_i,valid_i,display_ready_i,
  input [1:0] view_i,
  input object_valid_i,input [11:0] xmin_i,xmax_i,ymin_i,ymax_i,
  input [23:0] rgb_i,input de_i,hs_i,vs_i,input [11:0] x_i,y_i,
  output reg [23:0] rgb_o,output reg de_o,hs_o,vs_o,output reg [11:0] x_o,y_o,
  output reg limit_o,output reg [15:0] visible_count_o);
    localparam XW=$clog2(IMAGE_WIDTH+1),YW=$clog2(IMAGE_HEIGHT+1);
    reg [XW-1:0] x0[0:MAX_OBJECTS-1],x1[0:MAX_OBJECTS-1];
    reg [YW-1:0] y0[0:MAX_OBJECTS-1],y1[0:MAX_OBJECTS-1];
    reg [15:0] collected;
    reg ready,vs_d;
    wire [12:0] right={xmax_i,1'b0},bottom={ymax_i,1'b0};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin collected<=0;ready<=0;visible_count_o<=0;limit_o<=0;vs_d<=1;end
        else begin
            vs_d<=vs_i;
            if(restart_i || !frozen_i) begin collected<=0;ready<=0;limit_o<=0;end
            else begin
                if(object_valid_i) begin
                    if(collected<MAX_OBJECTS) collected<=collected+1'b1;
                    else limit_o<=1;
                end
                if(done_i) ready<=valid_i;
            end
            if(vs_d && !vs_i) visible_count_o<=!restart_i && frozen_i && ready && valid_i && display_ready_i && view_i==2 ? collected : 0;
        end
    end
    // No reset on rectangle storage. visible_count protects uninitialized data.
    always @(posedge clk) if(!restart_i && frozen_i && object_valid_i && collected<MAX_OBJECTS) begin
        // Compensate the causal majority filter's one analysis-pixel shift.
        x0[collected]<=xmin_i==0?0:(xmin_i-12'd1)<<1;
        y0[collected]<=ymin_i==0?0:(ymin_i-12'd1)<<1;
        x1[collected]<=right>IMAGE_WIDTH?IMAGE_WIDTH:right[11:0];
        y1[collected]<=bottom>IMAGE_HEIGHT?IMAGE_HEIGHT:bottom[11:0];
    end
    function [34:0] digit;
        input integer d;
        begin case(d)
            0:digit={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
            1:digit={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
            2:digit={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
            3:digit={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
            4:digit={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
            5:digit={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
            6:digit={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
            7:digit={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
            8:digit={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
            9:digit={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
            default:digit=0;
        endcase end
    endfunction
    wire [MAX_OBJECTS-1:0] edges,labels;
    genvar n,c;
    generate for(n=0;n<MAX_OBJECTS;n=n+1) begin: box
        wire enabled=n<visible_count_o;
        assign edges[n]=enabled && x_i>=x0[n] && x_i<x1[n] && y_i>=y0[n] && y_i<y1[n] &&
            (x_i<x0[n]+2 || x_i>=x1[n]-2 || y_i<y0[n]+2 || y_i>=y1[n]-2);
        localparam DIGITS=(n+1>=100)?3:(n+1>=10)?2:1;
        wire [11:0] label_y=y0[n]>=16?y0[n]-12'd16:y0[n]+12'd2;
        wire [11:0] dy=y_i-label_y;
        wire [2:0] hit;
        for(c=0;c<3;c=c+1) begin: character
            localparam DIVISOR=(DIGITS-c==3)?100:(DIGITS-c==2)?10:1;
            localparam [34:0] GLYPH=digit(((n+1)/DIVISOR)%10);
            wire [11:0] char_x=x0[n]+c*12;
            wire [11:0] dx=x_i-char_x;
            wire [5:0] bit_index=6'd34-({3'b0,dy[3:1]}*6'd5+{3'b0,dx[3:1]});
            assign hit[c]=(c<DIGITS) && enabled && x_i>=char_x && dx<10 &&
                           y_i>=label_y && dy<14 && GLYPH[bit_index];
        end
        assign labels[n]=|hit;
    end endgenerate
    reg [MAX_OBJECTS-1:0] edges_d,labels_d;
    reg [23:0] rgb_d;
    reg de_d,hs_d,video_vs_d;
    reg [11:0] x_d,y_d;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rgb_o<=0;de_o<=0;hs_o<=1;vs_o<=1;x_o<=0;y_o<=0;
            edges_d<=0;labels_d<=0;rgb_d<=0;de_d<=0;hs_d<=1;video_vs_d<=1;x_d<=0;y_d<=0;
        end else begin
            edges_d<=edges;labels_d<=labels;
            rgb_d<=rgb_i;de_d<=de_i;hs_d<=hs_i;video_vs_d<=vs_i;x_d<=x_i;y_d<=y_i;
            rgb_o<=!de_d?0:(|labels_d)?24'h80ff00:(|edges_d)?24'h00ff00:rgb_d;
            de_o<=de_d;hs_o<=hs_d;vs_o<=video_vs_d;x_o<=x_d;y_o<=y_d;
        end
    end
endmodule
