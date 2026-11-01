"""960x720 DVP qualification/crop and candidate mode table consistency."""
from pathlib import Path
import re
s=Path('tests/run_ov5640_video.py').read_text();s=s[:s.index("simulate('hdmi_1080p30'")]
s=s.replace('1920','960').replace('1080','720').replace('1280','960').replace('1919','959')
s=s.replace('ov5640_720p30_regs','ov5640_960x720_60_regs')
s=s.replace('ov5640_dvp dut','ov5640_dvp #(.WIDTH(960),.HEIGHT(720)) dut')
s=s.replace('pattern(ox+320,oy+180)','pattern(ox,oy)').replace("simulate('ov5640_dvp'", "simulate('960_camera'")
exec(compile(s,'960_camera_generated','exec'))
table=Path('src/cmos_i2c/ov5640_960x720_60_regs.v').read_text();regs={int(a,16):int(b,16) for a,b in re.findall(r"data=24'h([0-9a-f]{4})([0-9a-f]{2})",table)}
pair=lambda a:256*regs[a]+regs[a+1]
assert pair(0x3808)==960 and pair(0x380a)==720
assert 84000000==60*pair(0x380c)*pair(0x380e)
assert pair(0x3a02)<=pair(0x380e)-4 and pair(0x3a14)<=pair(0x380e)-4
assert ((pair(0x3804)-pair(0x3800)+1)//2-2*pair(0x3810))==960
assert ((pair(0x3806)-pair(0x3802)+1)//2-2*pair(0x3812))==720
assert regs[0x5001]&0x20==0 and regs[0x501f]==3 and regs[0x4300]==0
print('PASS mode table geometry, RAW/no-scaling, nominal60Hz clock arithmetic and bounded exposure (sensor silicon behavior needs board test)')
