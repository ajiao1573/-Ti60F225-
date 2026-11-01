`ifndef SINGLE_GRAY_VIEW_V
`define SINGLE_GRAY_VIEW_V
// Sequential full-gray FIFO -> two source-row caches -> one HDMI image.
// A frame consumes each source byte exactly once, independently of repeated
// HDMI pixels. Late rows are discarded by source row number, never relabeled.
// The negative-edge synchronous read matches lcd_driver's one-cycle-ahead
// request: its following positive edge samples the prepared RGB value.
module single_gray_view #(
 parameter SOURCE_WIDTH=848,SOURCE_HEIGHT=477,DISPLAY_WIDTH=1920,DISPLAY_HEIGHT=1080,
 parameter BOX_SOURCE_WIDTH=SOURCE_WIDTH,BOX_SOURCE_HEIGHT=SOURCE_HEIGHT
)(
 input clk,rst_n,vsync,lcd_request,input [11:0] x_pos,y_pos,
 input [7:0] stream_data,input stream_available,output stream_request,
 input box_valid,input [10:0] box_x,box_w,input [10:0] box_y,box_h,
 output [23:0] rgb,output reg [9:0] underflow_frame,underflow_total
);
 function integer gcd;
 input integer a,b;integer t;
 begin while(b!=0)begin t=a%b;a=b;b=t;end gcd=a;end
 endfunction
 localparam GX=gcd(SOURCE_WIDTH,DISPLAY_WIDTH),GY=gcd(SOURCE_HEIGHT,DISPLAY_HEIGHT);
 localparam XNUM=SOURCE_WIDTH/GX,XDEN=DISPLAY_WIDTH/GX;
 localparam YNUM=SOURCE_HEIGHT/GY,YDEN=DISPLAY_HEIGHT/GY;
 localparam XW=$clog2(SOURCE_WIDTH+1),YW=$clog2(SOURCE_HEIGHT+1);
 reg [7:0] lines[0:2*SOURCE_WIDTH-1];
 reg [XW-1:0] fill_x;
 reg [YW-1:0] fill_row,display_row;
 reg [1:0] ready;
 reg [YW-1:0] tag0,tag1;
 wire [23:0] scaled_x=x_pos*XNUM,scaled_y=y_pos*YNUM;
 wire [XW-1:0] source_x=scaled_x/XDEN;
 wire [YW-1:0] source_y=scaled_y/YDEN;
 wire [23:0] box_scaled_x=x_pos*BOX_SOURCE_WIDTH,box_scaled_y=y_pos*BOX_SOURCE_HEIGHT;
 wire [10:0] box_source_x=box_scaled_x/DISPLAY_WIDTH;
 wire [10:0] box_source_y=box_scaled_y/DISPLAY_HEIGHT;
 wire visible=vsync && lcd_request && x_pos<DISPLAY_WIDTH && y_pos<DISPLAY_HEIGHT;
 wire [YW-1:0] needed_row=visible ? source_y:display_row;
 wire fill_bank=fill_row[0];
 wire [YW-1:0] fill_tag=fill_bank ? tag1:tag0;
 wire bank_free=!ready[fill_bank] || fill_tag<needed_row;
 assign stream_request=rst_n && vsync && fill_row<SOURCE_HEIGHT && bank_free && stream_available;
 wire [XW:0] write_address=(fill_bank ? SOURCE_WIDTH:0)+fill_x;
 always @(posedge clk) if(stream_request) lines[write_address]<=stream_data;
 reg vsync_d;
 reg source_started;
 reg [9:0] missing;
 reg latched_box;
 reg [10:0] left;
 reg [10:0] top;
 reg [11:0] right;
 reg [10:0] bottom;
 reg [7:0] gray_q;
 reg valid_q,box_q;
 wire [YW-1:0] source_tag=source_y[0] ? tag1:tag0;
 wire source_ready=ready[source_y[0]] && source_tag==source_y;
 wire [XW:0] read_address=(source_y[0] ? SOURCE_WIDTH:0)+source_x;
 always @(negedge clk) if(visible) gray_q<=lines[read_address];
 always @(negedge clk or negedge rst_n) begin
  if(!rst_n)begin valid_q<=0;box_q<=0;end
  else begin
   valid_q<=visible && source_ready;
   box_q<=visible && latched_box && box_source_x>=left && box_source_x<=right &&
    box_source_y>=top && box_source_y<=bottom &&
    (box_source_x==left || box_source_x==right || box_source_y==top || box_source_y==bottom);
  end
 end
 assign rgb=valid_q ? (box_q ? 24'h00ff00:{gray_q,gray_q,gray_q}):24'd0;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   fill_x<=0;fill_row<=0;display_row<=0;ready<=0;tag0<=0;tag1<=0;
   vsync_d<=0;source_started<=0;missing<=0;underflow_frame<=0;underflow_total<=0;
   latched_box<=0;left<=0;top<=0;right<=0;bottom<=0;
  end else begin
   vsync_d<=vsync;
   if(stream_request)source_started<=1;
   if(vsync_d && !vsync)begin underflow_frame<=missing;missing<=0;end
   // Like the controller's display-start guard, camera startup with no
   // completed source frame is not charged as a running-video underflow.
   // Once data starts, missing cache pixels count even while FIFO is empty.
   else if(visible && source_started && !valid_q)begin
    if(missing<999)missing<=missing+1'b1;
    if(underflow_total<999)underflow_total<=underflow_total+1'b1;
   end
   // DDR chooses its display generation during low VSYNC. Latch the box
   // at sync release, after that generation is stable, before active pixels.
   if(!vsync_d && vsync)begin
    latched_box<=box_valid && box_w!=0 && box_h!=0 && box_x<BOX_SOURCE_WIDTH && box_y<BOX_SOURCE_HEIGHT;
    left<=box_x;top<=box_y;
    right<={1'b0,box_x}+{1'b0,box_w}-12'd1;
    bottom<={1'b0,box_y}+{1'b0,box_h}-11'd1;
   end
   if(!vsync)begin fill_x<=0;fill_row<=0;display_row<=0;ready<=0;end
   else begin
    if(visible)display_row<=source_y;
    if(ready[0] && tag0<needed_row)ready[0]<=0;
    if(ready[1] && tag1<needed_row)ready[1]<=0;
    if(stream_request)begin
     if(fill_x==SOURCE_WIDTH-1)begin
      fill_x<=0;fill_row<=fill_row+1'b1;
      if(fill_row>=needed_row)begin
       ready[fill_bank]<=1;
       if(fill_bank)tag1<=fill_row;else tag0<=fill_row;
      end
     end else fill_x<=fill_x+1'b1;
    end
   end
  end
 end
endmodule
`endif
