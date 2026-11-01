"""Install the reviewed UART endpoint into the two standalone projects.

This preserves algorithms and pin assignments. Run from any working directory.
Existing production bitstreams are never replaced by this script.
"""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / 'Host'

def replace_once(text, old, new):
    if text.count(old) != 1:
        raise RuntimeError(f'Expected exactly one integration marker: {old[:75]}')
    return text.replace(old, new, 1)

def install():
    uart = (ROOT/'Function_1_CMP/src/host_uart.v').read_text(encoding='utf-8')
    uart = replace_once(uart, 'BAUD=115200,CALIBRATION_ENABLE=0)', 'BAUD=115200,CALIBRATION_ENABLE=0,APP_TASK=0)')
    for code in ('10','11','12','14'):
        uart = replace_once(uart, f"8'h{code}:if(", f"8'h{code}:if(APP_TASK!=0)validation=2;else if(")
    uart = replace_once(uart, 'else if(first_byte!=0) validation=2;', 'else if(first_byte!=APP_TASK) validation=2;')
    uart = replace_once(uart, "8'h30:if(!CALIBRATION_ENABLE)", "8'h20:if(APP_TASK!=1)validation=2;else if(request_length!=1 || first_byte>1)validation=1;\n   8'h21:if(APP_TASK!=3)validation=2;else if(request_length!=0)validation=1;else if(status_payload[2*8+:8]==2)validation=3;\n   8'h22:if(APP_TASK!=3)validation=2;else if(request_length!=0)validation=1;\n   8'h30:if(!CALIBRATION_ENABLE)")
    (HOST/'rtl/host_uart.v').write_text(uart, encoding='utf-8')
    for name in ('Function_2_CMP','Function_3'):
        dest = ROOT/name/'src/host'
        dest.mkdir(exist_ok=True)
        for filename in ('host_uart.v','host_result_bridge.v','host_measurement_uart.v'):
            shutil.copyfile(HOST/'rtl'/filename, dest/filename)
        bridge=(dest/'host_result_bridge.v').read_text(encoding='utf-8').replace('host_uart #(', 'host_measurement_uart #(')
        (dest/'host_result_bridge.v').write_text(bridge,encoding='utf-8')
        top = ROOT/name/'example_top.v'
        text = top.read_text(encoding='utf-8')
        if 'HOST_WEB_RESULT_ENDPOINT' in text:
            print(f'{name}: endpoint already installed')
            continue
        text = '`include "src/host/host_uart.v"\n`include "src/host/host_result_bridge.v"\n' + text
        text='`include "src/host/host_measurement_uart.v"\n'+text
        endpoint = (HOST/'rtl'/('bean_endpoint.vh' if name=='Function_2_CMP' else 'part_endpoint.vh')).read_text(encoding='utf-8')
        text = replace_once(text, 'endmodule', endpoint + '\nendmodule')
        if name=='Function_2_CMP':
            text = replace_once(text, 'if(key1_set) freeze_request<=1;', "if(web_app_valid && web_app_code==8'h20)freeze_request<=web_app_value[0];\n            else if(key1_set) freeze_request<=1;")
            text = replace_once(text, '.overflow_o(bean_overflow), .busy_o(bean_busy)', '.overflow_o(bean_overflow), .busy_o(bean_busy),\n        .telemetry_config_o(web_config),.telemetry_boxes_o(web_boxes),.telemetry_id_o(web_result_id)')
        else:
            text = replace_once(text, 'if (ml_selftest_clear || !ml_active)', 'if (web_clear || !ml_active)')
            text = replace_once(text, 'if (ml_selftest_start && !scan_busy', 'if (web_sample && !scan_busy')
            text = text.replace('wire ml_feature_cancel = ml_selftest_clear;', 'wire ml_feature_cancel = web_clear || scan_start;')
            text = replace_once(text, '.selftest_clear(ml_selftest_clear)', '.selftest_clear(web_clear || scan_start)')
        top.write_text(text,encoding='utf-8')
        sdc = ROOT/name/'Ti60_Demo.pt.sdc'
        constraints = sdc.read_text(encoding='utf-8')
        if 'HOST_WEB_UART_INPUT' not in constraints:
            sdc.write_text(constraints+'\n# HOST_WEB_UART_INPUT: asynchronous RX is synchronized inside the endpoint.\nset_false_path -from [get_ports {uart_rx_i}]\n',encoding='utf-8')
        print(f'{name}: installed endpoint')
    bean = ROOT/'Function_2_CMP/src/bean/bean_counter_video.v'
    t = bean.read_text(encoding='utf-8')
    if 'telemetry_config_o' not in t:
        t = replace_once(t,'output [15:0] count_o, output result_valid_o, output overflow_o, output busy_o',
            'output [15:0] count_o, output result_valid_o, output overflow_o, output busy_o,\n    output [`BEAN_CFG_BITS-1:0] telemetry_config_o,output [15:0] telemetry_boxes_o,output reg [31:0] telemetry_id_o')
        t = replace_once(t,'    bean_osd #(', '''    assign telemetry_config_o=active_config;
    assign telemetry_boxes_o=boxes_visible;
    always @(posedge clk or negedge rst_n)
      if(!rst_n)telemetry_id_o<=0;
      else if(done && result_valid_o && !overflow_o)telemetry_id_o<=telemetry_id_o+1'b1;
    bean_osd #(''')
        bean.write_text(t,encoding='utf-8')

if __name__=='__main__': install()
