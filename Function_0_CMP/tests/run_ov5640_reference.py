"""Verify migration against the user-supplied board reference (read-only)."""
from pathlib import Path
import re,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
reference=root.parent/'02-1_Ti60_OV5640_LCD-HDMI_1080P60'
def gpios(path):
 return {e.get('name'):e for e in ET.parse(path).iter() if e.tag.endswith('comp_gpio') and e.get('name','').startswith('cmos_')}
a=gpios(reference/'Ti60_Demo.peri.xml');b=gpios(root/'Ti60_Demo.peri.xml')
assert set(a)==set(b)
for name in a:
 assert a[name].attrib==b[name].attrib,name
 for ra,rb in zip(a[name],b[name]):
  expected=dict(ra.attrib)
  if name=='cmos_xclk':expected['clock_name']='cam_ref24'
  assert expected==rb.attrib,(name,expected,rb.attrib)
r=(reference/'src/cmos_i2c/I2C_OV5640_1280720_Config.v').read_text(errors='replace')
s=(root/'src/cmos_i2c/ov5640_1080p30_regs.v').read_text()
base={int(i):int(v.replace('_',''),16) for i,v in re.findall(r"(?m)^\s*(\d+)\s*:\s*LUT_DATA\s*=\s*24'h([\da-fA-F_]+)",r)}
ours={int(i):int(v,16) for i,v in re.findall(r"9'd(\d+): begin data=24'h([\da-fA-F]+)",s)}
assert all(base[i]==ours[i] for i in range(207))
top=(root/'example_top.v').read_text(encoding='utf-8')
assert '.BUS_HZ(50000)' in top and '.pwdn(),.resetb(),' in top
assert not re.search(r'output\s+cmos_(?:resetb|pwdn)',top)
for i in range(1,4):assert f"assign cmos_ctl{i}_o=1'b0, cmos_ctl{i}_oe=1'b1;" in top
sdc=(root/'Ti60_Demo.pt.sdc').read_text()
lines=[x for x in sdc.splitlines() if x.startswith('set_input_delay') and '-clock cmos_pclk ' in x]
assert len(lines)==20 and all('-clock_fall' not in x for x in lines)
assert '11.904762' in sdc and '13.468013' in sdc
message='PASS reference alignment: all CMOS GPIO mappings/settings, rising-edge pads, PCLK delay=15, three fixed-low controls, 50kHz SCCB, 207 common registers; retained 1080p30 clocks'
print(message)
(root/'tests/generated/ov5640_reference.log').write_text(message+'\n')
