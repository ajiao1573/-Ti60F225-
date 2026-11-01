"""Reuse the independent UART waveform oracle for diagnostic protocol cases."""
from pathlib import Path
import ast,inspect
source=ast.parse(Path('tests/run_host_uart.py').read_text())
nodes=[]
for node in source.body:
    if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='logs' for t in node.targets):break
    nodes.append(node)
ns={"__file__":str(Path('tests/run_host_uart.py').resolve())}
exec(compile(ast.Module(body=nodes,type_ignores=[]),'uart_test','exec'),ns)
fn=next(ast.get_source_segment(Path('tests/run_host_uart.py').read_text(),n) for n in source.body if isinstance(n,ast.FunctionDef) and n.name=='verify')
extra='''
 transaction(40,0x32,[0,0],3)
 send(packet(41,0x31));response(41,0xb1,[0,0,64,1,180,0,0,225]);wait()
 send(packet(42,0x30));response(42,0x80,[0x30,0]);wait()
 stim.append('if(!image_arm)$fatal(1,"capture not armed");')
 transaction(43,0x30,(),3)
 send(packet(44,0x31));response(44,0xb1,[0,1,64,1,180,0,0,225]);wait()
 stim.append('image_ready=1;')
 for offset,seq in [(0,45),(57552,46)]:
  send(packet(seq,0x32,[offset&255,offset>>8]));response(seq,0xb2,[(i*7+11)&255 for i in range(offset,offset+48)]);wait()
 transaction(47,0x32,[209,224],1)
 transaction(48,1)
'''
fn=fn.replace(" stim.append('repeat(40*DIV)",extra+" stim.append('repeat(40*DIV)")
fn=fn.replace("name='host_uart_full' if full else 'host_uart_96mhz'","name='calibration_uart'")
fn=fn.replace('.BAUD(BAUD)) d(','.BAUD(BAUD),.CALIBRATION_ENABLE(1)) d(')
fn=fn.replace(' wire tx,cv;', ' reg image_ready=0;wire image_arm,image_read;wire[15:0]image_address;reg[7:0]image_data=0;always @(posedge clk)if(image_read)image_data<=image_address*7+11;\n wire tx,cv;')
fn=fn.replace('.command_value(value));','.command_value(value),.image_arm(image_arm),.image_read(image_read),.image_address(image_address),.image_ready(image_ready),.image_data(image_data));')
exec(fn,ns);ns['verify'](1000000,100000,False)
