# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['C:\\Users\\aj150\\Desktop\\FPGA\\FUNCTION_LAST\\Host\\app.py'],
    pathex=['C:\\Users\\aj150\\Desktop\\FPGA\\FUNCTION_LAST\\Host\\vendor'],
    binaries=[],
    datas=[('C:\\Users\\aj150\\Desktop\\FPGA\\FUNCTION_LAST\\Host\\static', 'static'), ('C:\\Users\\aj150\\Desktop\\FPGA\\FUNCTION_LAST\\Host\\vendor\\pyserial-3.5.dist-info', 'vendor/pyserial-3.5.dist-info')],
    hiddenimports=['serial.tools.list_ports_windows'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='Ti60PlateControl',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
