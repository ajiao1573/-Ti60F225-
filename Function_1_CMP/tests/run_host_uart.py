"""UART_PROTOCOL V1 regression at accelerated and actual96MHz/115200 ratios."""
from pathlib import Path
import os,subprocess
ROOT=Path(__file__).resolve().parents[1];os.chdir(ROOT)
SIM=ROOT/'tools/sim/mingw64/bin';OUT=ROOT/'tests/generated';OUT.mkdir(exist_ok=True)
os.environ['PATH']=str(SIM)+os.pathsep+os.environ.get('PATH','')

def crc(data):
 value=0
 for byte in data:
  value^=byte
  for _ in range(8):value=((value<<1)^7)&255 if value&128 else (value<<1)&255
 return value

def packet(seq,cmd,payload=()):
 body=bytes([1,seq,cmd,len(payload),*payload]);return bytes([0xa5,0x5a])+body+bytes([crc(body)])

def verify(clock,baud,full):
 name='host_uart_full' if full else 'host_uart_96mhz'
 gold=[];commands=[];stim=[];expected=0
 status=[(i*7+3)&255 for i in range(48)]
 def send(data,badstop=False):
  for i,v in enumerate(data):stim.append(f"send_byte(8'h{v:02x},1'b{int(not badstop or i<len(data)-1)});")
 def response(seq,cmd,payload):
  nonlocal expected
  gold.extend(packet(seq,cmd,payload));expected=len(gold)
 def wait():stim.append(f'wait(received=={expected});repeat(3*DIV) @(negedge clk);')
 def transaction(seq,cmd,payload=(),error=0,ready=True,change_status=False):
  stim.append(f'ready=1\'b{int(ready)};')
  send(packet(seq,cmd,payload))
  if cmd==1 and not error:response(seq,0x81,status)
  else:
   response(seq,0x80,[cmd,error])
   if not error:commands.append((cmd,(payload[0] if payload else 0)+(payload[1]<<8 if len(payload)>1 else 0)))
  if change_status:stim.append("status=~status;")
  wait()
 stim.append("rx=0;repeat(DIV/4) @(negedge clk);rx=1;repeat(3*DIV) @(negedge clk);")
 send([0,255,0xa5,0xa5,0])
 transaction(1,1,change_status=True)
 status=[v^255 for v in status]
 transaction(2,0x10,[27,0])
 if full:
  transaction(3,0x10,[0,4],1)
  transaction(4,0x10,[20],1)
  transaction(5,0x11,[0])
  transaction(6,0x11,[255])
  transaction(7,0x12)
  transaction(8,0x13,[1],2)
  transaction(9,0x13,[0])
  transaction(10,0x14,[2],1)
  transaction(11,0x14,[0])
  transaction(12,0x55,[],2)
  transaction(13,0x14,[1],3,False)
  stim.append('ready=1;')
  bad=bytearray(packet(14,0x12));bad[-1]^=1;send(bad)
  stim.append('repeat(20*DIV) @(negedge clk);')
  send(packet(15,0x12),badstop=True)
  stim.append('repeat(10*DIV) @(negedge clk);')
  # Truncated payload cannot consume a later complete frame after idle timeout.
  send(packet(16,0x10,[8,0])[:-2])
  stim.append('repeat(CLOCK_HZ/20+5*DIV) @(negedge clk);')
  transaction(17,0x14,[1])
  # Repeated A5 stays synchronized to the next A5 5A prefix.
  send([0xa5]);transaction(18,1)
  # One full status in flight, one queued ACK; excess commands cannot execute
  # without any response reservation. This checks congestion has no phantom writes.
  send(packet(19,1));response(19,0x81,status)
  send(packet(20,0x10,[255,3]));response(20,0x80,[0x10,0]);commands.append((0x10,1023))
  send(packet(21,0x11,[1]));send(packet(22,0x12))
  wait();transaction(23,1)
 stim.append('repeat(40*DIV) @(negedge clk);')
 for suffix,values in [('bytes',gold),('commands',[(c<<16)|v for c,v in commands])]:
  (OUT/(name+'_'+suffix+'.hex')).write_text(''.join(f'{v:x}\n' for v in values))
 payload=sum(v<<(8*i) for i,v in enumerate([(i*7+3)&255 for i in range(48)]))
 tb='''`timescale 1ns/1ps
module tb;
 localparam CLOCK_HZ=@CLOCK@,BAUD=@BAUD@,DIV=(CLOCK_HZ+BAUD/2)/BAUD;
 reg clk=0;always #5 clk=~clk;reg rst=0,rx=1,ready=1;
 wire tx,cv;wire[7:0] code;wire[15:0] value;reg[383:0] status=384'h@STATUS@;
 host_uart #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) d(.clk(clk),.rst_n(rst),.rx(rx),.tx(tx),.status_payload(status),.command_ready(ready),.command_valid(cv),.command_code(code),.command_value(value));
 reg[7:0] golden[0:@BYTES@-1];reg[23:0] goldcommands[0:@COMMANDS@-1];
 integer received=0,seen=0,k;reg[7:0] got;
 always @(posedge clk) if(rst && cv) begin
  if(seen>=@COMMANDS@ || {code,value}!==goldcommands[seen])$fatal(1,"command%0d code%h value%h want%h",seen,code,value,goldcommands[seen]);
  seen=seen+1;
 end
 // Independent serial waveform decoder, deliberately not host_uart_rx.
 initial forever begin
  @(negedge tx);repeat(DIV+DIV/2) @(posedge clk);
  for(k=0;k<8;k=k+1)begin got[k]=tx;repeat(DIV) @(posedge clk);end
  if(!tx)$fatal(1,"TX stop bit");
  if(received>=@BYTES@ || got!==golden[received])$fatal(1,"TX byte%0d got%h want%h",received,got,golden[received]);
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
  $readmemh("tests/generated/@NAME@_bytes.hex",golden);$readmemh("tests/generated/@NAME@_commands.hex",goldcommands);
  repeat(8)@(negedge clk);rst=1;
  @STIM@
  if(received!=@BYTES@ || seen!=@COMMANDS@)$fatal(1,"missing replies/commands %0d/%0d",received,seen);
  $display("PASS @NAME@: exact replies/CRC/sequence/status snapshot and commands; framing, parameter/CRC errors, timeout recovery and queue integrity");$finish;
 end
 initial begin repeat(@CYCLES@)@(posedge clk);$fatal(1,"timeout received%0d seen%0d",received,seen);end
endmodule
'''
 for key,val in [('CLOCK',clock),('BAUD',baud),('STATUS',f'{payload:x}'),('BYTES',len(gold)),('COMMANDS',len(commands)),('NAME',name),('STIM','\n'.join(stim)),('CYCLES',clock//10+len(gold)*((clock+baud//2)//baud)*50+100000)]:tb=tb.replace('@'+key+'@',str(val))
 src=OUT/(name+'.sv');src.write_text(tb);exe=src.with_suffix('.vvp')
 subprocess.run([str(SIM/'iverilog.exe'),'-g2012','-s','tb','-o',str(exe),str(src),'src/host_uart.v'],check=True)
 r=subprocess.run([str(SIM/'vvp.exe'),str(exe)],text=True,capture_output=True,timeout=120)
 (OUT/(name+'.log')).write_text(r.stdout+r.stderr);print(r.stdout+r.stderr);r.check_returncode()
 return r.stdout

logs=verify(1_000_000,100_000,True)+verify(96_000_000,115_200,False)
(OUT/'host_uart.log').write_text(logs)
