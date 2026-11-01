import sys
import math
import unittest
import tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from lens_geometry import LensProfile,rectify_gray,export_grid

def profile(d=(0,0,0,0,0),model='pinhole'):
    return LensProfile(dict(model=model,image_size=[64,48],
                            camera_matrix=[[40,0,31.5],[0,40,23.5],[0,0,1]],distortion_coefficients=list(d)))

class GeometryTests(unittest.TestCase):
    def test_identity_frame_and_edges(self):
        image=bytes((x*7+y*11)&255 for y in range(48) for x in range(64))
        self.assertEqual(rectify_gray(image,profile()),image)

    def test_barrel_inverse_sampling_direction(self):
        p=profile([-.2,0,0,0,0])
        x,y=p.source(63,23.5)
        self.assertLess(x,63);self.assertGreater(x,31.5);self.assertEqual(y,23.5)
        self.assertEqual(p.source(31.5,23.5),(31.5,23.5))

    def test_tangential_axes(self):
        p=profile([0,0,.01,.02,0])
        # At x=0,y=0.5, dx=p2*y^2 and dy=3*p1*y^2.
        x,y=p.source(31.5,43.5)
        self.assertAlmostEqual(x,31.7);self.assertAlmostEqual(y,43.8)

    def test_fisheye_is_not_zero_coefficient_pinhole(self):
        x,_=profile([0,0,0,0],'fisheye').source(63,23.5)
        self.assertAlmostEqual(x,31.5+40*math.atan(31.5/40))
        self.assertNotEqual(x,63)

    def test_resolution_scaling_and_crop_rejection(self):
        p=profile([-.2,.03,0,0,0]);q=p.scaled(128,96)
        a=p.source(20,10);b=q.source(40,20)
        self.assertAlmostEqual(b[0],2*a[0]);self.assertAlmostEqual(b[1],2*a[1])
        with self.assertRaises(ValueError):p.scaled(128,80)

    def test_grid_signed_out_of_bounds_and_last_pixel(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'grid.hex';m=export_grid(profile([.2,0,0,0,0]),path,16)
            existing=Path(folder)/'grid.json';existing.write_text('profile sentinel')
            export_grid(profile(),path,16)
            self.assertEqual(existing.read_text(),'profile sentinel')
            export_grid(profile([.2,0,0,0,0]),path,16)
            values=[int(s,16) for s in path.read_text().split()]
            self.assertEqual(m['x_nodes'][-1],63);self.assertEqual(m['y_nodes'][-1],47)
            self.assertFalse(values[0]>>42)
            qx=values[0]&0x1fffff
            self.assertTrue(qx&(1<<20))  # Negative source coordinate stays signed.

    def test_missing_wrong_model_and_resolution(self):
        with self.assertRaises(ValueError):profile([0,0,0,0])
        with self.assertRaises(ValueError):profile([float('nan'),0,0,0,0])
        with self.assertRaises(ValueError):rectify_gray(bytes(10),profile())

if __name__=='__main__':unittest.main()
