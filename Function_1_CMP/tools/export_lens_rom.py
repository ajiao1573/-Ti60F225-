"""Export the measured native-coordinate forward/inverse grid for ROI hardware."""
import hashlib
import json
import math
from pathlib import Path
from lens_geometry import LensProfile

ROOT = Path(__file__).resolve().parents[1]


def inverse(p, x, y):
    u, v = x, y
    for _ in range(25):
        a, b = p.source(u, v)
        if max(abs(a-x), abs(b-y)) < 1e-9:
            return u, v
        ax, bx = p.source(u+.01, v)
        ay, by = p.source(u, v+.01)
        j00, j10, j01, j11 = (ax-a)*100, (bx-b)*100, (ay-a)*100, (by-b)*100
        det = j00*j11-j01*j10
        if det <= 0:
            raise ValueError('noninvertible calibration map')
        du, dv = ((a-x)*j11-(b-y)*j01)/det, ((b-y)*j00-(a-x)*j10)/det
        # Limit Newton steps for points outside the image used for ROM padding.
        scale = max(1, abs(du)/128, abs(dv)/128)
        u, v = u-du/scale, v-dv/scale
    raise ValueError(f'inverse did not converge at {x},{y}')


def main():
    profile_path = ROOT/'docs/calibration/lens_profile_native1080.json'
    p = LensProfile(json.loads(profile_path.read_text()))
    grid = []
    for row in range(26):
        for col in range(39):
            x, y = col*64-256, row*64-256
            forward = p.source(x, y)
            # The inverse half is only queried within the physical sensor field;
            # padding keeps a single common address space for both directions.
            backward = inverse(p, x, y)
            q = [round(v*256) for v in (*forward, *backward)]
            if any(not -2**20 <= v < 2**20 for v in q):
                raise ValueError('signed Q8 ROM range exceeded')
            grid.append(sum((v & 0x1fffff) << (21*i) for i, v in enumerate(q)))
    path = ROOT/'src/calibration/lens_map.hex'
    path.parent.mkdir(exist_ok=True)
    path.write_text(''.join(f'{v:021x}\n' for v in grid), encoding='ascii')
    metadata = dict(profile=str(profile_path.relative_to(ROOT)),
                    profile_sha256=hashlib.sha256(profile_path.read_bytes()).hexdigest(),
                    rom_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                    origin=[-256,-256], step=64, columns=39, rows=26,
                    fraction_bits=8, coordinate_bits=21,
                    layout='LSB: forward_x, forward_y, inverse_x, inverse_y (21 bits each)')
    path.with_suffix('.json').write_text(json.dumps(metadata, indent=2)+'\n')
    print(json.dumps(metadata, indent=2))


if __name__ == '__main__':
    main()
