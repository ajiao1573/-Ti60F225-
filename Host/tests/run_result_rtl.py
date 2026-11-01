"""Real serial bits -> UART CRC/identity -> asynchronous command/status mailbox."""
from pathlib import Path
import subprocess,sys,os
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'Host'))
from protocol import encode
OUT=ROOT/'Host/tests/rtl_results';OUT.mkdir(exist_ok=True)
SIM=ROOT/'Function_1_CMP/tools/sim/mingw64/bin'
os.environ['PATH']=str(SIM)+os.pathsep+os.environ.get('PATH','')
for task in (1,3):
    payload=bytes((i*7+task)&255 for i in range(48))
    # Sample command validates the task-specific state field.
    payload=payload[:2]+b'\x01'+payload[3:]
    stim=[];gold=[];commands=[]
    def send(seq,cmd,body=b'',error=None,badcrc=False):
        raw=bytearray(encode(seq,cmd,body))
        if badcrc:raw[-1]^=1
        for b in raw:stim.append(f"send_byte(8'h{b:02x});")
        if not badcrc:
            response=encode(seq,0x81,payload) if cmd==1 else encode(seq,0x80,bytes((cmd,error or 0)))
            gold.extend(response)
        stim.append('repeat(9000)@(negedge clk);')
    send(1,1)
    if task==1:
        send(2,0x20,b'\x01');commands.append((0x20,1))
        send(3,0x20,b'\x02',1)
        send(4,0x21,error=2)
    else:
        send(2,0x21);commands.append((0x21,0))
        send(3,0x22);commands.append((0x22,0))
        send(4,0x20,b'\x01',2)
    send(5,0x10,b'\x1b\x00',2)
    send(6,0x13,bytes([task]));commands.append((0x13,task))
    send(7,0x13,bytes([0]),2)
    send(8,0x22 if task==3 else 0x20,b'' if task==3 else b'\x01',badcrc=True)
    # Stop source clock: endpoint must stay responsive, retain identity and clear result flags.
    stim.append('source_enable=0;repeat(260000)@(negedge clk);')
    dead=bytearray(payload);dead[2]=dead[3]=0
    raw=encode(9,1)
    stim.extend(f"send_byte(8'h{b:02x});" for b in raw)
    gold.extend(encode(9,0x81,dead))
    stim.append('repeat(9000)@(negedge clk);')
    (OUT/f'gold{task}.hex').write_text(''.join(f'{b:02x}\n' for b in gold))
    (OUT/f'commands{task}.hex').write_text(''.join(f'{(c<<16)|v:06x}\n' for c,v in commands))
    tb='''`timescale 1ns/1ps
module tb;
 localparam DIV=10;
 reg clk=0,source_clk=0,rst=0,rx=1,source_enable=1;
 always #5 clk=~clk;always #3 if(source_enable)source_clk=~source_clk;
 wire tx,valid;wire[7:0]code;wire[15:0]value;
 reg[383:0]status=384'h@PAYLOAD@;
 host_result_bridge #(.CLOCK_HZ(1000000),.TASK_ID(@TASK@)) dut(
 .sys_clk(clk),.sys_rst_n(rst),.source_clk(source_clk),.source_rst_n(rst),
 .source_status(status),.apply_boundary(1'b1),.app_ready(1'b1),.rx(rx),.tx(tx),.app_valid(valid),.app_code(code),.app_value(value));
 defparam dut.uart.BAUD=100000;
 reg[7:0]gold[0:@LAST@];reg[23:0]cmds[0:@CLAST@];integer received=0,seen=0,i;reg[7:0]b;
 always @(posedge source_clk)if(valid)begin
  if(seen>=@NC@ || {code,value}!==cmds[seen])$fatal(1,"command mismatch %0d code%h value%h",seen,code,value);
  seen=seen+1;
 end
 // Independent serial decoder (not the DUT's UART RX implementation).
 initial forever begin
  @(negedge tx);repeat(DIV+DIV/2)@(negedge clk);
  for(i=0;i<8;i=i+1)begin b[i]=tx;repeat(DIV)@(negedge clk);end
  if(tx!==1)$fatal(1,"stop bit");
  if(received>=@NB@ || b!==gold[received])$fatal(1,"byte mismatch at %0d got%h expected%h",received,b,gold[received]);
  received=received+1;
 end
 task send_byte(input[7:0]d);integer k;begin
  @(negedge clk);rx=0;repeat(DIV)@(negedge clk);
  for(k=0;k<8;k=k+1)begin rx=d[k];repeat(DIV)@(negedge clk);end
  rx=1;repeat(DIV)@(negedge clk);
 end endtask
 initial begin
  $readmemh("@GOLD@",gold);$readmemh("@COMMANDS@",cmds);
  repeat(10)@(negedge clk);rst=1;repeat(150000)@(negedge clk);
  @STIM@
  if(received!=@NB@ || seen!=@NC@)$fatal(1,"missing replies or commands %0d/%0d",received,seen);
  $display("PASS task@TASK@: serial CRC/sequence, mode restrictions, cross-clock commands/status, source clock loss invalidation");$finish;
 end
 initial begin repeat(1000000)@(posedge clk);$fatal(1,"timeout");end
endmodule
'''
    for key,val in {'PAYLOAD':f'{int.from_bytes(payload,"little"):096x}','TASK':task,'LAST':len(gold)-1,'CLAST':len(commands)-1,'NB':len(gold),'NC':len(commands),'GOLD':(OUT/f'gold{task}.hex').as_posix(),'COMMANDS':(OUT/f'commands{task}.hex').as_posix(),'STIM':'\n'.join(stim)}.items():tb=tb.replace('@'+key+'@',str(val))
    src=OUT/f'task{task}.sv';exe=src.with_suffix('.vvp');src.write_text(tb)
    for compact in (False,True):
        bridge=ROOT/'Host/rtl/host_result_bridge.v'
        if compact:
            bridge=OUT/'compact_bridge.v'
            bridge.write_text((ROOT/'Host/rtl/host_result_bridge.v').read_text().replace('host_uart #(', 'host_measurement_uart #('))
        subprocess.run([str(SIM/'iverilog.exe'),'-g2012','-s','tb','-o',str(exe),str(src),str(ROOT/'Host/rtl/host_uart.v'),str(ROOT/'Host/rtl/host_measurement_uart.v'),str(bridge)],check=True)
        r=subprocess.run([str(SIM/'vvp.exe'),str(exe)],capture_output=True,text=True,timeout=90)
        (OUT/f'task{task}_{"compact" if compact else "full"}.log').write_text(r.stdout+r.stderr);print(('COMPACT ' if compact else 'FULL ')+r.stdout+r.stderr);r.check_returncode()
