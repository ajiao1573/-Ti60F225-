"""On-site lens calibration. Use the bundled Efinity Python3.11 runtime."""
import argparse,json,sys,time,struct,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'tools/vision_deps'),str(ROOT/'host'),str(ROOT/'host/vendor')]
import cv2
import numpy as np
from lens_geometry import LensProfile,export_grid


def pattern(path):
    square=64; border=64
    image=np.full((7*square+2*border,10*square+2*border),255,np.uint8)
    for y in range(7):
        for x in range(10):
            if (x+y)%2==0:image[border+y*square:border+(y+1)*square,border+x*square:border+(x+1)*square]=0
    path.parent.mkdir(parents=True,exist_ok=True)
    if not cv2.imwrite(str(path),image):raise RuntimeError('cannot write checkerboard')


def capture(path,port,server):
    from protocol import encode,Parser
    from controller import open_serial
    old=None;device=None
    def post(route,body):
        request=urllib.request.Request(server+route,data=json.dumps(body).encode(),headers={'Content-Type':'application/json'})
        return json.load(urllib.request.urlopen(request,timeout=3))
    try:
        old=json.load(urllib.request.urlopen(server+'/api/state',timeout=2))
    except OSError:pass
    if old and old['connected']:
        if old['port']!=port:raise RuntimeError('control service uses a different board port')
        post('/api/disconnect',{})
    try:
        device=open_serial(port);device.reset_input_buffer();parser=Parser();seq=0
        def exchange(cmd,payload=b'',reply=0x80):
            nonlocal seq
            seq=(seq+1)&255;device.write(encode(seq,cmd,payload));deadline=time.monotonic()+2
            while time.monotonic()<deadline:
                for q,c,b in parser.feed(device.read(min(128,device.in_waiting or 1))):
                    if q!=seq:continue
                    if c==0x80 and (len(b)!=2 or b[0]!=cmd or b[1]):raise RuntimeError(f'board rejected capture command {cmd:02x}: {b.hex()}')
                    if c==reply:return b
            raise TimeoutError('capture firmware did not reply; check bitstream/port')
        exchange(0x30)
        for _ in range(30):
            info=exchange(0x31,reply=0xb1)
            if len(info)!=8:raise RuntimeError('invalid capture info')
            ready,requested,w,h,size=struct.unpack('<BBHHH',info)
            if ready:break
            time.sleep(.05)
        else:raise TimeoutError('camera did not finish a calibration frame')
        if (w,h,size)!=(320,180,57600):raise RuntimeError('unexpected diagnostic frame size')
        data=bytearray()
        for offset in range(0,size,48):
            block=exchange(0x32,struct.pack('<H',offset),0xb2)
            if len(block)!=48:raise RuntimeError('short image packet')
            data.extend(block)
        image=np.frombuffer(data,dtype=np.uint8).reshape(h,w)
        path.parent.mkdir(parents=True,exist_ok=True)
        if not cv2.imwrite(str(path),image):raise RuntimeError('cannot save capture')
        ok,corners=cv2.findChessboardCornersSB(image,(9,6))
        preview=cv2.cvtColor(image,cv2.COLOR_GRAY2BGR)
        if ok:cv2.drawChessboardCorners(preview,(9,6),corners,True)
        cv2.imwrite(str(path.with_name(path.stem+'_corners.png')),preview)
        result=dict(file=str(path),size=[w,h],source_size=[1920,1080],source_sample_step=6,checkerboard_found=bool(ok))
        path.with_suffix('.json').write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps(result),flush=True)
    finally:
        if device:device.close()
        if old and old['connected']:post('/api/connect',{'port':port})


def calibrate(directory,output,model):
    objects=[];images=[];used=[];size=None
    obj=np.zeros((54,3),np.float64);obj[:,:2]=np.mgrid[0:9,0:6].T.reshape(-1,2)
    for path in sorted(directory.glob('*.png')):
        if path.stem.endswith(('_corners','_rectified')):continue
        gray=cv2.imread(str(path),cv2.IMREAD_GRAYSCALE)
        if gray is None:continue
        current=(gray.shape[1],gray.shape[0])
        if size is not None and current!=size:raise ValueError('mixed camera image resolutions')
        ok,corners=cv2.findChessboardCornersSB(gray,(9,6))
        if ok:size=current;objects.append(obj.copy());images.append(corners.astype(np.float64));used.append(path)
    if len(used)<10:raise ValueError(f'need at least10 usable varied poses; found {len(used)}')
    if model=='fisheye':
        flags_api=cv2.fisheye if hasattr(cv2.fisheye,'CALIB_RECOMPUTE_EXTRINSIC') else cv2
        rms,k,d,rv,tv=cv2.fisheye.calibrate([a.reshape(1,-1,3) for a in objects],[a.reshape(1,-1,2) for a in images],size,
            np.zeros((3,3)),np.zeros((4,1)),flags=flags_api.CALIB_RECOMPUTE_EXTRINSIC|flags_api.CALIB_CHECK_COND|flags_api.CALIB_FIX_SKEW)
    else:
        rms,k,d,rv,tv=cv2.calibrateCamera([a.astype(np.float32) for a in objects],[a.astype(np.float32) for a in images],size,None,None)
    profile=dict(model=model,image_size=list(size),camera_matrix=k.tolist(),distortion_coefficients=d.ravel().tolist())
    checked=LensProfile(profile)
    if not np.isfinite(rms):raise ValueError('non-finite calibration error')
    native=checked.scaled(1920,1080)
    result=dict(model=model,image_size=[1920,1080],camera_matrix=native.k,distortion_coefficients=native.d,
                calibration_size=list(size),reprojection_rms_pixels=float(rms),native_reprojection_rms_pixels=float(rms)*1920/size[0],
                views=[str(p) for p in used],status='candidate_requires_review_before_hardware_enable')
    output.parent.mkdir(parents=True,exist_ok=True)
    export_grid(native,output.with_suffix('.hex'))
    output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result),flush=True)


def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='mode',required=True)
    q=sub.add_parser('pattern');q.add_argument('output',type=Path)
    q=sub.add_parser('capture');q.add_argument('output',type=Path);q.add_argument('--port',required=True);q.add_argument('--server',default='http://127.0.0.1:8765')
    q=sub.add_parser('calibrate');q.add_argument('directory',type=Path);q.add_argument('output',type=Path);q.add_argument('--model',choices=['pinhole','fisheye'],required=True)
    a=p.parse_args()
    if a.mode=='pattern':pattern(a.output)
    elif a.mode=='capture':capture(a.output,a.port,a.server)
    else:calibrate(a.directory,a.output,a.model)


if __name__=='__main__':main()
