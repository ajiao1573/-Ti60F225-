`ifndef TI60_EDGE_DISPLAY_WIDTH2_V
`define TI60_EDGE_DISPLAY_WIDTH2_V
// Display-only 2x2 dilation. One shift per right-view pixel, including gaps
// between valid pixels; the line head is the pixel directly above this one.
// First-row/first-column masks discard stale state across frames and modes.
module edge_display_width2 #(parameter WIDTH=848)(
 input clk,input rst_n,input valid,
 input [11:0] x,input [11:0] y,input edge_in,
 output edge_out
);
 reg [WIDTH-1:0] previous_line;
 reg previous_pixel,previous_above;
 // No line reset is needed: row zero ignores it and overwrites every bit.
 always @(posedge clk) begin
  if(rst_n && valid) previous_line<={previous_line[WIDTH-2:0],edge_in};
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin previous_pixel<=0;previous_above<=0;end
  else if(valid) begin
   previous_pixel<=edge_in;previous_above<=previous_line[WIDTH-1];
  end
 end
 assign edge_out=valid && (edge_in || (x!=0 && previous_pixel) ||
                 (y!=0 && (previous_line[WIDTH-1] || (x!=0 && previous_above))));
endmodule
`endif
