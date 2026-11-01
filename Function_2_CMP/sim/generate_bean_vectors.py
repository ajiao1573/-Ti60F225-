"""Independent flood-fill oracle and deterministic RTL regression inputs."""
from collections import deque
from pathlib import Path
import random

OUT = Path(__file__).resolve().parents[1] / 'build' / 'sim'
OUT.mkdir(parents=True, exist_ok=True)
W, H = 32, 24


def reference(mask, border_guard=0):
    # New provisional labels are needed only where all scanned neighbors are 0.
    provisional = sum(
        bool(mask[y][x]) and not any(
            0 <= xx < W and 0 <= yy < H and mask[yy][xx]
            for xx, yy in ((x-1,y),(x-1,y-1),(x,y-1),(x+1,y-1)))
        for y in range(H) for x in range(W))
    seen, count = set(), 0
    for y in range(H):
        for x in range(W):
            if not mask[y][x] or (x, y) in seen:
                continue
            q = deque([(x, y)])
            seen.add((x, y))
            points = []
            while q:
                px, py = q.popleft()
                points.append((px, py))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        nx, ny = px+dx, py+dy
                        if (0 <= nx < W and 0 <= ny < H and mask[ny][nx]
                                and (nx, ny) not in seen):
                            seen.add((nx, ny)); q.append((nx, ny))
            xs, ys = zip(*points)
            width, height = max(xs)-min(xs)+1, max(ys)-min(ys)+1
            border = (min(xs) <= border_guard or max(xs) >= W-1-border_guard
                      or min(ys) <= border_guard or max(ys) >= H-1-border_guard)
            count += (3 <= len(points) <= 120 and 2 <= width <= 20
                      and 2 <= height <= 20 and not border)
    return count, int(provisional > 31)


def blank():
    return [[0]*W for _ in range(H)]


def rect(m, x0, y0, x1, y1):
    for y in range(y0, y1):
        for x in range(x0, x1):
            m[y][x] = 1


cases = []
cases.append(('empty', blank()))
m = blank(); rect(m, 5, 5, 10, 9); cases.append(('one', m))
m = blank()
for r in ((3,3,7,7),(13,4,18,9),(23,15,28,20)): rect(m, *r)
cases.append(('three', m))
# Two vertical arms receive distinct labels, then join on a later row.
m = blank(); rect(m,5,3,7,10); rect(m,12,3,14,10); rect(m,5,9,14,11)
cases.append(('late_union', m))
# A chain of provisional equivalences must aggregate all areas before filtering.
m = blank()
for x in (3,8,13,18): rect(m,x,3,x+2,7)
rect(m,3,6,20,8); cases.append(('multiple_unions', m))
m = blank()
for i in range(6): m[5+i][5+i] = 1
cases.append(('diagonal_8_connected', m))
m = blank(); rect(m,0,3,4,7); rect(m,8,0,12,4); rect(m,28,10,32,14)
rect(m,8,20,12,24); rect(m,15,10,18,13); cases.append(('border_rejection', m))
m = blank(); m[3][3]=1; rect(m,12,7,16,10); cases.append(('noise', m))
m = blank(); rect(m,3,3,19,19); cases.append(('oversized', m))
m = blank(); rect(m,2,2,24,4); cases.append(('wide_thin', m))
m = blank()
for i in range(31):
    x, y = 1+(i%8)*4, 1+(i//8)*4
    rect(m,x,y,x+2,y+2)
cases.append(('exact_label_capacity', m))
m = blank()
for y in range(2,22,3):
    for x in range(2,31,3): m[y][x]=1
cases.append(('label_overflow', m))
cases.append(('recovery_empty', blank()))
rng = random.Random(5640)
for i in range(50):
    m = blank()
    if i % 3 == 0:
        for y in range(H):
            for x in range(W): m[y][x] = int(rng.random() < 0.18)
    else:
        for _ in range(rng.randrange(1, 14)):
            x, y = rng.randrange(W-5), rng.randrange(H-5)
            rect(m,x,y,x+rng.randrange(1,7),y+rng.randrange(1,6))
    cases.append((f'random_{i}', m))
with (OUT/'cca_vectors.txt').open('w', encoding='ascii') as f:
    f.write(f'{len(cases)}\n')
    for name, m in cases:
        count, error = reference(m)
        f.write(f'{count} {error}\n')
        f.write('\n'.join(' '.join(map(str,row)) for row in m)+'\n')
        print(f'{name}: count={count}, overflow={error}')

# Independent accepted-region bounding rectangles, unordered at the RTL output.
def reference_boxes(mask):
    seen=set();boxes=[]
    for y in range(H):
        for x in range(W):
            if not mask[y][x] or (x,y) in seen: continue
            queue=deque([(x,y)]);seen.add((x,y));points=[]
            while queue:
                px,py=queue.popleft();points.append((px,py))
                for dy in (-1,0,1):
                    for dx in (-1,0,1):
                        qx,qy=px+dx,py+dy
                        if 0<=qx<W and 0<=qy<H and mask[qy][qx] and (qx,qy) not in seen:
                            seen.add((qx,qy));queue.append((qx,qy))
            xs,ys=zip(*points);x0,x1,y0,y1=min(xs),max(xs),min(ys),max(ys)
            if 3<=len(points)<=120 and 2<=x1-x0+1<=20 and 2<=y1-y0+1<=20 and x0>0 and y0>0 and x1<W-1 and y1<H-1:
                boxes.append((x0,x1,y0,y1))
    return boxes
with (OUT/'cca_object_vectors.txt').open('w',encoding='ascii') as f:
    f.write(f'{len(cases)}\n')
    for name,m in cases:
        count,error=reference(m);boxes=reference_boxes(m) if not error else []
        f.write(f'{count} {error} {len(boxes)}\n')
        for box in boxes:f.write(' '.join(map(str,box))+'\n')
        f.write('\n'.join(' '.join(map(str,row)) for row in m)+'\n')

# End-to-end video stimulus: expand each analysis pixel into a 2x2 source block.
m = blank(); rect(m,3,3,9,9); rect(m,18,11,25,18); m[20][4]=1
# A clipped target must stay rejected after the causal filter moves its edge.
rect(m,0,12,4,17)
filtered = blank()
for y in range(2,H):
    for x in range(2,W):
        filtered[y][x] = int(sum(m[yy][xx] for yy in range(y-2,y+1)
                                 for xx in range(x-2,x+1)) >= 5)
with (OUT/'video_vectors.txt').open('w',encoding='ascii') as f:
    f.write(f'{reference(filtered,border_guard=2)[0]}\n')
    for y in range(H*2):
        f.write(' '.join('0' if m[y//2][x//2] else '255' for x in range(W*2))+'\n')
with (OUT/'filtered_expected.txt').open('w',encoding='ascii') as f:
    f.write('\n'.join(str(v) for row in filtered for v in row)+'\n')
