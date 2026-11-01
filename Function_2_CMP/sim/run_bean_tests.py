"""Run from any directory: python sim/run_bean_tests.py [--full-size]."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--full-size', action='store_true', help='also simulate four 720p frames')
parser.add_argument('--full-size-frames', type=int, choices=(2,4), default=4,
                    help='native-size frame count; 2 for smoke, 4 for extended regression')
parser.add_argument('--1080p', dest='native_1080p', action='store_true',
                    help='also check every native 1080p contour pixel and full-size count')
parser.add_argument('--only',nargs='+',help='run only the named regression tests')
args = parser.parse_args()
os.chdir(ROOT)
out = ROOT/'build'/'sim'
out.mkdir(parents=True, exist_ok=True)
tool_dir = Path(os.environ.get('IVERILOG_BIN', ROOT/'build/tools/iverilog/app/bin'))
iverilog = str(tool_dir/'iverilog.exe') if (tool_dir/'iverilog.exe').is_file() else shutil.which('iverilog')
vvp = str(tool_dir/'vvp.exe') if (tool_dir/'vvp.exe').is_file() else shutil.which('vvp')
if not iverilog or not vvp:
    sys.exit('Icarus Verilog not found; add it to PATH or set IVERILOG_BIN to its bin directory.')
subprocess.run([sys.executable,'sim/generate_bean_vectors.py'],check=True,
               stdout=(out/'vectors.log').open('w'))
subprocess.run([sys.executable,'sim/generate_contour_vectors.py'],check=True)
subprocess.run([sys.executable,'sim/generate_median_vectors.py'],check=True)
subprocess.run([sys.executable,'sim/generate_median_vectors.py','--kernel','5'],check=True)
subprocess.run([sys.executable,'sim/generate_median_vectors.py','--kernel','5','--native-width'],check=True)
sources = [str(p.relative_to(ROOT)) for p in sorted((ROOT/'src/bean').glob('*.v'))]
tests = ['bean_runtime_controls_tb','bean_runtime_osd_tb','bean_objects_tb','bean_cca_objects_tb','bean_banked_ram_tb','axi_video_fault_tb','bean_source_fault_tb','camera_sccb_fault_tb','camera_sccb_verify_tb','bean_median5_smooth_tb','bean_median5_native_tb','bean_smooth_tb','bean_median_tb','bean_contour_tb','bean_cca_tb','bean_video_tb','bean_preprocess_tb','bean_osd_tb',
         'key_debounce_tb','video_frame_banks_tb','camera_orientation_tb','bean_freeze_tb',
         'camera_1080p_tb','capture_1080p_tb','axi_video_write_tb',
         'camera_sccb_bus_tb','camera_sccb_readback_tb','bean_freeze_denoise_tb']
if args.full_size:
    tests.append('bean_720p_tb')
if args.native_1080p:
    tests.append('bean_1080p_tb')
if args.only:
    unknown=set(args.only)-set(tests)
    if unknown: sys.exit('Unknown test names: '+', '.join(sorted(unknown)))
    tests=[test for test in tests if test in args.only]
print('Requested tests: '+', '.join(tests),flush=True)
for test in tests:
    module = 'bean_freeze_tb' if test in ('bean_freeze_denoise_tb','bean_source_fault_tb') else test
    if test in ('bean_smooth_tb','bean_median5_smooth_tb','bean_median5_native_tb'):
        module = 'bean_median_tb'
    target = out/f'{test}.vvp'
    extras = []
    if test in ('camera_orientation_tb','camera_1080p_tb','camera_sccb_bus_tb'):
        extras += ['src/cmos_i2c/I2C_OV5640_1280720_Config.v','src/cmos_i2c/I2C_OV5640_19201080_Config.v']
    if test in ('camera_sccb_bus_tb','camera_sccb_fault_tb'):
        extras += ['src/cmos_i2c/i2c_timing_ctrl_16bit.v']
    if test == 'camera_sccb_readback_tb':
        extras += ['sim/camera_sccb_readback.v']
    if test == 'capture_1080p_tb':
        extras += ['src/Sensor_Image_XYCrop.v']
    if test in ('axi_video_write_tb','axi_video_fault_tb'):
        extras += ['src/axi/axi4_ctrl.v']
    if test == 'bean_1080p_tb':
        extras += ['src/lcd_driver.v']
    test_sources = sources + extras
    options = ([f'-Pbean_720p_tb.FRAMES={args.full_size_frames}']
               if test == 'bean_720p_tb' else [])
    if test == 'bean_source_fault_tb':
        options += ['-Pbean_freeze_tb.DENOISE_ENABLE=1','-Pbean_freeze_tb.FAULT_TEST=1','-Pbean_freeze_tb.HOLD_FRAMES=30']
    if test == 'bean_freeze_denoise_tb':
        options += ['-Pbean_freeze_tb.DENOISE_ENABLE=1']
    if test == 'bean_smooth_tb':
        options += ['-Pbean_median_tb.SMOOTH=1']
    if test in ('bean_median5_smooth_tb','bean_median5_native_tb'):
        options += ['-Pbean_median_tb.SMOOTH=1','-Pbean_median_tb.K=5']
    if test == 'bean_median5_native_tb':
        options += ['-Pbean_median_tb.NATIVE=1']
    subprocess.run([iverilog,'-g2005-sv','-Wall','-Isrc','-s',module,*options,'-o',str(target),
                    *test_sources,f'sim/{module}.v'],check=True)
    log = out/f'{test}.log'
    log.write_text('RUNNING\n',encoding='utf-8')
    try:
        result = subprocess.run([vvp,'-i',str(target)],capture_output=True,text=True,
                                timeout=1200 if test in ('bean_720p_tb','bean_1080p_tb','bean_source_fault_tb') else 300)
    except subprocess.TimeoutExpired as exc:
        def decoded(value):
            return value.decode(errors='replace') if isinstance(value,bytes) else value or ''
        log.write_text(decoded(exc.stdout)+decoded(exc.stderr)+'\nFAIL simulation wall-clock timeout\n',
                       encoding='utf-8')
        sys.exit(f'{test}: simulation timeout; see {log}')
    log.write_text(result.stdout+result.stderr,encoding='utf-8')
    if result.returncode:
        print(result.stdout,result.stderr)
        sys.exit(result.returncode)
    for line in result.stdout.splitlines():
        if line.startswith('PASS') and ('case ' not in line):
            print(line)
print('All requested bean RTL tests passed.')
