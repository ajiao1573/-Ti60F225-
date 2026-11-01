from pathlib import Path
s=Path('example_top.v').read_text(encoding='utf8');a=s.index(' reg scan_start, num_start, filter_go, live_pending;');b=s.index('\n ml_scan scan(',a)
h='''`timescale 1ns/1ps
module gap_fsm(input cmos_pclk,rstn_sys,ml_selftest_clear,ml_active,ml_selftest_start,scan_busy,num_busy,scan_done,num_done,filter_busy,filter_done,ml_feat_request_ready,input [9:0] scan_count,filter_count,input [4:0] scan_reason,output scan_start_o,num_start_o,filter_go_o,live_pending_o,output [2:0] state_o,output [9:0] saved_o);
'''
Path('tests/gap_fsm_extract.v').write_text(h+s[a:b]+'''\n assign scan_start_o=scan_start;assign num_start_o=num_start;assign filter_go_o=filter_go;assign live_pending_o=live_pending;assign state_o=live_state;assign saved_o=saved_count;endmodule\n''')
