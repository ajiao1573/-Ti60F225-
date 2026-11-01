# Portable simulation tools

This directory contains MSYS2 mingw64 binary packages unpacked locally for RTL
verification. No installer was run and no persistent system PATH was changed.
Tests add `mingw64/bin` to their own process environment only.

Source package repository: https://repo.msys2.org/mingw/mingw64/

- Icarus Verilog 13.0-2 (GPL-2.0-or-later), https://github.com/steveicarus/iverilog
- libgcc/libstdc++ 16.2.0-4, libwinpthread, bzip2, readline, termcap,
  zlib-ng-compat, gettext-runtime, libiconv, xz runtime dependencies.

Package license files are under `mingw64/share/licenses`. This directory is
only needed for simulation; FPGA compilation uses the existing Efinity install.
An existing Icarus installation on PATH also works with the test scripts.
