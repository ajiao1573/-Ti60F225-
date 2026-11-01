"""Independent-view pose residuals, straight lines and native-field fold checks."""
import sys,json,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'tools/vision_deps'),str(ROOT/'tools')]
import cv2
import numpy as np
from lens_geometry import LensProfile


def straightness(points):
    a=points.reshape(6,9,2);errors=[]
    for line in [*a,*a.transpose(1,0,2)]:
        centered=line-line.mean(axis=0)
        _,_,axes=np.linalg.svd(centered,full_matrices=False)
        errors.extend((centered@axes[-1])**2)
    return math.sqrt(float(np.mean(errors)))


def verify(profile_path,folder):
    data=json.loads(profile_path.read_text());native=LensProfile(data);p=native.scaled(320,180)
    k=np.array(p.k,np.float64);d=np.array(p.d,np.float64)
    obj=np.zeros((54,3),np.float64);obj[:,:2]=np.mgrid[0:9,0:6].T.reshape(-1,2)
    rows=[]
    for path in sorted(folder.glob('*.png')):
        if path.stem.endswith(('_corners','_rectified')):continue
        raw=cv2.imread(str(path),0)
        ok,points=cv2.findChessboardCornersSB(raw,(9,6))
        if not ok:continue
        points=points.astype(np.float64).reshape(-1,1,2)
        if p.model=='fisheye':
            normalized=cv2.fisheye.undistortPoints(points,k,d)
            corrected=cv2.fisheye.undistortPoints(points,k,d,P=k)
            ok,r,t=cv2.solvePnP(obj,normalized,np.eye(3),None)
            predicted,_=cv2.fisheye.projectPoints(obj.reshape(1,-1,3),r,t,k,d)
            mx,my=cv2.fisheye.initUndistortRectifyMap(k,d,np.eye(3),k,(320,180),cv2.CV_32FC1)
        else:
            corrected=cv2.undistortPoints(points,k,d,P=k)
            ok,r,t=cv2.solvePnP(obj,points,k,d)
            predicted,_=cv2.projectPoints(obj,r,t,k,d)
            mx,my=cv2.initUndistortRectifyMap(k,d,None,k,(320,180),cv2.CV_32FC1)
        if not ok:raise ValueError('held-out pose estimation failed')
        rms=float(np.sqrt(np.mean(np.sum((predicted.reshape(-1,2)-points.reshape(-1,2))**2,axis=1))))
        cv2.imwrite(str(path.with_name(path.stem+'_'+p.model+'_rectified.png')),cv2.remap(raw,mx,my,cv2.INTER_LINEAR))
        rows.append(dict(file=str(path),rms_pixels=rms,native_rms_pixels=rms*6,
                         line_error_before=straightness(points),line_error_after=straightness(corrected)))
    if len(rows)<2:raise ValueError('need at least2 independent usable validation views')
    determinants=[]
    for y in range(0,1080,16):
        for x in range(0,1920,16):
            a=native.source(x,y);b=native.source(x+1,y);c=native.source(x,y+1)
            determinants.append((b[0]-a[0])*(c[1]-a[1])-(c[0]-a[0])*(b[1]-a[1]))
    return dict(model=p.model,views=rows,mean_native_rms_pixels=float(np.mean([r['native_rms_pixels'] for r in rows])),
                minimum_sampled_jacobian=min(determinants),no_sampled_folds=min(determinants)>0)


if __name__=='__main__':
    base=ROOT/'docs/calibration'
    reports=[verify(base/f'candidate_{model}.json',base/'holdout') for model in ['pinhole','fisheye']]
    (base/'validation.json').write_text(json.dumps(reports,indent=2)+'\n')
    print(json.dumps(reports,indent=2))
