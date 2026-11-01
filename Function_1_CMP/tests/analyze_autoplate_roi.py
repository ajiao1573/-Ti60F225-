"""Read-only diagnostic of a dumped normalized ROI; no product threshold edits.

Compares current local mask with a white-surface enclosure candidate, keeping
the existing OCR template scores/limits. PNGs and JSON are diagnostic artifacts.
"""
from pathlib import Path
import json,sys
from PIL import Image,ImageDraw
from plate_reference import clean_mask,segment_mask
from run_canny import OUT,ROOT

def normalized(mask,boxes):
 result=[]
 for x0,x1,y0,y1 in boxes:
  bw=x1-x0+1;bh=y1-y0+1
  fw,fh=(20,max(1,bh*20//bw)) if bw*32>bh*20 else (max(1,bw*32//bh),32)
  ox,oy=(20-fw)//2,(32-fh)//2;glyph=[]
  for y in range(32):
   row=0
   for x in range(20):row=(row<<1)|int(ox<=x<ox+fw and oy<=y<oy+fh and mask[(y0+(y-oy)*bh//fh)*256+x0+(x-ox)*bw//fw])
   glyph.append(row)
  result.append(glyph)
 return result

def matches(glyphs):
 rows=[int(s,16) for s in (ROOT/'src/nz_ocr_rows.hex').read_text().split()]
 codes=[int(s,16) for s in (ROOT/'src/nz_ocr_codes.hex').read_text().split()]
 result=[]
 for i,glyph in enumerate(glyphs):
  scores={}
  for j,c in enumerate(codes):scores[c]=min(scores.get(c,9999),sum((a^b).bit_count() for a,b in zip(glyph,rows[j*32:(j+1)*32])))
  letters=sorted((v,c) for c,v in scores.items() if 65<=c<=90);digits=sorted((v,c) for c,v in scores.items() if 48<=c<=57)
  is_digit=i>=3 or i==2 and digits[0][0]<letters[0][0]
  best=digits if is_digit else letters;other=letters if is_digit else digits
  error,code=best[0];margin=best[1][0]-error
  ok=error<=145 and margin>=5 and error<=other[0][0]+24
  if i==2:ok=ok and abs(letters[0][0]-digits[0][0])>=5
  result.append(dict(character=chr(code),error=error,margin=margin,valid=ok))
 return result

def analyze(path):
 p=[int(s,16) for s in path.read_text().split()];assert len(p)==256*96
 hist=[0]*32;mi=[255]*32;ma=[0]*32
 for y in range(4,92):
  for x in range(4,252):
   v=p[y*256+x];t=y//32*8+x//32;mi[t]=min(mi[t],v);ma[t]=max(ma[t],v);hist[v>>3]+=1
 acc=0;lo=hi=None;total=sum(hist)
 for i,n in enumerate(hist):
  acc+=n
  if lo is None and acc>=total//20:lo=i
  if hi is None and acc>=total*19//20:hi=i
 white=((lo<<3)+3*(hi<<3))//4
 left=[min([x for x in range(256) if p[y*256+x]>=white]+[255]) for y in range(96)]
 right=[max([x for x in range(256) if p[y*256+x]>=white]+[0]) for y in range(96)]
 top=[min([y for y in range(96) if p[y*256+x]>=white]+[95]) for x in range(256)]
 bottom=[max([y for y in range(96) if p[y*256+x]>=white]+[0]) for x in range(256)]
 results={}
 for kind in ['adaptive','white_rows','white_both']:
  ink=clean_mask([ma[y//32*8+x//32]-mi[y//32*8+x//32]>=24 and p[y*256+x]<(mi[y//32*8+x//32]+ma[y//32*8+x//32])//2 and
   (kind=='adaptive' or left[y]<x<right[y]) and (kind!='white_both' or top[x]<y<bottom[x]) for y in range(96) for x in range(256)])
  boxes=segment_mask(ink)[1];scores=matches(normalized(ink,boxes))
  results[kind]=dict(boxes=boxes,scores=scores,ascii=''.join(s['character'] for s in scores),valid=len(scores)==6 and all(s['valid'] for s in scores))
  im=Image.frombytes('L',(256,96),bytes(0 if v else 255 for v in ink)).convert('RGB');d=ImageDraw.Draw(im)
  for b in boxes:d.rectangle((b[0],b[2],b[1],b[3]),outline=(255,0,0))
  im.resize((1024,384),Image.Resampling.NEAREST).save(OUT/f'autoplate_{kind}_diagnostic.png')
 report={'source':str(path),'white_threshold':white,'results':results}
 (OUT/'autoplate_roi_diagnostic.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))

if __name__=='__main__':analyze(Path(sys.argv[1]) if len(sys.argv)>1 else OUT/'autoplate_core_small_case1_roi.hex')
