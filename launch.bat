@echo off
setlocal

rem Launch Hybrid Identity Reporter from this folder, whatever its location.
set "ROOT=%~dp0"
set "SCRIPT=%ROOT%Start-Hybrid-Identity-Reporter.ps1"

if not exist "%SCRIPT%" (
    echo [ERROR] Script not found:
    echo "%SCRIPT%"
    echo.
    echo Make sure launch.bat is located in the project root folder.
    pause
    exit /b 1
)

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] powershell.exe was not found in PATH.
    pause
    exit /b 1
)

cd /d "%ROOT%"
echo Starting Hybrid Identity Reporter...
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%SCRIPT%"
set "EXITCODE=%ERRORLEVEL%"

if not "%EXITCODE%"=="0" (
    echo.
    echo [ERROR] Hybrid Identity Reporter exited with code %EXITCODE%.
    echo Check the Logs folder for details:
    echo "%ROOT%Logs"
    echo.
    pause
)

exit /b %EXITCODE%
