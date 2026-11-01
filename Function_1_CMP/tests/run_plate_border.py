from PIL import ImageDraw,ImageOps
from plate_reference import sample,oracle,run_cases,M

base=sample('AUY359');second_right=oracle(base)[4][1][1]
cases=[]
for slope in [False,True]:
    im=base.copy();draw=ImageDraw.Draw(im)
    if slope:
        draw.line((M,27,second_right,30),fill=30,width=3)
    else:draw.rectangle((M,29,second_right,31),fill=30)
    for negative in [False,True]:
        image=ImageOps.invert(im) if negative else im
        cases.append((f'border_{slope}_{negative}',image,6,128))
run_cases(cases,'plate_border')
