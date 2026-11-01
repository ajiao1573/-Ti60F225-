"""Independent centered spatial reference, no RTL line-buffer emulation."""
from pathlib import Path

W,H,L=64,56,80
out=Path(__file__).resolve().parents[1]/'build/sim'
out.mkdir(parents=True,exist_ok=True)

def morph(a,r,erode):
    return [[(all if erode else any)(
        0<=y+dy<H and 0<=x+dx<W and a[y+dy][x+dx]
        for dy in range(-r,r+1) for dx in range(-r,r+1))
        for x in range(W)] for y in range(H)]

red_total=0
with (out/'contour_vectors.txt').open('w') as f:
    for frame in range(4):
        rgb=[[(224+x%16,232+y%12,240) for x in range(W)] for y in range(H)]
        shift=0 if frame==0 else 5
        for y in range(H):
            for x in range(W):
                if (10+shift<=x<30+shift and 12<=y<34) or ((x-46)**2/64+(y-40)**2/81<1):
                    rgb[y][x]=(24,36,12)
        # Isolated dark speckle, one-pixel bright hole, and short edge notch.
        rgb[8][8]=(0,0,0)
        rgb[22][20+shift]=(255,255,255)
        rgb[17][10+shift]=(255,255,255)
        if frame==3:  # empty next frame detects frame-old contour ghosts
            rgb=[[(240,240,240) for x in range(W)] for y in range(H)]
        lum=[[(77*r+150*g+29*b)>>8 for r,g,b in row] for row in rgb]
        weights=(1,2,1)
        mask=[[4<=x<W-4 and 4<=y<H-4 and
               (sum(weights[dy+1]*weights[dx+1]*lum[y+dy][x+dx]
                    for dy in (-1,0,1) for dx in (-1,0,1))+8)//16<112
               if 0<x<W-1 and 0<y<H-1 else False
               for x in range(W)] for y in range(H)]
        clean=morph(morph(morph(morph(mask,1,True),1,False),1,False),1,True)
        inner=morph(clean,2,True)
        edge=[[clean[y][x] and not inner[y][x] for x in range(W)] for y in range(H)]
        # Explicit 2px straight boundary and untouched interior checks.
        if frame==0:
            assert [edge[25][x] for x in range(9,15)]==[False,True,True,False,False,False]
            assert [edge[y][20] for y in range(11,17)]==[False,True,True,False,False,False]
            assert not edge[8][8] and not edge[22][20]
        red_total+=sum(map(sum,edge))
        if frame==0:
            with (out/'contour_preview.ppm').open('wb') as preview:
                preview.write(f'P6\n{W} {H}\n255\n'.encode())
                preview.write(bytes(v for y in range(H) for x in range(W)
                                    for v in ((255,0,0) if edge[y][x] else rgb[y][x])))
        for row in range(H+16):
            for col in range(L):
                de=int(8<=row<H+8 and col<W)
                x,y=(col,row-8) if de else (0,0)
                color=rgb[y][x] if de else (0,0,0)
                expected=(255,0,0) if de and edge[y][x] else color
                f.write('%06x %d %d %d %d %d %06x\n' % (
                    (color[0]<<16)|(color[1]<<8)|color[2],de,int(col>=68),int(row>=2),x,y,
                    (expected[0]<<16)|(expected[1]<<8)|expected[2]))
assert red_total>500
print(f'Contour reference: 4 frames, {red_total} red pixels, 2px straight boundary verified')
