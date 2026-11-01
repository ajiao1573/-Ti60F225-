`ifndef VIDEO_KEY_CONTROL_V
`define VIDEO_KEY_CONTROL_V
// Release-based gestures. KEY+ = key1, KEY- = key0, active low.
// A chord owns the entire gesture until BOTH keys are released.
module video_key_control #(
 parameter CLOCK_HZ=100000000, DEBOUNCE=1000000,DEFAULT_TEMPORAL=0,
 parameter ENABLE_MEDIAN=1,ENABLE_CANNY=1,ENABLE_COLOR_OVERLAY=1,
 parameter ENABLE_DDR_FRAME=1,ENABLE_2FRAME_COMP=1,FRAME_DEPTH=8,ENABLE_ML_GEAR=1,
 parameter FW=($clog2(FRAME_DEPTH)<1 ? 1 : $clog2(FRAME_DEPTH))
)(input clk,input rst_n,input [1:0] keys,
 output reg [2:0] gear,
 output reg [2:0] algorithm,
 output reg [1:0] display_mode,
 output reg [9:0] threshold,
 output reg freeze_requested,compare_mode,
 output reg [FW-1:0] replay_frame,left_frame,right_frame,
 // gear 6 (ML) gestures: one-clock pulses in this clock domain
 output reg ml_selftest_start,ml_selftest_clear);
 localparam DW=($clog2(DEBOUNCE+1)<1 ? 1 : $clog2(DEBOUNCE+1));
 // Six gears when the ML interface is built, otherwise the original five.
 localparam [2:0] GEAR_MAX = ENABLE_ML_GEAR ? 3'd5 : 3'd4;
 localparam [2:0] ML_GEAR  = 3'd5;
 localparam HW=$clog2(2*CLOCK_HZ+2);
 reg [1:0] sync0,sync1,stable,candidate,gesture;
 reg [DW-1:0] debounce_count;
 reg [HW-1:0] held;
 reg active;
 wire change=sync1!=stable && sync1==candidate && debounce_count==DEBOUNCE-1;
 function supported_algorithm;
  input [2:0] a;
  begin supported_algorithm=a==4 ? (ENABLE_DDR_FRAME && FRAME_DEPTH>=3 && ENABLE_MEDIAN && ENABLE_CANNY) :
   a<4 && (!a[0] || ENABLE_MEDIAN) && (!a[1] || ENABLE_CANNY);end
 endfunction
 function [2:0] next_algorithm;
  input [2:0] a;input plus;
  reg [2:0] n;integer i;reg found;
  begin n=a;found=0;next_algorithm=a;
   for(i=0;i<5;i=i+1) begin
    n=plus ? (n==4 ? 3'd0 : n+3'd1) : (n==0 ? 3'd4 : n-3'd1);
    if(!found && supported_algorithm(n)) begin next_algorithm=n;found=1;end
   end
  end
 endfunction
 function [1:0] next_display;
  input [1:0] a;input plus;
  begin next_display=ENABLE_COLOR_OVERLAY ? (a==0 ? 2'd1 : 2'd0) : 2'd0;end
 endfunction
 reg [2:0] new_gear;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   sync0<=3;sync1<=3;stable<=3;candidate<=3;debounce_count<=0;
   gesture<=0;held<=0;active<=0;gear<=3'd5;
   algorithm<=DEFAULT_TEMPORAL && supported_algorithm(3'd4) ? 3'd4 : ENABLE_CANNY ? (ENABLE_MEDIAN ? 3 : 2) : 0;
   display_mode<=1;threshold<=72;freeze_requested<=0;compare_mode<=0;
   replay_frame<=FRAME_DEPTH-1;left_frame<=0;right_frame<=FRAME_DEPTH-1;
   ml_selftest_start<=0;ml_selftest_clear<=0;
  end else begin
   sync0<=keys;sync1<=sync0;
   ml_selftest_start<=0;ml_selftest_clear<=0;
   if(sync1!=candidate) begin candidate<=sync1;debounce_count<=0;end
   else if(sync1!=stable && !change) debounce_count<=debounce_count+1'b1;
   else debounce_count<=0;
   if(active && stable!=3 && sync1==stable && held<2*CLOCK_HZ+1) held<=held+1'b1;
   if(change) begin
    stable<=sync1;
    if(sync1!=3) begin
     gesture<=gesture | ~sync1;
     if(!active || ((gesture | ~sync1)==3 && gesture!=3)) held<=0;
     active<=1;
    end else if(active) begin
     active<=0;gesture<=0;held<=0;
     // Fixed sixth gear: short KEY+ requests a sample, KEY- cancels/clears.
     // Long presses and chords cannot change the operating mode.
     if (held < CLOCK_HZ/2) begin
      if (gesture==2) ml_selftest_start<=1'b1;
      else if (gesture==1) ml_selftest_clear<=1'b1;
     end

    end
   end
  end
 end
endmodule
`endif
