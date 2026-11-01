from pathlib import Path
s=Path('example_top.v').read_text(encoding='utf8');a=s.index(' reg scan_start, num_start, live_pending;');b=s.index('\n ml_scan scan(',a)
header='''`timescale 1ns/1ps
module live_fsm2(input cmos_pclk,rstn_sys,ml_selftest_clear,ml_active,ml_selftest_start,scan_busy,num_busy,scan_done,num_done,ml_feat_request_ready,input [9:0] scan_count,input [4:0] scan_reason,output scan_start_o,num_start_o,live_pending_o,output [2:0] state_o,output [9:0] saved_o,output [11:0] id_o);
'''
Path('tests/fsm_extract2.v').write_text(header+s[a:b]+'''\n assign scan_start_o=scan_start;assign num_start_o=num_start;assign live_pending_o=live_pending;assign state_o=live_state;assign saved_o=saved_count;assign id_o=sample_id;endmodule\n''')
