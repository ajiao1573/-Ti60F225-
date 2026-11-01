@echo off
setlocal
cd /d "%~dp0"
if not defined EFINITY_HOME set "EFINITY_HOME=C:\Efinity\2026.1"
set "PYTHONHOME=%EFINITY_HOME%\python311"
set "PYTHONUTF8=1"
set "PATH=%EFINITY_HOME%\python311\bin;%EFINITY_HOME%\bin;%EFINITY_HOME%\lib;%EFINITY_HOME%\scripts;%PATH%"
"%EFINITY_HOME%\python311\bin\python.exe" tools\build.py %*
exit /b %errorlevel%
