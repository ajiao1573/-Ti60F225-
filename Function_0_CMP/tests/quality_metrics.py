"""Reproducible synthetic quality check; not a substitute for camera testing."""
from run_canny import reference, OUT
import random, json
w,h=96,64;rng=random.Random(2424);n=w*h
results={name:dict(false_edges=0,flicker_pixels=0,detected_rows=0,previous=None)
         for name in ('old_gaussian_t10','median_gaussian_t10','median_gaussian_t24')}
for frame in range(12):
    # Static vertical object with changing sensor-like noise and sparse hot pixels.
    pixels=[]
    for y in range(h):
        for x in range(w):
            v=(70 if x<w//2 else 170)+rng.randrange(-8,9)
            if rng.random()<0.015:v=rng.choice([0,255])
            pixels.append(v)
    for name,low,median in [('old_gaussian_t10',10,False),('median_gaussian_t10',10,True),('median_gaussian_t24',24,True)]:
        _,_,edge=reference(pixels,w,h,low,median=median,gaussian_passes=2 if name=='median_gaussian_t24' else 1)
        r=results[name]
        for y in range(3,h-3):
            r['detected_rows']+=any(edge[y*w+x] for x in range(w//2-3,w//2+4))
            for x in range(3,w-3):
                if abs(x-w//2)>3:r['false_edges']+=bool(edge[y*w+x])
                if r['previous'] is not None:r['flicker_pixels']+=edge[y*w+x]!=r['previous'][y*w+x]
        r['previous']=edge
for r in results.values():
    del r['previous'];r['coverage']=r['detected_rows']/(12*(h-6))
assert results['median_gaussian_t24']['false_edges'] < results['old_gaussian_t10']['false_edges']*.1
assert results['median_gaussian_t24']['flicker_pixels'] < results['old_gaussian_t10']['flicker_pixels']*.5
assert results['median_gaussian_t24']['coverage']>=.95
(OUT/'noise_quality.json').write_text(json.dumps(results,indent=2))
print(json.dumps(results,indent=2));print('PASS synthetic noise suppression and contour preservation')
