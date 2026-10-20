<#PSScriptInfo
.NAME Server_Manager
.VERSION 1.1.0
.AUTHOR Joanna Wick
.TAGS Sandstorm, Server
.PROJECTURI https://github.com/JoannaWick/Sandstorm-Server-Manager
#>

param(
    [string]$batchLaunch=0
)

$Version = "1.1.0"

<# 
    Resize and center window
#>

# Read the current OS build framework directly from memory
$buildNumber = [Environment]::OSVersion.Version.Build

if ($buildNumber -ge 22000) {

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

    $hWnd = [Win32]::GetForegroundWindow()

    if ($hWnd -ne [IntPtr]::Zero) {
        # Move and resize the current hosting cmd window frame instantly
        [void][Win32]::MoveWindow($hWnd, $posX, $posY, $targetWidth, $targetHeight, $true)
    } else {
        # Fallback to standard Mode Con formatting if running classic Conhost
        mode con: cols=120 lines=40
    }
} else {
    Add-Type -AssemblyName System.Windows.Forms

    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    $screenWidth  = ($workingArea.Width-1024)/2
    $screenHeight = $workingArea.Height

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
    # Move window to of screen + 2 pixels center horizontally and resize it (Width=1024, Height=max height - taskbar)
    [void][Window]::MoveWindow($hWnd, $screenWidth, 2, 1024, $screenHeight, $true)
}

<#
    Create ServerList.json if not found
#>

$ServerListJsonPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ServerList.json"

if (-not(Test-Path $ServerListJsonPath))
{
    # Create ServerList.json 
    $global:SeverListData=@{}
    $global:SeverListData | ConvertTo-Json | Set-Content $ServerListJsonPath
}

$global:SeverListData=Get-Content $ServerListJsonPath -Raw | ConvertFrom-Json

<# 
    Used to simplify y/n prompts
#>

function User-Confirm
{
	param ([string]$msg)

    Write-Host "$msg [Y/N]: " -NoNewline

    while ($true) {
        # Capture a single keypress invisibly
        $key = [Console]::ReadKey($true).KeyChar

        # Process and exit the loop on a valid match
        if ($key -match '^[Yy]$') {
            Write-Host "Y" -ForegroundColor Green
            return 'y'
        }
        if ($key -match '^[Nn]$') {
            Write-Host "N" -ForegroundColor Red
            return 'n'
        }
    }
}

<#
    Word Wrap long text lines and allow for fore and background colors
#>

function Write-WrappedHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        
        [string]$ForegroundColor = 'Gray',
        
        [string]$BackgroundColor = 'Black'
    )

    # Get the current console buffer width, subtracting 1 to avoid forcing a newline
    $width = $Host.UI.RawUI.WindowSize.Width - 1

    # Split the string by spaces to get all individual words
    $words = $Text -split ' '

    $spaceCount = $Text.Length - $Text.TrimStart().Length
    $currentLine = (" " * ($spaceCount/2))

    foreach ($word in $words) {
        # Test if adding the next word exceeds the window width
        if (($currentLine.Length + $word.Length + 1) -gt $width) {
            # Print current line, then reset
            Write-Host $currentLine -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
            $currentLine = $word
        } else {
            # Otherwise, append the word with a space
            if ($currentLine) { $currentLine += " " }
            $currentLine += $word
        }
    }
    # Output the remaining text
    if ($currentLine) {
        Write-Host $currentLine -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
    }
}

<#
    Add or Update ServerList.json with Server_ID and/or Patch to InsurgencyServer.exe
#>

function add_update_server
{
    param(
        [string]$Server_ID,
        [bool]$isDisabled = $false
    )

    if ($global:SeverListData.${Server_ID} -eq $null)
    {
        $global:SeverListData | Add-Member -Name $Server_ID -Value @{} -MemberType NoteProperty
        $global:SeverListData.${Server_ID}.Disabled=$isDisabled
    }
    else
    {
        $global:SeverListData.${Server_ID}.Disabled=$isDisabled
    }

    $global:SeverListData | ConvertTo-Json | Set-Content $ServerListJsonPath
    $global:SeverListData = Get-Content $ServerListJsonPath -Raw | ConvertFrom-Json
}

function restore_server_userjson
{

    do {
        Clear-Host
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "          Restore user.json Backup         " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host ""

        [int]$global:Server_List_Count = show_server_list
        $exitSelection = $global:Server_List_Count + 1
        Write-Host " $exitSelection. Exit Restore user.json Backup" -ForegroundColor DarkYellow
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host ""

        [int]$selection = Read-Host -Prompt " Please enter your selection (1-$exitSelection)"
    
        if(($selection -gt 0) -and ($selection -le $global:Server_List_Count))
        {
            $downOne = $selection - 1
            Write-Host ""
            $countup = 0
            foreach ($item in $global:SeverListData) {
                
                # Get each dynamic top element name and value
                foreach ($property in $item.PSObject.Properties) {
                    $server_ID = $property.Name
                    if ($countup -eq $downOne)
                    {
                        $Base_Server_ID = $server_ID
                        $isDisabled = $property.Value.Disabled
                    }
                    $countup = $countup + 1
                }
            }

            Write-Host "==============================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host ("{0,24} {1,-60}" -f "Server ID: ", "$Base_Server_ID") -ForegroundColor Yellow
            Write-Host ""


            $SourceServerDir = "$env:LOCALAPPDATA\mod.io.$Base_Server_ID\254\ModServer"

            if (Test-Path -Path $SourceServerDir) {
    
                $userList = [System.Collections.Generic.List[string]]::new()

                $SelectedFiles = Get-ChildItem -Path $SourceServerDir -Filter "user*.json" -File | 
                Where-Object { $_.Name -ne "user.json" }

                foreach ($File in $SelectedFiles) {
                    $userJsonName = $File.Name 
                    [void]$userList.Add($userJsonName + (' ' * 50))
                }

                $userList.Sort()
                $userList.Reverse()

                $selectedFile = mod_GUI_selector -ModList $userList -GUItitle "Select user[DATE].json file to restore. (Most Recent First)" -multiSelect $false -nameUsed "user.json"

                # Output what the user selected (if anything)
                if ($SelectedFile) {
                    Write-Host "You selected the following file: " -NoNewline -ForegroundColor Green
                    Write-host "$SelectedFile" -ForegroundColor Yellow
                    Write-Host ""

                    $response = User-Confirm "Last Chance: Do you really want to replace user.json with this backup?"

                    if ($response -eq 'y') 
                    {
                        $SourceFile = Join-Path -Path $SourceServerDir -ChildPath "$SelectedFile"
                        $DestinationFile = Join-Path -Path $SourceServerDir -ChildPath "user.json"
    
#                        Copy-Item -Path $SourceFile -Destination $DestinationFile -Force

                        Write-Host ""
                        Write-Host "user.json replaced with  " -NoNewline -ForegroundColor Green
                        Write-host "$SelectedFile" -ForegroundColor Yellow
                    }
                    else
                    {
                        Write-Host "Copy was canceled." -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "No files were selected or the window was canceled." -ForegroundColor Yellow
                }

            } else {
                Write-Warning "The directory does not exist: $SourceServerDir"
            }

            Write-Host ""
            pause
        }
    } until ($selection -eq $exitSelection -or -not($selection))
}

function disable_server
{

    do {
        Clear-Host
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "         Disable/Enable Server Toggle         " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host ""

        [int]$global:Server_List_Count = show_server_list
        $exitSelection = $global:Server_List_Count + 1
        Write-Host " $exitSelection. Disable/Enable Server Toggle" -ForegroundColor DarkYellow
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host ""

        [int]$selection = Read-Host -Prompt " Please enter your selection (1-$exitSelection)"
    
        if(($selection -gt 0) -and ($selection -le $global:Server_List_Count))
        {
            $downOne = $selection - 1
            Write-Host ""
            $countup = 0
            foreach ($item in $global:SeverListData) {
                
                # Get each dynamic top element name and value
                foreach ($property in $item.PSObject.Properties) {
                    $server_ID = $property.Name
                    if ($countup -eq $downOne)
                    {
                        $Base_Server_ID = $server_ID
                        $isDisabled = $property.Value.Disabled
                    }
                    $countup = $countup + 1
                }
            }

            Write-Host "==============================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host ("{0,24} {1,-60}" -f "Server ID: ", "$Base_Server_ID") -ForegroundColor Yellow
            Write-Host ""

            if ($isDisabled) {
                $statusText = "ENABLE"
            } else {
                $statusText = "DISABLE"
            }

            $response = User-Confirm "Do you wish to $statusText Server Boot?"
                
            if ($response -eq 'y') {
                if ($isDisabled)
                {
                    $isDisabled = $false
                }
                else
                {
                    $isDisabled = $true
                }

                add_update_server -Server_ID $Base_Server_ID -isDisabled $isDisabled
            }
        }
    } until ($selection -eq $exitSelection -or -not($selection))
}

<#
    GUI for selecting where to store Mod.io mod files with Default of C:\Users\Public
#>

function Modio_mod_directory
{
    param(
        [bool]$is_New_Server = $false,
        [string]$directoryPath =$null,
        [string]$guiTitle
    )

	# Load the Windows Forms assembly quietly
	Add-Type -AssemblyName System.Windows.Forms

    # Create a dummy form to act as the owner and force focus
    $parentForm = New-Object System.Windows.Forms.Form -Property @{TopMost = $true}
    $parentForm.TopLevel = $true
    $parentForm.ShowInTaskbar = $true
    $parentForm.StartPosition = "CenterParent"
    $parentForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $parentForm.MaximizeBox = $false
    $parentForm.MinimizeBox = $false
    $parentForm.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250) # Dark Theme

	# Create the folder browser dialog object
	$FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog

    if ($null -ne $directoryPath)
    {
        $FolderBrowser.SelectedPath = "$directoryPath"
        $FolderBrowser.RootFolder = [System.Environment+SpecialFolder]::Desktop

        # Create a background keystroke loop to force the tree view to expand and jump
        $Shell = New-Object -ComObject WScript.Shell
        $Task = Start-Job -ScriptBlock {
            Start-Sleep -Milliseconds 250
            # Tabs over to the directory tree panel and strikes the Right Arrow key to expand
            (New-Object -ComObject WScript.Shell).SendKeys("{TAB}{TAB}{RIGHT}")
        }
    }

  	# Set custom prompt description text
    $FolderBrowser.Description = $guiTitle

	# Show the 'New Folder' button inside the GUI
	$FolderBrowser.ShowNewFolderButton = $true

	# Open the GUI dialog and check if the user clicked 'OK'
	if ($FolderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) 
    {
       # Store the selected folder path in a variable
 	    $destination = $FolderBrowser.SelectedPath
 	    $destination = $destination.TrimEnd('\')
    }
    else
    {
        if($is_New_Server)
        {
            $destination = $false
        }
        else
        {
            if ([string]::IsNullOrWhiteSpace($directoryPath)) 
            {
                $destination="C:\Users\Public"
            }
            else
            {
                $destination = $directoryPath
            }
        }
    }

    # Cleanup
    $parentForm.Dispose()
    $FolderBrowser.Dispose()
    return $destination
}

<#
    filebrowser_GUI -directoryPath  -guiTitle  -filter  -allowNoEntry
#>

function filebrowser_GUI
{
    param(
        [string]$directoryPath,
        [string]$guiTitle,
        [string]$filter = "(*.*)|*.*"
    )

    Add-Type -AssemblyName System.Windows.Forms

    # Fetch the working area of the primary display
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    # Output the width and height
    $screenHeight = $workingArea.Height/2

    # Create a hidden wrapper form set to center on the screen
    $AnchorForm = New-Object System.Windows.Forms.Form
    $AnchorForm.StartPosition = "CenterScreen"
    $AnchorForm.Size = New-Object System.Drawing.Size(1024, $screenHeight)
    $AnchorForm.FormBorderStyle = "None"
    $AnchorForm.Opacity = 0
    $AnchorForm.MaximizeBox = $false
    $AnchorForm.MinimizeBox = $false
    $AnchorForm.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250) # Dark Theme

    # Display the dialog attached to the centered parent form
    $AnchorForm.Add_Shown({
        $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog
        $FileBrowser.Title = $guiTitle
        $FileBrowser.InitialDirectory = $directoryPath
        $FileBrowser.Filter = $filter
        $FileBrowser.FilterIndex = 1

        $DialogResult = $FileBrowser.ShowDialog($AnchorForm)

        if ($DialogResult -eq "OK") {
            # Store selection in a global scope to access outside the event hook
            $script:SelectedFile = $FileBrowser.FileName
        }
        else
        {
            $script:SelectedFile = $false
        }
        $AnchorForm.Close()
    })

    # Execute the form 
    [void]$AnchorForm.ShowDialog()

    # Cleanup
    $AnchorForm.Dispose()
    return $script:SelectedFile
}

<#
    Check if these entries are in Engine.ini and if not insert them
#>

function engineINIcheck
{
    param(
        [string]$section,
        [string[]]$settingsToAdd = @(),
        [string]$filePath
    )

    # Read file lines
    $lines = Get-Content -Path $filePath
    $newLines = New-Object System.Collections.Generic.List[string]
    $inSection = $false
    $sectionFound = $false
    $addedSettings = New-Object System.Collections.Generic.List[string]

    # Track which settings already exist in the target section
    foreach ($setting in $settingsToAdd) {
        $itemToCheck = $setting.Split('=')[0]
        $exists = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq $section) { $inSection = $true; continue }
            if ($inSection -and $lines[$i].Trim().StartsWith("[")) { $inSection = $false }
            if ($inSection -and $lines[$i].Trim() -like "$itemToCheck*") { $exists = $true }
        }
        if (-not $exists) { $addedSettings.Add($setting) }
        $inSection = $false
    }

    # Rebuild file content and insert missing settings right after [Core.Log]
    $inSection = $false
    foreach ($line in $lines) {
        $newLines.Add($line)
        if ($line.Trim() -eq $section) {
            $sectionFound = $true
            $inSection = $true
            continue
        }
        if ($inSection -and $line.Trim().StartsWith("[")) {
            # Reached next section, insert missing ones before leaving
            foreach ($missing in $addedSettings) {
                $newLines.Insert($newLines.Count - 1, $missing)
            }
            $inSection = $false
        }
    }

    # If [Core.Log] is the very last section in the file
    if ($sectionFound -and $inSection) {
        foreach ($missing in $addedSettings) {
            $newLines.Add($missing)
        }
    } elseif (-not $sectionFound) {
        # If section doesn't exist at all, append it with settings
        $newLines.Add($section)
        foreach ($setting in $settingsToAdd) {
            $newLines.Add($setting)
        }
    }

    # Save updated lines back to file
    $newLines | Set-Content -Path $filePath
}

<#
    Build and save ModList.json for new and imported servers
#>

function build_ModList
{
    param(
        [string]$server_ID
    )

    $settingsPath = Join-Path "$env:LOCALAPPDATA" "mod.io.$server_ID\globalsettings.json"

    if (Test-Path $settingsPath) {
        $StoragePath = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
    }
    else
    {
        Write-Error "globalsettings.json File Missing at $settingsPath"
        Write-Error "Exiting"
        Pause
        exit
    }

    $destination=$StoragePath.RootLocalStoragePath
    $destination=$destination.Replace('/', '\')

    $finalpath = Join-Path -Path $destination -ChildPath "254\metadata\state.json"

    if (Test-Path $finalpath) {
        $getstatejson = Get-Content -Raw -Path $finalpath | ConvertFrom-Json
    }
    else
    {
        Write-Error "state.json File Missing at $finalpath"
        Write-Error "Exiting"
        Pause
        exit
    }

    $ModListJsonPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ModList.$server_ID.json"

	$ModListData=@{}
    # Write initial ModList.json file
    # (so that the user doesn't have to go trough the setup again if the script doesn't run completely)
    $ModListData | ConvertTo-Json | Set-Content $ModListJsonPath

    # Scan state.json building initial ModList.json so mods not downloaded on first run.
    $ModListData=Get-Content $ModListJsonPath | ConvertFrom-Json
    # Loop through the Mods array and change the path
    $getstatejson.Mods | ForEach-Object {
        # Replace the path with the C: drive (adjust folder structure as needed)
        $subname = $_.PSObject.Properties['Profile'].Value
        $modid = $subname.modfile.'mod_id'
        $date_added = $subname.modfile.'date_added'
        $name = $subname.name

        $ModListData | Add-Member -Name $modid -Value @{} -MemberType NoteProperty
	    $ModListData.${modid}.date_added=$date_added
        $ModListData.${modid}.name = $name
    }

    $ModListData | ConvertTo-Json | Set-Content $ModListJsonPath
}

Function mod_GUI_selector
{
    param (
        [string[]]$ModList,
        [string]$GUItitle,
        [bool]$multiSelect = $true,
        [string]$nameUsed = "Mod"
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Fetch the working area of the primary display
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    # Output the width and height
    $screenHeight = $workingArea.Height/2

    # Create Form Layout
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = $GUItitle
    $Form.Size = New-Object System.Drawing.Size(650, $screenHeight)
    $Form.StartPosition = "CenterScreen"

    # Create DataGridView
    $DataGridView = New-Object System.Windows.Forms.DataGridView
    $DataGridView.Dock = [System.Windows.Forms.DockStyle]::Fill
    $DataGridView.ReadOnly = $true
    $DataGridView.AllowUserToAddRows = $false
    $DataGridView.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill

    # --- KEY MULTI-SELECT SETTINGS ---
    $DataGridView.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $DataGridView.MultiSelect = $multiSelect  # Allows Ctrl+Click and Shift+Click selections

    # Define Column Layout
    $Column = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $Column.HeaderText = "$nameUsed Name"
    $Column.Name = "$nameUsed"
    [void]$DataGridView.Columns.Add($Column)

    # Populating Rows
    foreach ($Mod in $ModList) {
        [void]$DataGridView.Rows.Add($Mod)
    }

    # Create a Bottom Button Panel
    $ButtonPanel = New-Object System.Windows.Forms.Panel
    $ButtonPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $ButtonPanel.Height = 50

    # Create Clear Button
    $ClearButton = New-Object System.Windows.Forms.Button
    $ClearButton.Text = "Clear All"
    $ClearButton.Location = New-Object System.Drawing.Point(35, 10)
    $ClearButton.Size = New-Object System.Drawing.Size(85, 30)

    # Bind the Clear method to the button
    $ClearButton.Add_Click({
        $dataGridView.ClearSelection()
    })

    # Create Select All Button
    $SelectAllButton = New-Object System.Windows.Forms.Button
    $SelectAllButton.Text = "Select All"
    $SelectAllButton.Location = New-Object System.Drawing.Point(135, 10)
    $SelectAllButton.Size = New-Object System.Drawing.Size(85, 30)

    # Bind the SelectAll method to the button
    $SelectAllButton.Add_Click({
        $dataGridView.SelectAll()
    })

    # Create OK Button
    $OKButton = New-Object System.Windows.Forms.Button
    $OKButton.Text = "OK"
    $OKButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $OKButton.Location = New-Object System.Drawing.Point(410, 10)
    $OKButton.Size = New-Object System.Drawing.Size(85, 30)

    # Create Cancel Button
    $CancelButton = New-Object System.Windows.Forms.Button
    $CancelButton.Text = "Cancel"
    $CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $CancelButton.Location = New-Object System.Drawing.Point(510, 10)
    $CancelButton.Size = New-Object System.Drawing.Size(85, 30)

    # Attach buttons to the panel, and panel to the form
    $ButtonPanel.Controls.AddRange(@($OKButton, $CancelButton, $SelectAllButton, $ClearButton))
    $Form.Controls.Add($DataGridView)  # Added first so Dock.Fill respects the panel space
    $Form.Controls.Add($ButtonPanel)
    $Form.AcceptButton = $OKButton
    $Form.CancelButton = $CancelButton

    # --- FIX: CLEAR AUTO-SELECTION ON LOAD ---
    # This runs exactly when the window visualizes, stripping the default auto-focus highlight.
    $Form.Add_Load({
        $DataGridView.ClearSelection()
    })

    # Show the window dialog and capture the result
    $Result = $Form.ShowDialog()

    # Process Selected Rows if user clicked OK
    if ($Result -eq [System.Windows.Forms.DialogResult]::OK) {
        # Extract the string cell value from each selected grid row
        $SelectedMods = foreach ($Row in $DataGridView.SelectedRows) {
            $Row.Cells["ModName"].Value
        }
    
        # Reverse the collection so output matches the top-to-bottom visual order selected
        if ($null -ne $SelectedMods) {
            [array]::Reverse($SelectedMods)
        }
    } else {
        $SelectedMods = $null
    }

    # Clean up memory
    $Form.Dispose()

    return $SelectedMods
}

<#
    This will install/import a server to the location you indicate, perform a complete setup,
    download SteamCMD.exe and the Insurgency Server Package.  You can select the directory
    for storing mod files for the new server.  It will start the server for the first time
    and then start your other servers if you have them.
#>

function install_server
{
    param(
        [bool]$is_New_Server = $false
    )

    Clear-Host

    # Require running script in Administration Mode to allow setting of Server Ports
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not($isAdmin)) {
        Write-Warning "You need to run Start_Server_Manager.bat in ADMINISTRATOR Mode"
        Write-Warning "Exit the Manager and Right-Click on Start_Server_Manager.bat"
        Write-Warning "Then select 'Run As Administrator' you will be able to install"
        Write-Warning "or import a new server."
        Write-Host "`nPress any key to Continue..." -ForegroundColor White
        $null = [System.Console]::ReadKey($true)
        return
    }

    Write-Host "==============================================" -ForegroundColor Cyan
    if ($is_New_Server)
    {
        Write-Host "              Install New Server              " -ForegroundColor Yellow
    }
    else
    {
        Write-Host "           Import Existing Server             " -ForegroundColor Yellow
    }
    Write-Host "==============================================" -ForegroundColor Cyan

    $global:Server_List_Count = show_server_list

    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""

    if ($is_New_Server)
    {
        Write-WrappedHost -Text "* This will install a New Server with basic settings and under the Server ID you enter."
    }
    else
    {
        Write-WrappedHost -Text "* This will Import/Copy the existing Server Configuration files under the Server ID you enter.  The launch information (Ports, Host Name, Password, Mutators, etc.) will need to be entered manually into the Configuration Wizard.  Admin.txt/ini, MapCycle.txt/ini and Motd.txt are copied and editors for each will be opened so you can change them if needed." -ForegroundColor Yellow
    }
    Write-Host ""
    Write-WrappedHost -Text "* Downloaded server mods will be stored in a UnifiedMods directory where mods for all servers are stored.  This avoids duplicate downloads of mods used by multiple servers."
    Write-Host ""
    if (-not $is_New_Server)
    {
        Write-WrappedHost -Text "* The User.json for the Imported/Copied Server will be copied so you will not need to get a new Security Code." -ForegroundColor Green
        Write-Host ""
        Write-WrappedHost -Text "* All of the mods.maps downloaded by Imported Server will be copied to the UnifiedMods directory.  You will be prompted to locate the state.json file which contains information about the mods and location to copy the mods from.  The imported server will not have to re-download any mods when started unless mods have been added or updated." -ForegroundColor Yellow
        Write-Host ""
    }
    Write-WrappedHost -Text "* The Configuration Wizard will be started and guide you through setting the most important items needed to start the server. Make sure you have the following information ready."
    Write-Host ""
    Write-Host "    All of the Mutator Configurations you want to add to the Game.ini file"
    Write-Host "    Game Port - Query Port - Rcon Listen Port (Rcon Port is REQUIRED for the Server Info Window to function)"
    Write-Host "    Server Password (optional) - Rcon Password (REQUIRED for Rcon Dashboard and Server Dashboard to function)"
    Write-Host "    Server Host Name (including [Scenarios] in the name will show the number of scenarios available)"
    Write-Host "    Number of Players - Game Stats Token - GSLT Token"
    Write-Host "    Mutator List with a comma between each mutator (EX: beyondmeat,NoRestrictPlus,Medicon )"
    Write-Host "    Steam64IDs for all Admins - Message of the Day"
    Write-Host "    List of any Boot Maps you would like to add to the stock maps"
    Write-Host "    List of any Maps to add to the Map Cycle"
    Write-Host ""
    Write-WrappedHost -Text "* Editors will be opened for Game.ini, Admins, MOTD, Boot Maps and Map Cycle."
    Write-Host ""
    Write-WrappedHost -Text "* Firewall Rules for the UDP and TCP ports will be created under the Server ID."
    Write-Host ""
    Write-WrappedHost -Text "* The server will be added to Sandstorm Multi Server launcher."
    Write-Host ""
    Write-WrappedHost -Text "* The new server will be started and once the user.json is updated the server will be shut down and the Server Launcher will be started."
    Write-Host ""
    Write-WrappedHost -Text "* Any existing servers will be started and when the new server is launched all server mods will be downloaded before the server is started."
    Write-Host ""

    if ($is_New_Server)
    {
        $promptText = "Do you wish to install a new Server?"
    }
    else
    {
        $promptText = "Do you wish to Import a Server?"
    }

    $response = User-Confirm "$promptText"

    if ($response -eq 'n') {
        return
    }
    else
    {
        Write-Host ""
        Write-Host "Enter Server_ID you would like to create for installing your server.  Make the name descriptive of Game Type or Theater."
        Write-Host "Only letters and numbers will be accepted up to 32 characters."
        Write-Host ""

        $isValid = $false

        do {
            $server_Directory_Name = Read-Host -Prompt "Enter the Server_ID (Press Enter to Abort / 32 Characters Maximum): "
            $server_Directory_Name = $server_Directory_Name -replace '[^a-zA-Z0-9]', ''

            # Check for length equal to 0
            if ($server_Directory_Name.Length -eq 0) {
                return $false
            }
            # Check for length greater than 32
            if ($server_Directory_Name.Length -gt 32) {
                Write-Warning "Invalid ID! The Server_ID must be between 1 and 32 characters."
            }
            elseif ($null -ne $global:SeverListData.${server_Directory_Name}) 
            {
                # Check for match in Server List
                Write-Warning "Invalid ID! The Server_ID is already in use."
            }
            else
            {
                $isValid = $true
            }
        } while ($isValid -eq $false)

        Write-Host "Server Directory Name: $server_Directory_Name" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan

        if ($is_New_Server)
        {
            $promptText = "Install"
        }
        else
        {
            $promptText = "Import"
        }

        $install_Directory = $PSScriptRoot

        $Base_Server_ID = $server_Directory_Name
        Write-Host ""
        Write-Host "Server_ID: $Base_Server_ID" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host ""

        $Base_Server_Path = Join-Path -Path $install_Directory -ChildPath "InsurgencySandstorm\steamapps\common\sandstorm_server"
        $workingPath = Join-Path -Path $install_Directory -ChildPath "config\ServerData\$Base_Server_ID\WindowsServer\Game.ini"
        $EngineiniPath = Join-Path -Path $install_Directory -ChildPath "config\ServerData\$Base_Server_ID\WindowsServer\Engine.ini"
        $settingsPath = Join-Path -Path "$env:LOCALAPPDATA" -ChildPath "mod.io.$Base_Server_ID"

        if (-not ($is_New_Server))
        {
            # GUI to Find Executable path

            Write-Host "Select the location of the InsurgencyServer.exe of the Server Configuration you would like to copy."
            Write-Host ""
            Write-WrappedHost -Text "You can copy the config data from computers on your network. The Server data you are copying will not be deleted."
            Write-Host ""

            $script:SelectedFile = filebrowser_GUI -directoryPath "shell:MyComputerFolder" -guiTitle "Select Path to InsurgencyServer.exe for importing" -filter "Insurgency Server Executable (InsurgencyServer.exe)|InsurgencyServer.exe"

            if ($script:SelectedFile -ne $false) {
                $SelectedFilePath = $script:SelectedFile
                $Source_Server_Path = Split-Path -Path $SelectedFilePath -Parent
  
                Write-Host "Directory path to InsurgencyServer.exe: $Source_Server_Path" -ForegroundColor Yellow
    
            } else {
                Remove-Item -Path $install_Directory -Recurse -Force
                Write-Host "Operation cancelled by user." -ForegroundColor Yellow
                Write-Host "`nPress any key to Continue..." -ForegroundColor White
                $null = [System.Console]::ReadKey($true)
                return $false
            }

            # Copy config files from old server to confid/ServerData

            $sourceDir = Join-Path -Path $Source_Server_Path -ChildPath "Insurgency\Saved\Config\WindowsServer"
            $destinationDir = Join-Path -Path $install_Directory -ChildPath "config\ServerData\$Base_Server_ID\WindowsServer"

           	if(-not(Test-Path "$destinationDir"))
            {
               	$null=mkdir "$destinationDir" -ErrorAction SilentlyContinue
            }

            robocopy "$sourceDir" "$destinationDir" "Game.ini" "Engine.ini" /IS | Out-Null

            $sourceDir = Join-Path -Path $Source_Server_Path -ChildPath "Insurgency\Config\server"
            $destinationDir = Join-Path -Path $install_Directory -ChildPath "config\ServerData\$Base_Server_ID\server"

           	if(-not(Test-Path "$destinationDir"))
            {
               	$null=mkdir "$destinationDir" -ErrorAction SilentlyContinue
            }

            robocopy "$sourceDir" "$destinationDir" "Admins.txt" "Admins.ini" "bootmaps.txt" "mapcycle.txt" "mapcycle.ini" "Motd.txt" /IS | Out-Null

            $sourceDir = Join-Path -Path $PSScriptRoot -ChildPath "support\InsurgencySandstorm\steamapps\common\sandstorm_server"
            $destinationDir = Join-Path -Path $install_Directory -ChildPath "config\ServerData\$Base_Server_ID"

           	if(-not(Test-Path "$destinationDir"))
            {
               	$null=mkdir "$destinationDir" -ErrorAction SilentlyContinue
            }

            robocopy "$sourceDir" "$destinationDir" "ServerStartup.json" /IS | Out-Null

            # Make sure Password, RconListenPort and MaxPlayers are commented out in Game.ini

            Write-Host ""
            Write-Host "Comment out Password, ListenPort and MaxPlayer if they exist in Game.ini" -ForegroundColor Yellow
            (Get-Content $workingPath) -replace '(?<!;)\b(Password\b)', ';$1' | Set-Content $workingPath
            (Get-Content $workingPath) -replace '(?<!;)\b(ListenPort\b)', ';$1' | Set-Content $workingPath
            (Get-Content $workingPath) -replace '(?<!;)\b(MaxPlayers\b)', ';$1' | Set-Content $workingPath

            # Make sure Port and GameServerQueryPort are commented out in Engine.ini

            Write-Host ""
            Write-Host "Comment out Port and GameServerQueryPort if they exist in Engine.ini" -ForegroundColor Yellow
            (Get-Content $workingPath) -replace '(?<!;)\b(Port\b)', ';$1' | Set-Content $workingPath
            (Get-Content $workingPath) -replace '(?<!;)\b(GameServerQueryPort\b)', ';$1' | Set-Content $workingPath

            # add Networking error fix to Engine.ini if missing in Engine.ini

            Write-Host ""
            Write-Host "Add Network Fix to Engine.ini" -ForegroundColor Yellow
            $textToCheck = "[/script/engine.networksettings]"

            $section = "[/script/engine\.networksettings\]"
            $settingsToAdd = @(
                "n.VerifyPeer=false"
            )

            # add log entries to suppress that spam and make log files enormous in Engine.ini
             
            Write-Host ""
            Write-WrappedHost -Text "Add the following items to Engine.ini [Core.Log] to suppress in the logs to prevent spamming: LogSkinnedMeshComp, LogGameMode, LogStreaming, LogNetPackageMap, LogProjectileMovement, LogRcon, LogAI, LogAssetRegistryI and LogBlueprintUserMessages" -ForegroundColor Yellow
            $result = engineINIcheck -section $section -settingsToAdd $settingsToAdd -filePath $EngineiniPath

            $section = "[Core.Log]"
            $settingsToAdd = @(
                "LogSkinnedMeshComp=error", 
                "LogGameMode=error",
                "LogStreaming=error",
                "LogNetPackageMap=error",
                "LogProjectileMovement=error",
                "LogRcon=error",
                "LogAI=error",
                "LogAssetRegistryI=error",
                "LogBlueprintUserMessages=error",
                "LogPros=error",
                "LogRedstoneSocket=error",
                "LogRedstoneVoiceChatLib=error",
                "LogRedstoneVoiceChat=error",
                "LogVOIP=error",
                "LogINSChallangesEventProcessor=Error",
                "LogHttpReplay=Error",
                "LogAnimMontage=Error",
                "LogNetPlayerMovement=Error"

            )

            $result = engineINIcheck -section $section -settingsToAdd $settingsToAdd -filePath $EngineiniPath

            Write-Host ""
        }
        else
        {
            $sourceDir = Join-Path -Path $PSScriptRoot -ChildPath "support\InsurgencySandstorm\steamapps\common\sandstorm_server\Insurgency\Saved\Config\WindowsServer"
            $destinationDir = Join-Path -Path $install_Directory -ChildPath "config\ServerData\$Base_Server_ID\WindowsServer"

           	if(-not(Test-Path "$destinationDir"))
            {
               	$null=mkdir "$destinationDir" -ErrorAction SilentlyContinue
            }

            robocopy "$sourceDir" "$destinationDir" "Game.ini" "Engine.ini" /IS | Out-Null

            $sourceDir = Join-Path -Path $PSScriptRoot -ChildPath "support\InsurgencySandstorm\steamapps\common\sandstorm_server\Insurgency\Config\server"
            $destinationDir = Join-Path -Path $install_Directory -ChildPath "config\ServerData\$Base_Server_ID\server"

           	if(-not(Test-Path "$destinationDir"))
            {
               	$null=mkdir "$destinationDir" -ErrorAction SilentlyContinue
            }

            robocopy "$sourceDir" "$destinationDir" "Admins.txt" "Admins.ini" "bootmaps.txt" "mapcycle.txt" "mapcycle.ini" "Motd.txt" /IS | Out-Null

            $sourceDir = Join-Path -Path $PSScriptRoot -ChildPath "support\InsurgencySandstorm\steamapps\common\sandstorm_server"
            $destinationDir = Join-Path -Path $install_Directory -ChildPath "config\ServerData\$Base_Server_ID"

           	if(-not(Test-Path "$destinationDir"))
            {
               	$null=mkdir "$destinationDir" -ErrorAction SilentlyContinue
            }

            robocopy "$sourceDir" "$destinationDir" "ServerStartup.json" /IS | Out-Null
        }

       	if(-not(Test-Path "$settingsPath"))
        {
            Remove-Item -Path $settingsPath -Recurse -Force *>$null
        }

        # Copy dummy user.json to allow server to boot even if not subscribed to any mods
        $makeDIRpath = Join-Path -Path $settingsPath -ChildPath "254\ModServer"
       	$null=mkdir "$makeDIRpath" -ErrorAction SilentlyContinue
        $sourceDir = Join-Path -Path $PSScriptRoot -ChildPath "support"

        robocopy "$sourceDir" "$makeDIRpath" "user.json" /IS | Out-Null

        if (-not ($is_New_Server))
        {
            # GUI to Find user.json path and copy

            Write-Host ""
            Write-Host "Select the location of the user.json for the Server you have copied."
            Write-Host ""
            Write-Host "Usually located in C:\Users\[AccountName]\AppData\Local\mod.io\254\ModServer" -ForegroundColor DarkYellow
            Write-Host ""
            Write-Host "You can pull this information from computers on your network."
            Write-Host "The user.json File you are copying will not be deleted."
            Write-Host ""

            $script:SelectedFile = filebrowser_GUI -directoryPath "$env:LocalAppData" -guiTitle "Select Path to user.json for importing" -filter "Insurgency Server user.json (user.json)|user.json"

            if ($script:SelectedFile -ne $false) {
                $SelectedFilePath = $script:SelectedFile
                $Source_Users_Path = Split-Path -Path $SelectedFilePath -Parent

                Write-Host "Directory path to user.json: $Source_Users_Path" -ForegroundColor Yellow
    
            } else {
                Remove-Item -Path $install_Directory -Recurse -Force
                Write-Host "Operation cancelled by user." -ForegroundColor Yellow
                Write-Host "`nPress any key to Continue..." -ForegroundColor White
                $null = [System.Console]::ReadKey($true)
                return $false
            }

            $settingsPathUser = Join-Path -Path "$settingsPath" -ChildPath "254\ModServer"
            robocopy "$Source_Users_Path" "$settingsPathUser" /E /IS

            Write-Host ""
            Write-Host "==============================================" -ForegroundColor Cyan
        }

        $destination = Join-Path -Path $PSScriptRoot -ChildPath "mods\mod.io.$Base_Server_ID\mod.io"
        $destination254 = Join-Path -Path $destination -ChildPath "254"

        $rootdestination=$destination.Replace('\', '/')

        $globalsettings=@{
            RootLocalStoragePath = "$rootdestination/"
        }

        $globalsettings | ConvertTo-Json | Set-Content "$settingsPath\globalsettings.json"

        Write-Host ""
        Write-Host "Created $settingsPath\globalsettings.json with RootLocalStoragePath = $rootdestination"

       	if(-not(Test-Path "$destination254\metadata"))
        {
           	$null=mkdir "$destination254\metadata" -ErrorAction SilentlyContinue
        }

       	if(-not(Test-Path "$destination254\mods"))
        {
           	$null=mkdir "$destination254\mods" -ErrorAction SilentlyContinue
        }

        # Copy dummy state.json to allow server to boot even if not subscribed to any mods
        $sourceDir = Join-Path -Path $PSScriptRoot -ChildPath "support"
        $destinationDir = Join-Path -Path $destination254 -ChildPath "metadata"

        robocopy "$sourceDir" "$destinationDir" "state.json" /IS | Out-Null

        Write-Host ""
        Write-Host "Created $destination254 directories (metadata, mods)"
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host ""

        # Copy mod files from old directory to new directory and update state.json

        if (-not ($is_New_Server))
        {

            Write-WrappedHost -Text "Select the directory path to where the state.json is located for the mod files you are wanting to import.  These files can be located on this server or any server accessable on your network." -ForegroundColor DarkYellow
            Write-Host ""

            $script:SelectedFile = filebrowser_GUI -directoryPath "shell:MyComputerFolder" -guiTitle "Select Path to state.json for importing" -filter "Insurgency Server state.json (state.json)|state.json"

            if ($script:SelectedFile -ne $false) {
                $SelectedFilePath = $script:SelectedFile
                $Source_mods_Path = Split-Path -Path $SelectedFilePath -Parent

                Write-Host "Directory path to state.json: $Source_mods_Path" -ForegroundColor Yellow
    
            } else {
                Remove-Item -Path $install_Directory -Recurse -Force
                Write-Host "Operation cancelled by user." -ForegroundColor Yellow
                Write-Host "`nPress any key to Continue..." -ForegroundColor White
                $null = [System.Console]::ReadKey($true)
                return $false
            }

            Write-Host ""
            Write-Host "Source Directory path: $Source_mods_Path" -ForegroundColor Yellow
            Write-Host "Destination Directory path: $destination" -ForegroundColor Yellow

            #copy cache, metadata and mods directory    
            robocopy "$Source_mods_Path" "$destination254\metadata" /E /IS | Out-Null

            $Source_mods_Path = Split-Path -Path $Source_mods_Path -Parent
            $serverDownloadedMods = Join-Path -Path $Source_mods_Path -ChildPath "mods\"
            $destinationMods = Join-Path -Path $PSScriptRoot -ChildPath "mods\UnifiedMods"
            $modsLocation = $destinationMods
            $destinationMods = $destinationMods + "\"
            robocopy "$serverDownloadedMods" "$destinationMods" /E /XO

            $newStatejsonPath = Join-Path -Path $destination -ChildPath "254\metadata\state.json"
          
            # Load and convert JSON to a PowerShell object
            $state = Get-Content -Path $newStatejsonPath -Raw | ConvertFrom-Json

            # Loop through the Mods array and change the path
            $state.Mods | ForEach-Object {
                $_.PSObject.Properties['PathOnDisk'].Value = -join ("$modsLocation", "\") + ($_.PSObject.Properties['PathOnDisk'].Value | Split-Path -Leaf)
            }

            # Convert your object to JSON
            $jsonc = $state | ConvertTo-Json -Compress -Depth 100
                          
            # Fix ONLY Unicode characters (e.g., \u0027) while keeping literal \n untouched
            $cleanJson = [regex]::Replace($jsonc, '\\u([0-9a-fA-F]{4})', { 
                param($match) [char][int]"0x$($match.Groups[1].Value)" 
            })

            # Export to a valid UTF-8 file
            $cleanJson | Out-File "$newStatejsonPath" -Encoding utf8

            build_ModList -server_ID $Base_Server_ID

            Write-Host ""
            Write-Host "==============================================" -ForegroundColor Cyan
            Write-Host ""
        }

        add_update_server -Server_ID $Base_Server_ID

        if ($is_New_Server)
        {
            Write-WrappedHost -Text "It is recommended that you edit the Game.ini for this server if you will be using Mutators. All Mutator Configurations need to be added to the Game.ini before the server begins. There is no need to configure the Rcon Listen Port, Rcon Password or MaxPlayers as they are configured next in Server Configuration section. The Game.ini uses toned down AI settings for hearing and sight as well as difficulty and you should adjust them to suit your needs. The server WILL be started as soon as you finish the Server Configuration section coming up next." -ForegroundColor Green
            Write-Host ""
        }

        $response = User-Confirm "Do you wish to Edit Game.ini?"

        if ($response -eq 'y') {

            [string[]]$workingList = Get-Content -Path $workingPath
            $textData = edit_TXT_config_files -menuTitle "Server Game.ini Editor" -returnType 6 -workingListArray $workingList

            $textData | Set-Content -Path $workingPath
        }

        Write-Host ""
        Write-WrappedHost -Text "It is OPTIONAL to edit the Engine.ini for this server" -ForegroundColor Green
        Write-Host ""
        $response = User-Confirm "Do you wish to Edit Engine.ini?"

        if ($response -eq 'y') {

            $enginePath = Join-Path -Path $install_Directory -ChildPath "steamapps\common\sandstorm_server\Insurgency\Saved\Config\WindowsServer\Engine.ini"
            [string[]]$workingList = Get-Content -Path $enginePath
            $textData = edit_TXT_config_files -menuTitle "Server Engine.ini Editor" -returnType 7 -workingListArray $workingList

            $textData | Set-Content -Path $enginePath
        }

        Write-Host ""
        Write-Host "Starting Setup Server Config: $setupServerPath"
        Write-Host ""

        $configPath = Join-Path -Path $install_Directory -ChildPath "config\ServerData\$Base_Server_ID\ServerStartup.json"

        do {
            server_configuration_editor -Base_Server_ID $Base_Server_ID -configPath $configPath -isNewServer $true
            $configData = load_server_configuration -configPath $configPath

            Write-Host ""
            Write-Host "Port:            $($configData.Port)" -ForegroundColor Yellow
            Write-Host "QueryPort:       $($configData.QueryPort)" -ForegroundColor Yellow
            Write-Host "RconListenPort:  $($configData.RconListenPort)" -ForegroundColor Yellow
            Write-Host "Server Password: $($configData.Password)" -ForegroundColor Green
            Write-Host "RconPassword:    $($configData.RconPassword)" -ForegroundColor Green
            Write-Host "HostName:        $($configData.HostName)" -ForegroundColor Cyan
            Write-Host "MaxPlayers:      $($configData.MaxPlayers)" -ForegroundColor White
            Write-Host "GameStatsToken:  $($configData.GameStatsToken)" -ForegroundColor Gray
            Write-Host "GSLTToken:       $($configData.GSLTToken)" -ForegroundColor Gray
            Write-Host "Mutators:        $($configData.Mutators)" -ForegroundColor Cyan
            Write-Host "SecurityCode:    $($configData.SecurityCode)" -ForegroundColor Magenta
            Write-Host ""

            $answer = User-Confirm "Do changes need to be made to the Server Configuration?"
        } while ($answer -eq 'y')

        Write-Host ""

        $Port = $configData.Port
        $QueryPort = $configData.QueryPort

        $TCP_UDPServerPath = Join-Path -Path $install_Directory -ChildPath "steamapps\common\sandstorm_server\insurgency\binaries\win64\InsurgencyServer-Win64-Shipping.exe"
        $displayName = "Insurgency $Base_Server_ID TCP"

        $existingRule = Get-NetFirewallRule -DisplayName $displayName -ErrorAction SilentlyContinue | 
            Where-Object { 
                # Check if the program matches
                ($_ | Get-NetFirewallApplicationFilter).Program -eq $TCP_UDPServerPath -and
                # Check if the protocol is TCP
                ($_ | Get-NetFirewallPortFilter).Protocol -eq 'TCP'
            }

        if (-not $existingRule) {
            try {
                New-NetFirewallRule -DisplayName $displayName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port,$QueryPort -Program $TCP_UDPServerPath -Profile Private,Public
                Write-Warning "Insurgency $Base_Server_ID TCP Ports $Port,$QueryPort are now Open"
            }
            catch {
                Write-Host "Failure: Failed to create firewall rule '$displayName'." -ForegroundColor Red
                Write-Host "Error details: $_" -ForegroundColor Yellow
            }
        }
        else
        {
            $existingRule | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -LocalPort $Port,$QueryPort

            Write-Host "Insurgency $Base_Server_ID TCP Ports $Port,$QueryPort are Open"  -ForegroundColor Green
        }

        $displayName = "Insurgency $Base_Server_ID UDP"

        $existingRule = Get-NetFirewallRule -DisplayName $displayName -ErrorAction SilentlyContinue | 
            Where-Object { 
                # Check if the program matches
                ($_ | Get-NetFirewallApplicationFilter).Program -eq $TCP_UDPServerPath -and
                # Check if the protocol is UDP
                ($_ | Get-NetFirewallPortFilter).Protocol -eq 'UDP'
            }

        if (-not $existingRule) {
            try {
                New-NetFirewallRule -DisplayName $displayName -Direction Inbound -Action Allow -Protocol UDP -LocalPort $Port,$QueryPort -Program $TCP_UDPServerPath -Profile Private,Public
                Write-Warning "Insurgency $Base_Server_ID UDP Ports $Port,$QueryPort are now Open"
            }
            catch {
                Write-Host "Failure: Failed to create firewall rule '$displayName'." -ForegroundColor Red
                Write-Host "Error details: $_" -ForegroundColor Yellow
            }
        }
        else
        {
            $existingRule | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -LocalPort $Port,$QueryPort
            Write-Host "Insurgency $Base_Server_ID UDP Ports $Port,$QueryPort are Open" -ForegroundColor Green
        }

        # Mirror/Overwrite server mod.io.$Base_Server_ID to mod.io directory
        $ModioDir  = "$env:LOCALAPPDATA\mod.io"
        $ModioServerDir = "$env:LOCALAPPDATA\mod.io.$Base_Server_ID"

        # Silently remove the existing mod.io directory if it exists (Equivalent to rmdir /S /Q)
        if (Test-Path -Path $ModioDir) {
            Remove-Item -Path $ModioDir -Recurse -Force *>$null
        }

        robocopy "$ModioServerDir" "$ModioDir" /E /IS | Out-Null

        Write-Host ""
        Write-Host "Starting Server: $Base_Server_ID"
        Write-Host ""

        Start-Sleep -Milliseconds 500

        # Copy config\ServerData\$Base_Server_ID\ServerStartup.json file to InsurgencySandstorm\steamapps\common\sandstorm_server

        $sourceDir = Join-Path -Path $PSScriptRoot -ChildPath "config\ServerData\$Base_Server_ID"
        $destinationDir = Join-Path -Path $PSScriptRoot -ChildPath "InsurgencySandstorm\steamapps\common\sandstorm_server"
        robocopy "$sourceDir" "$destinationDir" "ServerStartup.json" /IS | Out-Null

        # Copy config\ServerData\$Base_Server_ID\server DIR to InsurgencySandstorm\steamapps\common\sandstorm_server\Insurgency\Config

        $sourcePath = Join-Path -Path $PSScriptRoot -ChildPath "config\ServerData\$Base_Server_ID\server"
        $destinationPath = Join-Path -Path $PSScriptRoot -ChildPath "InsurgencySandstorm\steamapps\common\sandstorm_server\Insurgency\Config\server"
        robocopy "$sourcePath" "$destinationPath" /E /IS | Out-Null

        # Copy config\ServerData\$Base_Server_ID\WindowsServer DIR to InsurgencySandstorm\steamapps\common\sandstorm_server\Insurgency\Saved\Config

        $sourcePath = Join-Path -Path $PSScriptRoot -ChildPath "config\ServerData\$Base_Server_ID\WindowsServer"
        $destinationPath = Join-Path -Path $PSScriptRoot -ChildPath "InsurgencySandstorm\steamapps\common\sandstorm_server\Insurgency\Saved\Config\WindowsServer"
        robocopy "$sourcePath" "$destinationPath" /E /IS | Out-Null

        $batchfile = "startSandstormServer.bat"
        $startSandstormPath = Join-Path -Path $PSScriptRoot -ChildPath "InsurgencySandstorm\steamapps\common\sandstorm_server"

        Start-Process "cmd.exe" -ArgumentList "/c TITLE $server_Directory_Name && CALL $batchFile", "$Base_Server_ID" -WorkingDirectory "$startSandstormPath" # -PassThru

        # Define the variables
        $fileName = "serverStart.txt"
        $fullPath = Join-Path -Path $startSandstormPath -ChildPath $fileName

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
            Write-Host "`r$Base_Server_ID Server Boot: ${SecondsRemaining}s remaining   " -NoNewline -ForegroundColor $RandomColor

            # Only sleep if we haven't reached the 30th check yet
            if ($LoopCounter -lt 30) {
                Start-Sleep -Seconds 1
            }
        }

        Write-Host "`r                                                 `r" -NoNewline

        # Mirror/Overwrite back to the server directory at the end
        $ModioDir  = "$env:LOCALAPPDATA\mod.io"
        $ModioServerDir = "$env:LOCALAPPDATA\mod.io.$Base_Server_ID"
        robocopy "$ModioDir" "$ModioServerDir" /E /IS | Out-Null

        # kill running Sandstorm Server after user.json created and saved

        Stop-Process -Name "InsurgencyServer-Win64-Shipping" -Force

        # start Server Launcher to download mods and start server

        $launcherName = "Start_Server_Launcher"
        $batchfile = "Start_Server_Launcher.bat"
        Start-Process "cmd.exe" -ArgumentList "/c TITLE $launcherName && CALL $batchFile", "$launcherName" -WorkingDirectory "$PSScriptRoot" -PassThru
        exit
    }
}

<#
    This will delete the Server_ID from the ServerList.json and delete the
    %localappdata%\mod.io.[Server_ID] directory.  The game server directory and
    mod.io[Server_ID] mod storage directories will not be removed.
#>

function delete_server
{
    do {
        Clear-Host
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "        Remove Server from Server List        " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host ""

        [int]$global:Server_List_Count = show_server_list
        $exitSelection = $global:Server_List_Count + 1
        Write-Host " $exitSelection. Exit Remove Server" -ForegroundColor DarkYellow
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host ""

        [int]$selection = Read-Host -Prompt " Please enter your selection (1-$exitSelection)"
    
        if(($selection -gt 0) -and ($selection -le $global:Server_List_Count))
        {
            $downOne = $selection - 1
            Write-Host ""
            $countup = 0
            foreach ($item in $global:SeverListData) {
                
                # Get each dynamic top element name and value
                foreach ($property in $item.PSObject.Properties) {
                    $server_ID = $property.Name
                    if ($countup -eq $downOne)
                    {
                        $Base_Server_ID = $server_ID
                        $isDisabled = $property.Value.Disabled
                    }
                    $countup = $countup + 1
                }
            }

            Write-Host ""
            Write-Host ("{0,24} {1,-60}" -f "Server ID: ", "$Base_Server_ID") -ForegroundColor Yellow
            Write-Host ""
            Write-Host "---===>>> If you delete this Server ID the" -ForegroundColor Gray
            Write-Host "---===>>> $env:LOCALAPPDATA\mod.io.$Base_Server_ID" -ForegroundColor Gray
            Write-Host "---===>>> will be DELETED!!!" -ForegroundColor Gray
            Write-Host ""
            Write-Host "---===>>> The Server Configuration Directory will NOT be deleted: $Base_Server_Path " -ForegroundColor Green
            Write-Host "---===>>> The Mods Directory will NOT be deleted" -ForegroundColor Green
            Write-Host ""

            $response = User-Confirm "Do you want to Delete this Server?"

            if ($response -eq 'y') {
                $global:SeverListData.PSObject.Properties.Remove($Base_Server_ID)
                $global:SeverListData | ConvertTo-Json | Set-Content $ServerListJsonPath
                $global:SeverListData=Get-Content $ServerListJsonPath | ConvertFrom-Json

               	if(-not(Test-Path "$env:LOCALAPPDATA\mod.io.$Base_Server_ID"))
                {
                    Write-Host ""
                    Write-Host "$env:LOCALAPPDATA\mod.io.$Base_Server_ID directory not found" -ForegroundColor Yellow
                    Write-Host "`nPress any key to Continue..." -ForegroundColor White
                    $null = [System.Console]::ReadKey($true)
                }
                else
                {
                    Write-Host ""
                    Write-Host "Deleting: $env:LOCALAPPDATA\mod.io.$Base_Server_ID" -ForegroundColor Red
                    Remove-Item -Path "$env:LOCALAPPDATA\mod.io.$Base_Server_ID" -Recurse -Force
                    Write-Host "`nPress any key to Continue..." -ForegroundColor White
                    $null = [System.Console]::ReadKey($true)
                }
            }
        }
    } until ($selection -eq $exitSelection -or -not($selection))
}

function unsubscribe_mods
{
    do {
        Clear-Host
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "  Unsubscribe Mods from Server Mod.io Account     " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host ""

        [int]$global:Server_List_Count = show_server_list
        $exitSelection = $global:Server_List_Count + 1
        Write-Host " $exitSelection. Exit Unsubscribe Mods" -ForegroundColor DarkYellow
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host ""

        [int]$selection = Read-Host -Prompt " Please enter your selection (1-$exitSelection)"
    
        if(($selection -gt 0) -and ($selection -le $global:Server_List_Count))
        {
            $downOne = $selection - 1
            Write-Host ""
            $countup = 0
            foreach ($item in $global:SeverListData) {
                
                # Get each dynamic top element name and value
                foreach ($property in $item.PSObject.Properties) {
                    $server_ID = $property.Name
                    if ($countup -eq $downOne)
                    {
                        $Base_Server_ID = $server_ID
                        $isDisabled = $property.Value.Disabled
                    }
                    $countup = $countup + 1
                }
            }

            Write-Host ""
            Write-Host ("{0,24} {1,-60}" -f "Server ID: ", "$Base_Server_ID") -ForegroundColor Yellow
            Write-Host ""

            $response = User-Confirm "Do you want to Unsubscribe Mods for this Server?"

            if ($response -eq 'y') {
                $ModListJsonPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ModList.$Base_Server_ID.json"
                Mod-Unsub -ModListJsonPath $ModListJsonPath -Server_ID$Base_Server_ID
            }
        }
    } until ($selection -eq $exitSelection -or -not($selection))
}

# Display GUI Selector of all subscribed mods and ask user to
# select any number of the mods to UNSUBSCRIBE and DELETE
function Mod-Unsub
{
    param(
        [string]$ModListJsonPath,
        [string]$Server_ID
    )

    echo ""
    echo "=============================================="
    echo "    Select Mods to Unsubscribe and Delete   "
    echo "=============================================="
    echo ""

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

    # Get Sandstorm OAuth Token and UserID

    $mod_io_254_server="$env:LOCALAPPDATA\mod.io.$Server_ID\254\ModServer\user.json" 

    if (Test-Path $mod_io_254_server) {
        $getuserjson = Get-Content -Raw -Path $mod_io_254_server | ConvertFrom-Json
    }
    else 
    {
        Write-Host "MISSING $mod_io_254_user" -ForegroundColor Red
        Write-Host "MISSING $mod_io_254_server" -ForegroundColor Red
        Write-Host "Cannot proceed." -ForegroundColor Red
        pause
        return
    }

    [string]$token=$getuserjson.Oauth.token

    $gameId = 254
    $apiUrl = "https://api.mod.io/v1"
    $destinationMods = Join-Path -Path $PSScriptRoot -ChildPath "mods\UnifiedMods"
    $destinationMods = $destinationMods + "\"

    if (Test-Path $ModListJsonPath)
    {
	    echo "Reading settings from ModList$Server_ID.json."
        echo ""
	    $ModListData=Get-Content $ModListJsonPath | ConvertFrom-Json
    }
    else
    {
        Write-Host "ModList.json is MISSING and cannot proceed." -ForegroundColor Red
        pause
        exit
    }

    # Set up the headers with Bearer Token authentication
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type"  = "application/x-www-form-urlencoded"
    }

    $ModList = [System.Collections.Generic.List[string]]::new()

    foreach ($item in $ModListData) {

        # Get each dynamic top element name and value
        foreach ($property in $item.PSObject.Properties) {
            $topName = $property.Name
            $topValue = $property.Value

            # Check if the value is a nested object/custom object
            if ($topValue -is [System.Management.Automation.PSCustomObject]) {
            
                # Extract nested names and values
                foreach ($nestedProp in $topValue.PSObject.Properties) {
                    if($($nestedProp.Name) -eq "name")
                    {
                        $modname = $($nestedProp.Value)
                    }
                }
            }
            # Standard property output
            [void]$ModList.Add($modname+" | "+$topName + (' ' * 50)) # [void] suppresses the default .Add() output
        }
    }

    $ModList.Sort()

    $GUItitle = "Select One or More Mods to UNSUBSCRIBE and DELETE"
    $SelectedMods = mod_GUI_selector -ModList $ModList -GUItitle $GUItitle

    if ($null -eq $SelectedMods -or $SelectedMods.Count -eq 0) {
        Write-Host "No Mods were selected" -ForegroundColor Red

        return
    }

    # Output the selected items
    Write-Host "You selected the following items:" -ForegroundColor Green
    $SelectedMods
    echo ""

    $response = User-Confirm "Last Chance: Do you really want to Unsubscribe and Delete these items (Deleted only of not used on other servers)?"

    if ($response -eq 'n')
    {
        return
    }
    else
    {
        $tlen=$SelectedMods.count
        if( $tlen -gt 1)
        {
            for ($t = 0; $t -lt $tlen; $t++) {
                $modid = ($SelectedMods[$t] -split " \| ")[1].Trim()
                $ModListData.PSObject.Properties.Remove($modid)

                # Construct the API endpoint
                $endpoint = "$apiUrl/games/$gameId/mods/$modid/subscribe"

                # Execute the Unsubscribe request
                try {
                    $response = Invoke-RestMethod -Uri $endpoint -Method Delete -Headers $headers -ErrorAction Stop
                    Write-Host "Successfully unsubscribed from mod: $modid" -ForegroundColor Green

                	if(-not(Test-Path "$destinationMods$modid"))
	                {
                        Write-Host "Mod: $modid directory not found" -ForegroundColor Yellow
                    }
                    else
                    {
                        if ($AllMods -notcontains [string]$modid) {
                            Write-Host "Deleting Unsubscribed Mod Directory: $modid" -ForegroundColor Red
                            Remove-Item -Path "$destinationMods$modid" -Recurse -Force
                        }
                    }
                } catch {
#                    Write-Host "Failed to unsubscribe. Error: $_" -ForegroundColor Red
                    # 1. Retrieve the HTTP status code
                    $StatusCode = $_.Exception.Response.StatusCode.value__

                    # 2. Extract the error body
                    $ErrorStream = $_.Exception.Response.GetResponseStream()
                    $Reader = New-Object System.IO.StreamReader($ErrorStream)
                    $ResponseBody = $Reader.ReadToEnd()
    
                    # 3. Convert to a PowerShell object to access mod.io's specific error_ref
                    $ErrorDetails = $ResponseBody | ConvertFrom-Json

                    if ($StatusCode -eq 400) {
                        Write-Warning "Not Currently Subscribed to $modid"
                    }
                }

                $headers2 = @{
                    "Authorization" = "Bearer $token"
                    "Accept"        = "application/json"
                }

                $endpoint = "$apiUrl/games/$gameId/mods/$modid/events"
                $epResult = Invoke-RestMethod -Uri $endpoint -Method Get -Headers $headers2 -ErrorAction Stop

                # Delay for mod.io api limit
                Start-Sleep -Milliseconds 250
            }
        }
        else
        {
            $modid = ($SelectedMods -split " \| ")[1].Trim()
            $ModListData.PSObject.Properties.Remove($modid)

            # Construct the API endpoint
            $endpoint = "$apiUrl/games/$gameId/mods/$modid/subscribe"

            # Execute the Unsubscribe request
            try {
                $response = Invoke-RestMethod -Uri $endpoint -Method Delete -Headers $headers -ErrorAction Stop
                Write-Host "Successfully unsubscribed from mod: $modid" -ForegroundColor Green

               	if(-not(Test-Path "$destinationMods$modid"))
                {
                    Write-Host "Mod: $modid directory not found" -ForegroundColor Yellow
                }
                else
                {
                        if ($AllMods -notcontains [string]$modid) {
                        Write-Host "Deleting Unsubscribed Mod Directory: $modid" -ForegroundColor Red
                        Remove-Item -Path "$destinationMods$modid" -Recurse -Force
                    }
                }
            } catch {
#                Write-Host "Failed to unsubscribe. Error: $_" -ForegroundColor Red
                # 1. Retrieve the HTTP status code
                $StatusCode = $_.Exception.Response.StatusCode.value__

                # 2. Extract the error body
                $ErrorStream = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorStream)
                $ResponseBody = $Reader.ReadToEnd()

                # 3. Convert to a PowerShell object to access mod.io's specific error_ref
                $ErrorDetails = $ResponseBody | ConvertFrom-Json

                if ($StatusCode -eq 400) {
                    Write-Warning "Not Currently Subscribed to $modid"
                }
            }

            $headers2 = @{
                "Authorization" = "Bearer $token"
                "Accept"        = "application/json"
            }

            $endpoint = "$apiUrl/games/$gameId/mods/$modid/events"
            $epResult = Invoke-RestMethod -Uri $endpoint -Method Get -Headers $headers2 -ErrorAction Stop
        }

        # Update ModList.json 
        $ModListData | ConvertTo-Json | Set-Content $ModListJsonPath

        echo ""
        echo "=============================================="
        echo " Selected Mods have been Unsubscribed/Deleted    "
        echo "=============================================="
        pause
        return
    }
}

function load_server_configuration
{
    param(
        [string]$configPath
    )

    try {
        $configData = Get-Content -Path $configPath -Raw -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        $configData = $false
    }
    return $configData
}

function save_server_configuration
{
    param(
        [PSCustomObject]$configData,
        [string]$configPath
    )

    $configData | ConvertTo-Json | Set-Content -Path $configPath
}


<# 
    Get Valid and Unused Port Number
#>

function get_port_number
{
    param(
        [string]$ExcludedList = @(),
        [string]$portTitle,
        $currentPort = 0
    )

    Write-Host "Excluded Ports: $($ExcludedList -join ', ')" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press ENTER to keep current Port $currentPort." -ForegroundColor Yellow
    Write-Host ""

    $Port = $null
    $isValid = $false

    do {
        $inputStr = Read-Host -Prompt "Enter a $portTitle number between 1024 and 49151 (Current Port: $currentPort)"
        Write-Host ""

        if ([string]::IsNullOrWhiteSpace($inputStr) -and ($null -ne $currentPort)) {
            if ($currentPort -ne 0)
            {
                $Port = $currentPort
                $isValid = $true
            }
            else
            {
                Write-Host "Input cannot be 0. Try again." -ForegroundColor Red
            }
        }
        else
        {
            # Validate if input is a valid integer and falls within the allowed range
            if ($inputStr -match '^\d+$') {
                $parsedPort = [int]$inputStr

                if ($parsedPort -ge 1024 -and $parsedPort -le 49151) {
                    # Check if the number is in the excluded list
                    if ($ExcludedList -notcontains $parsedPort) {
                        $Port = $parsedPort
                        $isValid = $true
                    } else {
                        Write-Host "That number is on the excluded list. Try again." -ForegroundColor Red
                    }
                } else {
                    Write-Host "Input must be between 1024 and 49151. Try again." -ForegroundColor Red
                }
            } else {
                Write-Host "Invalid input. Please enter a valid whole number." -ForegroundColor Red
            }
        }
    } while (-not $isValid)

    Write-Host "Success! You entered $portTitle : $Port" -ForegroundColor Green
    Write-Host ""
    return $Port
}

<#
    Validate GameStatsToken
#>

function Test-SteamGameStatsToken {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Token
    )

    # Strip common prefixes if an admin pasted the whole launch argument string
    # e.g., strips "-GameStatsToken=" or "GameStatsToken="
    $SanitizedToken = $Token -replace '(?i)-?GameStatsToken=\s*', ''
    $SanitizedToken = $SanitizedToken.Trim()

    # Define validation properties
    # Valid tokens are exactly 32 characters long and match MD5 Hex (0-9, A-F)
    $HexPattern = "^[0-9a-fA-F]{32}$"
    $IsHexMatch = $SanitizedToken -match $HexPattern

    Write-Host "`n=== GameStatsToken Validation Report ===" -ForegroundColor Cyan
    Write-Host "Raw Input String: " -NoNewline; Write-Host $Token -ForegroundColor Yellow
    Write-Host "Processed Token:  " -NoNewline; Write-Host $SanitizedToken -ForegroundColor Gray

    if ($IsHexMatch) {
        Write-Host "[SUCCESS] Token structure is 100% correct!" -ForegroundColor Green
        Write-Host "• Length check: Passed (Exactly 32 characters)" -ForegroundColor Green
        Write-Host "• Alphanumeric/Hex check: Passed (Valid characters only)" -ForegroundColor Green
        return $SanitizedToken
    } else {
        Write-Host "[FAILURE] The Token provided is structurally INVALID!" -ForegroundColor Red
        
        # Diagnostics
        if ($SanitizedToken.Length -ne 32) {
            Write-Host "• Length check: Failed (Length is $($SanitizedToken.Length) but must be exactly 32)" -ForegroundColor Red
        }
        if ($SanitizedToken -match '[^0-9a-fA-F]') {
            Write-Host "• Character check: Failed (Contains illegal non-hex characters outside of 0-9 and A-F)" -ForegroundColor Red
        }
        
        Write-Host "`n[FIX] Please regenerate a fresh token at your game's official web panel." -ForegroundColor Yellow
        return $false
    }
}

function get-GameStatsToken
{
    param(
        [string]$promptQuestion,
        $textData = ""
    )

    Write-Host "Press ENTER to keep: $textData" -ForegroundColor Green
    Write-Host ""

    do {
        $TokenInput = Read-Host "$promptQuestion"

        # If input is blank, break out of the loop immediately
        if ([string]::IsNullOrWhiteSpace($TokenInput) -and -not([string]::IsNullOrWhiteSpace($textData))) {
            $TokenInput = $textData
            break
        }

        $Result = Test-SteamGameStatsToken -Token $TokenInput

        if (-not $Result) {
            Write-Host "`n---------------Invalid Token----------------" -ForegroundColor DarkGray
        }

    } while (-not $Result)
    
    pause
    return $TokenInput
}

function Test-SteamGSLTToken {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Token
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        Write-Host "`n[CANCELLED] No GSLT token provided. Exiting." -ForegroundColor Orange
        return $false
    }

    # Clean up whitespace around the direct token entry
    $SanitizedToken = $Token.Trim()

    # Define GSLT validation properties (Exactly 32 alphanumeric characters)
    $GSLTPattern = "^[0-9a-zA-Z]{32}$"
    $IsGSLTMatch = $SanitizedToken -match $GSLTPattern

    # Present Results
    Write-Host "`n=== Steam GSLT Validation Report ===" -ForegroundColor Cyan
    Write-Host "Raw Input String: " -NoNewline; Write-Host $Token -ForegroundColor Yellow
    Write-Host "Processed Token:  " -NoNewline; Write-Host $SanitizedToken -ForegroundColor Gray

    if ($IsGSLTMatch) {
        Write-Host "[SUCCESS] GSLT structure is 100% correct!" -ForegroundColor Green
        Write-Host "• Length check: Passed (Exactly 32 characters)" -ForegroundColor Green
        Write-Host "• Character check: Passed (Valid alphanumeric values)`n" -ForegroundColor Green
        return $SanitizedToken
    } else {
        Write-Host "[FAILURE] The Token provided is structurally INVALID for a GSLT!" -ForegroundColor Red
        
        if ($SanitizedToken.Length -ne 32) {
            Write-Host "• Length check: Failed (Length is (SanitizedToken.Length) but must be exactly 32)" -ForegroundColor Red
        }
        if ($SanitizedToken -match '[^0-9a-zA-Z]') {
            Write-Host "• Character check: Failed (Contains illegal special characters or symbols)" -ForegroundColor Red
        }
        return $false
    }
}

function get-GSLTToken
{
    param(
        [string]$promptQuestion,
        $textData = ""
    )

    Write-Host "Press ENTER to keep: $textData" -ForegroundColor Green
    Write-Host ""

    do {
        # Prompt user for input
        $TokenInput = Read-Host "$promptQuestion"

        # Catch empty string inputs immediately to break out of the loop safely
        if ([string]::IsNullOrWhiteSpace($TokenInput) -and -not([string]::IsNullOrWhiteSpace($textData))) {
            $TokenInput = $textData
            break
        }

        # Execute the validation function
        $Result = Test-SteamGSLTToken -Token $TokenInput

        if (-not $Result) {
            Write-Host "`n---------------Invalid Token----------------" -ForegroundColor DarkGray
        }

    } while (-not $Result)

    pause
    return $TokenInput
}
<# 
    Get Text input allow Password and RconPassword to be empty
#>

function get_text_input
{
    param(
        [string]$promptQuestion,
        [string]$variablename,
        $textData = ""
    )

    $isValid = $false
    Write-Host "Press ENTER to keep: $textData" -ForegroundColor Green
    Write-Host ""

    do {
        [System.Windows.Forms.SendKeys]::SendWait($textData)
        $inputStr = Read-Host -Prompt "$promptQuestion"
        Write-Host ""

        if ([string]::IsNullOrWhiteSpace($inputStr)) 
        {
            if (($variablename -eq "Password") -or ($variablename -eq "RconPassword") -or ($variablename -eq "MutatorList"))
            {
                $returnText = ""
                $isValid = $true
            }
            elseif (-not ([string]::IsNullOrWhiteSpace($textData)))
            {
                $returnText = $textData
                $isValid = $true
            }
            else
            {
                Write-Host ""
                if ($variablename -eq "MaxPlayers") 
                { 
                    Write-Warning "Input must be a number between 1 and 32." 
                }
                else 
                { 
                    Write-Warning "Input must be between 5 and 128 characters." 
                }
                Write-Host ""
            }
        }
        else
        {
            if ($variablename -eq "MaxPlayers")
            {
                $parsedPlayers = $inputStr -as [int]

                # If it's a valid number and within the 1-32 threshold
                if ($null -ne $parsedPlayers -and $parsedPlayers -ge 1 -and $parsedPlayers -le 32) 
                {
                    $returnText = $parsedPlayers
                    $isValid = $true
                }
                else
                {
                    Write-Host ""
                    Write-Warning "Input must be a valid number between 1 and 32 players."
                    Write-Host ""
                }
            }
            elseif ($variablename -eq "MutatorList")
            {
                if ($inputStr.Length -eq 0 -or $inputStr -match '^[a-zA-Z0-9_-]+(?:,[a-zA-Z0-9_-]+)*$') {
                    $returnText = $inputStr
                    $isValid = $true
                }
                else
                {
                    Write-Host ""
                    Write-Warning "Input must contain NO spaces, and each word must be delimited by a comma (or leave completely blank)."
                    Write-Host ""
                }
            }
            else
            {
                $maxLength = if ($inputStr.Contains("[ScenarioCount] ")) { 78 } else { 63 }

                if ($inputStr.Length -le $maxLength -and $inputStr.Length -ge 5) {
                    $returnText = $inputStr
                    $isValid = $true
                }
                else
                {
                    Write-Host ""
                    Write-Warning "Input must be from 5 to $maxLength characters."
                    Write-Host ""
                }
            }
        }
    } while (-not $isValid)

    Write-Host ""
    Write-Host "Success! You entered $variablename = $returnText" -ForegroundColor Green
    Write-Host ""
    return $returnText
}

function edit_TXT_config_files
{
    param(
        [string]$menuTitle,
        [int]$returnType,
        [string[]]$workingListArray
    )

    # menuTitle = "Server Mutator Wizard"
    # returnType 1 = Mutator - $configData.Mutators = $mutatorList -join ','
    #            2 = Admins - $singleString = $mutatorList -join [Environment]::NewLine
    #            3 = bootmaps - $singleString = $mutatorList -join [Environment]::NewLine - GUI for bootmaps
    #            4 = mapcycle - $singleString = $mutatorList -join [Environment]::NewLine - gui for mapcycle
    #            5 = Message of the Day Editor
    #            6 = Game.ini Editor
    #            7 = Engine.ini Editor

    $workingList = New-Object System.Collections.Generic.List[string] (,[string[]]@($workingListArray))

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # 1. Define your initial input variable
    $myTextVariable = $workingListArray -join [Environment]::NewLine

    # Create the main window form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $menuTitle
    $form.Size = New-Object System.Drawing.Size(800,580)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)

    # --- NEW: Create Column Header Bar Labels ---
    if ($returnType -eq 1)
    {
        $headers = @("Mutators", "One", "per", "Line")
    }
    elseif ($returnType -eq 2)
    {
        $headers = @("Admin", "Steam64ID", "One", "per", "Line")
    }
    elseif ($returnType -eq 3)
    {
        $headers = @("MapName", "?Scenario=", "?Game=", "?Lighting=", "?Mutators=")
    }
    elseif ($returnType -eq 4)
    {
        $headers = @("(Scenario=`"`"", ",Mode=`"`"", ",Lighting=`"`"", ",Options=`"`")")
    }
    elseif ($returnType -eq 5)
    {
        $headers = @("Message", "of", "the", "Day")
    }
    elseif ($returnType -eq 6)
    {
        $headers = @("Server", "Game.ini", "Editor")
    }
    elseif ($returnType -eq 7)
    {
        $headers = @("Server", "Engine.ini", "Editor")
    }


    $labelWidth = 152
    $startX = 10
    $yPos = 15

    foreach ($header in $headers) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $header
        $label.Location = New-Object System.Drawing.Point($startX, $yPos)
        $label.Size = New-Object System.Drawing.Size($labelWidth, 30)
        $label.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
        $label.ForeColor = [System.Drawing.Color]::Black
        $form.Controls.Add($label)
    
        $startX += $labelWidth # Shift next label to the right
    }

    # Create a Container Panel to handle the rounded corners
    $PanelContainer = New-Object System.Windows.Forms.Panel
    $PanelContainer.Location = New-Object System.Drawing.Point(10, 45)
    $PanelContainer.Size = New-Object System.Drawing.Size(764, 430)
    $PanelContainer.Anchor = "Top, Bottom, Left, Right"
    $PanelContainer.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#FFFFFF") # Match TextBox background

    # Custom Paint Event to draw the rounded border on the panel
    $PanelContainer.Add_Paint({
        param($sender, $e)
        
        $Graphics = $e.Graphics
        $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    
        # Define corner radius and bounding rectangle
        $Radius = 5
        $Rect = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 1), ($sender.Height - 1))
    
        # Build the rounded path
        $Path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $Path.AddArc($Rect.X, $Rect.Y, $Radius, $Radius, 180, 90)
        $Path.AddArc(($Rect.X + $Rect.Width - $Radius), $Rect.Y, $Radius, $Radius, 270, 90)
        $Path.AddArc(($Rect.X + $Rect.Width - $Radius), ($Rect.Y + $Rect.Height - $Radius), $Radius, $Radius, 0, 90)
        $Path.AddArc($Rect.X, ($Rect.Y + $Rect.Height - $Radius), $Radius, $Radius, 90, 90)
        $Path.CloseAllFigures()
    
        # Optional: Draw a subtle border outline (e.g., Light Gray)
        $Pen = New-Object System.Drawing.Pen([System.Drawing.Color]::LightGray, 1)
        $Graphics.DrawPath($Pen, $Path)
    
        # Clip the panel's region so child controls (the TextBox) don't bleed out of the curves
        $sender.Region = New-Object System.Drawing.Region($Path)
    })

    # Modify your existing TextBox to be borderless and fit inside the panel
    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None # Hides sharp native border
    $textBox.Location = New-Object System.Drawing.Point(10, 10)     # Offset slightly for padding
    $textBox.Size = New-Object System.Drawing.Size(744, 410)        # Smaller than panel to create padding
    $textBox.MultiLine = $true
    $textBox.ScrollBars = "Vertical"
    $textBox.Anchor = "Top, Bottom, Left, Right"
    $textBox.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $textBox.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#FFFFFF") # Matches the container
    $textBox.MaxLength = 0 
    $textBox.Text = $myTextVariable

    # Add TextBox to the Panel, and Add Panel to the Main Form
    $PanelContainer.Controls.Add($textBox)
    $form.Controls.Add($PanelContainer)

    # Flag to determine if we should save the changes
    $Global:isSaved = $false

    # Button dimensions and spacing
    $buttonWidth = 100
    $buttonHeight = 30
    $buttonSpacing = 15
    $totalButtonsWidth = ($buttonWidth * 2) + $buttonSpacing

    # ($form.ClientSize.Width / 2) finds the middle of the window area
    $saveButtonX = ($form.ClientSize.Width / 2) - ($totalButtonsWidth / 2)
    $cancelButtonX = $saveButtonX + $buttonWidth + $buttonSpacing
    $buttonY = 490

    # Create the Save button
    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Location = New-Object System.Drawing.Point($saveButtonX, $buttonY)
    $saveButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $saveButton.Text = "Save"
    $saveButton.Anchor = "Bottom, Left"
    $saveButton.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $saveButton.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $saveButton.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)

    # CRITICAL STYLE SETTINGS: 
    # If these two lines are missing, Windows draws a sharp fallback border over the curve.
    $saveButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $saveButton.FlatAppearance.BorderSize = 0

    # FORCE ROUNDING VIA PAINT EVENT (Fixes the non-rounding issue)
    $saveButton.Add_Paint({
        param($sender, $e)

        $width = $sender.Width
        $height = $sender.Height
        $radius = 5 # Change this to make it more or less round
        $diameter = $radius * 2

        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    
        # Construct the curved shape path
        $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
        $path.AddArc(($width - $diameter), 0, $diameter, $diameter, 270, 90)
        $path.AddArc(($width - $diameter), ($height - $diameter), $diameter, $diameter, 0, 90)
        $path.AddArc(0, ($height - $diameter), $diameter, $diameter, 90, 90)
        $path.CloseAllFigures()
    
        # Apply the mask directly to the active control region
        $sender.Region = New-Object System.Drawing.Region($path)
    })

    $saveButton.Add_Click({
        $Global:isSaved = $true
        $form.Close()
    })
    $form.Controls.Add($saveButton)

    # Create the Cancel button
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point($cancelButtonX, $buttonY)
    $cancelButton.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $cancelButton.Text = "Cancel"
    $cancelButton.Anchor = "Bottom, Left"
    $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $cancelButton.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $cancelButton.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)

    # CRITICAL STYLE SETTINGS: 
    # If these two lines are missing, Windows draws a sharp fallback border over the curve.
    $cancelButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $cancelButton.FlatAppearance.BorderSize = 0

    # FORCE ROUNDING VIA PAINT EVENT (Fixes the non-rounding issue)
    $cancelButton.Add_Paint({
        param($sender, $e)

        $width = $sender.Width
        $height = $sender.Height
        $radius = 5 # Change this to make it more or less round
        $diameter = $radius * 2

        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    
        # Construct the curved shape path
        $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
        $path.AddArc(($width - $diameter), 0, $diameter, $diameter, 270, 90)
        $path.AddArc(($width - $diameter), ($height - $diameter), $diameter, $diameter, 0, 90)
        $path.AddArc(0, ($height - $diameter), $diameter, $diameter, 90, 90)
        $path.CloseAllFigures()
    
        # Apply the mask directly to the active control region
        $sender.Region = New-Object System.Drawing.Region($path)
    })

    $cancelButton.Add_Click({
        $Global:isSaved = $false
        $form.Close()
    })
    $form.Controls.Add($cancelButton)

    # Prevent auto-selection when the form becomes visible
    $form.Add_Shown({
        $textBox.SelectionStart = 0
        $textBox.SelectionLength = 0
    })
    # Display the window (Script pauses here until closed)
    [void]$form.ShowDialog()

    if ($Global:isSaved) {
        # Save the final text back to your variable after closing
        if ($returnType -eq 1) # Mutator List
        {
            $returnText = $textBox.Text -replace '(?s)\s+$', ''
            return $returnText -replace '\r\n', ','
        }
        elseif ($returnType -eq 2) # Admin List
        {
             # check each Steam64ID to see if correct
            $adminList = $textBox.Text -replace '(?s)\s+$', ''

            $adminListArray = $adminList -split '\r?\n'

            # Regex pattern for a 17-digit Steam64ID
            $steam64Pattern = '^7656119\d{10}$'

            # Initialize an empty array to store the matches
            $validIDarray = @()

            # Scan through the loop
            foreach ($item in $adminListArray) {
                if ($item -match $steam64Pattern) {
                    # Add it to our results collection
                    $validIDarray += $item
                } else {
                    # Optional: Handle invalid items
                    Write-Warning "Skipped invalid item: $item"
                }
            }

           Write-Host ""

            # Final filtered list
            $uniqueIDs = $validIDarray | Select-Object -Unique

            foreach ($item in $uniqueIDs) {
                Write-Host "Found valid ID: $item" -ForegroundColor Green
            }

            $validIDs = $uniqueIDs -join "`r`n"

            if (-not [string]::IsNullOrWhiteSpace($validIDs)) 
            {
                pause
            }

            return $validIDs
        }
        elseif ($returnType -eq 3) # Boot Maps
        {
            # format each line to make sure entries are correct
            $sb = New-Object System.Text.StringBuilder
            $bootList = $textBox.Text -replace '(?s)\s+$', ''
            $bootListArray = $bootList -split '\r?\n'
            if ($bootListArray.Count -gt 0)
            {
                # Display items dynamically with their index
                for ($i = 0; $i -lt $bootListArray.Count; $i++) {
                    $selection = $bootListArray[$i]

                    $bootItem = $selection -split '\?'
                                
                    # Map the resulting items to specific variables
                    $mapName     = $bootItem[0]
                    $scenario    = ($bootItem -match '^Scenario=')[0]
                    $gamemode    = ($bootItem -match '^Game=')[0]
                    $lighting    = ($bootItem -match '^Lighting=')[0]
                    $mutators    = ($bootItem -match '^Mutators=')[0]

                    # To clean off the "key=" prefixes, you can remove them via string replacement
                    $scenario = $scenario -replace '^Scenario='
                    $gamemode = $gamemode -replace '^Game='
                    $lighting = $lighting -replace '^Lighting='
                    $mutators = $mutators -replace '^Mutators='
                    $mutators = $mutators -replace '\[Mutators\],', ''
                    $mutators = $mutators -replace '\[Mutators\]', ''
        
                    $bootmapTXT = $mapName + "?Scenario=" + $scenario +"?Game=" + $gameMode + "?Lighting=" + $lighting +"?Mutators=" + $mutators
                    [void]$sb.AppendLine($bootmapTXT)
                }
            }
            $returnText = $sb.ToString()
            return $returnText -replace '(?s)\s+$', ''
        }
        elseif ($returnType -eq 4) # Map Cycle
        {
            # format each line to make sure entries are correct
            $sb = New-Object System.Text.StringBuilder
            $mapcycleList = $textBox.Text -replace '(?s)\s+$', ''
            $mapcycleListArray = $mapcycleList -split '\r?\n'
            if ($mapcycleListArray.Count -gt 0)
            {
                # Display items dynamically with their index
                for ($i = 0; $i -lt $mapcycleListArray.Count; $i++) {
                    $mapItem = $mapcycleListArray[$i]

                    # Extract the key-value pairs
                    $matches = @{}
                    [regex]::Matches($mapItem, '(\w+)="([^"]*)"') | ForEach-Object {
                        $matches[$_.Groups[1].Value] = $_.Groups[2].Value
                    }

                    # Store into individual variables
                    $scenario = $matches['Scenario']
                    $gameMode = $matches['Mode']
                    $lighting = $matches['Lighting']
                    $options  = $matches['Options']

                    $mapcycleTXT = "(Scenario=`"" + $scenario +"`",Mode=`"" + $gameMode + "`",Lighting=`"" + $lighting +"`",Options=`"" + $options + "`")"
                    [void]$sb.AppendLine($mapcycleTXT)
                }
            }
            $returnText = $sb.ToString()
            return $returnText -replace '(?s)\s+$', ''
        }
        elseif ($returnType -eq 5 -or $returnType -eq 6 -or $returnType -eq 7)
        {
            return $textBox.Text -replace '(?s)\s+$', ''
        }
    } else {
        if ($returnType -eq 1)
        {
            return $workingList  -join ','
        }
        else
        {
            return $workingList -join [Environment]::NewLine
        }
    }
}

<#
    Server Configuration Editor
#>

function server_configuration_editor
{
    param(
        [string]$Base_Server_ID,
        [string]$configPath,
        [bool]$isNewServer = $false,
        [array]$textArray
    )

    $selection = 1
    $totalSwitches = 15
    $configData = load_server_configuration -configPath $configPath

    if ($configData -eq $false)
    {
        Write-Host "`n Configuration not found for: $Base_Server_ID" -ForegroundColor Red
        pause
        return
    }

    do {    
        Clear-Host
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "         Server Configuration Wizard          " -ForegroundColor Yellow
        Write-Host "         Server ID: $Base_Server_ID          " -ForegroundColor Green
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host ""

        Write-Host "    1. Set Server Ports - " -NoNewLine
        Write-Host "Port: " -ForegroundColor Cyan -NoNewLine
        Write-Host "$($configData.Port)" -ForegroundColor Green -NoNewLine
        Write-Host ", Query Port: " -ForegroundColor Cyan -NoNewLine
        Write-Host "$($configData.QueryPort)" -ForegroundColor Green -NoNewLine
        Write-Host ", RconListenPort: " -ForegroundColor Cyan -NoNewLine
        Write-Host "$($configData.RconListenPort)" -ForegroundColor Green
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        If($isAdmin)
        {
            Write-Host "       Enabled: Running as Administrator" -ForegroundColor Green
        }
        else
        {
            Write-Host "       Disabled: Start Server Manager as Administrator" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "    2. Server Passwords - " -NoNewLine
        Write-Host "Server Password: " -ForegroundColor Cyan -NoNewLine
        Write-Host "$($configData.Password)" -ForegroundColor Green -NoNewLine
        Write-Host " , Rcon Password: " -ForegroundColor Cyan -NoNewLine
        Write-Host "$($configData.RconPassword)" -ForegroundColor Green
        Write-Host "       * Rcon Password REQUIRED for Server Analytics and Server Dashboard" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    3. Server Host Name - " -NoNewLine
        Write-Host "$($configData.HostName)" -ForegroundColor Green
        Write-Host ""
        Write-Host "    4. Maximum Players Supported - " -NoNewLine
        Write-Host "$($configData.MaxPlayers)" -ForegroundColor Green -NoNewLine
        Write-Host " Players" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "    5. Server GameStats Token - " -NoNewLine
        Write-Host "GameStatsToken: " -ForegroundColor Cyan -NoNewLine
        Write-Host "$($configData.GameStatsToken)" -ForegroundColor Green
        Write-Host "       * REQUIRED            " -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    6. Server GSLT Token - " -NoNewLine
        Write-Host "GSLTToken: " -ForegroundColor Cyan -NoNewLine
        Write-Host "$($configData.GSLTToken)" -ForegroundColor Green
        Write-Host "       * REQUIRED            " -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    7. Edit Mutators - " -NoNewLine
        Write-Host "Mutators: " -ForegroundColor Cyan -NoNewLine
        Write-Host "$($configData.Mutators)" -ForegroundColor Green
        Write-Host ""
        Write-Host "    8. Edit Motd.txt File"
        Write-Host ""
        Write-Host "    9. Edit Admins.txt File"
        Write-Host ""
        Write-Host "   10. Edit bootmaps.txt File"
        Write-Host ""
        Write-Host "   11. Edit mapcycle.txt File"
        Write-Host ""
        Write-Host "   12. Edit Game.ini File"
        Write-Host ""
        Write-Host "   13. Edit Engine.ini File"
        Write-Host ""
        Write-Host "   14. Security Code Wizard - " -NoNewLine
        Write-Host "SecurityCode: " -ForegroundColor Cyan -NoNewLine
        Write-Host "$($configData.SecurityCode)" -ForegroundColor Green
        Write-Host ""
        Write-Host "   15. Exit"
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "              Changes Auto Saved              " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host ""

        if (-not $isNewServer) {
            $selection = Read-Host -Prompt " Please enter your selection (1-$totalSwitches)"
        }

        switch ($selection) {
            '1' {
                $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                If($isAdmin)
                {
                    Write-Host "==============================================" -ForegroundColor Cyan
                    Write-Host "               Set Server Ports               " -ForegroundColor Yellow
                    Write-Host "==============================================" -ForegroundColor Cyan
                    Write-Host ""

                    $ExcludedList = @()
                        
                    $configData.Port = get_port_number -ExcludedList $ExcludedList -portTitle "Server Port" -currentPort $configData.Port
                    $ExcludedList+=$configData.Port
                    $configData.QueryPort = get_port_number -ExcludedList $ExcludedList -portTitle "Server Query Port" -currentPort $configData.QueryPort
                    $ExcludedList+=$configData.QueryPort
                    $configData.RconListenPort = get_port_number -ExcludedList $ExcludedList -portTitle "Rcon Listen Port" -currentPort $configData.RconListenPort

                    save_server_configuration -configData $configData -configPath $configPath

                    if ($isNewServer -eq $false)
                    {
                        $Port = $configData.Port
                        $QueryPort = $configData.QueryPort
                            
                        $TCP_UDPServerPath = Join-Path -Path $PSScriptRoot -ChildPath "InsurgencySandstorm\steamapps\common\sandstorm_server\insurgency\binaries\win64\InsurgencyServer-Win64-Shipping.exe"
                        $displayName = "Insurgency $Base_Server_ID TCP"

                        $existingRule = Get-NetFirewallRule -DisplayName $displayName -ErrorAction SilentlyContinue | 
                            Where-Object { 
                                # Check if the program matches
                                ($_ | Get-NetFirewallApplicationFilter).Program -eq $TCP_UDPServerPath -and
                                # Check if the protocol is TCP
                                ($_ | Get-NetFirewallPortFilter).Protocol -eq 'TCP'
                            }

                        if (-not $existingRule) {
                            try {
                                New-NetFirewallRule -DisplayName $displayName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port,$QueryPort -Program $TCP_UDPServerPath -Profile Private,Public
                                Write-Warning "Insurgency $Base_Server_ID TCP Ports $Port,$QueryPort are now Open"
                            }
                            catch {
                                Write-Host "Failure: Failed to create firewall rule '$displayName'." -ForegroundColor Red
                                Write-Host "Error details: $_" -ForegroundColor Yellow
                            }
                        }
                        else
                        {
                            $existingRule | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -LocalPort $Port,$QueryPort
                            Write-Host "Insurgency $Base_Server_ID TCP Ports $Port,$QueryPort are Open"  -ForegroundColor Green
                        }

                        $displayName = "Insurgency $Base_Server_ID UDP"

                        $existingRule = Get-NetFirewallRule -DisplayName $displayName -ErrorAction SilentlyContinue | 
                            Where-Object { 
                                # Check if the program matches
                                ($_ | Get-NetFirewallApplicationFilter).Program -eq $TCP_UDPServerPath -and
                                # Check if the protocol is UDP
                                ($_ | Get-NetFirewallPortFilter).Protocol -eq 'UDP'
                            }
                            
                        if (-not $existingRule) {
                            try {
                                New-NetFirewallRule -DisplayName $displayName -Direction Inbound -Action Allow -Protocol UDP -LocalPort $Port,$QueryPort -Program $TCP_UDPServerPath -Profile Private,Public
                                Write-Warning "Insurgency $Base_Server_ID UDP Ports $Port,$QueryPort are now Open"
                            }
                            catch {
                                Write-Host "Failure: Failed to create firewall rule '$displayName'." -ForegroundColor Red
                                Write-Host "Error details: $_" -ForegroundColor Yellow
                            }
                        }
                        else
                        {
                            $existingRule | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -LocalPort $Port,$QueryPort
                            Write-Host "Insurgency $Base_Server_ID UDP Ports $Port,$QueryPort are Open" -ForegroundColor Green
                        }
                        Write-Host ""
                        Pause
                    }
                }
            }
            '2' {
                Write-Host ""
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host "               Server Passwords               " -ForegroundColor Yellow
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host ""

                Write-Host "Enter Server Password if you want to restict who can join"
                Write-Host "otherwise leave empty (Current Password: $($configData.Password)"
                $configData.Password = get_text_input -promptQuestion "Enter Server Password if needed" -variablename "Password" -textData $configData.Password
                Write-Host ""

                # Loop until the password length is between 5 and 32 characters
                while ($true) {
                    Write-Host "Enter Rcon Password (REQUIRED: 5-32 Characters)" -ForegroundColor Yellow
                    Write-Host "Needed for Server Analytics and Server Dashboard (Current RconPassword: $($configData.RconPassword))"
    
                    # Capture the input using your custom function
                    $inputPassword = get_text_input -promptQuestion "Enter Rcon Password" -variablename "RconPassword" -textData $configData.RconPassword

                    # Validate the length
                    if ($inputPassword.Length -ge 5 -and $inputPassword.Length -le 32) {
                        $configData.RconPassword = $inputPassword
                        break # Exit the loop if valid
                    } else {
                        Write-Host "ERROR: Password must be between 5 and 32 characters. You entered $($inputPassword.Length) characters.`n" -ForegroundColor Red
                    }
                }

                # Save the valid configuration
                save_server_configuration -configData $configData -configPath $configPath
            }
            '3' {
                Write-Host ""
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host "               Server Host Name               " -ForegroundColor Yellow
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host ""

                Write-Host "Insert [ScenarioCount] in host name to include the number of Scenarios on your server."
                Write-Host ""
                Write-Host "EX: This is my server with [ScenarioCount] Scenarios"
                Write-Host ""
                Write-Host "Displays: This is my server with 43 Scenarios"
                Write-Host ""
                Write-Host "Input must be from 5 to 63 characters  (78 characters with [ScenarioCount])."

                $configData.HostName = get_text_input -promptQuestion "Enter new Host Name" -variablename "HostName" -textData $configData.HostName

                save_server_configuration -configData $configData -configPath $configPath
            }
            '4' {
                Write-Host ""
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host "           Maximum Players Supported          " -ForegroundColor Yellow
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host ""

                $configData.MaxPlayers = get_text_input -promptQuestion "Enter Maximum number of players from 1 to 32 players" -variablename "MaxPlayers" -textData $configData.MaxPlayers

                save_server_configuration -configData $configData -configPath $configPath
            }
            '5' {
                Write-Host ""
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host "            Server GameStats Token            " -ForegroundColor Yellow
                Write-Host "                 * REQUIRED            " -ForegroundColor Yellow
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host ""

                $configData.GameStatsToken = get-GameStatsToken -promptQuestion "Enter Steam GameStatsToken (or press Enter to cancel)" -textData $configData.GameStatsToken

                save_server_configuration -configData $configData -configPath $configPath
            }
            '6' {
                Write-Host ""
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host "              Server GSLT Token               " -ForegroundColor Yellow
                Write-Host "                 * REQUIRED            " -ForegroundColor Yellow
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host ""

                $configData.GSLTToken = get-GSLTToken -promptQuestion "Enter Steam GSLT Token (or press Enter to cancel)" -textData $configData.GSLTToken
            }
            '7' {
                Write-Host ""
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host "              Mutator Editor              " -ForegroundColor Yellow
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host ""

                if (-not $isNewServer) {
                    $workingList = $configData.Mutators -split ','
                    $configData.Mutators = edit_TXT_config_files -menuTitle "Server Mutator Editor" -returnType 1 -workingList $workingList
                }
                else
                {
                    $workingList = $configData.Mutators
                    $configData.Mutators = (get_text_input -promptQuestion "Enter list of mutators with commas and no spaces (EX: beyondmeat,NoRestrictPlus,Medicon )" -variablename "MutatorList" -textData "$workingList") -replace '\s+', ''
                }
                save_server_configuration -configData $configData -configPath $configPath
            }
            '8' {
                Write-Host ""
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host "               Motd.txt Editor               " -ForegroundColor Yellow
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host ""

                $directoryPath = Split-Path -Path $configPath

                $iniPath = Join-Path -Path $directoryPath -ChildPath "server\motd.ini"
                $txtPath = Join-Path -Path $directoryPath -ChildPath "server\motd.txt"

                if (Test-Path -Path $iniPath) {
    
                    if (Test-Path -Path $txtPath) {
                        Remove-Item -Path $txtPath -Force
                    }
    
                    Rename-Item -Path $iniPath -NewName "motd.txt"
                }

                $workingPath = Join-Path -Path $directoryPath -ChildPath "server\motd.txt"
                [string[]]$workingList = Get-Content -Path $workingPath
                $textData = edit_TXT_config_files -menuTitle " Message of the Day Editor: $Base_Server_ID" -returnType 5 -workingListArray $workingList

                $textData | Set-Content -Path $workingPath
            }
            '9' {
                Write-Host ""
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host "              Admins.txt Editor              " -ForegroundColor Yellow
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host ""

                $directoryPath = Split-Path -Path $configPath

                $iniPath = Join-Path -Path $directoryPath -ChildPath "server\admins.ini"
                $txtPath = Join-Path -Path $directoryPath -ChildPath "server\admins.txt"

                if (Test-Path -Path $iniPath) {
    
                    if (Test-Path -Path $txtPath) {
                        Remove-Item -Path $txtPath -Force
                    }
    
                    Rename-Item -Path $iniPath -NewName "admins.txt"
                }

                $workingPath = Join-Path -Path $directoryPath -ChildPath "server\admins.txt"

                [string[]]$workingList = Get-Content -Path $workingPath
                $textData = edit_TXT_config_files -menuTitle "Server Administrator SteamID64 ID: $Base_Server_ID" -returnType 2 -workingListArray $workingList

                $textData | Set-Content -Path $workingPath
            }
            '10' {
                Write-Host ""
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host "             bootmaps.txt Editor             " -ForegroundColor Yellow
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host ""

                $directoryPath = Split-Path -Path $configPath
                $workingPath = Join-Path -Path $directoryPath -ChildPath "server\bootmaps.txt"
                [string[]]$workingList = Get-Content -Path $workingPath

                $textData = edit_TXT_config_files -menuTitle "Boot Map Editor: $Base_Server_ID"  -returnType 3 -workingListArray $workingList

                $textData | Set-Content -Path $workingPath
            }
            '11' {
                Write-Host ""
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host "             mapcycle.txt Editor             " -ForegroundColor Yellow
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host ""

                $directoryPath = Split-Path -Path $configPath

                $iniPath = Join-Path -Path $directoryPath -ChildPath "server\Mapcycle.ini"
                $txtPath = Join-Path -Path $directoryPath -ChildPath "server\MapCycle.txt"

                if (Test-Path -Path $iniPath) {
    
                    if (Test-Path -Path $txtPath) {
                        Remove-Item -Path $txtPath -Force
                    }
    
                    Rename-Item -Path $iniPath -NewName "MapCycle.txt"
                }

                $workingPath = Join-Path -Path $directoryPath -ChildPath "server\mapcycle.txt"

                [string[]]$workingList = Get-Content -Path $workingPath

                $textData = edit_TXT_config_files -menuTitle "Map Cycle Editor: $Base_Server_ID" -returnType 4 -workingListArray $workingList

                $textData | Set-Content -Path $workingPath
            }
            '12' {
                if ($isNewServer -eq $false)
                {
                    Write-Host ""
                    Write-Host "==============================================" -ForegroundColor Cyan
                    Write-Host "             Game.ini Editor             " -ForegroundColor Yellow
                    Write-Host "==============================================" -ForegroundColor Cyan
                    Write-Host ""

                    $directoryPath = Split-Path -Path $configPath
                    $workingPath = Join-Path -Path $directoryPath -ChildPath "WindowsServer\Game.ini"
                    [string[]]$workingList = Get-Content -Path $workingPath

                    $textData = edit_TXT_config_files -menuTitle "Game.ini Editor: $Base_Server_ID"  -returnType 6 -workingListArray $workingList
                        
                    $textData | Set-Content -Path $workingPath
                }
            }
            '13' {
                if ($isNewServer -eq $false)
                {
                    Write-Host ""
                    Write-Host "==============================================" -ForegroundColor Cyan
                    Write-Host "             Engine.ini Editor             " -ForegroundColor Yellow
                    Write-Host "==============================================" -ForegroundColor Cyan
                    Write-Host ""

                    $directoryPath = Split-Path -Path $configPath
                    $workingPath = Join-Path -Path $directoryPath -ChildPath "WindowsServer\Engine.ini"
                    [string[]]$workingList = Get-Content -Path $workingPath

                    $textData = edit_TXT_config_files -menuTitle "Engine.ini Editor: $Base_Server_ID"  -returnType 7 -workingListArray $workingList
                        
                    $textData | Set-Content -Path $workingPath
                }
            }
            '14' {
                Write-Host ""
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host "             Security Code Wizard             " -ForegroundColor Yellow
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host ""

                $response = User-Confirm "Do you need to request a new SecurityCode from mod.io (Not needed if newly IMPORTED Server)?"

                if ($response -eq 'y') 
                {
                    $apiKey = "bbf3af200848aef28418c032a601e7a2"
                    $gameId = "254" # e.g., 254
                    $url = "https://g-$gameId.modapi.io/v1/oauth/emailrequest"

                     do {
                        $serverEmail = Read-Host -Prompt "Enter Server/Game Email Address"
   
                        # Regex pattern to ensure proper email format
                        $isValid = $serverEmail -match '^[A-Z0-9._%%+-][A-Z0-9._%%+-]*@[A-Z0-9.-][A-Z0-9.-]*\.[A-Z][A-Z]*$'

                        if (-not $isValid) {
                            Write-Host "Invalid format. Please try again." -ForegroundColor Red
                        }
                    } until ($isValid)

                    Write-Host ""
                    Write-Host "Success! '$serverEmail' is a valid email format." -ForegroundColor Green

                    # Define headers and body
                    $headers = @{
                        "Accept" = "application/json"
                        "Content-Type" = "application/x-www-form-urlencoded"
                    }
    
                    $body = @{
                        "api_key" = $apiKey
                        "email" = $serverEmail
                    }

                    # Send the POST request
                    try {
                        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
                        $response | ConvertTo-Json | Out-Null
                        Write-Host ""
                        Write-Host "Success: Security code requested. Check your email for the 5-digit code." -ForegroundColor Green
                        Write-Host ""
                        Write-Host $response.message
                        Write-Host ""
                        }
                    catch {
                        Write-Host ""
                        Write-Host "Error occurred: $_" -ForegroundColor Red
                    }

                    do {
                        $code = Read-Host -Prompt "Enter 5-digit Security Code sent to Email ($serverEmail) "
                    } while ($code -notmatch '^[a-zA-Z0-9]{5}$')

                    Write-Host ""
                    $validCode = $code.ToUpper()
                    Write-Host "Accepted and capitalized code: $validCode" -ForegroundColor Green
                    Write-Host ""

                    $configData.SecurityCode = $validCode

                    Write-Host "SecurityCode in ServerStartup.json updated for $Base_Server_ID" -ForegroundColor Green
                    Write-Host "The code is good for only 15 minutes and the server must be started before that time runs out."
                }

                save_server_configuration -configData $configData -configPath $configPath
            }
            '15' {
                return
            }
            default {
                Write-Host "`n Invalid choice! Please select a number from 1 to $totalSwitches." -ForegroundColor Red
            }
        }

        if ($isNewServer -eq $true)
        {
            $selection++
        }
    } until ($selection -eq $totalSwitches -or -not($selection))
}

<#
    Change the startup configuration of a server
#>

function change_server_configuration
{

    do {
        Clear-Host
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "          Change Server Configuration         " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host ""

        [int]$global:Server_List_Count = show_server_list
        $exitSelection = $global:Server_List_Count + 1
        Write-Host " $exitSelection. Exit Change Server Configuration" -ForegroundColor DarkYellow
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host ""

        [int]$selection = Read-Host -Prompt " Please enter your selection (1-$exitSelection)"
    
        if(($selection -gt 0) -and ($selection -le $global:Server_List_Count))
        {
            $downOne = $selection - 1
            Write-Host ""
            $countup = 0
            foreach ($item in $global:SeverListData) {
                
                # Get each dynamic top element name and value
                foreach ($property in $item.PSObject.Properties) {
                    $server_ID = $property.Name

                    if ($countup -eq $downOne)
                    {
                        $Base_Server_ID = $server_ID
                        $isDisabled = $property.Value.Disabled
                    }
                    $countup = $countup + 1
                }
            }

            Write-Host "==============================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host ("{0,24} {1,-60}" -f "Server ID: ", "$Base_Server_ID") -ForegroundColor Yellow
            Write-Host ""

            $configPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ServerData\$Base_Server_ID\ServerStartup.json"
            server_configuration_editor -Base_Server_ID $Base_Server_ID -configPath $configPath -isNewServer $false

        }
    } until ($selection -eq $exitSelection -or -not($selection))
}

<#
    Shows a formatted list of all configured Server_IDs and Execution paths.
#>

function show_server_list
{
    if (($global:SeverListData.PSObject.Properties).count -gt 0) {
        $Server_Count = 1
        $ServerListDisplay = @()
        Write-Host ("{0,-6}{1,-40} {2,-10}`n" -f "[##]", "Server ID", "Server Status") -ForegroundColor Green

        foreach ($property in $global:SeverListData.psobject.Properties) {
            $server_ID   = $property.Name

            if ($property.Value.Disabled) {
                $statusText = "DISABLED"
                $statusColor = "Yellow"
            } else {
                $statusText = "ENABLED"
                $statusColor = "Green"
            }

            Write-Host ("{0,-6}{1,-40} {2,-10}" -f "[$Server_Count]", $server_ID, $statusText) -ForegroundColor $statusColor
            $Server_Count=$Server_Count+1
        }

        $Server_Count=$Server_Count-1

        if ($Server_Count -ne 1)
        {
            $serverPlural = "s"
        }
        else
        {
            $serverPlural = ""
        }

        Write-Host ""
        Write-Host ("{0,32}`n" -f "$Server_Count Server$serverPlural Configured")-ForegroundColor DarkYellow
        return $Server_Count
    }
    else
    {
        Write-Host ("{0,32}`n" -f "0 Servers Configured")-ForegroundColor DarkYellow
        return $Server_Count=0
    }
}

<# 
    Open GUI to allow setting of Server Reboot Times (Global for all servers)
#>

function Schedule_Server_Reboot 
{
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Create main form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Select Multiple Times"
    $form.Size = New-Object System.Drawing.Size(300, 350)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250) # Dark Theme

    $numHour = New-Object System.Windows.Forms.ComboBox
    $numHour.Location = New-Object System.Drawing.Point(30, 30)
    $numHour.Size = New-Object System.Drawing.Size(45, 20)

    for ($i = 1; $i -le 12; $i++) {
        $null = $numHour.Items.Add($i)
    }

    $numHour.SelectedIndex = 0
    $form.Controls.Add($numHour)

    $numMin = New-Object System.Windows.Forms.ComboBox
    $numMin.Location = New-Object System.Drawing.Point(80, 30)
    $numMin.Size = New-Object System.Drawing.Size(45, 20)

    for ($i = 0; $i -le 59; $i++) {
        $null = $numMin.Items.Add($i)
    }

    $numMin.SelectedIndex = 0
    $form.Controls.Add($numMin)

    $ampm = New-Object System.Windows.Forms.ComboBox
    $ampm.Location = New-Object System.Drawing.Point(130, 30)
    $ampm.Size = New-Object System.Drawing.Size(45, 20) # Slightly wider for "AM"/"PM" text

    # Add the AM/PM options
    $null = $ampm.Items.Add("AM")
    $null = $ampm.Items.Add("PM")

    $ampm.SelectedIndex = 0
    $form.Controls.Add($ampm)

    # List Box to show selected times
    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.Location = New-Object System.Drawing.Point(30, 70)
    $listBox.Size = New-Object System.Drawing.Size(220, 180)
    $form.Controls.Add($listBox)

    # Add Button
    $btnAdd = New-Object System.Windows.Forms.Button
    $btnAdd.Location = New-Object System.Drawing.Point(180, 28)
    $btnAdd.Size = New-Object System.Drawing.Size(70, 25)
    $btnAdd.Text = "Add Time"
    $btnAdd.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnAdd.ForeColor = [System.Drawing.Color]::White
    $btnAdd.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 136)

    # CRITICAL STYLE SETTINGS: 
    # If these two lines are missing, Windows draws a sharp fallback border over the curve.
    $btnAdd.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnAdd.FlatAppearance.BorderSize = 0

    # FORCE ROUNDING VIA PAINT EVENT (Fixes the non-rounding issue)
    $btnAdd.Add_Paint({
        param($sender, $e)
    
        $width = $sender.Width
        $height = $sender.Height
        $radius = 5 # Change this to make it more or less round
        $diameter = $radius * 2

        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    
        # Construct the curved shape path
        $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
        $path.AddArc(($width - $diameter), 0, $diameter, $diameter, 270, 90)
        $path.AddArc(($width - $diameter), ($height - $diameter), $diameter, $diameter, 0, 90)
        $path.AddArc(0, ($height - $diameter), $diameter, $diameter, 90, 90)
        $path.CloseAllFigures()
    
        # Apply the mask directly to the active control region
        $sender.Region = New-Object System.Drawing.Region($path)
    })

    $btnAdd.Add_Click({
        $h = $numHour.SelectedItem.ToString("00")
        $m = $numMin.SelectedItem.ToString("00")
        $ap = $ampm.SelectedItem
        $listBox.Items.Add("$h`:$m $ap")
    })
    $form.Controls.Add($btnAdd)

    # Remove Button
    $btnRemove = New-Object System.Windows.Forms.Button
    $btnRemove.Location = New-Object System.Drawing.Point(30, 260)
    $btnRemove.Size = New-Object System.Drawing.Size(120, 25)
    $btnRemove.Text = "Remove Selected"
    $btnRemove.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnRemove.ForeColor = [System.Drawing.Color]::White
    $btnRemove.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 136)

    # CRITICAL STYLE SETTINGS: 
    # If these two lines are missing, Windows draws a sharp fallback border over the curve.
    $btnRemove.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnRemove.FlatAppearance.BorderSize = 0

    # FORCE ROUNDING VIA PAINT EVENT (Fixes the non-rounding issue)
    $btnRemove.Add_Paint({
        param($sender, $e)
    
        $width = $sender.Width
        $height = $sender.Height
        $radius = 5 # Change this to make it more or less round
        $diameter = $radius * 2

        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    
        # Construct the curved shape path
        $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
        $path.AddArc(($width - $diameter), 0, $diameter, $diameter, 270, 90)
        $path.AddArc(($width - $diameter), ($height - $diameter), $diameter, $diameter, 0, 90)
        $path.AddArc(0, ($height - $diameter), $diameter, $diameter, 90, 90)
        $path.CloseAllFigures()
    
        # Apply the mask directly to the active control region
        $sender.Region = New-Object System.Drawing.Region($path)
    })

    $btnRemove.Add_Click({
        if ($listBox.SelectedIndex -ne -1) {
            $listBox.Items.Remove($listBox.SelectedItem)
        }
    })
    $form.Controls.Add($btnRemove)

    # OK / Return Button
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Location = New-Object System.Drawing.Point(170, 260)
    $btnOk.Size = New-Object System.Drawing.Size(80, 25)
    $btnOk.Text = "OK"
    $btnOk.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $btnOk.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 136)

    # CRITICAL STYLE SETTINGS: 
    # If these two lines are missing, Windows draws a sharp fallback border over the curve.
    $btnOk.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnOk.FlatAppearance.BorderSize = 0

    # FORCE ROUNDING VIA PAINT EVENT (Fixes the non-rounding issue)
    $btnOk.Add_Paint({
        param($sender, $e)
    
        $width = $sender.Width
        $height = $sender.Height
        $radius = 5 # Change this to make it more or less round
        $diameter = $radius * 2

        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    
        # Construct the curved shape path
        $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
        $path.AddArc(($width - $diameter), 0, $diameter, $diameter, 270, 90)
        $path.AddArc(($width - $diameter), ($height - $diameter), $diameter, $diameter, 0, 90)
        $path.AddArc(0, ($height - $diameter), $diameter, $diameter, 90, 90)
        $path.CloseAllFigures()
    
        # Apply the mask directly to the active control region
        $sender.Region = New-Object System.Drawing.Region($path)
    })

    $btnOk.Add_Click({
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($btnOk)

    $scheduledTimes = @()
    foreach ($time in $global:ManagerConfig.scheduledTimes) {
        $scheduledTimes += $time
        $null = $listBox.Items.Add($time) 
    }

    # Show form and collect results into an array
    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $scheduledTimes = @()
        foreach ($item in $listBox.Items) {
            $scheduledTimes += $item
        }
    }

    $global:ManagerConfig.scheduledTimes = $scheduledTimes
    $global:ManagerConfig | ConvertTo-Json -Depth 10 | Set-Content $ManagerConfigPath
}

$global:Server_List_Count = 0

<#
    Display Main Menu
#>
<#
function Show-Menu {
    Clear-Host

    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "        Sandstorm Multi Server Manager        " -ForegroundColor Yellow
    Write-Host "               Version: $Version               " -ForegroundColor DarkYellow
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        Write-Host "          Running as Administrator           " -ForegroundColor Red
    } else {
        Write-Host "          Running as Standard User           " -ForegroundColor Green
    }
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""

    [int]$global:Server_List_Count = show_server_list

    If($global:Server_List_Count -eq 0)
    {
        $disabled = " - Disabled: No Servers"
    }
    else
    {
        $disabled = ""
    }

    If($isAdmin)
    {
        $disabledAdmin = ""
    }
    else
    {
        $disabledAdmin = " - Disabled: Start Server Manager as Administrator"
    }

    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    1. Install New Server" -NoNewLine
    Write-Host $disabledAdmin -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    2. Import Existing Server" -NoNewLine
    Write-Host $disabledAdmin -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    3. Remove Server from Server List" -NoNewLine
    Write-Host $disabled -ForegroundColor Red
    Write-Host ""
    Write-Host "    4. Enable/Disable Server" -NoNewLine
    Write-Host $disabled -ForegroundColor Red
    Write-Host ""
    Write-Host "    5. Change Server Configuration" -NoNewLine
    Write-Host $disabled -ForegroundColor Red
    Write-Host ""
    Write-Host "    6. Unsubscribe/Delete Mods" -NoNewLine
    Write-Host $disabled -ForegroundColor Red
    Write-Host ""
    Write-Host "    7. Restore Backup Server user.json" -NoNewLine
    Write-Host $disabled -ForegroundColor Red
    Write-Host ""
    Write-Host "    8. Exit and Start Servers" -NoNewLine
    Write-Host $disabled -ForegroundColor Red
    Write-Host ""
    Write-Host "    9. Exit"
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    S. Schedule Server Reboot Times" -ForegroundColor Green
    $scheduledTimes = @()
    foreach ($time in $global:ManagerConfig.scheduledTimes) { 
        $scheduledTimes += $time
        $rebootTimes = $rebootTimes + $time  + " : "
    }

    if ($scheduledTimes.count -gt 0)
    {
        $rebootTimes = $rebootTimes -replace ' : $'
        Write-Host "       Reboot Schedule: $rebootTimes" -ForegroundColor Yellow
    }
    else
    {
        Write-Host "       No Schedule Reboot Time" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "    I. Server Launcher and Multi-Server Status Dashboard Windows" -ForegroundColor Green
    if($global:ManagerConfig.closeAllWindows -eq 0)
    {
        $infoText = "Leave Open After All Servers Launched"
    }
    else
    {
        $infoText = "Minimize After All Servers Launched"
    }
    Write-Host "       Current Setting: $infoText" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    W. Server windows after booting" -ForegroundColor Green
    if($global:ManagerConfig.closeServerWindows -eq 0)
    {
        $infoText = "Leave Server Windows Open"
    }
    else
    {
        $infoText = "Minimized Server Windows"
    }
    Write-Host "       Current Setting: $infoText" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    T. Sandstorm Taskbar after booting" -ForegroundColor Green
    if($global:ManagerConfig.closeTaskbar -eq 0)
    {
        $infoText = "Leave Sandstorm Taskbar Open"
    }
    else
    {
        $infoText = "Minimize Sandstorm Taskbar"
    }
    Write-Host "       Current Setting: $infoText" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""
}
#>

function ExitAndStartServers
{
    $forcedReboot = Join-Path -Path $PSScriptRoot -ChildPath "config\forcedReboot.check"
    Set-Content -Path $forcedReboot -Value "1" -Force

    $isWindowOpen = [bool](Get-Process -ErrorAction SilentlyContinue | Where-Object { 
        $_.MainWindowTitle -like '*Sandstorm_Multi_Server*' -and $_.MainWindowHandle -ne 0 
    })

    if (-not $isWindowOpen) 
    {
        $scriptTitle = "Start Server Launcher"
        $batchFilename = "Start_Server_Launcher.bat"
 
        Start-Process "cmd.exe" -ArgumentList "/c TITLE $scriptTitle && CALL $batchFilename" -WorkingDirectory "$PSScriptRoot"
    }
    Exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Native Windows API Call to safely handle smooth corner geometry across Windows 10 & 11
$Win32NativeCode = @"
using System;
using System.Runtime.InteropServices;

public class Win32 {
    [DllImport("gdi32.dll", EntryPoint = "CreateRoundRectRgn")]
    public static extern IntPtr CreateRoundRectRgn(
        int nLeftRect,     // x-coordinate of upper-left corner
        int nTopRect,      // y-coordinate of upper-left corner
        int nRightRect,    // x-coordinate of lower-right corner
        int nBottomRect,   // y-coordinate of lower-right corner
        int nWidthEllipse, // width of ellipse (rounding amount)
        int nHeightEllipse // height of ellipse (rounding amount)
    );
}
"@
Add-Type -TypeDefinition $Win32NativeCode -ErrorAction SilentlyContinue

# ---------------------------------------------------------
# GLOBAL FIX: Hardware Corner Rounding Function
# ---------------------------------------------------------
function Set-RoundCorners {
    param(
        [System.Windows.Forms.Control]$TargetControl, 
        [int]$Radius = 10
    )
    if ($null -ne $TargetControl) {
        $Handle = [Win32]::CreateRoundRectRgn(0, 0, $TargetControl.Width, $TargetControl.Height, $Radius, $Radius)
        $TargetControl.Region = [System.Drawing.Region]::FromHrgn($Handle)
    }
}

function Show-Menu {
    # ---------------------------------------------------------
    # 1. State Verification (Preserved from console logic)
    # ---------------------------------------------------------
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $adminAllowed = $isAdmin

    # ---------------------------------------------------------
    # 2. Main Form Window Styling
    # ---------------------------------------------------------
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "Sandstorm Multi Server Manager v$Version"
    $Form.Size = New-Object System.Drawing.Size(520, 880)
    $Form.StartPosition = "CenterScreen"
    $Form.FormBorderStyle = "FixedSingle"
    $Form.MaximizeBox = $false
    $Form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)

    # ---------------------------------------------------------
    # 3. Header & Admin Status Bar
    # ---------------------------------------------------------
    $HeaderLabel = New-Object System.Windows.Forms.Label
    $HeaderLabel.Text = "Sandstorm Multi Server Manager"
    $HeaderLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $HeaderLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 51, 153)
    $HeaderLabel.Location = New-Object System.Drawing.Point(20, 15)
    $HeaderLabel.Size = New-Object System.Drawing.Size(460, 35)
    $HeaderLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $Form.Controls.Add($HeaderLabel)

    $AdminStatusLabel = New-Object System.Windows.Forms.Label
    if ($isAdmin) {
        $AdminStatusLabel.Text = "🛡️ Running as Administrator"
        $AdminStatusLabel.ForeColor = [System.Drawing.Color]::DarkRed
    } else {
        $AdminStatusLabel.Text = "👤 Running as Standard User"
        $AdminStatusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
    }
    $AdminStatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $AdminStatusLabel.Location = New-Object System.Drawing.Point(20, 50)
    $AdminStatusLabel.Size = New-Object System.Drawing.Size(460, 25)
    $AdminStatusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $Form.Controls.Add($AdminStatusLabel)

    # ---------------------------------------------------------
    # 4. Server Inventory List Box 
    # ---------------------------------------------------------
    $ServerStatusBox = New-Object System.Windows.Forms.TextBox
    $ServerStatusBox.Multiline = $true
    $ServerStatusBox.ReadOnly = $true
    $ServerStatusBox.ScrollBars = "Vertical"
    $ServerStatusBox.BackColor = [System.Drawing.Color]::White
    $ServerStatusBox.ForeColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
    $ServerStatusBox.Font = New-Object System.Drawing.Font("Consolas", 9.5)
    $ServerStatusBox.Location = New-Object System.Drawing.Point(35, 85)
    $ServerStatusBox.Size = New-Object System.Drawing.Size(430, 160)
    $ServerStatusBox.BorderStyle = "FixedSingle"

    $boxOutput = ""
    if (($global:SeverListData.PSObject.Properties).count -gt 0) {
        $Server_Count = 1
        $boxOutput += ("{0,-6}{1,-32} {2,-10}`r`n" -f "[##]", "Server ID", "Status")
        $boxOutput += ("-" * 50 + "`r`n")

        foreach ($property in $global:SeverListData.psobject.Properties) {
            $server_ID = $property.Name
            $statusText = if ($property.Value.Disabled) { "DISABLED" } else { "ENABLED" }
            $boxOutput += ("{0,-6}{1,-32} {2,-10}`r`n" -f "[$Server_Count]", $server_ID, $statusText)
            $Server_Count++
        }
        $Server_Count = $Server_Count - 1
    } else {
        $Server_Count = 0
    }
    
    [int]$global:Server_List_Count = $Server_Count
    
    $hasServers = $global:Server_List_Count -gt 0
    $serverAllowed = $hasServers

    $ServerStatusBox.Text = $boxOutput
    $Form.Controls.Add($ServerStatusBox)

    # CRITICAL CROSS-COMPATIBLE SELECTION FIX
    $ServerStatusBox.SelectionStart = $ServerStatusBox.Text.Length
    $ServerStatusBox.SelectionLength = 0

    # Shifting control focus natively onto the "Install New Server" action button instead
    $Form.Add_Shown({
        if ($Form.Controls.Contains($Form.FindForm())) {
            # Bypasses the text box by dropping mouse focus directly down into operational controls
            $Form.SelectNextControl($ServerStatusBox, $true, $true, $true, $true)
        }
    })
 
    $Line1 = New-Object System.Windows.Forms.Label
    $Line1.BackColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
    $Line1.Location = New-Object System.Drawing.Point(20, 260)
    $Line1.Size = New-Object System.Drawing.Size(460, 2)
    $Form.Controls.Add($Line1)

    # ---------------------------------------------------------
    # 5. Helper Function to Build Operational Buttons (1 - 9)
    # ---------------------------------------------------------
    $script:currentY = 275 
    function Add-MenuButton ($text, $enabled, $clickAction, $isDanger = $false) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $text
        $btn.Location = New-Object System.Drawing.Point(35, ($script:currentY))
        $btn.Size = New-Object System.Drawing.Size(430, 32)
        $btn.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $btn.FlatStyle = "Flat"
        $btn.FlatAppearance.BorderSize = 0
        
        if (-not $enabled) {
            $btn.Enabled = $false
            $btn.BackColor = [System.Drawing.Color]::FromArgb(215, 215, 215)
            $btn.ForeColor = [System.Drawing.Color]::DarkGray
        } elseif ($isDanger) {
            $btn.BackColor = [System.Drawing.Color]::FromArgb(255, 210, 210)
            $btn.ForeColor = [System.Drawing.Color]::DarkRed
            $btn.Add_Click($clickAction)
        } else {
            $btn.BackColor = [System.Drawing.Color]::White
            $btn.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
            $btn.Add_Click($clickAction)
        }
        
        Set-RoundCorners -TargetControl $btn
        $Form.Controls.Add($btn)
        $script:currentY += 38
    }

    # ---------------------------------------------------------
    # 6. Adding Operational Action Buttons (Options 1 - 9)
    # ---------------------------------------------------------
    Add-MenuButton "1. Install New Server" $adminAllowed { install_server -is_New_Server $true }
    Add-MenuButton "2. Import Existing Server" $adminAllowed { install_server -is_New_Server $false }
    Add-MenuButton "3. Remove Server from Server List" $serverAllowed { delete_server } $true
    Add-MenuButton "4. Enable/Disable Server" $serverAllowed { disable_server }
    Add-MenuButton "5. Change Server Configuration" $serverAllowed { change_server_configuration }
    Add-MenuButton "6. Unsubscribe/Delete Mods" $serverAllowed { unsubscribe_mods } $true
    Add-MenuButton "7. Restore Backup Server user.json" $serverAllowed { restore_server_userjson }
    Add-MenuButton "8. Exit and Start Servers" $serverAllowed { $Form.Close(); ExitAndStartServers }
    Add-MenuButton "9. Exit Application" $true { $Form.Close(); exit }

    $Line2 = New-Object System.Windows.Forms.Label
    $Line2.BackColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
    $Line2.Location = New-Object System.Drawing.Point(20, ($script:currentY + 5))
    $Line2.Size = New-Object System.Drawing.Size(460, 2)
    $Form.Controls.Add($Line2)
    
    $script:currentY += 15

    $SettingsHeaderLabel = New-Object System.Windows.Forms.Label
    $SettingsHeaderLabel.Text = "ACTIVE SETTINGS & CONFIGURATION"
    $SettingsHeaderLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $SettingsHeaderLabel.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    $SettingsHeaderLabel.Location = New-Object System.Drawing.Point(35, ($script:currentY))
    $SettingsHeaderLabel.Size = New-Object System.Drawing.Size(430, 20)
    $Form.Controls.Add($SettingsHeaderLabel)
    
    $script:currentY += 25

    # ---------------------------------------------------------
    # 7. FIXED: Configuration Stacking Engine (Uses native dot execution strings)
    # ---------------------------------------------------------
    function Create-ConfigButton {
        param(
            [string]$Prefix,
            [scriptblock]$GetTextScript,
            [scriptblock]$ActionScript,
            [int]$YPosition
        )
        $btn = New-Object System.Windows.Forms.Button
        $btn.Location = New-Object System.Drawing.Point(35, $YPosition)
        $btn.Size = New-Object System.Drawing.Size(430, 35)
$btn.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
$btn.FlatStyle = "Flat"
$btn.BackColor = [System.Drawing.Color]::FromArgb(232, 240, 252)
$btn.ForeColor = [System.Drawing.Color]::FromArgb(0, 51, 153)
$btn.FlatAppearance.BorderSize = 0
$btn.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
# Lock strings into individual context nodes
$btn.Tag = @{
Prefix = $Prefix
GetText = $GetTextScript
Action = $ActionScript
}
# Safe label rendering using native pipeline extraction rules
$dynamicStatus = . $GetTextScript
$btn.Text = "  $Prefix $dynamicStatus"
$btn.Add_Click({
param($sender, $e)
$cfg = $sender.Tag
# Fire structural setting context toggles securely
. $cfg.Action
# Immediately pull updated dynamic data back onto text canvas
$updatedStatus = . $cfg.GetText
$sender.Text = "  " + $cfg.Prefix + " " + $updatedStatus
})
Set-RoundCorners -TargetControl $btn
$Form.Controls.Add($btn)
}
# ---------------------------------------------------------
# 8. Creating the 4 Settings Toggles Independently
# ---------------------------------------------------------
# Toggle [S]
Create-ConfigButton -Prefix "[S] Reboot Schedule:" -GetTextScript {
$scheduledTimes = @()
$rebootTimes = ""
foreach ($time in $global:ManagerConfig.scheduledTimes) {
$scheduledTimes += $time
$rebootTimes = $rebootTimes + $time  + " : "
}
if ($scheduledTimes.count -gt 0) { return "➡ " + ($rebootTimes -replace ' : $') } else { return "➡ No Schedule Reboot Time" }
} -ActionScript { $Form.Close(); & Schedule_Server_Reboot } -YPosition $script:currentY
$script:currentY += 40
# Toggle [I]
Create-ConfigButton -Prefix "[I] Dashboard Window:" -GetTextScript {
if ($global:ManagerConfig.closeAllWindows -eq 0) { "➡ Leave Open After All Launched" } else { "➡ Minimize After All Launched" }
} -ActionScript {
if ($global:ManagerConfig.closeAllWindows -eq 0) { $global:ManagerConfig.closeAllWindows = 1 } else { $global:ManagerConfig.closeAllWindows = 0 }
} -YPosition $script:currentY
$script:currentY += 40
# Toggle [W]
Create-ConfigButton -Prefix "[W] Server Windows:" -GetTextScript {
if ($global:ManagerConfig.closeServerWindows -eq 0) { "➡ Leave Server Windows Open" } else { "➡ Minimized Server Windows" }
} -ActionScript {
if ($global:ManagerConfig.closeServerWindows -eq 0) { $global:ManagerConfig.closeServerWindows = 1 } else { $global:ManagerConfig.closeServerWindows = 0 }
} -YPosition $script:currentY
$script:currentY += 40
# Toggle [T]
Create-ConfigButton -Prefix "[T] Sandstorm Taskbar:" -GetTextScript {
if ($global:ManagerConfig.closeTaskbar -eq 0) { "➡ Leave Sandstorm Taskbar Open" } else { "➡ Minimize Sandstorm Taskbar" }
} -ActionScript {
if ($global:ManagerConfig.closeTaskbar -eq 0) { $global:ManagerConfig.closeTaskbar = 1 } else { $global:ManagerConfig.closeTaskbar = 0 }
} -YPosition $script:currentY
# ---------------------------------------------------------
# 9. Render Canvas Window Frame
# ---------------------------------------------------------
[void]$Form.ShowDialog()
}
<#
    Sandstorm Server Manager First Run
    Check for UE4 Prerequisites and proper .NET files installed and if not
    download and install.

    Windows 11 change default Terminal to Console Host as managing Windows and GUIs
    embeded in the Terminal is a nightmare as the Terminal obscures the IDs needed
    to move and resize the windows and GUIs.

    Windows 11 check for Smart App Control Enabled or in Evaluation Mode.  This must
    be turned off because it will prevent the Sandstorm server executable from
    running.
#>


$ManagerConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ManagerConfig.json"
if (-not(Test-Path $ManagerConfigPath))
{
    $global:ManagerConfig = @'
{
    "isfirstRun":  0,
    "closeServerWindows":  0,
    "closeAllWindows":  0,
    "closeTaskbar":  0,
    "scheduledTimes":  [
                       ]
}
'@ | ConvertFrom-Json
    $global:ManagerConfig | ConvertTo-Json | Set-Content $ManagerConfigPath
}

$global:ManagerConfig=Get-Content $ManagerConfigPath -Raw | ConvertFrom-Json

if ($global:ManagerConfig.isFirstRun -eq 0)
{
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not($isAdmin)) {
        Write-Warning "This your first time running Sandstorm Server Manager."
        Write-Warning "Initial setup requires Administrator Mode."
        Write-Host ""
        Write-Warning "You need to run Start_Server_Manager.bat in ADMINISTRATOR Mode"
        Write-Warning "Exit the Manager and Right-Click on Start_Server_Manager.bat"
        Write-Warning "Then select 'Run As Adminitrator'"
        Write-Host "`nPress any key to Continue..." -ForegroundColor White
        $null = [System.Console]::ReadKey($true)
        exit
    }

    <#
        Check if script is running on computer with Insurgency Sandstorm Client installed.  If so give a warning.
    #>

    $RegPath = "HKCU:\Software\Valve\Steam\Apps\581320"
    if (Test-Path $RegPath) 
    {
        $Installed = Get-ItemProperty -Path $RegPath -Name "Installed" -ErrorAction SilentlyContinue
        if ($Installed.Installed -eq 1) 
        { 
            Write-Warning "Insurgency: Sandstorm game client is installed." 
            Write-Host "" 
            Write-Warning "Installing a Sandstorm Server on the same machine as the game client" 
            Write-Warning "may cause data corruption on either the server, client or BOTH." 
            Write-Warning "If you install a Sandstorm Server with the game client all downloaded" 
            Write-Warning "mod files from both will be saved to the SAME location and intermingled."
            Write-Warning "If a mod is unsubscribed from the server that you are subscribed"
            Write-Warning "on the client it will be redownloaded by the client. You can do it"
            Write-Warning "but things might get wonky. You have been warned."
            Write-Host "" 
            pause
        }
    }

    # Check if Visual C++ Redistributables installed

    $is_VisualInstalled = [bool](Get-Package -Name "*Visual C++*2015*" , "*Visual C++*2017*" , "*Visual C++*2015-2022*" -ErrorAction SilentlyContinue)
    if ($is_VisualInstalled -eq $false)
    {
        Write-Host ""
        Write-Host "Visual C++ Redistributable (x64) needs to be installed before running Sandstorm Server" -ForegroundColor Yellow
        Write-Host ""

        # Define Official Microsoft Download URLs
        $x64Url = "https://aka.ms/vs/17/release/vc_redist.x64.exe"

        # Create a temporary directory for the installers
        $tempDir = "$env:TEMP\VC_Redistributable"
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

        $x64Path = "$tempDir\vc_redist.x64.exe"
            
        # Download the files
        Write-Host "Downloading Visual C++ Redistributable (x64)..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $x64Url -OutFile $x64Path

        # Install silently (no UI prompts, automatic reboot suppression)
        Write-Host "Installing Visual C++ (x64)..." -ForegroundColor Yellow
        Start-Process -FilePath $x64Path -ArgumentList "/install /passive /norestart" -Wait

        # Clean up
        Remove-Item -Path $tempDir -Recurse -Force
        Write-Host "Installation completed successfully!" -ForegroundColor Green
    }

    robocopy "$PSScriptRoot\support\InsurgencySandstorm" "$PSScriptRoot\InsurgencySandstorm" /E /NDL /NFL /NJH /NJS
    $serverTitle = "Installing UE4 Prequisites"
    $batchFile = "downloadSteamServerFiles.bat"
    $serverPath = Join-Path -Path $PSScriptRoot -ChildPath "InsurgencySandstorm\steamapps\common\sandstorm_server"
    $UE4PrereqPath = Join-Path -Path $PSScriptRoot -ChildPath "InsurgencySandstorm\steamapps\common\sandstorm_server\Engine\Extras\Redist\en-us\UE4PrereqSetup_x64.exe"

    Start-Process "cmd.exe" -ArgumentList "/c TITLE $serverTitle && CALL $batchFile", "$serverTitle" -WorkingDirectory "$serverPath" -Wait

    # --- Check for UE4 Prerequisites installed and install if not

    $PrereqName = "UE4 Prerequisites"
    Write-Host "Checking for $PrereqName..."

    # Define the base registry hives without wildcards
    $RegPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    # Use Get-ChildItem to safely grab all child subkeys, then read their DisplayName property
    $InstalledApps = Get-ChildItem -Path $RegPaths -ErrorAction SilentlyContinue | 
                 Get-ItemProperty -ErrorAction SilentlyContinue |
                 Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue

    $Found = $InstalledApps | Where-Object { $_ -like "*$PrereqName*" }

    if (-not $Found) {
        Write-Host ""
        Write-Host "$PrereqName not found. Installing..."
        Write-Host ""
        $process = Start-Process -FilePath $UE4PrereqPath -Wait -PassThru

        # Verify if it was successful (0 or 3010 usually mean success/reboot required)
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-Output "UE4 Prerequisites installed successfully."
        } else {
            Write-Error "Installation failed with exit code: $($process.ExitCode)"
        }
    } else {
        Write-Host ""
        Write-Host "$PrereqName is already installed."
    }

    Remove-Item -Path "$PSScriptRoot\InsurgencySandstorm\steamapps\common\sandstorm_server\downloadSteamServerFiles.bat" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$PSScriptRoot\InsurgencySandstorm\steamapps\common\sandstorm_server\SupportStartup.json" -Force -ErrorAction SilentlyContinue

    Write-Host ""

    $Build = [System.Environment]::OSVersion.Version.Build

    if ($Build -ge 22000) 
    {
        # Disable Windows 11 Terminal {B23D10C0-E52E-411E-9D5B-C09FDF709C7D} - Enable: {E19405D4-DE52-4EE4-BE0E-92DE97A52B1E}
        # Create the Startup key if it doesn't already exist
        $registryPath = "HKCU:\Console\%%Startup"
        if (-not (Test-Path $registryPath)) {
            New-Item -Path $registryPath -Force | Out-Null
        }

        # Set the GUIDs to force Windows Console Host as the default handler
        Set-ItemProperty -Path $registryPath -Name "DelegationConsole" -Value "{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}"
        Set-ItemProperty -Path $registryPath -Name "DelegationTerminal" -Value "{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}"

        Write-Host ""
        Write-Host "Default terminal successfully reverted to Windows Console Host!" -ForegroundColor Green
        Write-Host "" -ForegroundColor Green
        Write-Host "Terminal was disabled because it causes problems when working with" -ForegroundColor Green
        Write-Host "CMD, Powershell and GUI windows as it masks window IDs for these" -ForegroundColor Green
        Write-Host "window types as they are executed inside the Terminal App." -ForegroundColor Green
        Write-Host "Reverting to Classic Console Host will not affect any scripts," -ForegroundColor Green
        Write-Host "system files or programs as having it enabled is optional." -ForegroundColor Green
        Write-Host ""
        Write-Host "If it is re-enabled expect some window operations to not function" -ForegroundColor Green
        Write-Host "properly under Windows 11 for Sandstorm Server Manager." -ForegroundColor Green
        Write-Host ""
        Write-Host "=============================================" -ForegroundColor Cyan
        Write-Host "    Windows 11 Smart App Control Check      " -ForegroundColor Cyan
        Write-Host "=============================================" -ForegroundColor Cyan

        # Fetch the status via Windows Defender configuration
        $sacStatus = (Get-MpComputerStatus).SmartAppControlState

        # Backup check via Registry if Get-MpComputerStatus isn't reporting properly
        if ($null -eq $sacStatus) {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
            if (Test-Path $regPath) {
                $regValue = (Get-ItemProperty -Path $regPath -Name "VerifiedAndReputablePolicyState" -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState
                switch ($regValue) {
                    0 { $sacStatus = 'Off' } # Off
                    1 { $sacStatus = 'On' } # On / Enforce
                    2 { $sacStatus = 'Eval' } # Evaluation
                    Default { $sacStatus = "Unknown" }
                }
            }
        }

        switch ($sacStatus) {
            'Off' { 
                Write-Host "[*] Smart App Control Status: " -NoNewline
                Write-Host "DISABLED (Off)" -ForegroundColor Green
                Write-Host "`nYour server binaries should not be blocked by SAC." -ForegroundColor Gray
                $needsAction = $false
            }
            'On' { 
                Write-Host "[*] Smart App Control Status: " -NoNewline
                Write-Host "ENABLED (Enforcing)" -ForegroundColor Red
                $needsAction = $true
            }
            'Eval' { 
                Write-Host "[*] Smart App Control Status: " -NoNewline
                Write-Host "EVALUATION MODE" -ForegroundColor Yellow
            $needsAction = $true
            }
            Default { 
                Write-Host "[!] Could not determine Smart App Control status automatically." -ForegroundColor Gray
                $needsAction = $true
            }
        }

        # Prompt user if SAC is active
        if ($needsAction) {
            if ($sacStatus -eq "On")
            {
                Write-Host "`n[!] If you leave Smart App Control ENABLED Windows 11 will BLOCK the" -ForegroundColor Yellow
                Write-Host "[!] execution of InsurgencyServer-Win64-Shipping.exe and your Server WILL NOT START!`n" -ForegroundColor Yellow
            }
            else
            {
                Write-Host "`n[!] If you leave Smart App Control in EVALUATION MODE Windows 11" -ForegroundColor Yellow
                Write-Host "[!] MAY eventually BLOCK execution of InsurgencyServer-Win64-Shipping.exe" -ForegroundColor Yellow
                Write-Host "[!] if it decides the program is problematic and your Server WILL NOT START!`n" -ForegroundColor Yellow
            }

            Write-Host "[!] Smart App Control MUST BE DISABLED!`n" -ForegroundColor Yellow

            $response = Read-Host "Would you like to turn OFF Smart App Control? (Y/N)"
    
            if ($response -eq 'Y' -or $response -eq 'y') {
                Write-Host "`nModifying Registry configuration..." -ForegroundColor Cyan
        
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
        
                # Ensure path exists
                if (-not (Test-Path $regPath)) {
                    New-Item -Path $regPath -Force | Out-Null
                }
        
                # Set registry value to 0 (Off)
                Set-ItemProperty -Path $regPath -Name "VerifiedAndReputablePolicyState" -Value 0 -Type DWord -Force
        
                Write-Host "[!] Registry updated successfully." -ForegroundColor Green
                Write-Host "[!] Note: You must restart your computer for these changes to take full effect." -ForegroundColor Yellow

                Add-Type -AssemblyName PresentationFramework

                $msgBody   = "Your system requires a reboot. Would you like to restart now?"
                $msgTitle  = "Restart Required"
                $msgButton = [System.Windows.MessageBoxButton]::YesNo
                $msgIcon   = [System.Windows.MessageBoxImage]::Question

                $response = [System.Windows.MessageBox]::Show($msgBody, $msgTitle, $msgButton, $msgIcon)

                if ($response -eq "Yes") {
                    $global:ManagerConfig.isFirstRun = 1
                    $global:ManagerConfig | ConvertTo-Json | Set-Content $ManagerConfigPath
                    Restart-Computer -Force
                }
                exit
            } else {
                Write-Host "`nNo changes were made. Smart App Control remains active." -ForegroundColor Gray
                Write-Host "`nExiting Server Manager" -ForegroundColor Gray
                pause
                exit
            }
        }

        $global:ManagerConfig.isFirstRun = 1
        $global:ManagerConfig | ConvertTo-Json | Set-Content $ManagerConfigPath
    }
    else
    {
        $global:ManagerConfig.isFirstRun = 1
        $global:ManagerConfig | ConvertTo-Json | Set-Content $ManagerConfigPath
    }

    Write-Host ""
    Write-Host "A Steam GameStatsToken is REQUIRED." -ForegroundColor Yellow
    Write-Host "The same GameStatsToken is used on all servers you create." -ForegroundColor Yellow
    Write-Host "Get GameStatsToken here: https://gamestats.sandstorm.game/auth/login?ReturnUrl=%2F" -ForegroundColor Green
    Write-Host ""
    Write-Host "A Steam GSLTToken is REQUIRED." -ForegroundColor Yellow
    Write-Host "Each Server you create will use its own unique GSLTToken." -ForegroundColor Yellow
    Write-Host "Get GSLTToken Here: https://steamcommunity.com/dev/managegameservers" -ForegroundColor Green
    Write-Host ""
    pause
}

<#
    Display the main menu and process any requests.
#>

do {
    Show-Menu
    $selection = Read-Host -Prompt " Please enter your selection (1-9)"
    
    switch ($selection) {
        '1' {
            install_server -is_New_Server $true
        }
        '2' {
            install_server -is_New_Server $false
        }
        '3' {
            If($global:Server_List_Count -eq 0)
            {
                Write-Host ""
                Write-Host "There are no servers to delete."  -ForegroundColor Magenta
            }
            else
            {
                delete_server
            }
        }
        '4' {
            If($global:Server_List_Count -eq 0)
            {
                Write-Host ""
                Write-Host "There are no servers to disable."  -ForegroundColor Magenta
            }
            else
            {
                disable_server
            }
        }
        '5' {
            If($global:Server_List_Count -eq 0)
            {
                Write-Host ""
                Write-Host "There are no servers to change."  -ForegroundColor Magenta
            }
            else
            {
                change_server_configuration
            }
        }
        '6' {
            If($global:Server_List_Count -eq 0)
            {
                Write-Host ""
                Write-Host "There are no servers to unsubscribe mods."  -ForegroundColor Magenta
            }
            else
            {
                unsubscribe_mods
            }
        }
        '7' {
            If($global:Server_List_Count -eq 0)
            {
                Write-Host ""
                Write-Host "There are no servers to restore user.json."  -ForegroundColor Magenta
            }
            else
            {
                restore_server_userjson
            }
        }
        '8' {
            If($global:Server_List_Count -eq 0)
            {
                Write-Host ""
                Write-Host "There are no servers to Start."  -ForegroundColor Magenta
            }
            else
            {
                Write-Host "`n Starting all Sandstorm Servers Goodbye!" -ForegroundColor Yellow

                $forcedReboot = Join-Path -Path $PSScriptRoot -ChildPath "config\forcedReboot.check"
                Set-Content -Path $forcedReboot -Value "1" -Force

                $isWindowOpen = [bool](Get-Process -ErrorAction SilentlyContinue | Where-Object { 
                    $_.MainWindowTitle -like '*Sandstorm_Multi_Server*' -and $_.MainWindowHandle -ne 0 
                })

                if (-not $isWindowOpen) 
                {
                    $scriptTitle = "Start Server Launcher"
                    $batchFilename = "Start_Server_Launcher.bat"
 
                    Start-Process "cmd.exe" -ArgumentList "/c TITLE $scriptTitle && CALL $batchFilename" -WorkingDirectory "$PSScriptRoot"
                }
                Exit
            }
        }
        '9' {
            Write-Host "`n Exiting the script. Goodbye!" -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            Exit
        }
        'S' {
            Schedule_Server_Reboot
        }
        'I' {
            $global:ManagerConfig.closeAllWindows = 1 - $ManagerConfig.closeAllWindows
            $global:ManagerConfig | ConvertTo-Json | Set-Content $ManagerConfigPath
        }
        'W' {
            $global:ManagerConfig.closeServerWindows = 1 - $ManagerConfig.closeServerWindows
            $global:ManagerConfig | ConvertTo-Json | Set-Content $ManagerConfigPath
        }
        'T' {
            $global:ManagerConfig.closeTaskbar = 1 - $ManagerConfig.closeTaskbar
            $global:ManagerConfig | ConvertTo-Json | Set-Content $ManagerConfigPath
        }
        default {
            Write-Host "`n Invalid choice! Please select a number from 1 to 9." -ForegroundColor Red
        }
    }
} until ($selection -eq '9')

