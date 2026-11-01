`ifndef ML_DEC9_V
`define ML_DEC9_V
// Sign + magnitude of a 29-bit accumulator rendered as 9 packed BCD digits.
// Plain double-dabble: one binary bit per clock, 29 clocks per conversion.
// Used only for the on-screen diagnostic, never in the decision path.
module ml_dec9 (
 input clk,
 input rst_n,
 input start,
 input signed [28:0] value,
 output reg busy,
 output reg done,
 output reg negative,
 output reg [35:0] digits
);
 reg [28:0] bin;
 reg [35:0] bcd;
 reg [4:0] step;
 function [3:0] plus3;
  input [3:0] n;
  begin plus3 = (n > 4'd4) ? (n + 4'd3) : n; end
 endfunction
 wire [35:0] adjusted = {plus3(bcd[35:32]), plus3(bcd[31:28]), plus3(bcd[27:24]),
                         plus3(bcd[23:20]), plus3(bcd[19:16]), plus3(bcd[15:12]),
                         plus3(bcd[11:8]),  plus3(bcd[7:4]),   plus3(bcd[3:0])};
 wire [35:0] shifted = {adjusted[34:0], bin[28]};
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   busy<=1'b0; done<=1'b0; negative<=1'b0; digits<=36'd0; bin<=29'd0; bcd<=36'd0; step<=5'd0;
  end else begin
   done<=1'b0;
   if(start) begin
    busy<=1'b1;
    bin<= value[28] ? (~value + 29'd1) : value;
    bcd<=36'd0;
    step<=5'd0;
    negative<=value[28];
   end else if(busy) begin
    bcd<=shifted;
    bin<={bin[27:0],1'b0};
    if(step==5'd28) begin
     busy<=1'b0;
     done<=1'b1;
     digits<=shifted;
    end else begin
     step<=step+5'd1;
    end
   end
  end
 end
endmodule
`endif
