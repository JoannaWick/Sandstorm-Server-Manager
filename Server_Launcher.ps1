<#PSScriptInfo
.NAME Server_Launcher
.VERSION 1.0.0
.AUTHOR Joanna Wick
.TAGS Sandstorm, Mods
.PROJECTURI https://github.com/JoannaWick/Sandstorm-Server-Manager
#>

$Host.UI.RawUI.WindowTitle = "Sandstorm_Multi_Server"

$Version = "1.0.0"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "        Sandstorm Multi Server Launcher       " -ForegroundColor Yellow
Write-Host "              Version: $Version               " -ForegroundColor DarkYellow
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

$windows_to_move = 1

$ServerListJsonPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ServerList.json"
$ServerListData=Get-Content $ServerListJsonPath | ConvertFrom-Json

foreach ($item in $ServerListData) {

    # Get each dynamic top element name and value
    foreach ($property in $item.PSObject.Properties) {
        $Server_ID = $property.Name
        $serverValue = $property.Value

        if ($Server_ID -ne "Version")
        {
           $windows_to_move += 1
        }
    }
}

$windows_to_move += 1

$infoMonitor_to_move = $windows_to_move

# Read the current OS build framework directly from memory
$buildNumber = [Environment]::OSVersion.Version.Build

if ($buildNumber -ge 22000) {
    <# 
        Resize and center window
    #>

    Start-Sleep -Milliseconds 1000

    Add-Type -AssemblyName System.Windows.Forms
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    # Calculations for your tile dimensions
    $targetWidth  = $workingArea.Width
    $targetHeight = $workingArea.Height - 40
    $Cols         = [Math]::Ceiling([Math]::Sqrt($windows_to_move))
    $Rows         = [Math]::Ceiling($windows_to_move / $Cols)
    $TileWidth    = [Math]::Floor($targetWidth / $Cols)
    $TileHeight   = [Math]::Floor($targetHeight / $Rows)

    # Win32 Signatures capable of piercing Windows 11 tab abstractions
    $Signature = @"
using System;
using System.Runtime.InteropServices;

public class Win11CmdOverride {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
}
"@
    Add-Type -TypeDefinition $Signature -ErrorAction SilentlyContinue

    # Grab the current session handle (often virtualized on Win 11)
    $localHwnd = [Win11CmdOverride]::GetConsoleWindow()

    # Extract the actual visible GUI Frame Owner (GW_OWNER = 4)
    $realHwnd = [Win11CmdOverride]::GetWindow($localHwnd, 4)

    # Fallback to local handle if not nested inside a modern frame layer
    if ($realHwnd -eq [IntPtr]::Zero) {
        $realHwnd = $localHwnd
    }

    # Fire the placement matrix transformation
    $xPos = 0
    $yPos = 0

    if ($realHwnd -ne [IntPtr]::Zero) {
        [void][Win11CmdOverride]::MoveWindow($realHwnd, $xPos, $yPos, $TileWidth, $TileHeight, $true)
    }

} else {
    # Load the required .NET assembly
    Add-Type -AssemblyName System.Windows.Forms

    # Fetch the working area of the primary display
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    # Extract isolated integer values 
    $ScreenWidth  = $WorkingArea.Width
    $ScreenHeight = $WorkingArea.Height - 40

    # Math calculation engine for grid layout
    $Cols = [Math]::Ceiling([Math]::Sqrt($windows_to_move))
    $Rows    = [Math]::Ceiling($windows_to_move / $Cols)
    $TileWidth  = [Math]::Floor($ScreenWidth / $Cols)
    $TileHeight = [Math]::Floor($ScreenHeight / $Rows)

    # Definition for User32 MoveWindow
$TypeDefinition = @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
}
"@
    Add-Type -TypeDefinition $TypeDefinition

    if ($batchLaunch -eq 0)
    {
        # Get the current Powershell process window handle
        $hWnd = (Get-Process -Id $PID).MainWindowHandle
    }
    else
    {
        # Get the current cmd.exe window handle that launched Powershell process
        $parentID = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID").ParentProcessId
        $hWnd = (Get-Process -Id $parentID).MainWindowHandle
    }

    $xPos = 0
    $yPos = 0
                
    # Perform window layout shift
    [void][Window]::MoveWindow($hWnd, $xPos, $yPos, $TileWidth, $TileHeight, $true)
}

$windows_to_move = 2

function resize_windows {
    param
    (
        $finalRun = $false
    )

    # Compile WinAPI smoothly without duplicate type generation crashes
    if (-not ([System.Management.Automation.PSTypeName]'WinAPI').Type) {
        Add-Type @"
        using System;
        using System.Runtime.InteropServices;
        public class WinAPI {
            [DllImport("user32.dll", SetLastError = true)]
            public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
            [DllImport("user32.dll")]
            public static extern bool IsIconic(IntPtr hWnd);
        }
"@
    }

    # Ensure $windows_to_move fallback check
    if ($null -eq $windows_to_move -or $windows_to_move -le 0) {
        $windows_to_move = 4 # Universal safety default
    }

    # Load the required Windows Forms assembly
    Add-Type -AssemblyName System.Windows.Forms

    # Fetch the usable screen area properties
    $WorkingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    # Extract clean area spacing bounds
    $ScreenWidth  = $WorkingArea.Width
    $ScreenHeight = $WorkingArea.Height - 40

    # Math calculation engine for grid layout
    $Cols       = [Math]::Ceiling([Math]::Sqrt($windows_to_move))
    $Rows       = [Math]::Ceiling($windows_to_move / $Cols)
    $TileWidth  = [Math]::Floor($ScreenWidth / $Cols)
    $TileHeight = [Math]::Floor($ScreenHeight / $Rows)

    $start = 0
    $True_Count = 2

    $processes2 = Get-Process -Name InsurgencyServer-Win64-Shipping -ErrorAction SilentlyContinue | 
                     Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
                     Sort-Object StartTime

#    Write-Host "Processes to move: $($processes2.Count)"
    for ($i = $start; $i -lt $processes2.Count; $i++) {
        if ($True_Count -ge $windows_to_move) { break }

        $currentProc = $processes2[$i]
#        $currentProc | Select-Object * | Out-GridView
        if ($null -eq $currentProc) { continue }

        # Force process UI property refresh to bypass Windows 11 handle-caching lag
#        $currentProc.Refresh()
        $hWnd = $currentProc.MainWindowHandle

        if ($hWnd -and $hWnd -ne [IntPtr].Zero) {
#        Write-Host "hwnd check: $($hWnd)"
            # Check if minimized using modern native property wrapper
            $isMinimized = [WinAPI]::IsIconic($hWnd)
    
            if (-not $isMinimized) {
                $row = [Math]::Floor($True_Count / $Cols)
                $col = $True_Count % $Cols

                $xPos = $col * $TileWidth
                $yPos = $row * $TileHeight
                
                # Perform window layout shift
                $is_True = [WinAPI]::MoveWindow($hWnd, $xPos, $yPos, $TileWidth, $TileHeight, $true)

                if ($is_True) {
                    $True_Count++
                }
            }
        }
    }
}

# Initialize the synchronized, thread-safe FIFO queue
$global:TaskQueue = [System.Collections.Concurrent.ConcurrentQueue[PSCustomObject]]::new()

# State tracking
$global:ActiveTasks = 0
$global:TaskProcessingActive = $false

function Test-TargetWindowExists {
    param (
        [string]$Server_ID
    )
    $pattern = "(?<=TITLE\s+)$Server_ID(?=\s+&&)"
#    Write-Host "Searching for tracking ID: $Server_ID"

    # Check native Window Titles (Works perfectly on Win 10 or forced Conhost)
    $nativeMatch = Get-Process -Name "cmd" -ErrorAction SilentlyContinue | 
                   Where-Object { $_.MainWindowTitle -match $pattern }
    
    if ($nativeMatch) {
#        Write-Host "Found match via active Window Title."
        return $true
    }

    # Fallback for Windows 11 Terminal (Inspects the CLI parameters)
    # This reads the actual script file, path, or title parameters fed to cmd.exe when launched
    $cimMatches = Get-CimInstance -ClassName Win32_Process -Filter "Name = 'cmd.exe'" -ErrorAction SilentlyContinue
    foreach ($proc in $cimMatches) {
        if ($proc.CommandLine -match $pattern) {
#            Write-Host "Found match via background CommandLine arguments: $($proc.CommandLine)"
            return $true
        }
    }

    # Deep check - if your launch script sets a dynamic title using the 'title' command
    # Windows Terminal keeps these titles inside its tab manager.
    # If the above steps fail, we look at the main Windows Terminal text frames.
    $terminalMatches = Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue | 
                       Where-Object { $_.MainWindowTitle -match $pattern }

    if ($terminalMatches) {
#        Write-Host "Found match inside Windows Terminal active title frame."
        return $true
    }

#    Write-Host "No active matching process found."
    return $false
}

function Get-TargetWindowId {
    param (
        [string]$Server_ID
    )
    $pattern = "(?<=TITLE\s+)$Server_ID(?=\s+&&)"
    
    # Create an empty array to collect all matching IDs
    $foundIds = [System.Collections.Generic.List[int]]::new()

    # Check native Window Titles
    $nativeMatches = Get-Process -Name "cmd" -ErrorAction SilentlyContinue | 
                     Where-Object { $_.MainWindowTitle -match $pattern }
    foreach ($match in $nativeMatches) { $foundIds.Add($match.Id) }

    # Fallback for Windows 11 Terminal (CommandLine args)
    $cimMatches = Get-CimInstance -ClassName Win32_Process -Filter "Name = 'cmd.exe'" -ErrorAction SilentlyContinue
    foreach ($proc in $cimMatches) {
        if ($proc.CommandLine -match $pattern) {
            # Ensure we don't add duplicate IDs if already caught by native title
            if ($proc.ProcessId -notin $foundIds) {
                $foundIds.Add($proc.ProcessId)
            }
        }
    }

    # Deep check - Windows Terminal active title frame
    $terminalMatches = Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue | 
                       Where-Object { $_.MainWindowTitle -match $pattern }
    foreach ($match in $terminalMatches) {
        if ($match.Id -notin $foundIds) { $foundIds.Add($match.Id) }
    }

    # If we collected any IDs, return them. Otherwise, return $false.
    if ($foundIds.Count -gt 0) {
        return $foundIds.ToArray()
    }

    return $false
}

<# 
    Add Processing_Subscriptions function call to update all mods before starting server to Start-TaskProcessor.
#>

function Start-TaskProcessor {
    <#
    .SYNOPSIS
    Starts the consumer loop to process the FIFO task queue.
    #>
    Write-Host "Task processor started. Processing Tasks." -ForegroundColor Green
    $task = $null

    # Consumer loop
    while ($global:TaskProcessingActive) {
        # Dequeue the next task
        if ($global:TaskQueue.TryDequeue([ref]$task)) {
            $global:ActiveTasks++

            # Process the task in a background thread
            $job = Start-Job -ArgumentList $task -ScriptBlock {
                param($taskObj)

                $serverTitle = $($taskObj.Param1)
                $PSScriptRootDir = $($taskObj.Param2)
                Write-Output "Starting Server --> Server ID: $serverTitle"

                $processName = "Updating Server Subscriptions: $serverTitle" 
                $updateFile = "Start_Server_Mod_Update.bat"

                Start-Process "cmd.exe" -ArgumentList "/c TITLE $processName && CALL $updateFile", "$serverTitle" -WorkingDirectory "$PSScriptRootDir" -Wait

                $SourceServerDir = "$env:LOCALAPPDATA\mod.io.$serverTitle"
                $TargetModioDir  = "$env:LOCALAPPDATA\mod.io"

                if (Test-Path -Path $TargetModioDir) {
                    Remove-Item -Path $TargetModioDir -Recurse -Force *>$null
                }

                if (Test-Path -Path $SourceServerDir) {
                    robocopy "$SourceServerDir" "$TargetModioDir" /E /IS | Out-Null
                }

                # Copy config\ServerData\$serverTitle\ServerStartup.json file to InsurgencySandstorm\steamapps\common\sandstorm_server

                $sourceDir = Join-Path -Path $PSScriptRootDir -ChildPath "config\ServerData\$serverTitle"
                $destinationDir = Join-Path -Path $PSScriptRootDir -ChildPath "InsurgencySandstorm\steamapps\common\sandstorm_server"
                robocopy "$sourceDir" "$destinationDir" "ServerStartup.json" /IS | Out-Null

                # Copy config\ServerData\$serverTitle\server DIR to InsurgencySandstorm\steamapps\common\sandstorm_server\Insurgency\Config

                $sourcePath = Join-Path -Path $PSScriptRootDir -ChildPath "config\ServerData\$serverTitle\server"
                $destinationPath = Join-Path -Path $PSScriptRootDir -ChildPath "InsurgencySandstorm\steamapps\common\sandstorm_server\Insurgency\Config\server"
                robocopy "$sourcePath" "$destinationPath" /E /IS | Out-Null

                # Copy config\ServerData\$serverTitle\WindowsServer DIR to InsurgencySandstorm\steamapps\common\sandstorm_server\Insurgency\Saved\Config

                $sourcePath = Join-Path -Path $PSScriptRootDir -ChildPath "config\ServerData\$serverTitle\WindowsServer"
                $destinationPath = Join-Path -Path $PSScriptRootDir -ChildPath "InsurgencySandstorm\steamapps\common\sandstorm_server\Insurgency\Saved\Config\WindowsServer"
                robocopy "$sourcePath" "$destinationPath" /E /IS | Out-Null

                $serverPath = Join-Path -Path $PSScriptRootDir -ChildPath "InsurgencySandstorm\steamapps\common\sandstorm_server"
                $batchFile = "startSandstormServer.bat"
                Start-Process "cmd.exe" -ArgumentList "/c TITLE $serverTitle && CALL $batchFile", "$serverTitle" -WorkingDirectory "$serverPath"

                # Define the variables
                $fileName = "serverStart.txt"
                $fullPath = Join-Path -Path $serverPath -ChildPath $fileName

                # Create the file
                New-Item -Path $fullPath -ItemType "File" -Value "Server started." -Force *>$null

                # Loop and check until the file is deleted
                while (Test-Path -Path $fullPath) {
                    Start-Sleep  -Milliseconds 500
                }

                $FilePath = "$env:LOCALAPPDATA\mod.io\254\ModServer\user.json"

                # Wait Loop for file creation
                while (-not (Test-Path -Path $FilePath -PathType Leaf)) {
                    Start-Sleep -Seconds 5
                }

                # Capture the initial modification timestamp
                $InitialTime = (Get-Item -Path $FilePath).LastWriteTime
                $LoopCounter = 0

                # Initialize countdown tracking variables before the loop
                $TotalSeconds = 30
                $StartTime = Get-Date

                # Define an array of bright, readable console colors (avoiding dark black/blue)
                $ConsoleColors = "Cyan", "Green", "Yellow", "Magenta", "White", "Gray"

                # Check Loop (Up to 30 times)
                while ($LoopCounter -lt 30) {
                    $LoopCounter++

                    # Calculate and display remaining seconds on the exact same line
                    $TimeElapsed = (Get-Date) - $StartTime
                    $SecondsRemaining = [Math]::Max(0, $TotalSeconds - [Math]::Round($TimeElapsed.TotalSeconds))
                    $RandomColor = $ConsoleColors | Get-Random
                    Write-Host "`r$serverTitle Server Boot: ${SecondsRemaining}s remaining   " -NoNewline -ForegroundColor $RandomColor

                    # Only sleep if we haven't reached the 30th check yet
                    if ($LoopCounter -lt 30) {
                        Start-Sleep -Seconds 1
                    }
                }
                Write-Host "`r                                                 `r" -NoNewline

                $RenameUserJson = Join-Path -Path "$env:LOCALAPPDATA" -ChildPath "mod.io.$serverTitle\254\ModServer\user.json"
                # rename original user.json

                Rename-Item -Path "$RenameUserJson" -NewName ("user_{0:yyyyMMdd_HHmmss}.json" -f (Get-Date))

                $SourceServerDir = "$env:LOCALAPPDATA\mod.io.$serverTitle"
                $TargetModioDir  = "$env:LOCALAPPDATA\mod.io"
                # Mirror back to the server directory at the end
                robocopy "$TargetModioDir" "$SourceServerDir" /E /IS | Out-Null

                $cleanupPath = Join-Path -Path "$env:LOCALAPPDATA" -ChildPath "mod.io.$serverTitle\254\ModServer"
                Get-ChildItem -Path "$cleanupPath" -File | Sort-Object LastWriteTime -Descending | Select-Object -Skip 12 | Remove-Item -Force

                # Define the new title you want for your Insurgency server log window
                $NewTitle = "Insurgency: Sandstorm - $serverTitle"

                # Inject the Windows API function needed to change external window titles
                Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
    [DllImport("User32.dll", EntryPoint="SetWindowText", CharSet=CharSet.Unicode)]
    public static extern int SetWindowText(IntPtr hWnd, string strTitle);
}
"@

                $ServerProcess = Get-Process -Name "*InsurgencyServer-Win64-Shipping*" -ErrorAction SilentlyContinue | 
                     Sort-Object -Property StartTime -Descending | 
                    Select-Object -First 1

                if ($ServerProcess) {
                    # Check if the most recent process has a visible window handle
                    if ($ServerProcess.MainWindowHandle -ne [IntPtr]::Zero) {
                        [void][Win32]::SetWindowText($ServerProcess.MainWindowHandle, $NewTitle)
#                        Write-Host "Successfully renamed the most recent log window to: $NewTitle" -ForegroundColor Green
                    } else {
                        Write-Warning "Most recent server process found (ID: $($ServerProcess.Id)), but its window handle isn't ready yet."
                    }
                } else {
                    Write-Error "No Insurgency Sandstorm server processes are currently running."
                }

                # Copy config\ServerData\$serverTitle\ServerStartup.json file to InsurgencySandstorm\steamapps\common\sandstorm_server

                $sourceDir = Join-Path -Path $PSScriptRootDir -ChildPath "InsurgencySandstorm\steamapps\common\sandstorm_server"
                $destinationDir = Join-Path -Path $PSScriptRootDir -ChildPath "config\ServerData\$serverTitle"
                robocopy "$sourceDir" "$destinationDir" "ServerStartup.json" /IS | Out-Null
            }
            Receive-Job -Job $Job -Wait -AutoRemoveJob

            resize_windows

            $global:ActiveTasks--
        } else {
            # No tasks currently in queue, check if all tasks are finished
            if ($global:TaskQueue.IsEmpty -and ($global:ActiveTasks -eq 0)) {
                $global:TaskProcessingActive = $false
                Write-Host "All tasks finished. Task processor stopped." -ForegroundColor Cyan
            } else {
                # Brief pause before checking for new tasks dynamically
                Start-Sleep -Milliseconds 200
            }
        }
    }
}

<# 
    Add Servers to start to the Task Queue 
#>

function Add-TaskToQueue {
    <#
    .SYNOPSIS
    Dynamically adds a new task with exactly two parameters to the queue.
    .DESCRIPTION
    If the processor isn't running, this will optionally kick it off.
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$Param1
    )

    # Create the task payload
    $newTask = [PSCustomObject]@{
        Param1 = $Param1
        Param2 = $PSScriptRoot
    }

    # Add to FIFO Queue
    $global:TaskQueue.Enqueue($newTask)
    Write-Host "Added Task to Queue (Server_ID=$Param1)" -ForegroundColor DarkGreen

}

if (($ServerListData.PSObject.Properties).count -eq 0) {
    Write-Host ""
    Write-Host "There are no installed servers to start."
    Write-Host ""
    pause
    exit
}

$targetTitles = @()
$rebootTitles = @()

<# 
    Assemble list of servers to start from ServerList.json
    Check if any servers currently running and exclude them from start list
    Add non-running servers to Task Processor
#>

if (($ServerListData.PSObject.Properties).count -gt 0) {
    foreach ($property in $ServerListData.psobject.Properties) {
        $Server_ID = $property.Name
        $serverValue = $property.Value.Disabled

        if (-not $serverValue)
        {
            $windows_to_move += 1
            
            if (-not (Test-TargetWindowExists -Server_ID $Server_ID)) {
                $rebootTitles += @($Server_ID)

                $sourceLoopCheck = Join-Path -Path $PSScriptRoot -ChildPath "config\$Server_ID.check"

                if (Test-Path -Path $sourceLoopCheck) {
                    $currentValue = [int](Get-Content -Path $sourceLoopCheck -Raw)
                    $newValue = $currentValue + 1    
                } else {
                    $newValue = 0
                }

                Set-Content -Path $sourceLoopCheck -Value $newValue -Force

                Add-TaskToQueue -Param1 "$Server_ID"
            }
            else
            {
                $targetTitles += @($Server_ID)
            }
        }
        else
        {
            $sourceLoopCheck = Join-Path -Path $PSScriptRoot -ChildPath "config\$Server_ID.check"
            if (Test-Path -Path $sourceLoopCheck) {
                Remove-Item -Path $sourceLoopCheck -Force -ErrorAction SilentlyContinue
            }
            Write-Host "(Server_ID=$Server_ID) -=> DISABLED" -ForegroundColor DarkYellow
        }
    }
}
else
{
    Write-Host ""
    Write-Host ("{0,32}`n" -f "0 Servers Configured")-ForegroundColor DarkYellow
    pause
    exit
}

$targetTitles += $rebootTitles

if ($targetTitles.count -eq 0) {
    Write-Host ""
    Write-Host ("{0,32}`n" -f "0 Servers ENABLED")-ForegroundColor DarkYellow
    pause
    exit
}

<# 
    Start the processing loop if it's currently idle
#>

if (-not $global:TaskProcessingActive) {
    $global:TaskProcessingActive = $true
    Start-TaskProcessor
}

<# 
    Wait for all Server Tasks to finish starting all servers
#>

while ($global:TaskProcessingActive) {
    Start-Sleep -Milliseconds 500
}

Write-Host ""
Write-Host "Servers to Monitor:"

<# 
    Check to see if all servers booted properly
#>

$ServerInstances = @(Get-Process -Name InsurgencyServer-Win64-Shipping -ErrorAction SilentlyContinue | Select-Object Name, Id, MainWindowTitle, StartTime | Sort-Object -Property StartTime)
$serverOverrideButtons = @()
$serverfailed = $false

for ($i = 0; $i -lt $ServerInstances.Count; $i++) {
    $Server = $ServerInstances[$i]

    $myString = $Server.MainWindowTitle
    $pattern = @($targetTitles) -join '|'
    if ($myString -match $pattern) {
        $Title = $Matches[0]
    }
    else
    {
        $Title = "NotFound"
    }

    "[$Title] PID $($Server.Id) started $($Server.StartTime)"

    # check state.json for each server for {"Mods":[],"version":1}
    # If found then no subscribed mods and ignore $logPath checks

    $settingsPath = Join-Path "$env:LOCALAPPDATA" "mod.io.$Title\globalsettings.json"

    $StoragePath = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json

    $destination=$StoragePath.RootLocalStoragePath
    $destination=$destination.Replace('/', '\')

    $stateJsonPath = Join-Path -Path $destination -ChildPath "254\metadata\state.json"
    $getstatejson = Get-Content -Raw -Path $stateJsonPath

    if ($getstatejson -ne '{"Mods":[],"version":1}')
    {
        # Define all the strings you want to flag a server failure on
        $searchStrings = @(
            "OnCreateSessionComplete: Session: (GameSession) Result: (0)", 
            "Empty session setting ModList  : OnlineService of type String"
            "LogOnline: Warning: OSS: Async task 'FOnlineAsyncTaskSteamCreateServer bWasSuccessful: 0' failed"
        )

        # Safely define your file path
        $logPath = Join-Path -Path $PSScriptRoot -ChildPath "InsurgencySandstorm\steamapps\common\sandstorm_server\Insurgency\Saved\Logs\$Title.log"

        # Only proceed if the file actually exists
        if (Test-Path -Path $logPath) {
        
            # Pull the last 20 rows of the log file
            $logLines = Get-Content -Path $logPath -Tail 20

            # Pass the array of $searchStrings straight into the pattern.
            # -Quiet stops text array bugs and converts the result to a strict True/False boolean.
            $foundMatch = $logLines | Select-String -Pattern $searchStrings -SimpleMatch -Quiet

            # If $foundMatch evaluates to True, at least one (or both) strings were found
            if ($foundMatch) {
                # Kill the bad server process cleanly
                Stop-Process -Id $Server.Id -Force -ErrorAction SilentlyContinue
                taskkill /f /t /pid $Server.Id
                $serverfailed = $true

                $sourceLoopCheck = Join-Path -Path $PSScriptRoot -ChildPath "config\$Title.check"
                if (Test-Path -Path $sourceLoopCheck) {
                    $currentValue = [int](Get-Content -Path $sourceLoopCheck -Raw)
                    if ($currentValue -gt 4) {
                        Remove-Item -Path $sourceLoopCheck -Force -ErrorAction SilentlyContinue

                        $ServerListData.$Title.Disabled = $true
                        $ServerListJsonPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ServerList.json"
                        $ServerListData | ConvertTo-Json | Set-Content -Path $ServerListJsonPath
                    }
                }
            }
            else
            {
                $sourceLoopCheck = Join-Path -Path $PSScriptRoot -ChildPath "config\$Title.check"
                if (Test-Path -Path $sourceLoopCheck) {
                    Remove-Item -Path $sourceLoopCheck -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    $serverOverrideButtons += @($Title)
    $serverOverrideButtons += @($Server.Id)
}

<# 
    If all servers started successfully then launch Server Info Monitor and Server Taskbar
    Load Server Reeboot schedule
#>

if(-not $serverfailed)
{
    $scriptTitle = "Start_Server_Info_Monitor"
    $batchFilename = "Start_Server_Info_Monitor.bat"

    $joinedString = '"' + $infoMonitor_to_move + '"'
    $argumentPayload = "/c TITLE $scriptTitle && CALL `"$batchFilename`" $joinedString"

    $infoProcess = Start-Process "cmd.exe" -ArgumentList $argumentPayload -WorkingDirectory "$PSScriptRoot" -PassThru

    $ManagerConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ManagerConfig.json"
    $ManagerConfig=Get-Content $ManagerConfigPath -Raw | ConvertFrom-Json

    # Minimize all server windows

    if($ManagerConfig.closeServerWindows -eq 1)
    {
        $code = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
        $type = Add-Type -MemberDefinition $code -Name "Win32ShowWindowAsync" -Namespace "Win32" -PassThru
        $null = Get-Process -Name "InsurgencyServer-Win64-Shipping" -ErrorAction SilentlyContinue | ForEach-Object {
            $type::ShowWindowAsync($_.MainWindowHandle, 2)
        }
    }

    Start-Sleep -Seconds 1

    $scriptTitle = "Start_Server_Taskbar"
    $batchFilename = "Start_Server_Taskbar.bat"

    $joinedString = $serverOverrideButtons -join ';'
    $joinedString = '"' + $joinedString + '"'

    $argumentPayload = "/c TITLE $scriptTitle && CALL `"$batchFilename`" $joinedString"

    $overrideProcess = Start-Process "cmd.exe" -ArgumentList $argumentPayload -WorkingDirectory "$PSScriptRoot" -WindowStyle Hidden -PassThru # 

    $scheduledTimes = @()
    foreach ($time in $ManagerConfig.scheduledTimes) { 
        $scheduledTimes += @($time)
        $rebootTimes = $rebootTimes + $time  + " : "
    }

    if ($scheduledTimes.count -gt 0)
    {
        $rebootTimes = $rebootTimes -replace ' : $'
        Write-Host ""
        Write-Host "Reboot Schedule: $rebootTimes"
        Write-Host ""
    }
    else
    {
        Write-Host ""
        Write-Host "No Scheduled Reboot Time"
        Write-Host ""
    }
     
    $processFailed = $false

    Do {
        # wait 30 seconds before checking all servers to see if they are running
        Start-Sleep -Seconds 30

        # Get all cmd window titles
        for ($i = 0; $i -lt $targetTitles.Count; $i++) {
            $Server_ID = $targetTitles[$i]

            if(-not (Test-TargetWindowExists -Server_ID $Server_ID))
            {
                Write-Host "No active cmd process found with the window title $Server_ID."
                $processFailed = $true
            }
        }

        $forcedReboot = Join-Path -Path $PSScriptRoot -ChildPath "config\forcedReboot.check"
        if (Test-Path $forcedReboot)
        {
             Remove-Item -Path $forcedReboot -Force -ErrorAction SilentlyContinue
             $processFailed = $true
        }

        # Check if time to reboot Servers from Schedule List
        if ($scheduledTimes.count -gt 0)
        {
            # Check Scheduled times and if after Reboot all Servers
            # Get current time formatted exactly like the array items
            $currentTime = Get-Date -Format "hh:mm tt"

            # Check if the current time exists inside the array
            if ($scheduledTimes -contains $currentTime) {
                # Stop all running servers
                Stop-Process -Name "InsurgencyServer-Win64-Shipping" -Force

                Start-Sleep -Seconds 30

                for ($i = 0; $i -lt $targetTitles.Count; $i++) 
                {
                    $windowIds = Get-TargetWindowId -Server_ID $targetTitles[$i]

                    if ($windowIds) 
                    {
                        foreach ($id in $windowIds) 
                        {
                            taskkill /F /PID $id /T

                        }
                    }
                }

                $processFailed = $true 
            }
        }
    } Until ($processFailed -eq $true)
}

<# 
     Restart Start_Server_Launcher.ps1 to restart crashed servers or servers rebooted from Server Task Bar
#>

$code = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
$type = Add-Type -MemberDefinition $code -Name "Win32ShowWindowAsync" -Namespace "Win32" -PassThru
$null = Get-Process -Name "InsurgencyServer-Win64-Shipping" -ErrorAction SilentlyContinue | ForEach-Object {
    $type::ShowWindowAsync($_.MainWindowHandle, 9)
}

taskkill /F /PID $infoProcess.id /T
taskkill /F /PID $overrideProcess.id /T

$scriptTitle = "Start Server Launcher"
$batchFilename = "Start_Server_Launcher.bat"
 
Start-Process "cmd.exe" -ArgumentList "/c TITLE $scriptTitle && CALL $batchFilename" -WorkingDirectory "$PSScriptRoot"
exit