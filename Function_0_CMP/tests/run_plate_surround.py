from PIL import Image,ImageOps
from plate_reference import sample,run_cases,oracle

cases=[]
for shift in [-6,0,6]:
    scene=Image.new('L',(256,96),30)
    scene.paste(sample('AUY359').resize((210,60)),(18,12+shift))
    for inverse in [False,True]:
        image=ImageOps.invert(scene) if inverse else scene
        # Repeated identical frames exercise static scenes without motion.
        for repeat in range(2):
            cases.append((f'static_{shift}_{inverse}_{repeat}',image,6,128))
if __name__=='__main__':run_cases(cases,'plate_surround')
