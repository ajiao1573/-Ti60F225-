"""Independent spatial median: sort all nine values, never mimic RTL stages."""
from pathlib import Path
import json
import random
import argparse

parser=argparse.ArgumentParser()
parser.add_argument('--kernel',type=int,choices=(3,5),default=3)
parser.add_argument('--native-width',action='store_true')
args=parser.parse_args()
K=args.kernel
R=K//2
W,H,L,FRAMES=(1920,16,2200,1) if args.native_width else (64,56,80,4)
prefix='native_median5' if args.native_width else ('median5' if K==5 else 'median')
out=Path(__file__).resolve().parents[1]/'build/sim'
out.mkdir(parents=True,exist_ok=True)
rng=random.Random(5640)

def morph(a,r,erode):
    return [[(all if erode else any)(
        0<=y+dy<H and 0<=x+dx<W and a[y+dy][x+dx]
        for dy in range(-r,r+1) for dx in range(-r,r+1))
        for x in range(W)] for y in range(H)]

def packed(c):
    return c[0]<<16|c[1]<<8|c[2]

def contour(image):
    mask=[[4<=x<W-4 and 4<=y<H-4 and
           (77*image[y][x][0]+150*image[y][x][1]+29*image[y][x][2])//256<112
           for x in range(W)] for y in range(H)]
    clean=morph(morph(morph(morph(mask,1,True),1,False),1,False),1,True)
    inner=morph(clean,2,True)
    return [[clean[y][x] and not inner[y][x] for x in range(W)] for y in range(H)]

with (out/f'{prefix}_vectors.txt').open('w') as f,(out/f'{prefix}_smooth_vectors.txt').open('w') as fs:
    for frame in range(FRAMES):
        rgb=[]
        for y in range(H):
            row=[]
            for x in range(W):
                obj=(10+frame*3<=x<30+frame*3 and 12<=y<34) or ((x-46)**2+(y-40)**2<64)
                base=(24,36,16) if obj and frame<2 else (192,208,224)
                if args.native_width:
                    base=(32+((x//17)%24)*8,32+((y//3)%40)*4,32+((x//29)%24)*8)
                if frame==2:
                    color=(rng.randrange(32)*8,rng.randrange(64)*4,rng.randrange(32)*8)
                elif rng.random()<0.07:
                    color=(248,252,248) if rng.getrandbits(1) else (0,0,0)
                else:
                    color=tuple(max(0,min(limit,v+rng.randint(-1,1)*step))
                                for v,step,limit in zip(base,(8,4,8),(248,252,248)))
                row.append(color)
            rgb.append(row)
        filtered=[[tuple(sorted(rgb[y+dy][x+dx][c] for dy in range(-R,R+1)
                                for dx in range(-R,R+1))[K*K//2] for c in range(3))
                   if R<=x<W-R and R<=y<H-R else rgb[y][x]
                   for x in range(W)] for y in range(H)]
        smooth=[[c for c in row] for row in filtered]
        weights=(1,2,1)
        protected=0
        for y in range(1,H-1):
            for x in range(1,W-1):
                neighbors=[filtered[y+dy][x+dx] for dy in (-1,0,1) for dx in (-1,0,1)]
                if all(max(p[c] for p in neighbors)-min(p[c] for p in neighbors)<=48 for c in range(3)):
                    smooth[y][x]=tuple(((sum(weights[dy+1]*weights[dx+1]*(filtered[y+dy][x+dx][c]//step)
                                            for dy in (-1,0,1) for dx in (-1,0,1))+8)//16)*step
                                       for c,step in enumerate((8,4,8)))
                else:
                    protected+=1
        edge=contour(filtered)
        smooth_edge=contour(smooth)
        if frame==3:
            def mse(image):
                crop=R+1
                return sum((image[y][x][c]-(192,208,224)[c])**2
                           for y in range(crop,H-crop) for x in range(crop,W-crop) for c in range(3))/(3*(W-2*crop)*(H-2*crop))
            before,after,final=mse(rgb),mse(filtered),mse(smooth)
            assert final<after<before*0.1 and not any(map(any,smooth_edge))
            metrics={'synthetic_flat_field_mse_before':before,'synthetic_flat_field_mse_after':after,
                     'mse_after_median_and_smooth':final,
                     'reduction_percent':100*(1-final/before),'seed':5640}
            (out/f'{prefix}_metrics.json').write_text(json.dumps(metrics,indent=2))
            print(f'Denoise {K}x{K} reference: synthetic flat-field noise MSE {before:.2f} -> {after:.2f} -> {final:.2f}')
        for row in range(H+16):
            for col in range(L):
                de=int(8<=row<H+8 and col<W)
                x,y=(col,row-8) if de else (0,0)
                original=rgb[y][x] if de else (0,0,0)
                med=filtered[y][x] if de else (0,0,0)
                outline=(255,0,0) if de and edge[y][x] else med
                f.write('%06x %d %d %d %d %d %06x %06x\n' % (
                    packed(original),de,int(col>=W+4),int(row>=2),x,y,packed(med),packed(outline)))
                smooth_color=smooth[y][x] if de else (0,0,0)
                smooth_outline=(255,0,0) if de and smooth_edge[y][x] else smooth_color
                fs.write('%06x %d %d %d %d %d %06x %06x\n' % (
                    packed(original),de,int(col>=W+4),int(row>=2),x,y,packed(smooth_color),packed(smooth_outline)))

# Compact independent patches for the optional full 1920x1080 test. Outside
# these three rectangles, the isolated black impulses must become white.
if K==5 and not args.native_width:
    W=H=96
    red_counts={}
    for size in (40,50):
        source=[[16<=x<16+size and 16<=y<16+size for x in range(W)] for y in range(H)]
        median=[[sum(source[y+dy][x+dx] for dy in range(-2,3) for dx in range(-2,3))>=13
                 if 2<=x<W-2 and 2<=y<H-2 else source[y][x]
                 for x in range(W)] for y in range(H)]
        image=[[(0,0,0) if p else (248,252,248) for p in row] for row in median]
        edge=contour(image)
        red_counts[size]=sum(map(sum,edge))
        (out/f'native_denoise_rect{size}.hex').write_text(''.join(
            f'{packed((255,0,0) if edge[y][x] else image[y][x]):06x}\n'
            for y in range(16,16+size) for x in range(16,16+size)))
    (out/'native_denoise_red_total.txt').write_text(str(2*red_counts[40]+red_counts[50]))
