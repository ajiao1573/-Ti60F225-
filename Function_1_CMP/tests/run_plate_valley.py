from PIL import ImageDraw,ImageOps
from plate_reference import sample,oracle,run_cases

cases=[]
for text,pair in [('AUY359',4),('OI7105',0),('FAR441',0)]:
    im=sample(text);boxes=oracle(im)[4]
    assert len(boxes)==6,(text,boxes)
    a,b=boxes[pair:pair+2]
    y=(max(a[2],b[2])+min(a[3],b[3]))//2
    ImageDraw.Draw(im).rectangle((a[1]-1,y,b[0]+1,y+3),fill=30)
    for inverse in [False,True]:
        cases.append((f'weak_bridge_{text}_{inverse}',ImageOps.invert(im) if inverse else im,6,128))
for text in ['WMN108','I1O0U8']:
    cases.append((f'no_false_split_{text}',sample(text),6,128))
run_cases(cases,'plate_valley')
