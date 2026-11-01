// RAW8 DVP input qualification. VSYNC is a HIGH frame-sync pulse (0x4740=0x20).
// Downstream ISP expects HIGH between frame-sync pulses. Never sample a byte pair.
module ov5640_dvp #(parameter WIDTH=1920,HEIGHT=1080,WARMUP_FRAMES=3)(
 input pclk,rst_n,configured,vsync,href,input [7:0] data,
 output reg frame_valid,pixel_valid,output reg [7:0] pixel,
 output reg size_error,output reg [11:0] last_width,last_height
);
reg [1:0] cfg_sync;
reg vs_d,href_d,started;
reg [7:0] warmup;
reg [11:0] x_count,y_count;
reg bad_line;
wire vs_rise=vsync && !vs_d;
always @(posedge pclk or negedge rst_n) begin
 if(!rst_n) begin
  cfg_sync<=0;vs_d<=0;href_d<=0;started<=0;warmup<=0;
  x_count<=0;y_count<=0;bad_line<=0;frame_valid<=0;pixel_valid<=0;
  pixel<=0;size_error<=0;last_width<=0;last_height<=0;
 end else begin
  cfg_sync<={cfg_sync[0],configured};vs_d<=vsync;href_d<=href;
  frame_valid<=0;pixel_valid<=0;pixel<=data;
  if(!cfg_sync[1]) begin started<=0;warmup<=0;x_count<=0;y_count<=0;bad_line<=0;end
  else if(vs_rise) begin
   started<=1;x_count<=0;y_count<=0;bad_line<=0;
   if(started) begin
    last_height<=y_count;
    size_error<=bad_line || y_count!=HEIGHT;
    // Require complete correctly sized frames before opening the ISP gate.
    if(bad_line || y_count!=HEIGHT) warmup<=0;
    else if(warmup<WARMUP_FRAMES) warmup<=warmup+1'b1;
   end
  end else if(started && !vsync) begin
   frame_valid<=warmup>=WARMUP_FRAMES && !size_error;
   pixel_valid<=warmup>=WARMUP_FRAMES && !size_error && href && x_count<WIDTH && y_count<HEIGHT;
   if(href) begin if(x_count!=4095) x_count<=x_count+1'b1;end
   else begin
    x_count<=0;
    if(href_d) begin
     last_width<=x_count;
     if(x_count!=WIDTH) bad_line<=1;
     if(y_count!=4095) y_count<=y_count+1'b1;
    end
   end
  end
 end
end
endmodule
