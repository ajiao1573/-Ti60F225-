"""Dual-clock control/status mailbox regression; no UART or hardware required.

CLOCK_HZ=1e6 accelerates the timeout counter only. Clocks remain asynchronous
(10ns sys, 14ns cam); fixed heartbeat bit16 is exercised without RTL changes.
"""
from pathlib import Path
import os
import subprocess
import json

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
SIM = ROOT / "tools/sim/mingw64/bin"
OUT = ROOT / "tests/generated"
OUT.mkdir(exist_ok=True)

def packed(values):
    return f"{sum(v << (i*8) for i,v in enumerate(values)):096x}"

initial = [0]*48
initial[0],initial[3],initial[4],initial[6] = 1,128,27,128
initial[8:14] = b"??????"
for i,n in [(36,1920),(38,1080),(40,848),(42,477),(46,1)]:
    initial[i:i+2] = [n&255,n>>8]
initial[45] = 1
status = initial.copy()
status[2],status[3],status[4],status[5],status[6],status[7] = 5,231,0xff,3,133,6
status[8:14] = b"ABC123"
for i,n in [(16,123),(18,67),(20,321),(22,111),(24,30),(26,29),(28,1),(30,0x1234)]:
    status[i:i+2] = [n&255,n>>8]
status[32:36] = [0x78,0x56,0x34,0x12]
status[44] = 99
second = status.copy()
second[8:14] = b"AB1234"
second[16:18] = [0x21,0x03]
second[32:36] = [0xef,0xcd,0xab,0x89]

tb = r'''`timescale 1ns/1ps
module tb;
 reg sys_clk=0,cam_clk=0,cam_running=1;
 always #5 sys_clk=~sys_clk;
 always #7 if(cam_running) cam_clk=~cam_clk;
 reg sys_rst=0,cam_rst=0,boundary=0,cv=0;
 reg [7:0] code=0;reg [15:0] value=0;
 reg [383:0] camera_status=384'h@STATUS@;
 wire ready;wire[383:0] payload;wire[9:0] edge_value;wire run_value,load,rescan;wire[7:0] adjust;
 app_control_bridge #(.CLOCK_HZ(1000000)) d(
  .sys_clk(sys_clk),.sys_rst_n(sys_rst),.cam_clk(cam_clk),.cam_rst_n(cam_rst),.frame_boundary(boundary),
  .command_valid(cv),.command_code(code),.command_value(value),.command_ready(ready),
  .camera_status(camera_status),.status_payload(payload),.edge_threshold(edge_value),.run_enable(run_value),
  .remote_load(load),.remote_adjust(adjust),.remote_rescan(rescan));

 // Independent 384-bit source changes all bytes on every source-clock cycle.
 reg [7:0] tag=0;reg [383:0] tagged_source=0;
 reg snapshot_request=0;wire snapshot_busy,snapshot_valid;wire[383:0] atomic_data;
 status_snapshot #(.WIDTH(384)) atom(
  .source_clk(cam_clk),.source_rst_n(cam_rst),.source_data(tagged_source),
  .target_clk(sys_clk),.target_rst_n(sys_rst),.request(snapshot_request),
  .busy(snapshot_busy),.valid(snapshot_valid),.data(atomic_data));
 always @(negedge cam_clk) if(cam_rst) begin tag=tag+1'b1;tagged_source={48{tag}};end
 reg[383:0] captured=0;integer captures=0,delivered=0,requests=0,bytes_checked=0,j;
 always @(posedge cam_clk) if(cam_rst && atom.request_sync[2]!=atom.ack_toggle) begin
  captured=tagged_source;captures=captures+1;
 end
 always @(posedge sys_clk) begin
  if(sys_rst && snapshot_request && !snapshot_busy && !atom.waiting) requests=requests+1;
  #1;
  if(sys_rst && snapshot_valid) begin
   if(atomic_data!==captured)$fatal(1,"snapshot not exact source capture: got %h expected %h",atomic_data,captured);
   for(j=0;j<48;j=j+1) begin
    if(atomic_data[j*8+:8]!==atomic_data[0+:8])$fatal(1,"torn snapshot at byte %0d",j);
    bytes_checked=bytes_checked+1;
   end
   delivered=delivered+1;
  end
 end
 integer pulses=0;
 always @(posedge cam_clk) begin
  #1;if(cam_rst && rescan) pulses=pulses+1;
 end
 task command;
  input[7:0] c;input[15:0] v;input[9:0] want_edge;input[7:0] want_adjust;input want_run;
  reg[18:0] old;integer k,pulse_before;
  begin
   wait(ready);old={edge_value,adjust,run_value};pulse_before=pulses;
   @(negedge sys_clk);code=c;value=v;cv=1;
   @(posedge sys_clk);#1;if(ready)$fatal(1,"ready not low after command acceptance %h",c);
   @(negedge sys_clk);cv=0;
   repeat(7) begin @(posedge cam_clk);#1;
    if({edge_value,adjust,run_value}!==old || load || rescan || ready)$fatal(1,"command applied before frame boundary %h",c);
   end
   // Traffic while mailbox is full must not replace the accepted command.
   @(negedge sys_clk);cv=1;code=8'h10;value=999;
   @(negedge sys_clk);cv=0;
   repeat(4) @(negedge cam_clk);
   // Keep the #2 observation point before the first post-commit sys edge.
   while((($time+7)%10)>=3 && (($time+7)%10)<=5) @(negedge cam_clk);
   boundary=1;
   @(posedge cam_clk);#2;
   if(edge_value!==want_edge || adjust!==want_adjust || run_value!==want_run)
    $fatal(1,"applied values command%h edge%0d adj%0d run%0d",c,edge_value,adjust,run_value);
   if(!rescan || load!==(c==8'h11))$fatal(1,"wrong remote pulse command%h",c);
   if(ready)$fatal(1,"ack crossed immediately");
   // The accepted camera ACK must traverse all three system synchronizers.
   for(k=0;k<3;k=k+1) begin
    @(posedge sys_clk);#1;
    if(ready!==(k==2))$fatal(1,"ack latency cycle%0d ready%0d",k,ready);
   end
   @(negedge cam_clk);boundary=0;
   repeat(3) @(negedge cam_clk);
   if(load || rescan || pulses!=pulse_before+1)$fatal(1,"remote pulse repeated or missing command%h",c);
  end
 endtask

 integer k,idle_cycles;reg [383:0] saved;
 initial begin
  repeat(5) @(negedge sys_clk);
  if(edge_value!==27 || adjust!==128 || run_value!==1 || !ready || load || rescan)$fatal(1,"reset defaults");
  if(payload!==384'h@INITIAL@)$fatal(1,"reset status defaults %h",payload);
  sys_rst=1;cam_rst=1;
  command(8'h10,1023,1023,128,1);
  command(8'h11,0,1023,0,1);
  command(8'h11,255,1023,255,1);
  command(8'h12,0,1023,255,1);
  command(8'h13,0,1023,255,1);
  command(8'h14,0,1023,255,0);
  command(8'h14,1,1023,255,1);
  command(8'h10,0,0,255,1);
  $display("PASS 8 commands: frame-boundary commit, busy rejection, three-stage ACK, exact one-cycle pulses");
  // Requests held for several clocks, including busy cycles, cannot tear data.
  for(k=0;k<80;k=k+1) begin
   @(negedge sys_clk);snapshot_request=1;
   repeat(4) @(negedge sys_clk);snapshot_request=0;
   repeat(17) @(negedge sys_clk);
  end
  repeat(10) @(negedge sys_clk);
  if(requests!=80 || captures!=80 || delivered!=80)$fatal(1,"snapshot counts req%0d cap%0d out%0d",requests,captures,delivered);
  $display("PASS 80 atomic 384-bit snapshots, %0d byte comparisons, fast-changing tags",bytes_checked);
  wait(d.camera_alive);wait(payload===camera_status);
  if(payload[8*8+:48]!==48'h333231434241 || payload[4*8+:16]!==1023 || payload[32*8+:32]!==32'h12345678)
   $fatal(1,"protocol little-endian/ASCII status layout");
  $display("PASS heartbeat alive and 48-byte status byte order");

  // Camera clock stops while success is visible: UART-side status must expire.
  @(negedge cam_clk);cam_running=0;idle_cycles=0;
  while(d.camera_alive) begin @(negedge sys_clk);idle_cycles=idle_cycles+1;end
  repeat(2) @(negedge sys_clk);
  if(idle_cycles>125005)$fatal(1,"camera stale status took too long %0d",idle_cycles);
  if(payload[2*8+:8]!==0 || payload[3*8+:8]!==8'h80 || payload[8*8+:48]!==48'h3f3f3f3f3f3f)
   $fatal(1,"camera stop retained success");
  saved=payload;repeat(120000) @(negedge sys_clk);
  if(payload[2*8+:8]!==0 || payload[3*8+5]!==0)$fatal(1,"stopped clock revived stale OCR");
  // A system-side command remains pending; it must not apply without cam SOP.
  @(negedge sys_clk);code=8'h11;value=129;cv=1;
  @(negedge sys_clk);cv=0;repeat(12) @(negedge sys_clk);
  if(ready || adjust!==255)$fatal(1,"stopped camera applied pending command");
  camera_status=384'h@SECOND@;cam_running=1;
  repeat(8) @(negedge cam_clk);
  if(ready || adjust!==255)$fatal(1,"resume bypassed frame boundary");
  boundary=1;@(negedge cam_clk);boundary=0;
  wait(ready);if(adjust!==129)$fatal(1,"pending command not recovered");
  wait(d.camera_alive);wait(payload===camera_status);
  $display("PASS camera stop invalidates success in %0d sys cycles; resume and pending control recover",idle_cycles);

  // Both clock domains share reset in product; also reset while a command is pending.
  @(negedge sys_clk);code=8'h10;value=888;cv=1;
  @(negedge sys_clk);cv=0;sys_rst=0;cam_rst=0;
  repeat(4) @(negedge sys_clk);
  if(!ready || edge_value!==27 || run_value!==1 || adjust!==128 || payload!==384'h@INITIAL@)$fatal(1,"reset recovery defaults");
  sys_rst=1;cam_rst=1;repeat(8) @(negedge cam_clk);
  boundary=1;repeat(3) @(negedge cam_clk);boundary=0;
  if(edge_value!==27 || rescan)$fatal(1,"pre-reset command replayed");
  command(8'h11,128,27,128,1);
  wait(d.camera_alive);wait(payload===camera_status);
  $display("PASS shared reset discards pending command; mailbox and status recover");
  $display("PASS app_control_bridge regression");$finish;
 end
 initial begin #30000000;$fatal(1,"watchdog timeout state ready%0d alive%0d payload%h",ready,d.camera_alive,payload);end
endmodule
'''
tb = tb.replace('@INITIAL@',packed(initial)).replace('@STATUS@',packed(status)).replace('@SECOND@',packed(second))
name = 'app_control_bridge'
source = OUT / (name+'_tb.sv')
source.write_text(tb,encoding='utf-8')
exe=OUT/(name+'.vvp')
env=os.environ.copy();env['PATH']=str(SIM)+os.pathsep+env.get('PATH','')
compile_run=subprocess.run([str(SIM/'iverilog.exe'),'-g2012','-s','tb','-o',str(exe),str(source),'src/app_control_bridge.v'],capture_output=True,text=True,env=env)
log=compile_run.stdout+compile_run.stderr
if compile_run.returncode:
    (OUT/(name+'.log')).write_text(log);raise SystemExit(log)
result=subprocess.run([str(SIM/'vvp.exe'),str(exe)],capture_output=True,text=True,env=env,timeout=90)
log+=result.stdout+result.stderr
(OUT/(name+'.log')).write_text(log,encoding='utf-8')
print(log,end='')
if result.returncode: raise SystemExit(result.returncode)
(OUT/(name+'_metrics.json')).write_text(json.dumps({'result':'PASS','sys_period_ns':10,'cam_period_ns':14,
 'clock_hz_timeout_parameter':1000000,'fixed_heartbeat_bit':16,'applied_commands':10,'pending_command_discarded_by_reset':1,'atomic_snapshots':80,
 'atomic_bytes_checked':3840,'reset_scope':'both domains together; product shared reset',
 'hardware_test':False},indent=2),encoding='utf-8')
