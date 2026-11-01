`timescale 1ns/1ps
module tb_large_status;
reg [11:0] x0,y0,x1,y1;reg [2:0] state;wire [23:0] po,pn;wire ao,an;integer x,y,k,errors=0;reg [23:0] bg;
ml_status_osd_orig #(.X_START(32),.Y_START(76)) old(.x_pos(x0),.y_pos(y0),.gear6(1'b1),.source(1'b0),.state(state),.disp_class(2'd0),.test_pass(1'b0),.test_done(1'b0),.vec(2'd0),.acc_na(1'b0),.acc_neg(1'b1),.digits(36'h012345678),.frame_bcd(16'h1234),.pixel(po),.active(ao));
ml_status_osd #(.X_START(32),.Y_START(0)) now(.x_pos(x1),.y_pos(y1),.gear6(1'b1),.source(1'b0),.state(state),.disp_class(2'd0),.test_pass(1'b0),.test_done(1'b0),.vec(2'd0),.acc_na(1'b0),.acc_neg(1'b1),.digits(36'h012345678),.frame_bcd(16'h1234),.pixel(pn),.active(an));
initial begin
 for(k=0;k<5;k=k+1) begin state=k;bg=(k==2)?24'h075c22:(k==3)?24'hb20d1a:(k==4)?24'h8a5200:24'h16468a;
 for(y=0;y<96;y=y+1) for(x=0;x<512;x=x+1) begin
 x0=32+x;y0=76+y;x1=32+2*x;y1=2*y;#1;
 if(!ao || !an) errors=errors+1;
 if(y>=48 && y<72) begin if(pn !== ((po==24'h00ff80)?24'hffffff:bg)) errors=errors+1;end
 else if(pn!==po) errors=errors+1;
 end end
 x1=1056;y1=0;#1;if(an) errors=errors+1;
 if(errors==0)$display("TEST:PASS scaled glyphs, frame/ACC and five state colors"); else $display("FAIL errors=%0d",errors);$finish;
end
endmodule
