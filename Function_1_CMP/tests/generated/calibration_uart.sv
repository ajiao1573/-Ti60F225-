`timescale 1ns/1ps
module tb;
 localparam CLOCK_HZ=1000000,BAUD=100000,DIV=(CLOCK_HZ+BAUD/2)/BAUD;
 reg clk=0;always #5 clk=~clk;reg rst=0,rx=1,ready=1;
 reg image_ready=0;wire image_arm,image_read;wire[15:0]image_address;reg[7:0]image_data=0;always @(posedge clk)if(image_read)image_data<=image_address*7+11;
 wire tx,cv;wire[7:0] code;wire[15:0] value;reg[383:0] status=384'h4c453e373029221b140d06fff8f1eae3dcd5cec7c0b9b2aba49d968f88817a736c655e575049423b342d261f18110a03;
 host_uart #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD),.CALIBRATION_ENABLE(1)) d(.clk(clk),.rst_n(rst),.rx(rx),.tx(tx),.status_payload(status),.command_ready(ready),.command_valid(cv),.command_code(code),.command_value(value),.image_arm(image_arm),.image_read(image_read),.image_address(image_address),.image_ready(image_ready),.image_data(image_data));
 reg[7:0] golden[0:295-1];reg[23:0] goldcommands[0:1-1];
 integer received=0,seen=0,k;reg[7:0] got;
 always @(posedge clk) if(rst && cv) begin
  if(seen>=1 || {code,value}!==goldcommands[seen])$fatal(1,"command%0d code%h value%h want%h",seen,code,value,goldcommands[seen]);
  seen=seen+1;
 end
 // Independent serial waveform decoder, deliberately not host_uart_rx.
 initial forever begin
  @(negedge tx);repeat(DIV+DIV/2) @(posedge clk);
  for(k=0;k<8;k=k+1)begin got[k]=tx;repeat(DIV) @(posedge clk);end
  if(!tx)$fatal(1,"TX stop bit");
  if(received>=295 || got!==golden[received])$fatal(1,"TX byte%0d got%h want%h",received,got,golden[received]);
  received=received+1;
 end
 task send_byte;
  input[7:0] v;input stop_ok;integer b;
  begin
   rx=0;repeat(DIV) @(negedge clk);
   for(b=0;b<8;b=b+1)begin rx=v[b];repeat(DIV) @(negedge clk);end
   rx=stop_ok;repeat(DIV) @(negedge clk);rx=1;repeat(2) @(negedge clk);
  end
 endtask
 initial begin
  $readmemh("tests/generated/calibration_uart_bytes.hex",golden);$readmemh("tests/generated/calibration_uart_commands.hex",goldcommands);
  repeat(8)@(negedge clk);rst=1;
  rx=0;repeat(DIV/4) @(negedge clk);rx=1;repeat(3*DIV) @(negedge clk);
send_byte(8'h00,1'b1);
send_byte(8'hff,1'b1);
send_byte(8'ha5,1'b1);
send_byte(8'ha5,1'b1);
send_byte(8'h00,1'b1);
ready=1'b1;
send_byte(8'ha5,1'b1);
send_byte(8'h5a,1'b1);
send_byte(8'h01,1'b1);
send_byte(8'h01,1'b1);
send_byte(8'h01,1'b1);
send_byte(8'h00,1'b1);
send_byte(8'h68,1'b1);
status=~status;
wait(received==55);repeat(3*DIV) @(negedge clk);
ready=1'b1;
send_byte(8'ha5,1'b1);
send_byte(8'h5a,1'b1);
send_byte(8'h01,1'b1);
send_byte(8'h02,1'b1);
send_byte(8'h10,1'b1);
send_byte(8'h02,1'b1);
send_byte(8'h1b,1'b1);
send_byte(8'h00,1'b1);
send_byte(8'h9c,1'b1);
wait(received==64);repeat(3*DIV) @(negedge clk);
ready=1'b1;
send_byte(8'ha5,1'b1);
send_byte(8'h5a,1'b1);
send_byte(8'h01,1'b1);
send_byte(8'h28,1'b1);
send_byte(8'h32,1'b1);
send_byte(8'h02,1'b1);
send_byte(8'h00,1'b1);
send_byte(8'h00,1'b1);
send_byte(8'h07,1'b1);
wait(received==73);repeat(3*DIV) @(negedge clk);
send_byte(8'ha5,1'b1);
send_byte(8'h5a,1'b1);
send_byte(8'h01,1'b1);
send_byte(8'h29,1'b1);
send_byte(8'h31,1'b1);
send_byte(8'h00,1'b1);
send_byte(8'h83,1'b1);
wait(received==88);repeat(3*DIV) @(negedge clk);
send_byte(8'ha5,1'b1);
send_byte(8'h5a,1'b1);
send_byte(8'h01,1'b1);
send_byte(8'h2a,1'b1);
send_byte(8'h30,1'b1);
send_byte(8'h00,1'b1);
send_byte(8'h2b,1'b1);
wait(received==97);repeat(3*DIV) @(negedge clk);
if(!image_arm)$fatal(1,"capture not armed");
ready=1'b1;
send_byte(8'ha5,1'b1);
send_byte(8'h5a,1'b1);
send_byte(8'h01,1'b1);
send_byte(8'h2b,1'b1);
send_byte(8'h30,1'b1);
send_byte(8'h00,1'b1);
send_byte(8'h40,1'b1);
wait(received==106);repeat(3*DIV) @(negedge clk);
send_byte(8'ha5,1'b1);
send_byte(8'h5a,1'b1);
send_byte(8'h01,1'b1);
send_byte(8'h2c,1'b1);
send_byte(8'h31,1'b1);
send_byte(8'h00,1'b1);
send_byte(8'h43,1'b1);
wait(received==121);repeat(3*DIV) @(negedge clk);
image_ready=1;
send_byte(8'ha5,1'b1);
send_byte(8'h5a,1'b1);
send_byte(8'h01,1'b1);
send_byte(8'h2d,1'b1);
send_byte(8'h32,1'b1);
send_byte(8'h02,1'b1);
send_byte(8'h00,1'b1);
send_byte(8'h00,1'b1);
send_byte(8'hea,1'b1);
wait(received==176);repeat(3*DIV) @(negedge clk);
send_byte(8'ha5,1'b1);
send_byte(8'h5a,1'b1);
send_byte(8'h01,1'b1);
send_byte(8'h2e,1'b1);
send_byte(8'h32,1'b1);
send_byte(8'h02,1'b1);
send_byte(8'hd0,1'b1);
send_byte(8'he0,1'b1);
send_byte(8'h58,1'b1);
wait(received==231);repeat(3*DIV) @(negedge clk);
ready=1'b1;
send_byte(8'ha5,1'b1);
send_byte(8'h5a,1'b1);
send_byte(8'h01,1'b1);
send_byte(8'h2f,1'b1);
send_byte(8'h32,1'b1);
send_byte(8'h02,1'b1);
send_byte(8'hd1,1'b1);
send_byte(8'he0,1'b1);
send_byte(8'h2f,1'b1);
wait(received==240);repeat(3*DIV) @(negedge clk);
ready=1'b1;
send_byte(8'ha5,1'b1);
send_byte(8'h5a,1'b1);
send_byte(8'h01,1'b1);
send_byte(8'h30,1'b1);
send_byte(8'h01,1'b1);
send_byte(8'h00,1'b1);
send_byte(8'he2,1'b1);
wait(received==295);repeat(3*DIV) @(negedge clk);
repeat(40*DIV) @(negedge clk);
  if(received!=295 || seen!=1)$fatal(1,"missing replies/commands %0d/%0d",received,seen);
  $display("PASS calibration_uart: exact replies/CRC/sequence/status snapshot and commands; framing, parameter/CRC errors, timeout recovery and queue integrity");$finish;
 end
 initial begin repeat(347500)@(posedge clk);$fatal(1,"timeout received%0d seen%0d",received,seen);end
endmodule
