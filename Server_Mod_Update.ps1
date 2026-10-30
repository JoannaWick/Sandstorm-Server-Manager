<#PSScriptInfo
.NAME Server_Mod_Update
.AUTHOR Joanna Wick
.TAGS Sandstorm, Mods
.PROJECTURI https://github.com/JoannaWick/Sandstorm-Server-Manager
#>

param(
    [string]$server_ID
)

# Read the current OS build framework directly from memory
$buildNumber = [Environment]::OSVersion.Version.Build

#if ($buildNumber -ge 22000) {
    <# 
        Resize and center window fails on Windows 11 when other windows have focus and couldn't find a work around
    #>
<#
    Add-Type -AssemblyName System.Windows.Forms
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    # Output the width and height
    $targetWidth  = $workingArea.Width / 2
    $targetHeight = $workingArea.Height

    $posX = [math]::Round(($workingArea.Width - $targetWidth) / 2)
    $posY = [math]::Round(($workingArea.Height - $targetHeight) / 2)

    # FIX: Define both MoveWindow AND GetForegroundWindow in a single C# block
$Signature = @"
using System;
using System.Runtime.InteropServices;

public class Win32 {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
}
"@
    Add-Type -TypeDefinition $Signature -ErrorAction SilentlyContinue

    # FIX: Snag the active UI window handle directly. 
    # This completely bypasses process name filtering and permission blocks!
    $hWnd = [Win32]::GetForegroundWindow()

    if ($hWnd -ne [IntPtr]::Zero) {
        # Move and resize the current hosting cmd window frame instantly
        [void][Win32]::MoveWindow($hWnd, $posX, $posY, $targetWidth, $targetHeight, $true)
    } else {
        # Fallback to standard Mode Con formatting if running classic Conhost
        mode con: cols=120 lines=40
    }
#>
#} else {
    # Load the required .NET assembly
    Add-Type -AssemblyName System.Windows.Forms

    # Fetch the working area of the primary display
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    # Output the width and height
    $screenWidth  = ($workingArea.Width - 600)/2
    $screenHeight = ($workingArea.Height - 600)/2

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

    # Get the current cmd.exe window handle that launched Powershell process
    $parentID = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID").ParentProcessId
    $hWnd = (Get-Process -Id $parentID).MainWindowHandle

    # Move window to of screen + 2 pixels center horizontally and resize it (Width=1024, Height=max height - taskbar)
    [void][Window]::MoveWindow($hWnd, $screenWidth, $screenHeight, 600, 600, $true)
#}

function Get-DirectoryWriteInhibitionStatus {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DirectoryPath
    )

    if (-not (Test-Path -Path $DirectoryPath -PathType Container)) {
        Write-Error "Directory does not exist: $DirectoryPath"
        return
    }

    # Clean up trailing slashes for clean output paths
    $CleanPath = $DirectoryPath.TrimEnd('\', '/')

    Get-ChildItem -Path $CleanPath -File -Recurse | ForEach-Object {
        $FilePath = $_.FullName
        $Status = "Accessible" # Default assumption

        try {
            # 1. Test Write Access: Open for WRITING while allowing others to read
            $fileStream = [System.IO.File]::Open(
                $FilePath, 
                [System.IO.FileMode]::Open, 
                [System.IO.FileAccess]::Write, 
                [System.IO.FileShare]::Read
            )
            $fileStream.Close()
        }
        catch [System.UnauthorizedAccessException] {
            # File is marked read-only at the Windows OS file attribute level
            $Status = "OS Read-Only Attribute"
        }
        catch {
            # Write access failed! Now check if we can at least READ it
            try {
                $readStream = [System.IO.File]::Open(
                    $FilePath, 
                    [System.IO.FileMode]::Open, 
                    [System.IO.FileAccess]::Read, 
                    [System.IO.FileShare]::ReadWrite
                )
                $readStream.Close()
                # Readable but not writable = write-inhibited by another program
                $Status = "Write-Inhibited (In-Use but Readable)"
            }
            catch {
                # Cannot write AND cannot read = completely locked down
                $Status = "Completely Locked"
            }
        }

        # Output a clean object for every file checked
        [PSCustomObject]@{
            FileName = $_.Name
            RelativePath = $FilePath.Replace("$CleanPath\", "")
            Status   = $Status
        }
    }
}

$settingsPath = Join-Path "$env:LOCALAPPDATA" "mod.io.$server_ID\globalsettings.json"

if (Test-Path $settingsPath) {
    $StoragePath = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
}
else
{
    exit
}

$destination=$StoragePath.RootLocalStoragePath
$destination=$destination.Replace('/', '\')
$destination_Store=$destination
$verbose = 0
$global:forced_updates = 0

# Get Sandstorm OAuth Token and UserID

$userName = ("$env:LOCALAPPDATA" -split '\\')[-3]
$userName = $userName -replace ' ', ''
$mod_io_254_server="$env:LOCALAPPDATA\mod.io.$server_ID\254\ModServer\user.json" 

if (Test-Path $mod_io_254_server) {
    $getstatejson = Get-Content -Raw -Path $mod_io_254_server | ConvertFrom-Json
}
else {
    exit
}

[string]$token=$getstatejson.Oauth.token
$UserID=$getstatejson.Profile.id


$enable_testing=0 # 0 - Disabled, 1 - Test Json output 

$ModListJsonPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ModList.$server_ID.json"

if (-not(Test-Path $ModListJsonPath))
{
	$ModListData=@{}
    # Write initial ModList.json file
    # (so that the user doesn't have to go trough the setup again if the script doesn't run completely)
    $ModListData | ConvertTo-Json | Set-Content $ModListJsonPath
}

# Initialize an empty array to collect all mod data
$AllModLists = @()
$ConfigDir = Join-Path -Path $PSScriptRoot -ChildPath "config"

if (Test-Path $ConfigDir) {
    Get-ChildItem -Path $ConfigDir -Filter "ModList.*.json" -File | ForEach-Object {
        if ($_.FullName -ne $ModListJsonPath) {
            $JsonData = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json
         
            if ($null -ne $JsonData) {
                foreach ($Property in $JsonData.PSObject.Properties) {
                    $Id = $Property.Name  # Extracts "98204", "98373", etc.
                        
                    # 2. Add to array if it is not already in the scan list
                    if ($Id -notin $AllMods) {
                        $AllMods += $Id
                    }
                }
            }
        }
    }
}

$ManagerConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ManagerConfig.json"
$global:ManagerConfig = Get-Content $ManagerConfigPath -Raw | ConvertFrom-Json

# Check for midding configuration element and add if missing

echo ""
echo "=============================================="
echo "       Downloading your Subscriptions         "
echo "=============================================="
echo ""

Start-Sleep -Milliseconds 1000

if (Test-Path $ModListJsonPath)
{
    echo "Reading settings from ModList.$server_ID.json."
    echo ""
    $ModListData=Get-Content $ModListJsonPath | ConvertFrom-Json
}

if(-not(Test-Path "$destination"))
{
   $null=mkdir "$destination" -ErrorAction SilentlyContinue
}

$serverDownloadedMods = "$destination"+"254\mods\"
if (Test-Path -Path $serverDownloadedMods) {
    # Fetches everything inside the folder and removes them recursively
    Get-ChildItem -Path $serverDownloadedMods -Recurse | Remove-Item -Recurse -Force
}

$destinationMods = Join-Path -Path $PSScriptRoot -ChildPath "mods\UnifiedMods"
$destinationMods = $destinationMods + "\"

$isNetworkMonitor = $false

$error_success_msg=@()
$error_warning_msg=@()
$error_fatal_msg=@()
$error_success = 0
$error_warning = 0
$error_fatal = 0

$totalMBdownloaded = 0
$totalMBdiskStorage = 0
$totalTimeDownloading = 0

$dataOffset=0
$dataLimit=100
$workingHash = @{}
$workingHash.WorkArray = @()
$workingHashCounter=0

Do {
    $queryParams = @{
        "_limit" = $dataLimit
        "_offset" = $dataOffset
    }

    try {
        $sublist_json=Invoke-WebRequest -UseBasicParsing -URI https://api.mod.io/v1/me/subscribed?game_id=254 -Body $queryParams -Method GET -Headers @{"Authorization"="Bearer ${token}";"Accept"="application/json"}
        $sublist=ConvertFrom-Json $sublist_json.Content
    }
    catch {
        Write-Error "API request or JSON parsing failed: $_"
        Exit 1 # Exits the entire script immediately with an error code
    }

    $dataOffset   = $sublist.result_offset + $sublist.result_count
    $totalResults = $sublist.result_total
    $workingHash.WorkArray += $null
    $workingHash.WorkArray[$workingHashCounter] = $sublist.psobject.Copy()
    $workingHashCounter = $workingHashCounter + 1

    Start-Sleep -Milliseconds 250

} Until (($dataOffset) -ge $totalResults)

# Initial state.json array for Sandstorm

$jsonObject = [PSCustomObject]@{
    "Mods" = @(
    )
    "version" = 1
}

$result_total = $workingHash.WorkArray[0].result_total

for ($i = 1; $i -le $result_total; $i++) {
    $newMod = [ordered]@{
        Profile = [ordered]@{
            # Add specific key-value pairs here if needed
        }
    }
    
    # Append the object to the mods array
    $jsonobject.mods += $newMod
}

$dataOffset=0
$dataLimit=25
$count_of_files = 0
$ModListData_delete_comparison=@{}

# Get how many pages of mods found
$PageCount=$workingHash.WorkArray.length
if ($PageCount -ne 1)
{
    $plural="s"
}
else
{
    $plural=""
}
[string]$Page_Count=$PageCount
echo "Found $Page_Count Subscription Page$plural."
echo ""

[string]$resulttotal=$result_total
if ($result_total -ne 1)
{
    $plural="s"
}
else
{
    $plural=""
}
echo "Found $resulttotal Subscription$plural."
echo ""

for ($p = 0; $p -lt $PageCount; $p++)
{

    # Get current hashtable element count
    $len=$workingHash.WorkArray[$p].result_count

    for ($i = 0; $i -lt $len; $i++)
    {
        echo "=============================================="
        $sub=$workingHash.WorkArray[$p].data[$i]
        $subname=$sub.name

        # Variables and Data to be transfered from mod.io state.json to Sandstorm state.json

        $jsonObject.Mods[$count_of_files]["ID"]=$sub.id
        $jsonObject.Mods[$count_of_files]["NeverRetryCategory"]=0
        $jsonObject.Mods[$count_of_files]["NeverRetryCode"]=0
        $jsonObject.Mods[$count_of_files]["PathOnDisk"]=$destinationMods+$sub.id
        $jsonObject.Mods[$count_of_files]["Profile"]["date_added"]=$sub.date_added
        $jsonObject.Mods[$count_of_files]["Profile"]["date_live"]=$sub.date_live
        $jsonObject.Mods[$count_of_files]["Profile"]["date_updated"]=$sub.date_updated
        $jsonObject.Mods[$count_of_files]["Profile"]["description"]=$sub.description
        $jsonObject.Mods[$count_of_files]["Profile"]["description_plaintext"]=$sub.description_plaintext
        $jsonObject.Mods[$count_of_files]["Profile"]["id"]=$sub.id
        $jsonObject.Mods[$count_of_files]["Profile"]["logo"]=$sub.logo
        $jsonObject.Mods[$count_of_files]["Profile"]["maturity_option"]=0
        $jsonObject.Mods[$count_of_files]["Profile"]["media"]=$sub.media
        $jsonObject.Mods[$count_of_files]["Profile"]["metadata_blob"]=""
        $jsonObject.Mods[$count_of_files]["Profile"]["metadata_kvp"]=$sub.metadata_kvp

        $jsonObject.Mods[$count_of_files]["Profile"]["modfile"]=$sub.modfile
        $jsonObject.Mods[$count_of_files]["Profile"]["modfile"].PSObject.Properties.Remove("date_updated")
        $jsonObject.Mods[$count_of_files]["Profile"]["modfile"].PSObject.Properties.Remove("date_scanned")
        $jsonObject.Mods[$count_of_files]["Profile"]["modfile"].PSObject.Properties.Remove("virustotal_hash")
        $jsonObject.Mods[$count_of_files]["Profile"]["modfile"].PSObject.Properties.Remove("filehash")
        $jsonObject.Mods[$count_of_files]["Profile"]["modfile"]["md5"].PSObject.Properties.Remove("md5")
        $jsonObject.Mods[$count_of_files]["Profile"]["modfile"].PSObject.Properties.Remove("platforms")

        $jsonObject.Mods[$count_of_files]["Profile"]["name"]=$sub.name

        $jsonObject.Mods[$count_of_files]["Profile"]["stats"]=$sub.stats
        $jsonObject.Mods[$count_of_files]["Profile"]["stats"].PSObject.Properties.Remove("mod_id")
        $jsonObject.Mods[$count_of_files]["Profile"]["stats"].PSObject.Properties.Remove("downloads_today")
        $jsonObject.Mods[$count_of_files]["Profile"]["stats"].PSObject.Properties.Remove("downloads_unique")
        $jsonObject.Mods[$count_of_files]["Profile"]["stats"].PSObject.Properties.Remove("date_expires")

        $jsonObject.Mods[$count_of_files]["Profile"]["submitted_by"]=$sub.submitted_by
        $jsonObject.Mods[$count_of_files]["Profile"]["submitted_by"].PSObject.Properties.Remove("name_id")
        $jsonObject.Mods[$count_of_files]["Profile"]["submitted_by"].PSObject.Properties.Remove("date_joined")
        $jsonObject.Mods[$count_of_files]["Profile"]["submitted_by"].PSObject.Properties.Remove("timezone")
        $jsonObject.Mods[$count_of_files]["Profile"]["submitted_by"].PSObject.Properties.Remove("language")

        $jsonObject.Mods[$count_of_files]["Profile"]["summary"]=$sub.summary

        $jsonObject.Mods[$count_of_files]["Profile"]["tags"]=$sub.tags
        $tlen=$sub.tags.count
        for ($t = 0; $t -lt $tlen; $t++) {
            $jsonObject.Mods[$count_of_files]["Profile"]["tags"][$t].PSObject.Properties.Remove("name_localized")
            $jsonObject.Mods[$count_of_files]["Profile"]["tags"][$t].PSObject.Properties.Remove("date_added")
        }

        $jsonObject.Mods[$count_of_files]["Profile"]["profile_url"]=$sub.profile_url
        $jsonObject.Mods[$count_of_files]["Profile"]["visible"]=$sub.visible
        $jsonObject.Mods[$count_of_files]["SizeOnDisk"]=$sub.modfile.filesize_uncompressed
        $jsonObject.Mods[$count_of_files]["State"]=1
        $jsonObject.Mods[$count_of_files].SubscriptionCount = @(55681422)

        if($verbose -eq 1)
        {
            echo ""
        }
        $count_of_files++
        echo "Processing $count_of_files of $result_total Subscriptions : $subname"

    	[string]$modid=$sub.id
        [string]$modFilename=$sub.modfile.filename
        [string]$moddate_added_display=[DateTimeOffset]::FromUnixTimeSeconds($sub.modfile.date_added).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")
        [string]$moddate_added=$sub.modfile.date_added
        [string]$modVersion=$sub.modfile.version
        [string]$modURL=$sub.modfile.download.binary_url
        [string]$modFilesize="{0:N2}" -f ($sub.modfile.filesize / 1MB)

        if($verbose -eq 1)
        {
            echo ""
            echo "modid: $modid"
            echo "modFilename: $modFilename"
            echo "filesize: $modFilesize MB"
            echo "moddate_added: $moddate_added_display"
            echo "modVersion: $modVersion"
            echo "modURL: $modURL"
        }

      	# Write data about this sub to ModListData

       	$update=$true
        if ($ModListData.${modid} -eq $null)
        {
	        $ModListData | Add-Member -Name $modid -Value @{} -MemberType NoteProperty
   		    $ModListData.${modid}.date_added=$moddate_added
            $ModListData.${modid}.name = $sub.name
        }
        elseif ($moddate_added -le $ModListData.${modid}.date_added){
	        $update=$false #already up to date
        }
        else
        {
	        $ModListData.${modid}.date_added=$moddate_added
        }

        if($verbose -eq 1)
        {
           echo ""
        }

      	$file=$modFilename
        $directory_ID=$modid
        $ModListData_delete_comparison | Add-Member -Name $modid -Value @{} -MemberType NoteProperty

      	if(-not(Test-Path "$destinationMods$directory_ID"))
        {
           	$null=mkdir "$destinationMods$directory_ID" -ErrorAction SilentlyContinue

            if ($AllMods -contains [string]$modid) {
                $update=$false
            }
            else
            {
                $update=$true
            }
        }

        # if file already downloaded and in use by another server bypass the download

        $StuckFiles = Get-DirectoryWriteInhibitionStatus -DirectoryPath "$destinationMods$directory_ID" | Where-Object { $_.Status -eq "Write-Inhibited (In-Use but Readable)" }

        if ($StuckFiles) 
        {
            $update=$false
        }

       	if ($update)
        {
   	        Write-Host "  Downloading $subname - $directory_ID - $modFilename - $modFilesize MB" -ForegroundColor Yellow
	        echo ""

# Explicitly load the missing HTTP assembly into the current session
Add-Type -AssemblyName System.Net.Http

$elapsedTime = Measure-Command {
    # Initialize the modern web client handler using the type accelerator
    $httpClient = [System.Net.Http.HttpClient]::new()
    
    try {
        # Send request and pull the raw web data stream
        $responseTask = ($httpClient.GetAsync($modURL, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead))
        $response = $responseTask.GetAwaiter().GetResult()
        
        # Get true file size from headers (fallback to 0 if hidden)
        $totalBytes = if ($response.Content.Headers.ContentLength) {$response.Content.Headers.ContentLength } else { 0 }
        $totalMb = $totalBytes / 1MB

        $responseStreamTask = $response.Content.ReadAsStreamAsync()
        $responseStream = $responseStreamTask.GetAwaiter().GetResult()

        # Ensure \$modFilename isn't empty to prevent null file crashes
        if ([string]::IsNullOrWhiteSpace($modFilename)) {
            throw "The variable `$modFilename is empty. Cannot create a file with no name."
        }

        # Use an ABSOLUTE path for .NET compatibility
        $targetFolder = Join-Path $PSScriptRoot "zip" 
        if (-not (Test-Path $targetFolder)) { New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null }
        $absoluteFilePath = Join-Path $targetFolder $modFilename

        # Create local zip destination file payload layout securely
        $fileStream = [System.IO.File]::Create($absoluteFilePath)

        # Set a 64KB transit memory buffer block size
        $buffer = New-Object Byte[] 65536
        $bytesReceived = 0

        # Start a high-precision stopwatch to track live speed and ETA
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Actively copy chunks to disk and calculate numbers raw
        while (($bytesRead = $responseStream.Read($buffer, 0, $buffer.Length)) -gt 0) {$fileStream.Write($buffer, 0,$bytesRead)
            $bytesReceived += $bytesRead
            
            $mbReceived = $bytesReceived / 1MB
            $elapsedSec = $stopwatch.Elapsed.TotalSeconds

            if ($totalBytes -gt 0) {$percent = ($bytesReceived / $totalBytes) * 100
                
                # Calculate live speed and estimated time remaining
                if ($elapsedSec -gt 0.1) {$bytesPerSec = $bytesReceived / $elapsedSec
                    $bytesRemaining = $totalBytes - $bytesReceived
                    $secondsLeft = [Math]::Max(0, ($bytesRemaining / $bytesPerSec))
                    
                    # Format time cleanly as MM:SS
                    $etaTime = [TimeSpan]::FromSeconds($secondsLeft)
                    $etaString = "{0:D2}m:{1:D2}s" -f $etaTime.Minutes, $etaTime.Seconds
                } else {
                    $etaString = "--m:--s"
                }

                Write-Host ("`r  Downloaded: {0:N2} MB of {1:N2} MB ({2:N2}%) | ETA: {3}" -f $mbReceived, $totalMb, $percent, $etaString) -NoNewline
            } else {
                # Fallback layout if the web server hides the file size header
                Write-Host ("`r  Downloaded: {0:N2} MB (Total size unknown)" -f $mbReceived) -NoNewline
            }
        }
    }
    catch {
        # This catches errors that Measure-Command normally hides
        Write-Error "A terminating error occurred: \$_"
    }
    finally {
        # Clean up file handlers cleanly and reliably even if a crash happens
        if ($null -ne $stopwatch) {$stopwatch.Stop() }
        if ($null -ne $fileStream) { $fileStream.Close(); $fileStream.Dispose() }
        if ($null -ne $responseStream) { $responseStream.Close(); $responseStream.Dispose() }
        if ($null -ne $httpClient) { $httpClient.Dispose() }
        
        Write-Host "" # Break line safely on finish
        Write-Host "" # Break line safely on finish
    }
}

            # Calculate file size and download metrics
            $fileSizeInBytes = (Get-Item "zip\$modFilename").Length
            $totalSeconds = $elapsedTime.TotalSeconds
            $totalMBdownloaded += $fileSizeInBytes
            $totalTimeDownloading += $totalSeconds
            
            # Convert bytes to Megabits (Mb) for industry standard network speed (Mbps)
            $fileSizeInBits = $fileSizeInBytes * 8
            $megabits = $fileSizeInBits / 1MB
            $speedMbps = [Math]::Round(($megabits / $totalSeconds), 2)

            # Display the results and clean up the test file
            Write-Host "  Download complete!" -ForegroundColor Green
            Write-Host "  Time Elapsed  : $([Math]::Round($totalSeconds, 2)) seconds" -ForegroundColor White
            Write-Host "  Download Speed: $speedMbps Mbps" -ForegroundColor White
	        echo ""

           	Write-Host "  Unpacking $subname - $directory_ID - $modFilename" -ForegroundColor Cyan

            .\bin\7za.exe x "zip\$modFilename" -o"$destinationMods$directory_ID" -aoa -y

            if ($LASTEXITCODE -eq 0) {
                Write-Host "Success: Archive extracted with no errors." -ForegroundColor Green
                $error_success_msg += "Success: $subname - $directory_ID - $modFilename no errors."
                $error_success++
            } elseif ($LASTEXITCODE -eq 1) {
                $error_warning_msg += "Warning: Non-fatal error $subname - $directory_ID - $modFilename"
                $error_warning++
            } else {
                $error_fatal_msg += "Failure: $subname - $directory_ID - $modFilename code $LASTEXITCODE."
                $error_fatal++
            }

            $dirSize = (Get-ChildItem "$destinationMods$directory_ID" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $totalMBdiskStorage += $dirSize

            Remove-Item -Path "zip\$modFilename"
   	    }
        else
        {
   	        Write-Host "Skipped $subname up to date" -ForegroundColor Green
        }
    }
    $dataOffset+=$dataLimit
}

# Export new state.json file for Sandstorm

# Convert your object to JSON
$jsonc = $jsonObject | ConvertTo-Json -Compress -Depth 100

# Fix ONLY Unicode characters (e.g., \u0027) while keeping literal \n untouched
$cleanJson = [regex]::Replace($jsonc, '\\u([0-9a-fA-F]{4})', { 
    param($match) [char][int]"0x$($match.Groups[1].Value)" 
})

#$destinationMetadata=$destinationMods -replace '(.*)mods\\(.*)$', '${1}metadata\$2'
$destinationMetadata="$destination"+"254\metadata\"
$jsonfilename="state.json"

Rename-Item -Path "$destinationMetadata$jsonfilename" -NewName ("state_{0:yyyyMMdd_HHmmss}.json" -f (Get-Date))

# Export to a valid UTF-8 file
$cleanJson | Out-File "$destinationMetadata$jsonfilename" -Encoding utf8

$cleanupPath = "$destination\254\metadata"
Get-ChildItem -Path "$cleanupPath" -File | Sort-Object LastWriteTime -Descending | Select-Object -Skip 12 | Remove-Item -Force

# Display Total DL Time, Total GB downloaded, Total Disk Space Used 
echo "=============================================="
echo ""
$formattedTime = (New-TimeSpan -Seconds $totalTimeDownloading).ToString("mm\:ss")
Write-Host "Total Download Time: $formattedTime" -ForegroundColor Cyan
$diskStorageInGB = [Math]::Round(($totalMBdownloaded / 1GB), 2)
Write-Host "Total Download Size: $diskStorageInGB GB" -ForegroundColor Green
$diskStorageInGB = [Math]::Round(($totalMBdiskStorage / 1GB), 2)
Write-Host "Total Disk Storage : $diskStorageInGB GB" -ForegroundColor Yellow
echo ""

# Display Successful Downloaded and Installed message for each mod file
if ($error_success -ne 0) {
    echo "=============================================="
    Write-Host "Successfully Installed: $error_success file(s)" -ForegroundColor Green
    echo ""
    $error_success_msg | ForEach-Object { "$_" }
}

# Display WARNING about zip file for each mod
if ($error_warning -ne 0) {
    echo "=============================================="
    Write-Warning "Warning: $error_warning file(s)"
    echo ""
    $error_warning_msg | ForEach-Object { "$_" }
}

# Display mod files that had errors while unzipping
if ($error_fatal -ne 0) {
    echo "=============================================="
    echo "Error: $error_fatal file(s)"
    echo ""
    echo "If a CRC-ERROR files may have extracted without a problem."
    echo "Scroll up to find the mod to verify."
    echo ""
    $error_fatal_msg | ForEach-Object { "$_" }
}

# If any mods are missing from the mod.io subscribed list
# when compared to the stored ModList.json the missing files
# will be removed from the ModList.json and the directories 
# will be deleted from the computer.  Compare $ModListData with
# $ModListData_delete_comparison and remove directories of
# missing mods.

echo ""
echo "=============================================="
echo "        Checking for Unsubscribed Mods        "
echo "=============================================="
echo ""

$deletedMods=0

foreach ($item in $ModListData) {

    # Get each dynamic top element name and value
    foreach ($property in $item.PSObject.Properties) {
        $modDeleteID = $property.Name
        $modDeleteValue = $property.Value

        # Check if the value is a nested object/custom object
        if ($modDeleteValue -is [System.Management.Automation.PSCustomObject]) {
            
            # Extract nested names and values
            foreach ($nestedProp in $modDeleteValue.PSObject.Properties) {
                if($($nestedProp.Name) -eq "name")
                {
                    $modDeleteName = $($nestedProp.Value)
                }
            }
        }
 
        if ($ModListData_delete_comparison.${modDeleteID} -eq $null)
        {
            if ($AllMods -notcontains [string]$modid) 
            {
             	if(-not(Test-Path "$destinationMods$modDeleteID"))
                {
                    Write-Host "Mod: $modDeleteID - $modDeleteName not found" -ForegroundColor Yellow
                }
                else
                {
                    Write-Host "Deleting Unsubscribed Mod: $modDeleteID - $modDeleteName" -ForegroundColor Red
                    Remove-Item -Path "$destinationMods$modDeleteID" -Recurse -Force
                }
            }

            $ModListData.PSObject.Properties.Remove($modDeleteID)
            $deletedMods+=1
        }
    }
}

if ($deletedMods -eq 0)
{
    Write-Host "No Unsubscribed Mods found." -ForegroundColor Green
}

# Update ModList.json 
$ModListData | ConvertTo-Json | Set-Content $ModListJsonPath

echo ""
echo "=============================================="
echo "      Sandstorm Mod File Update Complete      "
echo "=============================================="
echo ""


