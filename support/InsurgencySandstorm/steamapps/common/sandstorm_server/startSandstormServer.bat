@echo off
@rem http://media.steampowered.com/installer/steamcmd.zip
@rem https://www.microsoft.com/en-us/download/details.aspx?id=53587
@rem https://aka.ms/vs/15/release/vc_redist.x64.exe

SETLOCAL ENABLEDELAYEDEXPANSION

echo.
echo ==============================================
echo           Server Execution Wizard        
echo ==============================================
echo.

rem This startSandstorm.bat file must be located in the "\steamapps\common\sandstorm_server" directory

rem DO NOT change the STEAMLOGIN or insserverBRANCH values

cd /d "%~dp0"

set "Server=%~1"

set STEAMLOGIN=anonymous
set insserverBRANCH=581330
set CONFIG_FILE=ServerStartup.json
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

echo Reading variables from %CONFIG_FILE%:
echo -----------------------------------

for /f "usebackq tokens=1* delims==" %%a in (`powershell -NoProfile -Command "(Get-Content '%CONFIG_FILE%' | ConvertFrom-Json).psobject.properties | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }"`) do (
    echo Found Variable: %%a = %%b
    set "%%a=%%b"
)

echo -----------------------------------

rem _________________________________________________________

echo.
echo Updating the Insurgency:Sandstorm server %Server%
echo Branch: %insserverBRANCH%
echo.

"%STEAMPATH%\steamcmd.exe" +login %STEAMLOGIN% +"app_update %insserverBRANCH%" validate +quit

if "%FirstRun%"=="1" (
    REM --- Write to Config File ---
    echo { > ServerStartup.json
    
        echo "FirstRun": "0", >> ServerStartup.json
        echo "Port": "%Port%", >> ServerStartup.json
        echo "QueryPort": "%QueryPort%", >> ServerStartup.json
        echo "Password": "%Password%", >> ServerStartup.json
        echo "RconListenPort": "%RconListenPort%", >> ServerStartup.json
        echo "RconPassword": "%RconPassword%", >> ServerStartup.json
        echo "SecurityCode": "%SecurityCode%", >> ServerStartup.json
        echo "HostName": "%HostName%", >> ServerStartup.json
        echo "MaxPlayers": "%MaxPlayers%", >> ServerStartup.json
        echo "GameStatsToken": "%GameStatsToken%", >> ServerStartup.json
        echo "GSLTToken": "%GSLTToken%", >> ServerStartup.json
        echo "Mutators": "%Mutators%", >> ServerStartup.json
        echo "startscenario": "%startscenario%" >> ServerStartup.json
    echo } >> ServerStartup.json
    
    call "%STEAMPATH%\steamapps\common\sandstorm_server\startSandstormServer.bat" %Server%
    exit
)

echo.
echo ==============================================
echo      Sandstorm server is now up to date        
echo ==============================================
echo.

rem Start Server with Random Scenerio

if not exist "insurgency\Config\server\bootmaps.txt" (
    echo [ERROR] "insurgency\Config\server\bootmaps.txt" is missing
    pause
    break
)

set "file=insurgency\Config\server\bootmaps.txt"

set /A i=0

for /F "usebackq tokens=*" %%a in ("%file%") do (
    set /A i+=1

    for /f %%b in ("%%a") do (
        call echo %%b

        call set bootmaparray[%%i%%]=%%b
    )
    call set n=%%i%%
)

call set /a _rand=(%RANDOM% * %n%) / 32768
call set /a _rand=((%RANDOM% * %n%) / 32768) + 1

call echo.
call echo Selected Scenario number %_rand% out of %n% Scenarios

call set MoveTo=%%bootmaparray[%_rand%]%%

:: 1. Strip spaces
set "MoveTo=%MoveTo: =%"

:: 2. Strip Carriage Returns (CR) and Line Feeds (LF)
for /f "delims=" %%A in ("%MoveTo%") do set "MoveTo=%%A"

if "%MoveTo%"=="" set MoveTo=%startscenario%

call set "defaultmap=?Scenario=?Game=?Lighting=?Mutators="

if "%MoveTo%"=="%defaultmap%" set MoveTo=%startscenario%

call echo.
call echo "ModDownloadTravelTo = %MoveTo%"
call echo.

rem Count the number of defined Scenarios contained in the MapCycle.txt file
set "file=Insurgency\Config\server\mapcycle.txt"

set /A i=0

REM Count lines not starting with // and store in variable
for /f %%A in ('findstr /V /B "^//" "%file%" ^| find /C /V ""') do set "lineCount=%%A"

echo Total active maps: %lineCount%

set count=%lineCount%

rem insert total number of Scenarios where [ScenarioCount] is in hostname string

if not "%SecurityCode%"=="none" (
    REM --- Write to Config File ---
    echo { > ServerStartup.json
    
        echo "FirstRun": "0", >> ServerStartup.json
        echo "Port": "%Port%", >> ServerStartup.json
        echo "QueryPort": "%QueryPort%", >> ServerStartup.json
        echo "Password": "%Password%", >> ServerStartup.json
        echo "RconListenPort": "%RconListenPort%", >> ServerStartup.json
        echo "RconPassword": "%RconPassword%", >> ServerStartup.json
        echo "SecurityCode": "none", >> ServerStartup.json
        echo "HostName": "%HostName%", >> ServerStartup.json
        echo "MaxPlayers": "%MaxPlayers%", >> ServerStartup.json
        echo "GameStatsToken": "%GameStatsToken%", >> ServerStartup.json
        echo "GSLTToken": "%GSLTToken%", >> ServerStartup.json
        echo "Mutators": "%Mutators%", >> ServerStartup.json
        echo "startscenario": "%startscenario%" >> ServerStartup.json
    echo } >> ServerStartup.json
)

call set hostname=%%hostname:[ScenarioCount]=%count%%%\

rem Let Launcher know Server Starting

del /f /q serverStart.txt

powershell -windowstyle minimized -command ""

set addPassword=

rem 1. Check if the variable is completely missing/empty
if "%Password%"=="" (
    goto :failed
)

rem 2. Check if the length is 2 or fewer characters
if "!Password:~2,1!"=="" (
     goto :failed
)

set addPassword=?Password=%Password%?Dummy
goto :end

:failed

:end

@echo on

InsurgencyServer.exe %startscenario%?MaxPlayers=%MaxPlayers%%addPassword% -Port=%Port% -QueryPort=%QueryPort% -Rcon -RconListenPort=%RconListenPort% -RconPassword=%RconPassword% -log -log=%Server%.log -hostname="%HostName%" -GameStatsToken=%GameStatsToken% -GSLTToken=%GSLTToken% -GameStats -MapCycle=mapcycle -mods -SecurityCode=%SecurityCode% -mutators=%Mutators% -ModDownloadTravelTo=%MoveTo%?MaxPlayers=%MaxPlayers%%addPassword%
