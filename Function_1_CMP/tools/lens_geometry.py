"""Calibration-driven inverse sampling for the native camera coordinate system.

Pure standard-library reference and Q8 grid exporter. This does not alter the
running FPGA. Profiles must contain measured intrinsics and distortion values.
"""
import argparse
import json
import math
from pathlib import Path


class LensProfile:
    def __init__(self, data):
        self.model = data.get("model")
        count = {"pinhole": 5, "fisheye": 4}.get(self.model)
        if count is None:
            raise ValueError("model must be pinhole or fisheye")
        self.width, self.height = data["image_size"]
        if type(self.width) is not int or type(self.height) is not int or min(self.width, self.height) < 2:
            raise ValueError("invalid calibration image_size")
        self.k = self.matrix(data["camera_matrix"])
        self.output_k = self.matrix(data.get("rectified_camera_matrix", data["camera_matrix"]))
        self.d = data["distortion_coefficients"]
        if len(self.d) != count or not all(type(v) in (int, float) and math.isfinite(v) for v in self.d):
            raise ValueError("wrong/missing distortion coefficients for this model")

    @staticmethod
    def matrix(k):
        if len(k) != 3 or any(len(row) != 3 for row in k):
            raise ValueError("camera_matrix must be 3x3")
        if not all(type(v) in (int, float) and math.isfinite(v) for row in k for v in row):
            raise ValueError("intrinsics must contain finite measured numbers")
        if k[0][0] <= 0 or k[1][1] <= 0 or k[1][0] != 0 or k[2] != [0, 0, 1]:
            raise ValueError("unsupported/invalid intrinsic matrix")
        return k

    def source(self, u, v):
        """Destination rectilinear pixel -> distorted camera pixel (inverse warp)."""
        k = self.output_k
        y = (v - k[1][2]) / k[1][1]
        x = (u - k[0][2] - k[0][1] * y) / k[0][0]
        r2 = x*x + y*y
        if self.model == "pinhole":
            k1, k2, p1, p2, k3 = self.d
            radial = 1 + r2*(k1 + r2*(k2 + r2*k3))
            xd = x*radial + 2*p1*x*y + p2*(r2 + 2*x*x)
            yd = y*radial + p1*(r2 + 2*y*y) + 2*p2*x*y
        else:
            r = math.sqrt(r2)
            theta = math.atan(r)
            t2 = theta*theta
            k1, k2, k3, k4 = self.d
            distorted_theta = theta*(1+t2*(k1+t2*(k2+t2*(k3+t2*k4))))
            scale = distorted_theta/r if r else 1.0
            xd, yd = x*scale, y*scale
        k = self.k
        return k[0][0]*xd + k[0][1]*yd + k[0][2], k[1][1]*yd + k[1][2]

    def scaled(self, width, height):
        """Scale intrinsics only when the image is resized without a crop."""
        if width*self.height != height*self.width:
            raise ValueError("aspect ratio changed; crop/resize needs a new calibrated coordinate transform")
        sx, sy = width/self.width, height/self.height
        def scale(k):
            return [[k[0][0]*sx, k[0][1]*sx, k[0][2]*sx],
                    [0, k[1][1]*sy, k[1][2]*sy], [0, 0, 1]]
        return LensProfile(dict(model=self.model, image_size=[width,height], camera_matrix=scale(self.k),
                                rectified_camera_matrix=scale(self.output_k), distortion_coefficients=self.d))


def rectify_gray(pixels, profile):
    """Bilinear reference sampler; outside the captured field is filled black."""
    w, h = profile.width, profile.height
    if len(pixels) != w*h:
        raise ValueError("raw frame size must match calibration resolution")
    out = bytearray(w*h)
    for v in range(h):
        for u in range(w):
            x, y = profile.source(u, v)
            if not (0 <= x <= w-1 and 0 <= y <= h-1):
                continue
            x0, y0 = int(x), int(y)
            x1, y1 = min(x0+1,w-1), min(y0+1,h-1)
            a, b = x-x0, y-y0
            out[v*w+u] = round((1-b)*((1-a)*pixels[y0*w+x0]+a*pixels[y0*w+x1]) +
                               b*((1-a)*pixels[y1*w+x0]+a*pixels[y1*w+x1]))
    return bytes(out)


def export_grid(profile, destination, step=16):
    """Signed21-bit source x/y Q8, bit42 validity; sparse DDR/ROI warp reference."""
    if type(step) is not int or not 1 <= step <= 256:
        raise ValueError("grid step must be 1..256")
    xs = list(range(0,profile.width-1,step)) + [profile.width-1]
    ys = list(range(0,profile.height-1,step)) + [profile.height-1]
    entries = []
    for v in ys:
        for u in xs:
            x,y = profile.source(u,v)
            qx,qy = round(x*256),round(y*256)
            if not (-2**20 <= qx < 2**20 and -2**20 <= qy < 2**20):
                raise ValueError("mapping exceeds signed21 Q8 range; review calibration/output field of view")
            valid = 0 <= x <= profile.width-1 and 0 <= y <= profile.height-1
            entries.append((int(valid)<<42) | ((qy&0x1fffff)<<21) | (qx&0x1fffff))
    # Validate every coordinate before writing either deliverable.
    destination = Path(destination)
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_text(''.join(f'{v:011x}\n' for v in entries),encoding='ascii')
    metadata = dict(model=profile.model,image_size=[profile.width,profile.height],
                    x_nodes=xs,y_nodes=ys,fraction_bits=8,coordinate_bits=21,
                    valid_bit=42,entry_count=len(entries),
                    note="Reference map only. Current FPGA bitstream does not consume this grid.")
    destination.with_name(destination.stem+'_grid.json').write_text(json.dumps(metadata,indent=2)+'\n',encoding='utf-8')
    return metadata


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('profile',type=Path)
    parser.add_argument('--grid',type=Path,required=True)
    parser.add_argument('--step',type=int,default=16)
    args=parser.parse_args()
    profile=LensProfile(json.loads(args.profile.read_text(encoding='utf-8')))
    print(json.dumps(export_grid(profile,args.grid,args.step),ensure_ascii=False))


if __name__=='__main__':
    main()
