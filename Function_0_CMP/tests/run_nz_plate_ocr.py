"""Known-string OCR regression. Photos are calibration checks, not held-out accuracy."""
from pathlib import Path
import json
from PIL import Image
from plate_reference import oracle,sample
from run_canny import simulate,OUT
root=Path('tests/plate_samples')
cases=[]
for record in json.loads((root/'sources.json').read_text(encoding='utf-8')):
    cases.append((record['plate'],Image.open(root/record['test_filename']).convert('L').resize((256,96),Image.Resampling.LANCZOS)))
for word in ['BKT682','ZX1470','CDE234','FGH567','JKL890','MNP123','QRS456','TUV789','WXY012','ZAB345']:
    cases.append((word,sample(word,size=52)))
values=[];expected=[]
for word,image in cases:
    result=oracle(image)
    assert len(result[4])==6,(word,result[4])
    values.extend(int(v>0) for v in result[5][:3840]);expected.append(word)
values.extend([1]*3840)
OUT.joinpath('nz_ocr_glyphs.hex').write_text(''.join(f'{v:x}\n' for v in values))
initial='\n'.join(f'expected[{i}]=48\'h{word.encode().hex()};' for i,word in enumerate(expected))
tb=r'''`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;reg rst=0,gv=0,gb=0,start=0;
 reg [3:0] gc=0;reg [4:0] gx=0,gy=0;wire busy,done,valid;wire [47:0] ascii;
 nz_plate_ocr dut(.clk(clk),.rst_n(rst),.glyph_valid(gv),.glyph_char(gc),.glyph_x(gx),.glyph_y(gy),
 .glyph_bit(gb),.start(start),.busy(busy),.done(done),.valid(valid),.ascii(ascii));
 reg bits[0:BIT_LAST];reg [47:0] expected[0:CASE_LAST];integer f,c,x,y;
 initial begin
  $readmemh("tests/generated/nz_ocr_glyphs.hex",bits);
INITIAL
  repeat(4) @(negedge clk);rst=1;
  for(f=0;f<CASE_COUNT+1;f=f+1) begin
   for(c=0;c<6;c=c+1) for(y=0;y<32;y=y+1) for(x=0;x<20;x=x+1) begin
    @(negedge clk);gv=1;gc=c;gx=x;gy=y;gb=bits[f*3840+c*640+y*20+x];
   end
   @(negedge clk);gv=0;start=1;@(negedge clk);start=0;
   wait(done);#1;
   if(f<CASE_COUNT && (!valid || ascii!==expected[f])) begin
    for(c=0;c<6;c=c+1) $display("char=%0d L=%c/%0d/%0d D=%c/%0d/%0d",c,dut.letters[c*8+:8],dut.letter_error[c*10+:10],dut.letter_margin[c*10+:10],dut.digits[c*8+:8],dut.digit_error[c*10+:10],dut.digit_margin[c*10+:10]);
    $fatal(1,"OCR case=%0d got=%s valid=%0d expected=%s",f,ascii,valid,expected[f]);
   end
   if(f==CASE_COUNT && valid) $fatal(1,"solid garbage accepted");
   $display("OCR case=%0d result=%s valid=%0d",f,ascii,valid);
   @(negedge clk);
  end
  $display("PASS NZ OCR: five photo calibration cases, ten unseen synthetic strings and garbage rejection");$finish;
 end
 initial begin #30000000;$fatal(1,"OCR timeout");end
endmodule
'''
for key,value in {'BIT_LAST':len(values)-1,'CASE_LAST':len(cases)-1,'CASE_COUNT':len(cases),'INITIAL':initial}.items():tb=tb.replace(key,str(value))
simulate('nz_plate_ocr',tb,['src/nz_plate_ocr.v'],timeout=180)