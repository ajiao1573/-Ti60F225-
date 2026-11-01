"""Create an isolated temporary color-bar project; never edit release HDL."""
from pathlib import Path
import subprocess
import sys
import re
import xml.etree.ElementTree as ET

root=Path(__file__).resolve().parents[1]
subprocess.run([sys.executable,str(root/'sim/prepare_bean_project.py')],check=True,cwd=root)
dest=root/'build/display_diagnostic'
dest.mkdir(parents=True,exist_ok=True)
top=(root/'example_top.v').read_text(encoding='utf-8')
if '--readback' in sys.argv:
    for port,signal in [('i2c_sclk','config_scl'),('i2c_sdat_OUT','config_sda_out'),('i2c_sdat_OE','config_sda_oe')]:
        top=re.sub(r'(\.'+port+r'\s*\(\s*)cmos_\w+',lambda m:m[1]+signal,top,count=1)
    probe='''
    wire config_scl,config_sda_out,config_sda_oe,probe_scl,probe_drive_low;
    wire [15:0] probe_width,probe_height;
    wire [7:0] probe_nacks;
    camera_sccb_readback readback(
        .clk(clk_sys),.rst_n(rstn_sys),.enable(ov5640_i2c_config_done),
        .sda_i(cmos_sdat_IN),.scl_o(probe_scl),.sda_drive_low_o(probe_drive_low),
        .image_width_o(probe_width),.image_height_o(probe_height),.nack_count_o(probe_nacks));
    assign cmos_sclk=ov5640_i2c_config_done ? probe_scl : config_scl;
    assign cmos_sdat_OUT=ov5640_i2c_config_done ? 1'b0 : config_sda_out;
    assign cmos_sdat_OE=ov5640_i2c_config_done ? probe_drive_low : config_sda_oe;
'''
    top=top.replace('\ti2c_timing_ctrl_16bit\n',probe+'\n\ti2c_timing_ctrl_16bit\n',1)
insert='''
    wire diag_vs,diag_en;
    wire [7:0] diag_data;
    wire [15:0] diag_bytes,diag_lines;
    diagnostic_1080p board_diagnostic(
        .clk(clk_sys),.rst_n(rstn_sys),.cam_clk(cmos_pclk),
        .cam_href(cmos_href),.cam_vs(cmos_vsync),
        .frame_vs(diag_vs),.frame_en(diag_en),.frame_data(diag_data),
        .measured_bytes(diag_bytes),.measured_lines(diag_lines));
    reg [27:0] diag_timer=0;
    always @(posedge clk_sys) diag_timer<=diag_timer+1'b1;
    reg [15:0] diag_meta=0,diag_value=0;
    always @(posedge clk_pixel) begin
        diag_meta<=diag_timer[27] ? diag_lines : diag_bytes;
        diag_value<=diag_meta;
    end
'''
if '--readback' in sys.argv:
    insert=insert.replace('[27:0] diag_timer','[28:0] diag_timer')
    insert=insert.replace('diag_timer[27] ? diag_lines : diag_bytes',
        "diag_timer[28:27]==0 ? diag_bytes : diag_timer[28:27]==1 ? diag_lines : diag_timer[28:27]==2 ? probe_width : (probe_nacks==0 ? probe_height : 16'd9000+probe_nacks)")
if '--camera' in sys.argv:
    top=top.replace('\twire\t\t\tcmos_frame_vsync = r_XYCrop_frame_vsync;',insert+'\n\twire cmos_frame_vsync = r_XYCrop_frame_vsync;')
else:
    top=top.replace('\twire\t\t\tcmos_frame_vsync = r_XYCrop_frame_vsync;',insert+'\n\twire cmos_frame_vsync = diag_vs;')
    top=top.replace('r_XYCrop_frame_href && r_XYCrop_frame_de','diag_en')
    top=top.replace('cmos_frame_Gray = r_XYCrop_frame_Gray','cmos_frame_Gray = {56\'d0,diag_data}')
    top=top.replace('.wframe_pclk    (w_cmos_pclk','.wframe_pclk    (clk_sys')
top=top.replace(') u_bean_counter (',') u_bean_counter (\n        .diagnostic_value_i(diag_value),')
assert 'board_diagnostic(' in top
(dest/'diagnostic_top.v').write_text(top,encoding='utf-8')
video=(root/'src/bean/bean_counter_video.v').read_text(encoding='utf-8')
video=video.replace('input clk, input rst_n,','input clk, input rst_n, input [15:0] diagnostic_value_i,')
video=video.replace('.count_i(count_o)','.count_i(diagnostic_value_i)')
(dest/'diagnostic_counter_video.v').write_text(video,encoding='utf-8')
tree=ET.parse(root/'build/bean_project/Ti60_Demo.xml')
ns='http://www.efinixinc.com/enf_proj'
ET.register_namespace('efx',ns)
ET.register_namespace('xsi','http://www.w3.org/2001/XMLSchema-instance')
design=tree.find(f'{{{ns}}}design_info')
if '--delay0' in sys.argv:
    peri=ET.parse(root/'Ti60_Demo.peri.xml')
    ET.register_namespace('efxpt','http://www.efinixinc.com/peri_design_db')
    for gpio in peri.iter():
        if gpio.tag.endswith('comp_gpio') and gpio.get('name')=='cmos_pclk':
            for config in gpio:
                if config.tag.endswith('input_config'): config.set('delay','0')
    peri.write(dest/'diagnostic.peri.xml',encoding='utf-8',xml_declaration=True)
    for entry in tree.iter():
        if entry.tag.endswith(('default_peri_file','peri_file')):
            entry.set('name',(dest/'diagnostic.peri.xml').as_posix())
for entry in design.findall(f'{{{ns}}}design_file'):
    name=entry.get('name')
    if name==(root/'example_top.v').as_posix(): entry.set('name',(dest/'diagnostic_top.v').as_posix())
    if name==(root/'src/bean/bean_counter_video.v').as_posix(): entry.set('name',(dest/'diagnostic_counter_video.v').as_posix())
ET.SubElement(design,f'{{{ns}}}design_file',name=(root/'sim/diagnostic_1080p.v').as_posix(),version='default',library='default')
if '--readback' in sys.argv:
    ET.SubElement(design,f'{{{ns}}}design_file',name=(root/'sim/camera_sccb_readback.v').as_posix(),version='default',library='default')
files=list(design.findall(f'{{{ns}}}design_file'))
for entry in files: design.remove(entry)
for i,entry in enumerate(files,1): design.insert(i,entry)
tree.write(dest/'Ti60_Demo.xml',encoding='utf-8',xml_declaration=True)
print('Prepared diagnostic project: FPGA color bars, COUNT alternates camera bytes/line and lines/frame.')
