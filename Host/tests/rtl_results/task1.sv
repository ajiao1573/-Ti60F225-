`timescale 1ns/1ps
module tb;
 localparam DIV=10;
 reg clk=0,source_clk=0,rst=0,rx=1,source_enable=1;
 always #5 clk=~clk;always #3 if(source_enable)source_clk=~source_clk;
 wire tx,valid;wire[7:0]code;wire[15:0]value;
 reg[383:0]status=384'h4a433c352e272019120b04fdf6efe8e1dad3ccc5beb7b0a9a29b948d867f78716a635c554e474039322b241d16010801;
 host_result_bridge #(.CLOCK_HZ(1000000),.TASK_ID(1)) dut(
 .sys_clk(clk),.sys_rst_n(rst),.source_clk(source_clk),.source_rst_n(rst),
 .source_status(status),.apply_boundary(1'b1),.app_ready(1'b1),.rx(rx),.tx(tx),.app_valid(valid),.app_code(code),.app_value(value));
 defparam dut.uart.BAUD=100000;
 reg[7:0]gold[0:163];reg[23:0]cmds[0:1];integer received=0,seen=0,i;reg[7:0]b;
 always @(posedge source_clk)if(valid)begin
  if(seen>=2 || {code,value}!==cmds[seen])$fatal(1,"command mismatch %0d code%h value%h",seen,code,value);
  seen=seen+1;
 end
 // Independent serial decoder (not the DUT's UART RX implementation).
 initial forever begin
  @(negedge tx);repeat(DIV+DIV/2)@(negedge clk);
  for(i=0;i<8;i=i+1)begin b[i]=tx;repeat(DIV)@(negedge clk);end
  if(tx!==1)$fatal(1,"stop bit");
  if(received>=164 || b!==gold[received])$fatal(1,"byte mismatch at %0d got%h expected%h",received,b,gold[received]);
  received=received+1;
 end
 task send_byte(input[7:0]d);integer k;begin
  @(negedge clk);rx=0;repeat(DIV)@(negedge clk);
  for(k=0;k<8;k=k+1)begin rx=d[k];repeat(DIV)@(negedge clk);end
  rx=1;repeat(DIV)@(negedge clk);
 end endtask
 initial begin
  $readmemh("C:/Users/aj150/Desktop/FPGA/FUNCTION_LAST/Host/tests/rtl_results/gold1.hex",gold);$readmemh("C:/Users/aj150/Desktop/FPGA/FUNCTION_LAST/Host/tests/rtl_results/commands1.hex",cmds);
  repeat(10)@(negedge clk);rst=1;repeat(150000)@(negedge clk);
  send_byte(8'ha5);
send_byte(8'h5a);
send_byte(8'h01);
send_byte(8'h01);
send_byte(8'h01);
send_byte(8'h00);
send_byte(8'h68);
repeat(9000)@(negedge clk);
send_byte(8'ha5);
send_byte(8'h5a);
send_byte(8'h01);
send_byte(8'h02);
send_byte(8'h20);
send_byte(8'h01);
send_byte(8'h01);
send_byte(8'h1f);
repeat(9000)@(negedge clk);
send_byte(8'ha5);
send_byte(8'h5a);
send_byte(8'h01);
send_byte(8'h03);
send_byte(8'h20);
send_byte(8'h01);
send_byte(8'h02);
send_byte(8'h00);
repeat(9000)@(negedge clk);
send_byte(8'ha5);
send_byte(8'h5a);
send_byte(8'h01);
send_byte(8'h04);
send_byte(8'h21);
send_byte(8'h00);
send_byte(8'h06);
repeat(9000)@(negedge clk);
send_byte(8'ha5);
send_byte(8'h5a);
send_byte(8'h01);
send_byte(8'h05);
send_byte(8'h10);
send_byte(8'h02);
send_byte(8'h1b);
send_byte(8'h00);
send_byte(8'hb5);
repeat(9000)@(negedge clk);
send_byte(8'ha5);
send_byte(8'h5a);
send_byte(8'h01);
send_byte(8'h06);
send_byte(8'h13);
send_byte(8'h01);
send_byte(8'h01);
send_byte(8'h1b);
repeat(9000)@(negedge clk);
send_byte(8'ha5);
send_byte(8'h5a);
send_byte(8'h01);
send_byte(8'h07);
send_byte(8'h13);
send_byte(8'h01);
send_byte(8'h00);
send_byte(8'h0a);
repeat(9000)@(negedge clk);
send_byte(8'ha5);
send_byte(8'h5a);
send_byte(8'h01);
send_byte(8'h08);
send_byte(8'h20);
send_byte(8'h01);
send_byte(8'h01);
send_byte(8'h82);
repeat(9000)@(negedge clk);
source_enable=0;repeat(260000)@(negedge clk);
send_byte(8'ha5);
send_byte(8'h5a);
send_byte(8'h01);
send_byte(8'h09);
send_byte(8'h01);
send_byte(8'h00);
send_byte(8'h39);
repeat(9000)@(negedge clk);
  if(received!=164 || seen!=2)$fatal(1,"missing replies or commands %0d/%0d",received,seen);
  $display("PASS task1: serial CRC/sequence, mode restrictions, cross-clock commands/status, source clock loss invalidation");$finish;
 end
 initial begin repeat(1000000)@(posedge clk);$fatal(1,"timeout");end
endmodule
