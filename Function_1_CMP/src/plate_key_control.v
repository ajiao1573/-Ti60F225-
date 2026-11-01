`ifndef PLATE_KEY_CONTROL_V
`define PLATE_KEY_CONTROL_V
// Release-based gestures: short +/- adjusts; both held >=1s rearms.
// Single-key long presses do nothing in this standalone application.
module plate_key_control #(parameter CLOCK_HZ=84000000,DEBOUNCE=840000,REMOTE_ENABLE=0)(
 input clk,rst_n,input [1:0] keys,output reg [7:0] adjust,output reg rescan_toggle,
 input remote_load,input [7:0] remote_adjust,input remote_rescan);
 localparam DW=($clog2(DEBOUNCE+1)<1 ? 1 : $clog2(DEBOUNCE+1));
 localparam HW=$clog2(2*CLOCK_HZ+2);
 reg [1:0] sync0,sync1,stable,candidate,gesture;
 reg [DW-1:0] debounce_count;
 reg [HW-1:0] held;
 reg active;
 wire change=sync1!=stable && sync1==candidate && debounce_count==DEBOUNCE-1;

 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   sync0<=3;sync1<=3;stable<=3;candidate<=3;debounce_count<=0;
   gesture<=0;held<=0;active<=0;adjust<=128;rescan_toggle<=0;
  end else begin
   sync0<=keys;sync1<=sync0;
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
     if(gesture==3) begin
      if(held>=CLOCK_HZ) begin adjust<=128;rescan_toggle<=!rescan_toggle;end
     end else if(held<CLOCK_HZ/2) begin
      adjust<=gesture==2 ? (adjust>250 ? 255 : adjust+8'd5) : (adjust<5 ? 0 : adjust-8'd5);
     end
    end
   end
   if(REMOTE_ENABLE && remote_load) adjust<=remote_adjust;
   if(REMOTE_ENABLE && remote_rescan) rescan_toggle<=!rescan_toggle;
  end
 end
endmodule
`endif
