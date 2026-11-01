"""Decode actual endpoint RTL payloads with the production Python protocol."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'Host'))
from protocol import decode_status
SIM=ROOT/'Function_1_CMP/tools/sim/mingw64/bin';os.environ['PATH']=str(SIM)+os.pathsep+os.environ.get('PATH','')
OUT=ROOT/'Host/tests/rtl_results'
stub='''module host_result_bridge #(parameter CLOCK_HZ=96000000,TASK_ID=1,WIDTH=1920,HEIGHT=1080,PROC_W=960,PROC_H=540)(
input sys_clk,sys_rst_n,source_clk,source_rst_n,input[383:0]source_status,input apply_boundary,app_ready,rx,output tx,app_valid,output[7:0]app_code,output[15:0]app_value);
assign tx=1;assign app_valid=0;assign app_code=0;assign app_value=0;endmodule
'''
part='''`define ML_ACC_W 29
module tb;
reg cmos_pclk=0;always #5 cmos_pclk=~cmos_pclk;
wire clk_sys=cmos_pclk;reg rstn_sys=0,uart_rx_i=1;wire uart_tx_o;
reg ml_selftest_start=0,ml_selftest_clear=0,scan_busy=0,filter_busy=0,num_busy=0,ml_feat_request_ready=1;
reg[2:0]live_state=0;reg scan_start=0,ml_res_valid=0,ml_res_source=0,i2c_config_done=1;
reg[1:0]ml_res_class=0;reg signed[28:0]ml_res_acc=0;reg[11:0]sample_id=0,ml_res_frame_id=0;
reg[3:0]ml_res_reason=0;reg[4:0]num_reason=0,scan_reason=0;
reg[9:0]saved_count=0,scan_count=0;
@ENDPOINT@
task tick;begin @(negedge cmos_pclk);end endtask
task show;begin #1;$display("STATUS %096h",web_source_status);end endtask
initial begin
tick;rstn_sys=1;tick;show;
live_state=1;tick;show;
live_state=0;ml_res_valid=1;ml_res_acc=-5325003;ml_res_frame_id=7;sample_id=7;saved_count=245;scan_count=318;tick;ml_res_valid=0;show;
scan_start=1;sample_id=8;tick;scan_start=0;show;
ml_res_valid=1;ml_res_class=2;ml_res_reason=1;num_reason=9;ml_res_frame_id=8;tick;ml_res_valid=0;show;
ml_selftest_clear=1;tick;ml_selftest_clear=0;show;
$finish;end
endmodule
'''
bean='''`include "bean/bean_config.vh"
module tb;
localparam VIDEO_WIDTH=1920,VIDEO_HEIGHT=1080;
reg clk_pixel=0;always #5 clk_pixel=~clk_pixel;
wire clk_sys=clk_pixel;reg rstn_sys=0,rstn_pixel=0,uart_rx_i=1;wire uart_tx_o;
reg lcd_vs=1,video_ready_pixel=1,video_error_pixel=0,bean_overflow=0,bean_busy=0,frozen_pixel=1,bean_result_valid=1,runtime_menu=0;
reg[15:0]bean_count=0;reg[7:0]ddr_error_status=0;
@ENDPOINT@
assign web_config={12'd240,12'd240,12'd5,12'd5,20'd11250,20'd36,12'd1008,12'd1824,12'd72,12'd96,2'd2,1'b1,8'd112};
assign web_boxes=0;assign web_result_id=19;
initial begin
@(negedge clk_pixel);rstn_sys=1;rstn_pixel=1;repeat(3)@(negedge clk_pixel);
#1;$display("STATUS %096h",web_source_status);
bean_count=129;#1;$display("STATUS %096h",web_source_status);
video_error_pixel=1;#1;$display("STATUS %096h",web_source_status);
$finish;end
endmodule
'''
for kind,tb in [('part',part),('bean',bean)]:
    endpoint=(ROOT/'Host/rtl'/(kind+'_endpoint.vh')).read_text()
    if kind=='bean':
        # Local Icarus requires this reg declaration before its combinational use.
        decl='(* async_reg="true" *) reg [7:0] web_error_meta,web_error_sync;'
        endpoint=decl+'\n'+endpoint.replace(decl,'')
    src=OUT/(kind+'_payload.sv');src.write_text(stub+tb.replace('@ENDPOINT@',endpoint))
    exe=src.with_suffix('.vvp')
    subprocess.run([str(SIM/'iverilog.exe'),'-g2012','-I'+str(ROOT/'Function_2_CMP/src'),'-s','tb','-o',str(exe),str(src)],check=True)
    r=subprocess.run([str(SIM/'vvp.exe'),str(exe)],text=True,capture_output=True,timeout=10);r.check_returncode()
    states=[decode_status(bytes.fromhex(line.split()[1])[::-1]) for line in r.stdout.splitlines() if line.startswith('STATUS ')]
    if kind=='part':
        assert [s['state'] for s in states]==[1,2,3,1,5,1]
        assert states[2]['classification']=='OK' and states[2]['accumulator']==-5325003 and states[2]['result_id']==7
        assert (states[2]['points'],states[2]['scan_points'])==(245,318)
        assert not states[3]['result_valid'] and states[3]['accumulator'] is None
        assert states[4]['classification']=='INVALID' and states[4]['numeric_reason']==9 and states[4]['accumulator'] is None
        assert not states[5]['result_valid']
    else:
        assert states[0]['count']==0 and states[0]['result_id']==19
        assert states[0]['bbox']=={'x':96,'y':72,'width':1728,'height':936}
        assert states[1]['count']==129 and states[2]['count'] is None
    (OUT/(kind+'_payload.log')).write_text('PASS actual '+kind+' endpoint packing and production Python decode\n'+r.stdout)
    print('PASS actual '+kind+' endpoint packing and production Python decode')
