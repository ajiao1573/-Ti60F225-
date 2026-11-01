@echo off
setlocal
cd /d "%~dp0"
if exist "%~dp0dist\Ti60PlateControl.exe" goto exe
if defined TI60_PYTHON goto custom
where python >nul 2>nul
if errorlevel 1 goto missing
python "%~dp0app.py" %*
goto done
:exe
"%~dp0dist\Ti60PlateControl.exe" %*
goto done
:custom
"%TI60_PYTHON%" "%~dp0app.py" %*
goto done
:missing
echo Missing dist\Ti60PlateControl.exe and Python 3.10+.
echo Extract the complete ZIP before starting this launcher.
:done
echo.
echo Service stopped. Keep the service window open while using the webpage.
pause
endlocal
