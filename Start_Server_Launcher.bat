@echo off

title Sandstorm_Multi_Server

setlocal DisableDelayedExpansion

rem Set up the configuration file path
set "cfgFile=%~dp0config\batchFirstRun.cfg"
set "cfgValue=0"

rem Read the config file if it exists
if exist "%cfgFile%" set /p cfgValue=<"%cfgFile%"

rem Clean up the read value
set "cfgValue=%cfgValue: =%"
if "%cfgValue%"=="ECHOisoff." set "cfgValue=0"
if "%cfgValue%"=="" set "cfgValue=0"

rem Jump straight to launching the game if it's not the first run
if not "%cfgValue%"=="0" goto LaunchGame

echo.
echo ---=== FIRST RUN SETUP OF DOWNLOADED FILES ===---
echo.

rem Query file system filters (requires true Admin privileges on Win 10 and Win 11)
fltmc >nul 2>&1

rem Checks if the previous command returned an error (1 or higher)
if errorlevel 1 (
    echo Must be in Administration Mode to UnBlock downloaded files.
    echo This will allow Scripts to execute without User being asked for Permissions.
    echo Administration mode will not be needed after this unless Script explicitly
    echo asks for it.
    pause
    exit /b
)

echo First run detected. Elevated Administrator rights confirmed.
echo Unblocking files...
echo.
echo All downloaded files should be UnBlocked and allowed to run without
echo asking User for permission to run from this point on.
echo.
echo No need to run this Batch (.bat) file in Administrator Mode unless required.

rem This line safe now that the outer parentheses are gone
powershell -NoProfile -Command "Get-ChildItem -Path '%~dp0' -File -Recurse | Unblock-File"

rem Safely write '1' using set /p
<nul set /p "=1" >"%cfgFile%"

echo.
echo Done! Configuration batchFirstRun.cfg updated.
echo User will not see this again.
echo.
pause

:LaunchGame

Powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Server_Launcher.ps1"

rem Finished