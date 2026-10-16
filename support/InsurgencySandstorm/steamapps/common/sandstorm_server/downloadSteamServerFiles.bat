@echo off
@rem http://media.steampowered.com/installer/steamcmd.zip
@rem https://www.microsoft.com/en-us/download/details.aspx?id=53587
@rem https://aka.ms/vs/15/release/vc_redist.x64.exe

SETLOCAL ENABLEDELAYEDEXPANSION

title Downloading Sandstorm Server Base Files

echo.
echo ==============================================
echo    Insurgency Sandstorm Server Pre-Download       
echo ==============================================
echo.

cd /d "%~dp0"

set STEAMLOGIN=anonymous
set insserverBRANCH=581330
set CONFIG_FILE=SupportStartup.json
set "STEAMPATH=%CD:\steamapps\common\sandstorm_server=%"
set SteamCMDURL=http://media.steampowered.com/installer/steamcmd.zip

echo The current working directory is: %STEAMPATH%

rem Check if SteamCMD.exe exists and download if missing

if not exist "%STEAMPATH%\SteamCMD.exe" (
    echo.
    echo Downloading SteamCMD Zip %SteamCMDURL% file...
    echo.

    curl.exe -L "%SteamCMDURL%" -o "%STEAMPATH%\temp_download.zip"

    if errorlevel 1 (
        echo [ERROR] Failed to download the file. Check the URL and try again.
        pause
        break
    )

    echo.
    echo Extracting SteamCMD.exe to: '%STEAMPATH%
    powershell.exe -Command "Expand-Archive -Path '%STEAMPATH%\temp_download.zip' -DestinationPath '%STEAMPATH%' -Force"

    echo.
    echo Cleaning up temporary files...
    del "%STEAMPATH%\temp_download.zip"

    echo [SUCCESS] Done!
    echo.
)

for /f "usebackq tokens=1* delims==" %%a in (`powershell -NoProfile -Command "(Get-Content '%CONFIG_FILE%' | ConvertFrom-Json).psobject.properties | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }"`) do (
    set "%%a=%%b"
)

echo.
echo Downloading UE4 Prerequisite Files
echo Branch: %insserverBRANCH%
echo.

"%STEAMPATH%\steamcmd.exe" +login %STEAMLOGIN% +"app_update %insserverBRANCH%" validate +quit

if "%FirstRun%"=="1" (
    REM --- Write to Config File ---
    echo { > SupportStartup.json
    
        echo "FirstRun": "0" >> SupportStartup.json
    echo } >> SupportStartup.json
    
    call "%STEAMPATH%\steamapps\common\sandstorm_server\downloadSteamServerFiles.bat"
    exit
)

