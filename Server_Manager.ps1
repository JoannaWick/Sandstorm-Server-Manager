<#PSScriptInfo
.NAME Server_Manager
.AUTHOR Joanna Wick
.TAGS Sandstorm, Server
.PROJECTURI https://github.com/JoannaWick/Sandstorm-Server-Manager
#>

param(
    [string]$batchLaunch=0
)

$Host.UI.RawUI.WindowTitle = "Sandstorm Server Manager Console"

$Version = "2.0.0"
$global:selectedServerID = ""
$global:selectedisDisabled = $false
[int]$global:Server_List_Count = 0
$script:ExitRequested = $false
$global:rebootServerList = ""

<# 
    Resize and center window
#>

# Read the current OS build framework directly from memory
$buildNumber = [Environment]::OSVersion.Version.Build

if ($buildNumber -ge 22000) {

    Add-Type -AssemblyName System.Windows.Forms
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    $posX = [math]::Round(($workingArea.Width + 500) / 2)
    $posY = [math]::Round(($workingArea.Height - 905) / 2)

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
        [void][Win32]::MoveWindow($hWnd, $posX, $posY, 600, 905, $true)
    } else {
        # Fallback to standard Mode Con formatting if running classic Conhost
        mode con: cols=120 lines=40
    }
} else {
    Add-Type -AssemblyName System.Windows.Forms

    # Fetch the working area of the primary display
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    # Output the width and height
    $screenWidth  = ($workingArea.Width+500)/2
    $screenHeight = ($workingArea.Height-905)/2

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
    [void][Window]::MoveWindow($hWnd, $screenWidth, $screenHeight, 600, 905, $true)
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
    param(
        [Parameter(Mandatory = $true)]
        [string]$title,
        
        [string]$infoMessage
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = $title
    $Form.Size = New-Object System.Drawing.Size(420,220)
    $Form.StartPosition = "CenterScreen"
    $Form.FormBorderStyle = "FixedDialog" 
    $Form.MaximizeBox = $false
    $Form.MinimizeBox = $false
    $Form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245) # Pure White Background

    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = $infoMessage
    $Label.Location = New-Object System.Drawing.Point(25, 30)
    $Label.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular)
    $Label.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32) # Dark Charcoal (Easier on eyes than pure black)

    $Label.AutoSize = $true
    $Label.MaximumSize = New-Object System.Drawing.Size(350, 0) 
    
    $Form.Controls.Add($Label)

    $ButtonYes = New-Object System.Windows.Forms.Button
    $ButtonYes.Text = "Yes"
    $ButtonYes.Size = New-Object System.Drawing.Size(110, 32)
    $ButtonYes.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $ButtonYes.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $ButtonYes.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)
    $ButtonYes.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $ButtonYes.FlatAppearance.BorderSize = 0
    $ButtonYes.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200) # Soft Gray Border
    $ButtonYes.DialogResult = [System.Windows.Forms.DialogResult]::Yes

    $ButtonNo = New-Object System.Windows.Forms.Button
    $ButtonNo.Text = "No"
    $ButtonNo.Size = New-Object System.Drawing.Size(110, 32)
    $ButtonNo.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $ButtonNo.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $ButtonNo.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)
    $ButtonNo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $ButtonNo.FlatAppearance.BorderSize = 0
    $ButtonNo.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $ButtonNo.DialogResult = [System.Windows.Forms.DialogResult]::No

    $Form.Add_FormClosing({
        param($sender, $e)
    
        # Check if the close action was triggered by the user clicking the 'X' or Alt+F4
        if ($e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            $Form.DialogResult = [System.Windows.Forms.DialogResult]::No
        }
    })

    $ButtonY = $Label.Bottom + 25
    $ButtonYes.Location = New-Object System.Drawing.Point(80, $ButtonY)
    $ButtonNo.Location = New-Object System.Drawing.Point(210, $ButtonY)

    $FormWidth = 420
    $FormHeight = $ButtonYes.Bottom + 25
    $Form.ClientSize = New-Object System.Drawing.Size($FormWidth, $FormHeight)

    Set-ControlRoundCorners -Control $ButtonYes -Radius 8
    $Form.Controls.Add($ButtonYes)
    Set-ControlRoundCorners -Control $ButtonNo -Radius 8
    $Form.Controls.Add($ButtonNo)

#    $Form.Controls.AddRange(@($Label, $ButtonYes, $ButtonNo))
    return $Form.ShowDialog()
}

function New_MessageBox
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$title,
        
        [string]$infoMessage
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = $title
    $Form.StartPosition = "CenterScreen"
    $Form.FormBorderStyle = "FixedDialog" 
    $Form.MaximizeBox = $false
    $Form.MinimizeBox = $false
    $Form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)

    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = $infoMessage
    $Label.Location = New-Object System.Drawing.Point(25, 30)
    $Label.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular)
    $Label.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
    
    $Label.AutoSize = $true
    $Label.MaximumSize = New-Object System.Drawing.Size(350, 0) 
    
    $Form.Controls.Add($Label)

    $ButtonOK = New-Object System.Windows.Forms.Button
    $ButtonOK.Text = "OK"
    $ButtonOK.Size = New-Object System.Drawing.Size(110, 32)
    $ButtonOK.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $ButtonOK.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $ButtonOK.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)
    $ButtonOK.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $ButtonOK.FlatAppearance.BorderSize = 0
    $ButtonOK.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $ButtonOK.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $ButtonY = $Label.Bottom + 25
    $ButtonOK.Location = New-Object System.Drawing.Point(150, $ButtonY)

    $FormWidth = 420
    $FormHeight = $ButtonOK.Bottom + 25
    $Form.ClientSize = New-Object System.Drawing.Size($FormWidth, $FormHeight)

    Set-ControlRoundCorners -Control $ButtonOK -Radius 8
    $Form.Controls.Add($ButtonOK)
    [void]$Form.ShowDialog()
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

<#
    GUI for selecting where to store Mod.io mod files with Default of C:\Users\Public
#>

function Modio_mod_directory {
    param(
        [string]$Filter = "" # Example: "*.pak", "*.zip", or leave empty/blank for folders only
    )

    [void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    [void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")

    # --- WIN32 API DECLARATIONS FOR NATIVE ICON EXTRACTION ---
    $IconApiDefinition = @"
    using System;
    using System.Runtime.InteropServices;
    public class Win32Icon {
        [DllImport("shell32.dll", EntryPoint = "ExtractIconExW", CharSet = CharSet.Unicode)]
        public static extern int ExtractIconEx(string lpszFile, int nIconIndex, out IntPtr phiconLarge, out IntPtr phiconSmall, int nIcons);
        
        [DllImport("user32.dll", EntryPoint = "DestroyIcon", SetLastError = true)]
        public static extern bool DestroyIcon(IntPtr hIcon);
    }
"@
    if (-not ([System.Management.Automation.PSTypeName]'Win32Icon').Type) {
        Add-Type -TypeDefinition $IconApiDefinition
    }

    # Helper function to pull system icons natively
    Function Get-SystemIcon {
        Param([string]$SourceFile, [int]$Index)
        $phiconLarge = [IntPtr]::Zero
        $phiconSmall = [IntPtr]::Zero
        [void][Win32Icon]::ExtractIconEx($SourceFile, $Index, [ref]$phiconLarge, [ref]$phiconSmall, 1)
        if ($phiconSmall -ne [IntPtr]::Zero) {
            $Icon = [System.Drawing.Icon]::FromHandle($phiconSmall).Clone()
            [void][Win32Icon]::DestroyIcon($phiconSmall)
            if ($phiconLarge -ne [IntPtr]::Zero) { [void][Win32Icon]::DestroyIcon($phiconLarge) }
            return $Icon
        }
        return $null
    }

    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $formWidth   = 500
    $formHeight  = 905
    $screenWidth  = [int](($workingArea.Width - ($formWidth + 1000)) / 2)
    $screenHeight = [int](($workingArea.Height - $formHeight) / 2)

    # Main Window Canvas (Light Theme UI)
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = if ([string]::IsNullOrEmpty($Filter)) { "Select Folder to Move Mod Directory" } else { "Select $Filter" }
    $Form.Size = New-Object System.Drawing.Size($formWidth, $formHeight)
    $Form.BackColor = [System.Drawing.Color]::White
    $Form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $Form.Location = New-Object System.Drawing.Point($screenWidth, $screenHeight)

    # Path Display Banner (Top Area)
    $PathLabel = New-Object System.Windows.Forms.Label
    $PathLabel.Text = "Current Folder: This PC"
    $PathLabel.Location = New-Object System.Drawing.Point(15, 15)
    $PathLabel.Size = New-Object System.Drawing.Size(450, 25)
    $PathLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $PathLabel.ForeColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    [void]$Form.Controls.Add($PathLabel)

    # --- SYSTEM ICON IMAGELIST SETUP ---
    $ImageList = New-Object System.Windows.Forms.ImageList
    $ImageList.ColorDepth = [System.Windows.Forms.ColorDepth]::Depth32Bit
    $ImageList.ImageSize = New-Object System.Drawing.Size(16, 16)

    # Map Windows resource indices into our library array
    $SysDir = [System.Environment]::SystemDirectory
    [void]$ImageList.Images.Add("Drive", (Get-SystemIcon "$SysDir\shell32.dll" 8))
    [void]$ImageList.Images.Add("Folder", (Get-SystemIcon "$SysDir\shell32.dll" 3))
    [void]$ImageList.Images.Add("HiddenFolder", (Get-SystemIcon "$SysDir\imageres.dll" 53)) 
    [void]$ImageList.Images.Add("Up", (Get-SystemIcon "$SysDir\shell32.dll" 45))
    [void]$ImageList.Images.Add("File", (Get-SystemIcon "$SysDir\shell32.dll" 0))

    # Main Folder Display Grid (List View)
    $ListView = New-Object System.Windows.Forms.ListView
    $ListView.Location = New-Object System.Drawing.Point(15, 50)
    $ListView.Size = New-Object System.Drawing.Size(450, 735)
    $ListView.View = [System.Windows.Forms.View]::Details
    $ListView.FullRowSelect = $true
    $ListView.GridLines = $false
    $ListView.SmallImageList = $ImageList 
    $ListView.BackColor = [System.Drawing.Color]::FromArgb(252, 252, 252) 
    $ListView.ForeColor = [System.Drawing.Color]::Black
    $ListView.Font = New-Object System.Drawing.Font("Segoe UI", 14)

    # Single column since we only focus on folder hierarchy
    $titleName = if ([string]::IsNullOrEmpty($Filter)) { "Select Folder to Move Mod Directory" } else { "Select $Filter" }
    [void]$ListView.Columns.Add($titleName, 430)
    [void]$Form.Controls.Add($ListView)

    # Action Buttons (Bottom Area)
    $CancelButton = New-Object System.Windows.Forms.Button
    $CancelButton.Text = "Cancel"
    $CancelButton.Location = New-Object System.Drawing.Point(15, 805) 
    $CancelButton.Size = New-Object System.Drawing.Size(100, 35)
    $CancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $CancelButton.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $CancelButton.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)
    $CancelButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $CancelButton.FlatAppearance.BorderSize = 0
    $CancelButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    Set-ControlRoundCorners -Control $CancelButton -Radius 8
    [void]$Form.Controls.Add($CancelButton)

    $SelectButton = New-Object System.Windows.Forms.Button
    $SelectButton.Text = if ([string]::IsNullOrEmpty($Filter)) { "Select Folder" } else { "Select File" }
    $SelectButton.Location = New-Object System.Drawing.Point(290, 805) 
    $SelectButton.Size = New-Object System.Drawing.Size(175, 35)
    $SelectButton.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $SelectButton.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $SelectButton.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)
    $SelectButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $SelectButton.FlatAppearance.BorderSize = 0
    $SelectButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200) # Soft Gray Border
    Set-ControlRoundCorners -Control $SelectButton -Radius 8
    [void]$Form.Controls.Add($SelectButton)

    # Global tracking variables
    $script:CurrentPath = "THIS_PC"
    $script:FinalSelection = $false

    # Function to safely pull directories, drives, or files
    Function Update-FolderBrowser {
        Param([string]$TargetDirectory)
        
        [void]$ListView.Items.Clear()
        $script:CurrentPath = $TargetDirectory

        # Default action button configuration based on active filters
        if (-not [string]::IsNullOrEmpty($Filter)) {
            $SelectButton.Enabled = $false # Lock down button globally until a matching file is highlighted
        } else {
            $SelectButton.Enabled = ($TargetDirectory -ne "THIS_PC") # Standard folder validation rules
        }

        # Scenario A: We are at the "This PC" root view
        if ($TargetDirectory -eq "THIS_PC") {
            $PathLabel.Text = "Current Folder: This PC"
            
            $Drives = [System.IO.DriveInfo]::GetDrives()
            ForEach ($Drive in $Drives) {
                $Label = if ($Drive.IsReady) { "$($Drive.Name) ($($Drive.VolumeLabel))" } else { "$($Drive.Name) (Drive not ready)" }
                $Item = New-Object System.Windows.Forms.ListViewItem($Label)
                $Item.Tag = @{ Path = $Drive.Name; IsDirectory = $true }
                $Item.ImageKey = "Drive" 
                [void]$ListView.Items.Add($Item)
            }
        } 
        # Scenario B: We are inside a standard folder path
        else {
            $PathLabel.Text = "Current Folder: $TargetDirectory"
            
            # Add up-navigation link
            $UpItem = New-Object System.Windows.Forms.ListViewItem(".. [Go Up to Parent Directory]")
            $UpItem.Tag = @{ Action = if ($TargetDirectory.Length -le 3) { "GO_TO_THIS_PC" } else { "UP_DIR" } }
            $UpItem.ImageKey = "Up"
            $UpItem.ForeColor = [System.Drawing.Color]::Gray
            [void]$ListView.Items.Add($UpItem)

            Try {
                # 1. Fetch Folders
                $Dirs = Get-ChildItem -LiteralPath $TargetDirectory -Directory -Force -ErrorAction SilentlyContinue
                ForEach ($Dir in $Dirs) {
                    $IsHidden = $Dir.Attributes.HasFlag([System.IO.FileAttributes]::Hidden)
                    $Item = New-Object System.Windows.Forms.ListViewItem($Dir.Name)
                    $Item.Tag = @{ Path = $Dir.FullName; IsDirectory = $true }
                    
                    if ($IsHidden) {
                        $Item.ImageKey = "HiddenFolder" 
                        $Item.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 140)
                    } else {
                        $Item.ImageKey = "Folder" 
                        $Item.ForeColor = [System.Drawing.Color]::Black
                    }
                    [void]$ListView.Items.Add($Item)
                }

                # 2. Fetch Files if a Filter argument is supplied
                if (-not [string]::IsNullOrEmpty($Filter)) {
                    $Files = Get-ChildItem -LiteralPath $TargetDirectory -File -Filter $Filter -Force -ErrorAction SilentlyContinue
                    ForEach ($File in $Files) {
                        $Item = New-Object System.Windows.Forms.ListViewItem($File.Name)
                        $Item.Tag = @{ Path = $File.FullName; IsDirectory = $false }
                        $Item.ImageKey = "File"
                        $Item.BackColor = [System.Drawing.Color]::FromArgb(235, 247, 238)
                        $Item.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
                        [void]$ListView.Items.Add($Item)
                    }
                }
            } Catch {
                New_MessageBox -title "Permission Error" -infoMessage "Access Denied or Directory Unreadable."
            }
        }
    }

    # --- DYNAMIC SELECTION VALIDATION LATCH ---
    # Monitors item clicks to lock or unlock the Select button instantly
    $ListView.Add_SelectedIndexChanged({
        if ($ListView.SelectedItems.Count -eq 1) {
            $Target = $ListView.SelectedItems[0].Tag
            
            if (-not [string]::IsNullOrEmpty($Filter)) {
                # If a filter is set, button ONLY unlocks when a non-directory file is highlighted
                $SelectButton.Enabled = ($null -ne $Target -and $Target.IsDirectory -eq $false -and $null -ne $Target.Path)
            } else {
                # Standard folder rule: Can select anything except root structural system commands
                $SelectButton.Enabled = ($null -ne $Target -and $null -ne $Target.Path)
            }
        } else {
            # No item selected
            if (-not [string]::IsNullOrEmpty($Filter)) {
                $SelectButton.Enabled = $false
            } else {
                $SelectButton.Enabled = ($script:CurrentPath -ne "THIS_PC")
            }
        }
    })

    # Interactive Navigation Logic (Triggered on Double-Click)
    $ListView.Add_DoubleClick({
        if ($ListView.SelectedItems.Count -eq 1) {
            $Target = $ListView.SelectedItems[0].Tag
            if ($Target.Action -eq "GO_TO_THIS_PC") {
                Update-FolderBrowser -TargetDirectory "THIS_PC"
            }
            elseif ($Target.Action -eq "UP_DIR") {
                $ParentDir = Split-Path $script:CurrentPath -Parent
                Update-FolderBrowser -TargetDirectory $ParentDir
            }
            elseif ($Target.IsDirectory) {
                Update-FolderBrowser -TargetDirectory $Target.Path
            }
            else {
                # If filter is passed, double-clicking a validated file exits and returns it
                if (-not [string]::IsNullOrEmpty($Filter)) {
                    $script:FinalSelection = $Target.Path
                    $Form.Close()
                }
            }
        }
    })

    # Button Commits
    $SelectButton.Add_Click({
        if ($ListView.SelectedItems.Count -eq 1) 
        {
            $Target = $ListView.SelectedItems[0].Tag
            if ($Target.Path) 
            {
                # Strict verification guard check
                if (-not [string]::IsNullOrEmpty($Filter) -and $Target.IsDirectory) { return }
                $script:FinalSelection = $Target.Path
                $Form.Close()
            }
        } else {
            # Fall back to folder logic if no explicit item highlighted and no filter exists
            if ([string]::IsNullOrEmpty($Filter) -and $script:CurrentPath -ne "THIS_PC") {
                $script:FinalSelection = $script:CurrentPath
                $Form.Close()
            }
        }
    })

    $CancelButton.Add_Click({
        $script:FinalSelection = $false
        $Form.Close()
    })

    # Kick off default layout population
    Update-FolderBrowser -TargetDirectory "THIS_PC"
    [void]$Form.ShowDialog()
    $Form.Dispose()
    return $script:FinalSelection
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

    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $formWidth   = 500
    $formHeight  = 905
    $screenWidth  = [int](($workingArea.Width - ($formWidth + 1000)) / 2)
    $screenHeight = [int](($workingArea.Height - $formHeight) / 2)

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = $GUItitle
    $Form.FormBorderStyle = "FixedSingle"
    $Form.MaximizeBox = $false
    $Form.Size = New-Object System.Drawing.Size($formWidth, $formHeight)
    $Form.BackColor = [System.Drawing.Color]::White
    $Form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $Form.Location = New-Object System.Drawing.Point($screenWidth, $screenHeight)

    $DataGridView = New-Object System.Windows.Forms.DataGridView
    $DataGridView.Dock = [System.Windows.Forms.DockStyle]::Fill
    $DataGridView.ReadOnly = $true
    $DataGridView.AllowUserToAddRows = $false
    $DataGridView.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill

    $DataGridView.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $DataGridView.MultiSelect = $multiSelect  # Allows Ctrl+Click and Shift+Click selections

    $Column = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $Column.HeaderText = "$nameUsed Name"
    $Column.Name = $nameUsed + "Name"
    [void]$DataGridView.Columns.Add($Column)

    foreach ($Mod in $ModList) {
        [void]$DataGridView.Rows.Add($Mod)
    }

    $ButtonPanel = New-Object System.Windows.Forms.Panel
    $ButtonPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $ButtonPanel.Height = 50

    $ClearButton = New-Object System.Windows.Forms.Button
    $ClearButton.Text = "Clear All"
    $ClearButton.Location = New-Object System.Drawing.Point(35, 10)
    $ClearButton.Size = New-Object System.Drawing.Size(85, 30)
    $ClearButton.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $ClearButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $ClearButton.FlatAppearance.BorderSize = 0
    $ClearButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200) # Soft Gray Border
    $ClearButton.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $ClearButton.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)

    $ClearButton.Add_Click({
        $dataGridView.ClearSelection()
    })

    $SelectAllButton = New-Object System.Windows.Forms.Button
    $SelectAllButton.Text = "Select All"
    $SelectAllButton.Location = New-Object System.Drawing.Point(135, 10)
    $SelectAllButton.Size = New-Object System.Drawing.Size(85, 30)
    $SelectAllButton.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $SelectAllButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $SelectAllButton.FlatAppearance.BorderSize = 0
    $SelectAllButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200) # Soft Gray Border
    $SelectAllButton.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $SelectAllButton.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)

    $SelectAllButton.Add_Click({
        $dataGridView.SelectAll()
    })

    $OKButton = New-Object System.Windows.Forms.Button
    $OKButton.Text = "OK"
    $OKButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $OKButton.Location = New-Object System.Drawing.Point(260, 10)
    $OKButton.Size = New-Object System.Drawing.Size(85, 30)
    $OKButton.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $OKButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $OKButton.FlatAppearance.BorderSize = 0
    $OKButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200) # Soft Gray Border
    $OKButton.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $OKButton.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)

    $CancelButton = New-Object System.Windows.Forms.Button
    $CancelButton.Text = "Cancel"
    $CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $CancelButton.Location = New-Object System.Drawing.Point(360, 10)
    $CancelButton.Size = New-Object System.Drawing.Size(85, 30)
    $CancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $CancelButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $CancelButton.FlatAppearance.BorderSize = 0
    $CancelButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200) # Soft Gray Border
    $CancelButton.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $CancelButton.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)

    Set-ControlRoundCorners -Control $OKButton -Radius 8
    Set-ControlRoundCorners -Control $CancelButton -Radius 8
    Set-ControlRoundCorners -Control $SelectAllButton -Radius 8
    Set-ControlRoundCorners -Control $ClearButton -Radius 8
    $ButtonPanel.Controls.AddRange(@($OKButton, $CancelButton, $SelectAllButton, $ClearButton))
    $Form.Controls.Add($DataGridView)  # Added first so Dock.Fill respects the panel space
    $Form.Controls.Add($ButtonPanel)
    $Form.AcceptButton = $OKButton
    $Form.CancelButton = $CancelButton

    $Form.Add_Load({
        $DataGridView.ClearSelection()
    })

    $Result = $Form.ShowDialog()

    $rowCellName = $nameUsed + "Name"
    if ($Result -eq [System.Windows.Forms.DialogResult]::OK) {
        $SelectedMods = foreach ($Row in $DataGridView.SelectedRows) {
            $Row.Cells["$rowCellName"].Value
        }
    
        if ($null -ne $SelectedMods) {
            [array]::Reverse($SelectedMods)
        }
    } else {
        $SelectedMods = $null
    }

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

    Write-Host ""

    if ($is_New_Server)
    {
        Write-WrappedHost -Text "* This will install a New Server with basic settings and under the Server ID you enter." -ForegroundColor Green
    }
    else
    {
        Write-WrappedHost -Text "* This will Import/Copy the existing Server Configuration files under the Server ID you enter." -ForegroundColor Yellow
    }
    Write-WrappedHost -Text "* Downloaded server mods will be stored in a UnifiedMods directory where mods for all servers are stored (no duplicate downloads)."
    if (-not $is_New_Server)
    {
        Write-WrappedHost -Text "* The User.json for the Imported Server will be copied so you will not need to get a new Security Code." -ForegroundColor Yellow
        Write-WrappedHost -Text "* All of the mods.maps downloaded by Imported Server will be copied to the UnifiedMods directory.  You will be prompted to locate the state.json file which contains information about the mods and location to copy the mods from." -ForegroundColor Yellow
    }
    Write-WrappedHost -Text "* The Configuration Wizard will be started to guide you through setting the most important items needed to start the server. Make sure you have the following information ready."
    Write-WrappedHost -Text "   All of the Mutator Configurations you want to add to the Game.ini file"
    Write-WrappedHost -Text "   Game Port - Query Port - Rcon Listen Port (Rcon Port is REQUIRED for the Server Info Window to function)"
    Write-WrappedHost -Text "   Server Password (optional) - Rcon Password (REQUIRED for Rcon Dashboard and Server Dashboard to function)"
    Write-WrappedHost -Text "   Server Host Name (including [Scenarios] in the name will show the number of scenarios available)"
    Write-WrappedHost -Text "   Number of Players - Game Stats Token - GSLT Token"
    Write-WrappedHost -Text "   Mutator List with a comma between each mutator (EX: beyondmeat,NoRestrictPlus,Medicon )"
    Write-WrappedHost -Text "   Steam64IDs for all Admins - Message of the Day"
    Write-WrappedHost -Text "   List of any Boot Maps you would like to add to the stock maps"
    Write-WrappedHost -Text "   List of any Maps to add to the Map Cycle"
    Write-WrappedHost -Text "* Editors will be opened for Game.ini, Admins, MOTD, Boot Maps and Map Cycle."
    Write-WrappedHost -Text "* Firewall Rules for the UDP and TCP ports will be created under the Server ID."
    Write-WrappedHost -Text "* The server will be added to Sandstorm Multi Server launcher."
    Write-WrappedHost -Text "* The new server will be started and once the user.json is updated the server will be shut down and the Server Launcher will be started."
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

    $UserChoice = User-Confirm -title "Install/Import Server" -infoMessage "$promptText"

    if ($UserChoice -eq 'No') 
    {
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "        Install/Import Server Aborted         " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
        return $false
    }
    else
    {
        $isValid = $false

        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        # 1. Create a Light-Themed Dialog Form
        $Form = New-Object System.Windows.Forms.Form
        $Form.Text = "Add New Server ID"
        $Form.Size = New-Object System.Drawing.Size(420, 220)
        $Form.StartPosition = "CenterScreen"
        $Form.FormBorderStyle = "FixedDialog"
        $Form.MaximizeBox = $false
        $Form.MinimizeBox = $false
        $Form.BackColor = [System.Drawing.Color]::White # Light background

        # 2. Description Label
        $Label = New-Object System.Windows.Forms.Label
        $Label.Text = "Enter the Server_ID (32 Characters Maximum):"
        $Label.Location = New-Object System.Drawing.Point(25, 25)
        $Label.Size = New-Object System.Drawing.Size(350, 20)
        $Label.ForeColor = [System.Drawing.Color]::Black
        $Form.Controls.Add($Label)

        # 3. Input Text Box
        $InputBox = New-Object System.Windows.Forms.TextBox
        $InputBox.Location = New-Object System.Drawing.Point(25, 50)
        $InputBox.Size = New-Object System.Drawing.Size(350, 25)
        $InputBox.MaxLength = 32 # Enforces the 32 character limit natively at the UI level
        $Form.Controls.Add($InputBox)

        # 4. Error/Warning Message Label (Hidden by default)
        $WarningLabel = New-Object System.Windows.Forms.Label
        $WarningLabel.Location = New-Object System.Drawing.Point(25, 85)
        $WarningLabel.Size = New-Object System.Drawing.Size(350, 35)
        $WarningLabel.ForeColor = [System.Drawing.Color]::Crimson # Red warning text
        $WarningLabel.Text = ""
        $Form.Controls.Add($WarningLabel)

        # 5. Submit Button
        $SubmitButton = New-Object System.Windows.Forms.Button
        $SubmitButton.Text = "Submit"
        $SubmitButton.Location = New-Object System.Drawing.Point(80, 130)
        $SubmitButton.Size = New-Object System.Drawing.Size(100, 32)
        $SubmitButton.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
        $SubmitButton.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
        $SubmitButton.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)
        $SubmitButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $SubmitButton.FlatAppearance.BorderSize = 0
        $SubmitButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200) # Soft Gray Border

        # Validation and Submission Logic
        $SubmitButton.Add_Click({
            # Clean input just like your regex rule
            $CleanedID = $InputBox.Text -replace '[^a-zA-Z0-9]', ''
    
            if ([string]::IsNullOrWhiteSpace($CleanedID)) {
                $WarningLabel.Text = "Invalid ID! Server_ID cannot be empty."
            }
            elseif ($null -ne $global:SeverListData.${CleanedID}) {
                # Check for duplication in your global object
                $WarningLabel.Text = "Invalid ID! The Server_ID is already in use."
            }
            else {
                # Success: Save output to script scope and return OK
                $script:ValidatedServerID = $CleanedID
                $this.FindForm().DialogResult = [System.Windows.Forms.DialogResult]::OK
                $this.FindForm().Close()
            }
        })
        Set-ControlRoundCorners -Control $SubmitButton -Radius 8
        $Form.Controls.Add($SubmitButton)

        # 6. Cancel Button (Mimics pressing Enter on an empty console line)
        $CancelButton = New-Object System.Windows.Forms.Button
        $CancelButton.Text = "Cancel"
        $CancelButton.Location = New-Object System.Drawing.Point(210, 130)
        $CancelButton.Size = New-Object System.Drawing.Size(90, 32)
        $CancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
        $CancelButton.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
        $CancelButton.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)
        $CancelButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $CancelButton.FlatAppearance.BorderSize = 0
        $CancelButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
        Set-ControlRoundCorners -Control $CancelButton -Radius 8
        $Form.Controls.Add($CancelButton)

        # 7. Form Display Logic
        $Form.AcceptButton = $SubmitButton # Pressing Enter clicks Submit
        $Form.CancelButton = $CancelButton # Pressing Esc clicks Cancel

        # Initialize tracking variable
        $script:ValidatedServerID = $null

        # Show the dialog box
        $UIResult = $Form.ShowDialog()

        # Handle the evaluation cleanly outside the UI thread context
        if ($UIResult -eq [System.Windows.Forms.DialogResult]::OK) {
           $server_Directory_Name = $script:ValidatedServerID
        } else {
                        Write-Host "==============================================" -ForegroundColor Cyan
                        Write-Host "        Install/Import Server Aborted         " -ForegroundColor Yellow
                        Write-Host "==============================================" -ForegroundColor Cyan
            return $false
        }

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

            Modio_mod_directory -filter "InsurgencyServer.exe"

            if ($script:FinalSelection -ne $false) {
                $SelectedFilePath = $script:FinalSelection
                $Source_Server_Path = Split-Path -Path $SelectedFilePath -Parent
  
                Write-Host "Directory path to InsurgencyServer.exe: $Source_Server_Path" -ForegroundColor Yellow
    
            } else {
                Remove-Item -Path $install_Directory -Recurse -Force
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host "        Install/Import Server Aborted         " -ForegroundColor Yellow
                Write-Host "==============================================" -ForegroundColor Cyan
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
            Write-WrappedHost -Text "Select the location of the user.json for the Server you have copied."
            Write-Host ""
            Write-WrappedHost -Text "Usually located in C:\Users\[AccountName]\AppData\Local\mod.io\254\ModServer" -ForegroundColor DarkYellow
            Write-Host ""
            Write-WrappedHost -Text "You can pull this information from computers on your network."
            Write-WrappedHost -Text "The user.json File you are copying will not be deleted."
            Write-Host ""

            Modio_mod_directory -filter "user.json"

            if ($script:FinalSelection -ne $false) {
                $SelectedFilePath = $script:FinalSelection
                $Source_Users_Path = Split-Path -Path $SelectedFilePath -Parent

                Write-WrappedHost -Text "Directory path to user.json: $Source_Users_Path" -ForegroundColor Yellow
    
            } else {
                Remove-Item -Path $install_Directory -Recurse -Force
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host "        Install/Import Server Aborted         " -ForegroundColor Yellow
                Write-Host "==============================================" -ForegroundColor Cyan
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
        Write-WrappedHost -Text "Created $settingsPath\globalsettings.json with RootLocalStoragePath = $rootdestination"

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

            Modio_mod_directory -filter "state.json"

            if ($script:FinalSelection -ne $false) {
                $SelectedFilePath = $script:FinalSelection
                $Source_mods_Path = Split-Path -Path $SelectedFilePath -Parent

                Write-Host "Directory path to state.json: $Source_mods_Path" -ForegroundColor Yellow
    
            } else {
                Remove-Item -Path $install_Directory -Recurse -Force
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host "        Install/Import Server Aborted         " -ForegroundColor Yellow
                Write-Host "==============================================" -ForegroundColor Cyan
                return $false
            }

            Write-Host ""
            Write-WrappedHost -Text "Source Directory path: $Source_mods_Path" -ForegroundColor Yellow
            Write-WrappedHost -Text "Destination Directory path: $destination" -ForegroundColor Yellow

            #copy cache, metadata and mods directory    
            robocopy "$Source_mods_Path" "$destination254\metadata" /E /IS | Out-Null

            $Source_mods_Path = Split-Path -Path $Source_mods_Path -Parent
            $serverDownloadedMods = Join-Path -Path $Source_mods_Path -ChildPath "mods\"
            $destinationMods = Join-Path -Path $PSScriptRoot -ChildPath "mods\UnifiedMods"
            Write-WrappedHost -Text "Destination Mods 1 path: $destination" -ForegroundColor Yellow
            $modsLocation = $destinationMods
            $destinationMods = $destinationMods + "\"
            Write-WrappedHost -Text "Destination Mods 2 path: $destination" -ForegroundColor Yellow

            $RobocopyArguments = @(
                $serverDownloadedMods,    # Source
                $destinationMods,         # Destination
                "/E",                     # Copy subdirectories (including empty ones)
                "/XO"                     # Exclude Older files (skips unchanged files)
            )

            try {
                Write-Host "Syncing mods from source to destination..." -ForegroundColor Cyan
    
                $Process = Start-Process -FilePath "robocopy.exe" -ArgumentList $RobocopyArguments -NoNewWindow -Wait -PassThru
    
                # Robocopy uses specific exit codes: 
                # Codes 0-7 mean success/copied files. Code 8+ means errors occurred.
                if ($Process.ExitCode -ge 8) {
                    Write-Host "Robocopy completed with errors. Exit Code: $($Process.ExitCode)" -ForegroundColor Red
                } else {
                    Write-Host "Mod sync completed successfully! Exit Code: $($Process.ExitCode)" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "Failed to start Robocopy execution: $_" -ForegroundColor Red
            }

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

        $UserChoice = User-Confirm -title "Edit Game.ini File" -infoMessage "Do you wish to Edit Game.ini?"

        if ($UserChoice -eq 'Yes') 
        {
            [string[]]$workingList = Get-Content -Path $workingPath
            $textData = edit_TXT_config_files -menuTitle "Server Game.ini Editor" -returnType 6 -workingListArray $workingList

            $textData | Set-Content -Path $workingPath
        }

        Write-Host ""
        Write-WrappedHost -Text "It is OPTIONAL to edit the Engine.ini for this server" -ForegroundColor Green
        Write-Host ""

        $UserChoice = User-Confirm -title "Edit Enfine.ini File" -infoMessage "Do you wish to Edit Engine.ini?"

        if ($UserChoice -eq 'Yes') 
        {
            $enginePath = Join-Path -Path $install_Directory -ChildPath "steamapps\common\sandstorm_server\Insurgency\Saved\Config\WindowsServer\Engine.ini"
            [string[]]$workingList = Get-Content -Path $enginePath
            $textData = edit_TXT_config_files -menuTitle "Server Engine.ini Editor" -returnType 7 -workingListArray $workingList

            $textData | Set-Content -Path $enginePath
        }

        Write-Host ""
        Write-WrappedHost -Text "Starting Setup Server Config: $setupServerPath"
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

            $UserChoice = User-Confirm -title "Check Configuration Settings" -infoMessage "Do changes need to be made to the Server Configuration?"

        } while ($UserChoice -eq 'Yes')

        Write-Host ""

        $Port = $configData.Port
        $QueryPort = $configData.QueryPort

        $TCP_UDPServerPath = Join-Path -Path $install_Directory -ChildPath "steamapps\common\sandstorm_server\insurgency\binaries\win64\InsurgencyServer-Win64-Shipping.exe"

        # --- PROCESS TCP RULE ---
        $displayNameTCP = "Insurgency $Base_Server_ID TCP"
        $existingRuleTCP = Get-NetFirewallRule -DisplayName $displayNameTCP -ErrorAction SilentlyContinue | 
            Where-Object { 
                $prog = ($_ | Get-NetFirewallApplicationFilter).Program
                $prot = ($_ | Get-NetFirewallPortFilter).Protocol
                # Force string comparison to handle path casing mismatches cleanly
                [string]::Equals($prog, $TCP_UDPServerPath, [System.StringComparison]::OrdinalIgnoreCase) -and $prot -eq 'TCP'
            }

        if ($null -eq $existingRuleTCP -or $existingRuleTCP.Count -eq 0) {
            try {
                New-NetFirewallRule -DisplayName $displayNameTCP -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port,$QueryPort -Program $TCP_UDPServerPath -Profile Private,Public -ErrorAction Stop
                Write-WrappedHost -Text "Insurgency $Base_Server_ID TCP Ports $Port,$QueryPort are now Open" -ForegroundColor Yellow
            }
            catch {
                Write-WrappedHost -Text "Failure: Failed to create firewall rule '$displayNameTCP'." -ForegroundColor Red
                Write-WrappedHost -Text "Error details: $_" -ForegroundColor Yellow
            }
        }
        else {
            try {
                # Loop through rules to prevent array pipeline crashes
                foreach ($rule in $existingRuleTCP) {
                    $rule | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -LocalPort $Port,$QueryPort -ErrorAction Stop
                }
                Write-WrappedHost -Text "Insurgency $Base_Server_ID TCP Ports $Port,$QueryPort are Open" -ForegroundColor Green
            }
            catch {
                Write-WrappedHost -Text "Failure updating existing TCP rules: $_" -ForegroundColor Red
            }
        }

        # --- PROCESS UDP RULE ---
        $displayNameUDP = "Insurgency $Base_Server_ID UDP"
        $existingRuleUDP = Get-NetFirewallRule -DisplayName $displayNameUDP -ErrorAction SilentlyContinue | 
            Where-Object { 
                $prog = ($_ | Get-NetFirewallApplicationFilter).Program
                $prot = ($_ | Get-NetFirewallPortFilter).Protocol
                [string]::Equals($prog, $TCP_UDPServerPath, [System.StringComparison]::OrdinalIgnoreCase) -and $prot -eq 'UDP'
            }

        if ($null -eq $existingRuleUDP -or $existingRuleUDP.Count -eq 0) {
            try {
                New-NetFirewallRule -DisplayName $displayNameUDP -Direction Inbound -Action Allow -Protocol UDP -LocalPort $Port,$QueryPort -Program $TCP_UDPServerPath -Profile Private,Public -ErrorAction Stop
                Write-WrappedHost -Text "Insurgency $Base_Server_ID UDP Ports $Port,$QueryPort are now Open" -ForegroundColor Yellow
            }
            catch {
                Write-WrappedHost -Text "Failure: Failed to create firewall rule '$displayNameUDP'." -ForegroundColor Red
                Write-WrappedHost -Text "Error details: $_" -ForegroundColor Yellow
            }
        }
        else {
            try {
                foreach ($rule in $existingRuleUDP) {
                    $rule | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -LocalPort $Port,$QueryPort -ErrorAction Stop
                }
                Write-WrappedHost -Text "Insurgency $Base_Server_ID UDP Ports $Port,$QueryPort are Open" -ForegroundColor Green
            }
            catch {
                Write-WrappedHost -Text "Failure updating existing UDP rules: $_" -ForegroundColor Red
            }
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
    }
    return $true
}

function restore_server_userjson
{
    Clear-Host
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "          Restore user.json Backup         " -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Checking Server ID: $global:selectedServerID" -ForegroundColor Green
    Write-Host ""

    $SourceServerDir = "$env:LOCALAPPDATA\mod.io.$global:selectedServerID\254\ModServer"

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

            $UserChoice = User-Confirm -title "Pick user.json to Restore" -infoMessage "Last Chance: Do you really want to replace user.json with this backup?"

            if ($UserChoice -eq 'Yes') 
            {
                $SourceFile = Join-Path -Path $SourceServerDir -ChildPath "$SelectedFile"
                $DestinationFile = Join-Path -Path $SourceServerDir -ChildPath "user.json"
    
                $SourceDir      = Split-Path -Path $SourceFile -Parent
                $DestinationDir = Split-Path -Path $DestinationFile -Parent
                $FileName       = Split-Path -Path $SourceFile -Leaf

                robocopy $SourceDir $DestinationDir $FileName /IS /IT

                Write-Host "user.json replaced with  " -NoNewline -ForegroundColor Green
                Write-host "$SelectedFile" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host "          user.json Restore Complete            " -ForegroundColor Yellow
                Write-Host "==============================================" -ForegroundColor Cyan
            }
            else
            {
                Write-Host "Copy was canceled." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "==============================================" -ForegroundColor Cyan
                Write-Host "           user.json Restore Aborted            " -ForegroundColor Yellow
                Write-Host "==============================================" -ForegroundColor Cyan
            }
        } else {
            Write-Host "No files were selected or the window was canceled." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "==============================================" -ForegroundColor Cyan
            Write-Host "           user.json Restore Aborted            " -ForegroundColor Yellow
            Write-Host "==============================================" -ForegroundColor Cyan
        }
     } else {
        Write-Warning "The directory does not exist: $SourceServerDir"
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "           user.json Restore Aborted            " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
    }
}

function disable_server
{
    if ($global:SeverListData.$global:selectedServerID.Disabled) {
        $statusText = "ENABLE"
    } else {
        $statusText = "DISABLE"
    }

    if ($global:SeverListData.$global:selectedServerID.Disabled)
    {
        $global:SeverListData.$global:selectedServerID.Disabled = $false
        $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightCyan
        $global:ServerButtons[$global:selectedServerID].Text = $global:ServerButtons["$global:selectedServerID"].Text.Replace("DISABLED", "ENABLED")
    }
    else
    {
        $global:SeverListData.$global:selectedServerID.Disabled = $true
        $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightPink
        $global:ServerButtons[$global:selectedServerID].Text = $global:ServerButtons["$global:selectedServerID"].Text.Replace("ENABLED", "DISABLED")
    }

    add_update_server -Server_ID $global:selectedServerID -isDisabled $global:SeverListData.$global:selectedServerID.Disabled
}

<#
    This will delete the Server_ID from the ServerList.json and delete the
    %localappdata%\mod.io.[Server_ID] directory.  The game server directory and
    mod.io[Server_ID] mod storage directories will not be removed.
#>

function delete_server
{
    Clear-Host
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "        Remove Server from Server List        " -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Checking Server ID: $global:selectedServerID" -ForegroundColor Green
    Write-Host ""
    Write-Host "---===>>> If you delete this Server ID the" -ForegroundColor Gray
    Write-Host "---===>>> $env:LOCALAPPDATA\mod.io.$global:selectedServerID" -ForegroundColor Gray
    Write-Host "---===>>> will be DELETED!!!" -ForegroundColor Gray
    Write-Host ""
    Write-Host "---===>>> The Server Configuration Directories will not be deleted." -ForegroundColor Green
    Write-Host "---===>>> The Mods Directory will NOT be deleted." -ForegroundColor Green
    Write-Host ""

    $UserChoice = User-Confirm -title "Remove $global:selectedServerID Server" -infoMessage "Do you want to Remove $global:selectedServerID ?"

    if ($UserChoice -eq 'Yes') 
    {
        $global:SeverListData.PSObject.Properties.Remove($global:selectedServerID)
        $global:SeverListData | ConvertTo-Json | Set-Content $ServerListJsonPath
        $global:SeverListData=Get-Content $ServerListJsonPath | ConvertFrom-Json

      	if(-not(Test-Path "$env:LOCALAPPDATA\mod.io.$global:selectedServerID"))
        {
            Write-Host ""
            Write-Host "$env:LOCALAPPDATA\mod.io.$global:selectedServerID directory not found" -ForegroundColor Yellow
        }
        else
        {
            Write-Host ""
            Write-Host "Deleting: $env:LOCALAPPDATA\mod.io.$global:selectedServerID" -ForegroundColor Red
            Remove-Item -Path "$env:LOCALAPPDATA\mod.io.$global:selectedServerID" -Recurse -Force
        }
        Write-Host ""
        Write-Host "$global:selectedServerID removed from Server List" -ForegroundColor Yellow

        # 1. Get the button object from your tracking hashtable
        $TargetButton = $global:ServerButtons["$global:selectedServerID"]

        if ($TargetButton) {
            # 2. Remove the button visually from the FlowLayoutPanel / Panel
            $ServerPanel.Controls.Remove($TargetButton)

            # 3. Dispose of the button object to free up system UI memory
            $TargetButton.Dispose()

            # 4. Remove it from your tracking hashtable so it can't be called again
            $global:ServerButtons.Remove("$global:selectedServerID")
    
            # 5. Clear the selection label since that server no longer exists in the panel
            $SelectedLabel.Text = "Currently Selected Server: None"
        }
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "           Server Removal Complete            " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
        return $true
    }
    else
    {
        Write-Host "$global:selectedServerID removal ABORTED" -ForegroundColor Gray
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "            Server Removal Aborted            " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
        return $false
    }
}

function unsubscribe_mods
{
    $UserChoice = User-Confirm -title "Unsubscribe $Base_Server_ID Server Mods" -infoMessage "Do you want to Unsubscribe Mods for $global:selectedServerID ?"

    if ($UserChoice -eq 'Yes') 
    {
        $ModListJsonPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ModList.$global:selectedServerID.json"
        Mod-Unsub -ModListJsonPath $ModListJsonPath -Server_ID $global:selectedServerID
    }
}

# Display GUI Selector of all subscribed mods and ask user to
# select any number of the mods to UNSUBSCRIBE and DELETE
function Mod-Unsub
{
    param(
        [string]$ModListJsonPath,
        [string]$Server_ID
    )
    Clear-Host
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "    Select Mods to Unsubscribe and Delete   " -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""

    # Initialize an empty array to collect all mod data
    $AllModLists = @()
    $ConfigDir = Join-Path -Path $PSScriptRoot -ChildPath "config"

    if (Test-Path $ConfigDir) 
    {
        Get-ChildItem -Path $ConfigDir -Filter "ModList.*.json" -File | ForEach-Object {
            if ($_.FullName -ne $ModListJsonPath) 
            {
                $JsonData = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json
                if ($null -ne $JsonData) 
                {
                    # Instantly gets all top-level keys like "98204", "98373"
                    $Keys = $JsonData.psobject.properties.name 

                    # Filter out what you already have and add them all at once
                    $NewMods = $Keys | Where-Object { $_ -notin $AllMods }
                    $AllMods += $NewMods
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
        Write-Host "MISSING $mod_io_254_server" -ForegroundColor Red
        Write-Host "Cannot proceed." -ForegroundColor Red
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "      Unsubscribe/Delete Action Aborted       " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
        return
    }

    [string]$token=$getuserjson.Oauth.token

    $gameId = 254
    $apiUrl = "https://api.mod.io/v1"
    $destinationMods = Join-Path -Path $PSScriptRoot -ChildPath "mods\UnifiedMods"
    $destinationMods = $destinationMods + "\"

    if (Test-Path $ModListJsonPath)
    {
	    Write-Host "Reading settings from ModList.$Server_ID.json."
        Write-Host ""
	    $ModListData=Get-Content $ModListJsonPath | ConvertFrom-Json
    }
    else
    {
        Write-Host "ModList.json is MISSING and cannot proceed." -ForegroundColor Red
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "      Unsubscribe/Delete Action Aborted       " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
        return
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
        Write-Host "No Mods Selected." -ForegroundColor Red
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "      Unsubscribe/Delete Action Aborted       " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
        return
    }

    $selectedModListDisplay = ""

    $tlen=$SelectedMods.count
    if( $tlen -gt 1)
    {
        for ($t = 0; $t -lt $tlen; $t++) {
            $selectedModListDisplay += $SelectedMods[$t].Trim() + "`n"
        }
    }
    else
    {
        $selectedModListDisplay = $SelectedMods.Trim() + "`n"
    }

    Write-Host "$selectedModListDisplay" -ForegroundColor Gray

    $UserChoice = User-Confirm -title "Unsubscribe $Server_ID Server Mods" -infoMessage "Last Chance: Are you sure you want to unsubcribe and delete the mod files listed in the Server Manager Console?"

    if ($UserChoice -eq 'No') 
    {
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "      Unsubscribe/Delete Action Aborted       " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
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

                $endpoint = "$apiUrl/games/$gameId/mods/$modid/subscribe"

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
                    $StatusCode = $_.Exception.Response.StatusCode.value__

                    $ErrorStream = $_.Exception.Response.GetResponseStream()
                    $Reader = New-Object System.IO.StreamReader($ErrorStream)
                    $ResponseBody = $Reader.ReadToEnd()
    
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

                Start-Sleep -Milliseconds 250
            }
        }
        else
        {
            $modid = ($SelectedMods -split " \| ")[1].Trim()
            $ModListData.PSObject.Properties.Remove($modid)

            $endpoint = "$apiUrl/games/$gameId/mods/$modid/subscribe"

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
                $StatusCode = $_.Exception.Response.StatusCode.value__

                $ErrorStream = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorStream)
                $ResponseBody = $Reader.ReadToEnd()

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

        $ModListData | ConvertTo-Json | Set-Content $ModListJsonPath

        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host " Selected Mods have been Unsubscribed/Deleted    " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
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

function Invoke-PortWizard {
    # 1. Main Window Container (Light Palette Elements)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Server Port Configuration"
    $form.Size = New-Object System.Drawing.Size(420, 360)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(244, 244, 247) # Soft Light Grey

    # 2. Header and Subtitle Labels
    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Location = New-Object System.Drawing.Point(25, 20)
    $lblHeader.Size = New-Object System.Drawing.Size(350, 28)
    $lblHeader.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $lblHeader.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 36)
    $lblHeader.Text = "Server Port Configuration"

    $lblSubtitle = New-Object System.Windows.Forms.Label
    $lblSubtitle.Location = New-Object System.Drawing.Point(25, 48)
    $lblSubtitle.Size = New-Object System.Drawing.Size(350, 20)
    $lblSubtitle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblSubtitle.ForeColor = [System.Drawing.Color]::FromArgb(94, 100, 117)
    $lblSubtitle.Text = "Assign unique ports between 1024 and 49151."

    # 3. Label & TextBox Rows
    # --- Server Port Row ---
    $lblPort = New-Object System.Windows.Forms.Label
    $lblPort.Location = New-Object System.Drawing.Point(25, 95)
    $lblPort.Size = New-Object System.Drawing.Size(140, 20)
    $lblPort.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblPort.ForeColor = [System.Drawing.Color]::FromArgb(45, 49, 66)
    $lblPort.Text = "Server Port:"

    $txtPort = New-Object System.Windows.Forms.TextBox
    $txtPort.Location = New-Object System.Drawing.Point(180, 92)
    $txtPort.Size = New-Object System.Drawing.Size(190, 26)
    $txtPort.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $txtPort.BackColor = [System.Drawing.Color]::White
    $txtPort.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
    $txtPort.Text = $configData.Port
    $txtPort.SelectionStart = $txtPort.Text.Length
    $txtPort.SelectionLength = 0

    # --- Server Query Port Row ---
    $lblQueryPort = New-Object System.Windows.Forms.Label
    $lblQueryPort.Location = New-Object System.Drawing.Point(25, 140)
    $lblQueryPort.Size = New-Object System.Drawing.Size(140, 20)
    $lblQueryPort.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblQueryPort.ForeColor = [System.Drawing.Color]::FromArgb(45, 49, 66)
    $lblQueryPort.Text = "Server Query Port:"

    $txtQueryPort = New-Object System.Windows.Forms.TextBox
    $txtQueryPort.Location = New-Object System.Drawing.Point(180, 137)
    $txtQueryPort.Size = New-Object System.Drawing.Size(190, 26)
    $txtQueryPort.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $txtQueryPort.BackColor = [System.Drawing.Color]::White
    $txtQueryPort.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
    $txtQueryPort.Text = $configData.QueryPort
    $txtQueryPort.SelectionStart = $txtQueryPort.Text.Length
    $txtQueryPort.SelectionLength = 0

    # --- Rcon Listen Port Row ---
    $lblRconPort = New-Object System.Windows.Forms.Label
    $lblRconPort.Location = New-Object System.Drawing.Point(25, 185)
    $lblRconPort.Size = New-Object System.Drawing.Size(140, 20)
    $lblRconPort.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblRconPort.ForeColor = [System.Drawing.Color]::FromArgb(45, 49, 66)
    $lblRconPort.Text = "Rcon Listen Port:"

    $txtRconPort = New-Object System.Windows.Forms.TextBox
    $txtRconPort.Location = New-Object System.Drawing.Point(180, 182)
    $txtRconPort.Size = New-Object System.Drawing.Size(190, 26)
    $txtRconPort.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $txtRconPort.BackColor = [System.Drawing.Color]::White
    $txtRconPort.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
    $txtRconPort.Text = $configData.RconListenPort
    $txtRconPort.SelectionStart = $txtRconPort.Text.Length
    $txtRconPort.SelectionLength = 0

    # 4. Save Configuration Action Button
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Location = New-Object System.Drawing.Point(25, 240)
    $btnSave.Size = New-Object System.Drawing.Size(345, 40)
    $btnSave.Text = "Save Configuration"
    $btnSave.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnSave.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(225, 240, 255)
    $btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSave.FlatAppearance.BorderSize = 0

    # 5. Validation Logic & Submission Handler
    $btnSave.Add_Click({
        $ports = @{
            "Server Port"       = $txtPort.Text
            "Server Query Port" = $txtQueryPort.Text
            "Rcon Listen Port"  = $txtRconPort.Text
        }

        $parsedPorts = @{}
        $seenPorts = @()

        # Parse data streams and run bounds/duplicate evaluations
        foreach ($key in $ports.Keys) {
            $val = $ports[$key]

            if (-not ($val -match '^\d+$')) {
                New_MessageBox -title "Validation Error" -infoMessage "Invalid input for $key. Please enter a valid number."
                return
            }

            $intVal = [int]$val
            if ($intVal -lt 1024 -or $intVal -gt 49151) {
                New_MessageBox -title "Validation Error" -infoMessage "$key must be between 1024 and 49151."
                return
            }

            if ($seenPorts -contains $intVal) {
                New_MessageBox -title "Validation Error" -infoMessage "Duplicate port usage detected! Each port must be unique."
                return
            }

            $seenPorts += $intVal
            $parsedPorts[$key] = $intVal
        }

        # Assign verified elements to local active config objects
        $configData.Port = $parsedPorts["Server Port"]
        $configData.QueryPort = $parsedPorts["Server Query Port"]
        $configData.RconListenPort = $parsedPorts["Rcon Listen Port"]

        # Run file update tasks
        if (Get-Command save_server_configuration -ErrorAction SilentlyContinue) {
            save_server_configuration -configData $configData -configPath $configPath
        }

        # NetFirewall rules handling segment
        if (-not $global:isNewServer) {
            $Port = $configData.Port
            $QueryPort = $configData.QueryPort
            $TCP_UDPServerPath = Join-Path -Path $PSScriptRoot -ChildPath "InsurgencySandstorm\steamapps\common\sandstorm_server\insurgency\binaries\win64\InsurgencyServer-Win64-Shipping.exe"
            $displayName = "Insurgency $Base_Server_ID TCP"

            # Find existing TCP rules safely using a string-insensitive path comparison
            $existingRule = Get-NetFirewallRule -DisplayName $displayName -ErrorAction SilentlyContinue | Where-Object {
                $prog = ($_ | Get-NetFirewallApplicationFilter).Program
                $prot = ($_ | Get-NetFirewallPortFilter).Protocol
                [string]::Equals($prog, $TCP_UDPServerPath, [System.StringComparison]::OrdinalIgnoreCase) -and $prot -eq 'TCP'
            }

            if ($null -eq $existingRule -or $existingRule.Count -eq 0) {
                try {
                    # Create the rule if it doesn't exist
                    New-NetFirewallRule -DisplayName $displayName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port,$QueryPort -Program $TCP_UDPServerPath -Profile Private,Public -ErrorAction Stop
                    Write-WrappedHost -Text "Insurgency $Base_Server_ID TCP Ports $Port,$QueryPort are now Open" -ForegroundColor Yellow
                } 
                catch {
                    Write-WrappedHost -Text "Failure: Failed to create firewall rule '$displayName'." -ForegroundColor Red
                    Write-WrappedHost -Text "Error details: $_" -ForegroundColor Yellow
                }
            } 
            else {
                try {
                    # Loop through found rules individually to prevent array pipeline crashes
                    foreach ($rule in $existingRule) {
                        $rule | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -LocalPort $Port,$QueryPort -ErrorAction Stop
                    }
                    Write-WrappedHost -Text "Insurgency $Base_Server_ID TCP Ports $Port,$QueryPort are Open" -ForegroundColor Green
                }
                catch {
                    Write-WrappedHost -Text "Failure updating existing TCP rules for '$displayName': $_" -ForegroundColor Red
                }
            }
        }

        # Update application interface element lists
        if ($script:Labels -and $script:Labels["1"]) {
            $script:Labels["1"].Text = "Server Ports - Port: $($configData.Port), Query Port: $($configData.QueryPort), RconListenPort: $($configData.RconListenPort)`n($adminText)"
        }

        New_MessageBox -title "Success" -infoMessage "Configuration saved and rules updated successfully!"
        $form.Close()
    })

    Set-ControlRoundCorners -Control $btnSave -Radius 8

    # 6. Add controls to layout tree and launch
    $form.Controls.AddRange(@($lblHeader, $lblSubtitle, $lblPort, $txtPort, $lblQueryPort, $txtQueryPort, $lblRconPort, $txtRconPort, $btnSave))
    $form.ShowDialog() | Out-Null
}

function Invoke-PasswordWizard {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Server Password Management"
    $form.Size = New-Object System.Drawing.Size(420, 340)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(244, 244, 247)

    # Header Controls
    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Location = New-Object System.Drawing.Point(25, 20)
    $lblHeader.Size = New-Object System.Drawing.Size(350, 28)
    $lblHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
    $lblHeader.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 36)
    $lblHeader.Text = "Server && Rcon Passrords"

    # Server Password (Optional)
    $lblPass = New-Object System.Windows.Forms.Label
    $lblPass.Location = New-Object System.Drawing.Point(25, 70)
    $lblPass.Size = New-Object System.Drawing.Size(350, 18)
    $lblPass.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lblPass.ForeColor = [System.Drawing.Color]::FromArgb(94, 100, 117)
    $lblPass.Text = "Server Password (Optional - Leave blank for public access)"

    $txtPass = New-Object System.Windows.Forms.TextBox
    $txtPass.Location = New-Object System.Drawing.Point(25, 92)
    $txtPass.Size = New-Object System.Drawing.Size(350, 26)
    $txtPass.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $txtPass.BackColor = [System.Drawing.Color]::White
    $txtPass.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
    $txtPass.Text = $configData.Password
    $txtPass.SelectionStart = $txtPass.Text.Length
    $txtPass.SelectionLength = 0

    # Rcon Password (Required)
    $lblRcon = New-Object System.Windows.Forms.Label
    $lblRcon.Location = New-Object System.Drawing.Point(25, 140)
    $lblRcon.Size = New-Object System.Drawing.Size(350, 18)
    $lblRcon.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lblRcon.ForeColor = [System.Drawing.Color]::FromArgb(94, 100, 117)
    $lblRcon.Text = "RCON Password (Required for Analytics: 5-32 Characters)"

    $txtRcon = New-Object System.Windows.Forms.TextBox
    $txtRcon.Location = New-Object System.Drawing.Point(25, 162)
    $txtRcon.Size = New-Object System.Drawing.Size(350, 26)
    $txtRcon.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $txtRcon.BackColor = [System.Drawing.Color]::White
    $txtRcon.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
    $txtRcon.Text = $configData.RconPassword
    $txtRcon.SelectionStart = $txtRcon.Text.Length
    $txtRcon.SelectionLength = 0

    # Submit Button
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Location = New-Object System.Drawing.Point(25, 220)
    $btnSave.Size = New-Object System.Drawing.Size(350, 40)
    $btnSave.Text = "Save Passwords"
    $btnSave.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnSave.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(225, 240, 255)
    $btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSave.FlatAppearance.BorderSize = 0

    $btnSave.Add_Click({
        $passVal = $txtPass.Text
        $rconVal = $txtRcon.Text

        # Enforce character criteria rules
        if ($rconVal.Length -lt 5 -or $rconVal.Length -gt 32) {
            New_MessageBox -title "Validation Notice" -infoMessage "Rcon Password validation failed! Requirements are between 5 and 32 characters."
            return
        }

        $configData.Password = $passVal
        $configData.RconPassword = $rconVal

        if (Get-Command save_server_configuration -ErrorAction SilentlyContinue) {
            save_server_configuration -configData $configData -configPath $configPath
        }

        if ($script:Labels -and $script:Labels["2"]) {
            $script:Labels["2"].Text = "Server Passwords - Password: $($configData.Password), Rcon: $($configData.RconPassword)`n* Rcon Required for Analytics & Dashboards"
        }

        $form.Close()
    })

    Set-ControlRoundCorners -Control $btnSave -Radius 8

    $form.Controls.AddRange(@($lblHeader, $lblPass, $txtPass, $lblRcon, $txtRcon, $btnSave))
    $form.ShowDialog() | Out-Null
}

function Invoke-HostNameWizard {

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Server Host Name"
    $form.Size = New-Object System.Drawing.Size(460, 310)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(244, 244, 247)

    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Location = New-Object System.Drawing.Point(25, 20)
    $lblHeader.Size = New-Object System.Drawing.Size(400, 25)
    $lblHeader.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblHeader.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 36)
    $lblHeader.Text = "Configure Host Server Name"

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Location = New-Object System.Drawing.Point(25, 55)
    $lblInfo.Size = New-Object System.Drawing.Size(400, 55)
    $lblInfo.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblInfo.ForeColor = [System.Drawing.Color]::FromArgb(94, 100, 117)
    $lblInfo.Text = "Include '[ScenarioCount]' string within target fields to append live calculations dynamically.`nLimits: 5-63 characters (Max 78 characters if macro string is included)."

    $txtHost = New-Object System.Windows.Forms.TextBox
    $txtHost.Location = New-Object System.Drawing.Point(25, 125)
    $txtHost.Size = New-Object System.Drawing.Size(390, 26)
    $txtHost.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $txtHost.Text = $configData.HostName
    $txtHost.SelectionStart = $txtHost.Text.Length
    $txtHost.SelectionLength = 0

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Location = New-Object System.Drawing.Point(25, 185)
    $btnSave.Size = New-Object System.Drawing.Size(390, 40)
    $btnSave.Text = "Save Server Host Name"
    $btnSave.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnSave.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(225, 240, 255)
    $btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSave.FlatAppearance.BorderSize = 0

    $btnSave.Add_Click({
        $inputStr = $txtHost.Text
        $maxLength = if ($inputStr.Contains("[ScenarioCount]")) { 78 } else { 63 }

        if ($inputStr.Length -lt 5 -or $inputStr.Length -gt $maxLength) {
            New_MessageBox -title "Bounds Check Error" -infoMessage "Character threshold boundary error! String must contain between 5 and $maxLength properties."
            return
        }

        $configData.HostName = $inputStr

        if (Get-Command save_server_configuration -ErrorAction SilentlyContinue) {
            save_server_configuration -configData $configData -configPath $configPath
        }

        if ($script:Labels -and $script:Labels["3"]) {
            $script:Labels["3"].Text = "Server Host Name - $($configData.HostName)"
        }

        $form.Close()
    })

    Set-ControlRoundCorners -Control $btnSave -Radius 8

    $form.Controls.AddRange(@($lblHeader, $lblInfo, $txtHost, $btnSave))
    $form.ShowDialog() | Out-Null
}

function Invoke-MaxPlayersWizard {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Player Capacity Limits"
    $form.Size = New-Object System.Drawing.Size(360, 240)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(244, 244, 247)

    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Location = New-Object System.Drawing.Point(25, 20)
    $lblHeader.Size = New-Object System.Drawing.Size(300, 25)
    $lblHeader.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblHeader.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 36)
    $lblHeader.Text = "Maximum Player Cap"

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Location = New-Object System.Drawing.Point(25, 50)
    $lblInfo.Size = New-Object System.Drawing.Size(300, 18)
    $lblInfo.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblInfo.ForeColor = [System.Drawing.Color]::FromArgb(94, 100, 117)
    $lblInfo.Text = "Select maximum concurrency allocation (1-32):"

    $txtPlayers = New-Object System.Windows.Forms.TextBox
    $txtPlayers.Location = New-Object System.Drawing.Point(25, 75)
    $txtPlayers.Size = New-Object System.Drawing.Size(290, 26)
    $txtPlayers.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $txtPlayers.Text = $configData.MaxPlayers
    $txtPlayers.SelectionStart = $txtPlayers.Text.Length
    $txtPlayers.SelectionLength = 0

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Location = New-Object System.Drawing.Point(25, 125)
    $btnSave.Size = New-Object System.Drawing.Size(290, 40)
    $btnSave.Text = "Save Player Limit"
    $btnSave.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnSave.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(225, 240, 255)
    $btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSave.FlatAppearance.BorderSize = 0

    $btnSave.Add_Click({
        if ($txtPlayers.Text -match '^\d+$') {
            $parsedInt = [int]$txtPlayers.Text
            if ($parsedInt -ge 1 -and $parsedInt -le 32) {
                $configData.MaxPlayers = $parsedInt

                if (Get-Command save_server_configuration -ErrorAction SilentlyContinue) {
                    save_server_configuration -configData $configData -configPath $configPath
                }

                if ($script:Labels -and $script:Labels["4"]) {
                    $script:Labels["4"].Text = "Maximum Players Supported - $($configData.MaxPlayers) Players"
                }
                $form.Close()
                return
            }
        }
        New_MessageBox -title "Player Count Exception" -infoMessage "Player Limit must be between 1 and 32 slots."
    })

    Set-ControlRoundCorners -Control $btnSave -Radius 8

    $form.Controls.AddRange(@($lblHeader, $lblInfo, $txtPlayers, $btnSave))
    $form.ShowDialog() | Out-Null
}

function Invoke-GameStatsWizard {
    # 1. Main Window Container (Light Theme Palette)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Steam GSLT Validator"
    $form.Size = New-Object System.Drawing.Size(460, 420)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(244, 244, 247) # Soft Light Grey

    # 2. Header and Instructional Text
    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Location = New-Object System.Drawing.Point(25, 20)
    $lblHeader.Size = New-Object System.Drawing.Size(400, 25)
    $lblHeader.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblHeader.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 36)
    $lblHeader.Text = "Steam Game Stats Login Token"

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Location = New-Object System.Drawing.Point(25, 50)
    $lblInfo.Size = New-Object System.Drawing.Size(400, 35)
    $lblInfo.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblInfo.ForeColor = [System.Drawing.Color]::FromArgb(94, 100, 117)
    $lblInfo.Text = "Enter your custom GameStats deployment key below. Token strings must match exactly 32 alphanumeric characters."

    # 3. Text Input Box Field
    $txtToken = New-Object System.Windows.Forms.TextBox
    $txtToken.Location = New-Object System.Drawing.Point(25, 95)
    $txtToken.Size = New-Object System.Drawing.Size(390, 26)
    $txtToken.Font = New-Object System.Drawing.Font("Consolas", 10.5)
    $txtToken.BackColor = [System.Drawing.Color]::White
    $txtToken.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
    $txtToken.Text = $configData.GameStatsToken
    $txtToken.SelectionStart = $txtToken.Text.Length
    $txtToken.SelectionLength = 0

    # 4. Built-in Real-time Validation Report Area
    $lblReportHeader = New-Object System.Windows.Forms.Label
    $lblReportHeader.Location = New-Object System.Drawing.Point(25, 140)
    $lblReportHeader.Size = New-Object System.Drawing.Size(400, 18)
    $lblReportHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lblReportHeader.ForeColor = [System.Drawing.Color]::FromArgb(45, 49, 66)
    $lblReportHeader.Text = "Validation Diagnostics Console:"

    $txtConsole = New-Object System.Windows.Forms.TextBox
    $txtConsole.Location = New-Object System.Drawing.Point(25, 162)
    $txtConsole.Size = New-Object System.Drawing.Size(390, 120)
    $txtConsole.Font = New-Object System.Drawing.Font("Consolas", 9.5)
    $txtConsole.Multiline = $true
    $txtConsole.ReadOnly = $true
    $txtConsole.ScrollBars = "Vertical"
    $txtConsole.BackColor = [System.Drawing.Color]::FromArgb(255, 255, 255)
    $txtConsole.ForeColor = [System.Drawing.Color]::FromArgb(55, 65, 81)
    $txtConsole.Text = "Status: Ready.`r`nClick 'Verify & Save Token' to test Token."

    # 5. Save and Validation Execution Button
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Location = New-Object System.Drawing.Point(25, 305)
    $btnSave.Size = New-Object System.Drawing.Size(390, 42)
    $btnSave.Text = "Verify & Save Token"
    $btnSave.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnSave.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(225, 240, 255)
    $btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSave.FlatAppearance.BorderSize = 0

    # 6. Embedded Test-SteamGSLTToken Verification Routine
    $btnSave.Add_Click({
        $rawToken = $txtToken.Text

        # Fallback default value handling loop if empty string submitted
        if ([string]::IsNullOrWhiteSpace($rawToken)) {
            if (-not ([string]::IsNullOrWhiteSpace($configData.GameStatsToken))) {
                $txtConsole.Text = "[CANCELLED] Empty input window detected. Keeping original fallback Token."
                New_MessageBox -title "Action Bypassed" -infoMessage "Input is blank. Retaining previous active Token."
                $form.Close()
                return
            } else {
                $txtConsole.Text = "[ERROR] Field value parameters cannot remain empty. Provide a valid 32 character structure token stream."
                return
            }
        }

        # Clear whitespace framing elements
        $sanitizedToken = $rawToken.Trim()
        $gamestatsPattern = "^[0-9a-fA-F]{32}$"
        $isgamestatsMatch = $sanitizedToken -match $gamestatsPattern

        # Build Console Diagnostic String Output Array
        $reportLog = New-Object System.Text.StringBuilder
        [void]$reportLog.AppendLine("=== Steam Game Stats Token Validation Report ===")
        [void]$reportLog.AppendLine("Raw Input Length: $($rawToken.Length)")
        [void]$reportLog.AppendLine("Processed Token:  $sanitizedToken")
        [void]$reportLog.AppendLine("----------------------------------------")

        if ($isgamestatsMatch) {
            [void]$reportLog.AppendLine("[SUCCESS] Game Stats structure is 100% correct!")
            [void]$reportLog.AppendLine("• Length check: Passed (Exactly 32 characters)")
            [void]$reportLog.AppendLine("• Character check: Passed (Valid alphanumeric values)")
            $txtConsole.Text = $reportLog.ToString()

            # Pass token parameters to operational system structures
            $configData.GameStatsToken = $sanitizedToken

            if (Get-Command save_server_configuration -ErrorAction SilentlyContinue) {
                save_server_configuration -configData $configData -configPath $configPath
            }

            if ($script:Labels -and $script:Labels["5"]) {
                $script:Labels["5"].Text = "Server GameStats Token - $($configData.GameStatsToken)`n* REQUIRED"
            }

            New_MessageBox -title "Success Validation" -infoMessage "Token structure verified successfully! Changes Saved."
            $form.Close()
        } else {
            [void]$reportLog.AppendLine("[FAILURE] Structurally INVALID Game Stats Token!")
            
            if ($sanitizedToken.Length -ne 32) {
                [void]$reportLog.AppendLine("• Length check: Failed (Length is $($sanitizedToken.Length) - must be exactly 32)")
            }
            if ($sanitizedToken -match '[^0-9a-zA-Z]') {
                [void]$reportLog.AppendLine("• Character check: Failed (Contains prohibited special characters/symbols)")
            }
            $txtConsole.Text = $reportLog.ToString()
            New_MessageBox -title "Syntax Failure" -infoMessage "The string signature does not comply with alphanumeric structural parameters. Adjust input strings."
        }
    })

    Set-ControlRoundCorners -Control $btnSave -Radius 8

    # Add components to active screen container and trigger
    $form.Controls.AddRange(@($lblHeader, $lblInfo, $txtToken, $lblReportHeader, $txtConsole, $btnSave))
    $form.ShowDialog() | Out-Null
}

function Invoke-GSLTWizard {
    # 1. Main Window Container (Light Theme Palette)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Steam GSLT Setup"
    $form.Size = New-Object System.Drawing.Size(460, 420)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(244, 244, 247) # Soft Light Grey

    # 2. Header and Instructional Text
    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Location = New-Object System.Drawing.Point(25, 20)
    $lblHeader.Size = New-Object System.Drawing.Size(400, 25)
    $lblHeader.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblHeader.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 36)
    $lblHeader.Text = "Steam GSLT Token"

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Location = New-Object System.Drawing.Point(25, 50)
    $lblInfo.Size = New-Object System.Drawing.Size(400, 35)
    $lblInfo.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblInfo.ForeColor = [System.Drawing.Color]::FromArgb(94, 100, 117)
    $lblInfo.Text = "Enter your GSLT Token below. GSLT token strings must be exactly 32 alphanumeric characters."

    # 3. Text Input Box Field
    $txtToken = New-Object System.Windows.Forms.TextBox
    $txtToken.Location = New-Object System.Drawing.Point(25, 95)
    $txtToken.Size = New-Object System.Drawing.Size(390, 26)
    $txtToken.Font = New-Object System.Drawing.Font("Consolas", 10.5)
    $txtToken.BackColor = [System.Drawing.Color]::White
    $txtToken.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
    $txtToken.Text = $configData.GSLTToken
    $txtToken.SelectionStart = $txtToken.Text.Length
    $txtToken.SelectionLength = 0

    # 4. Built-in Real-time Validation Report Area
    $lblReportHeader = New-Object System.Windows.Forms.Label
    $lblReportHeader.Location = New-Object System.Drawing.Point(25, 140)
    $lblReportHeader.Size = New-Object System.Drawing.Size(400, 18)
    $lblReportHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lblReportHeader.ForeColor = [System.Drawing.Color]::FromArgb(45, 49, 66)
    $lblReportHeader.Text = "Validation Diagnostics Console:"

    $txtConsole = New-Object System.Windows.Forms.TextBox
    $txtConsole.Location = New-Object System.Drawing.Point(25, 162)
    $txtConsole.Size = New-Object System.Drawing.Size(390, 120)
    $txtConsole.Font = New-Object System.Drawing.Font("Consolas", 9.5)
    $txtConsole.Multiline = $true
    $txtConsole.ReadOnly = $true
    $txtConsole.ScrollBars = "Vertical"
    $txtConsole.BackColor = [System.Drawing.Color]::FromArgb(255, 255, 255)
    $txtConsole.ForeColor = [System.Drawing.Color]::FromArgb(55, 65, 81)
    $txtConsole.Text = "Status: Ready.`r`nClick 'Verify & Save Token' to execute structural syntax testing logic."

    # 5. Save and Validation Execution Button
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Location = New-Object System.Drawing.Point(25, 305)
    $btnSave.Size = New-Object System.Drawing.Size(390, 42)
    $btnSave.Text = "Verify & Save Token"
    $btnSave.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnSave.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(225, 240, 255)
    $btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSave.FlatAppearance.BorderSize = 0

    # 6. Integrated GSLT Token Verification Routine
    $btnSave.Add_Click({
        $rawToken = $txtToken.Text

        # Fallback value handling if empty input is submitted
        if ([string]::IsNullOrWhiteSpace($rawToken)) {
            if (-not ([string]::IsNullOrWhiteSpace($configData.GSLTToken))) {
                $txtConsole.Text = "[CANCELLED] Empty input window detected. Keeping original fallback Token."
                New_MessageBox -title "Action Bypassed" -infoMessage "Input is blank. Retaining previous active Token."
                $form.Close()
                return
            } else {
                $txtConsole.Text = "[ERROR] Field value parameters cannot remain empty. Provide a valid 32 character token stream."
                return
            }
        }

        # Clear whitespace framing elements
        $sanitizedToken = $rawToken.Trim()
        $gsltPattern = "^[0-9a-zA-Z]{32}$"
        $isGSLTMatch = $sanitizedToken -match $gsltPattern

        # Build Console Diagnostic String
        $reportLog = New-Object System.Text.StringBuilder
        [void]$reportLog.AppendLine("=== Steam GSLT Validation Report ===")
        [void]$reportLog.AppendLine("Raw Input Length: $($rawToken.Length)")
        [void]$reportLog.AppendLine("Processed Token:  $sanitizedToken")
        [void]$reportLog.AppendLine("----------------------------------------")

        if ($isGSLTMatch) {
            [void]$reportLog.AppendLine("[SUCCESS] GSLT structure is 100% correct!")
            [void]$reportLog.AppendLine("• Length check: Passed (Exactly 32 characters)")
            [void]$reportLog.AppendLine("• Character check: Passed (Valid alphanumeric values)")
            $txtConsole.Text = $reportLog.ToString()

            # Assign valid token parameters back to active objects
            $configData.GSLTToken = $sanitizedToken

            if (Get-Command save_server_configuration -ErrorAction SilentlyContinue) {
                save_server_configuration -configData $configData -configPath $configPath
            }

            if ($script:Labels -and $script:Labels["6"]) {
                $script:Labels["6"].Text = "Server GSLT Token - $($configData.GSLTToken)`n* REQUIRED"
            }

            New_MessageBox -title "Validation Success" -infoMessage "Token structure verified successfully! Changes Saved."
            $form.Close()
        } else {
            [void]$reportLog.AppendLine("[FAILURE] Structurally INVALID Game Stats Token!")
            
            if ($sanitizedToken.Length -ne 32) {
                [void]$reportLog.AppendLine("• Length check: Failed (Length is $($sanitizedToken.Length) - must be exactly 32)")
            }
            if ($sanitizedToken -match '[^0-9a-zA-Z]') {
                [void]$reportLog.AppendLine("• Character check: Failed (Contains prohibited special characters/symbols)")
            }
            $txtConsole.Text = $reportLog.ToString()
            New_MessageBox -title "Syntax Failure" -infoMessage "The string signature does not comply with alphanumeric structural parameters. Adjust input strings."
        }
    })

    Set-ControlRoundCorners -Control $btnSave -Radius 8

    # Add components to active screen container and trigger
    $form.Controls.AddRange(@($lblHeader, $lblInfo, $txtToken, $lblReportHeader, $txtConsole, $btnSave))
    $form.ShowDialog() | Out-Null
}

function Invoke-MutatorsWizard {

    # If it is NOT a new server, route to your custom external list utility as the original script did
    if (-not $global:isNewServer) {
        if (Get-Command edit_TXT_config_files -ErrorAction SilentlyContinue) {
            $workingList = $configData.Mutators -split ','
            $configData.Mutators = edit_TXT_config_files -menuTitle "Server Mutator Editor" -returnType 1 -workingList $workingList
            
            if (Get-Command save_server_configuration -ErrorAction SilentlyContinue) {
                save_server_configuration -configData $configData -configPath $configPath
            }
            if ($script:Labels -and $script:Labels["7"]) {
                $script:Labels["7"].Text = "Edit Mutators: $($configData.Mutators)"
            }
        } else {
            New_MessageBox -title "Dependency Error" -infoMessage "Configuration utility 'edit_TXT_config_files' not found."
        }
        return
    }

    # 1. Main Window Container (Light Palette Elements)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Mutator Configuration"
    $form.Size = New-Object System.Drawing.Size(460, 310)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(244, 244, 247) # Soft Light Grey

    # 2. Header and Instructional Text
    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Location = New-Object System.Drawing.Point(25, 20)
    $lblHeader.Size = New-Object System.Drawing.Size(400, 25)
    $lblHeader.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblHeader.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 36)
    $lblHeader.Text = "Configure Server Gameplay Mutators"

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Location = New-Object System.Drawing.Point(25, 55)
    $lblInfo.Size = New-Object System.Drawing.Size(400, 55)
    $lblInfo.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblInfo.ForeColor = [System.Drawing.Color]::FromArgb(94, 100, 117)
    $lblInfo.Text = "Enter a comma-separated list of server mutators. `nRequirements: Prohibit spaces entirely. Delimit entries using commas. Leave completely blank to disable mutators entirely."

    # 3. Text Input Box Field
    $txtMutators = New-Object System.Windows.Forms.TextBox
    $txtMutators.Location = New-Object System.Drawing.Point(25, 125)
    $txtMutators.Size = New-Object System.Drawing.Size(390, 26)
    $txtMutators.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $txtMutators.BackColor = [System.Drawing.Color]::White
    $txtMutators.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
    $txtMutators.Text = $configData.Mutators
    $txtMutators.SelectionStart = $txtMutators.Text.Length
    $txtMutators.SelectionLength = 0

    # 4. Save Action Button
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Location = New-Object System.Drawing.Point(25, 185)
    $btnSave.Size = New-Object System.Drawing.Size(390, 42)
    $btnSave.Text = "Save Mutators"
    $btnSave.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnSave.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(225, 240, 255)
    $btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSave.FlatAppearance.BorderSize = 0

    # 5. Validation Logic & Submission Handler
    $btnSave.Add_Click({
        $inputStr = $txtMutators.Text

        # If it is empty or blank, it's valid (clears mutators)
        if ([string]::IsNullOrWhiteSpace($inputStr)) {
            $configData.Mutators = ""
        }
        else {
            # Strip whitespace anywhere in the string to fix casual typing mistakes
            $sanitizedStr = $inputStr -replace '\s+', ''

            # Match alphanumeric lists with dash/underscore allowed, delimited only by commas
            if ($sanitizedStr -match '^[a-zA-Z0-9_-]+(?:,[a-zA-Z0-9_-]+)*$') {
                $configData.Mutators = $sanitizedStr
            }
            else {
                New_MessageBox -title "Validation Notice" -infoMessage "Input syntax error! The list must contain NO spaces, and each name must be delimited strictly by a comma."
                return
            }
        }

        # Save to file
        if (Get-Command save_server_configuration -ErrorAction SilentlyContinue) {
            save_server_configuration -configData $configData -configPath $configPath
        }

        # Update parent script UI label tracker cleanly
        if ($script:Labels -and $script:Labels["7"]) {
            $script:Labels["7"].Text = "Edit Mutators: $($configData.Mutators)"
        }

        New_MessageBox -title "Success" -infoMessage "Mutator configurations saved successfully!"
        $form.Close()
    })

    Set-ControlRoundCorners -Control $btnSave -Radius 8

    # Add components to active screen container and trigger dialog window
    $form.Controls.AddRange(@($lblHeader, $lblInfo, $txtMutators, $btnSave))
    $form.ShowDialog() | Out-Null
}

function Invoke-MOTDWizard {
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
    $script:Labels["8"].Text = "Edit Motd.txt File: Edited"
}

function Invoke-AdminsWizard {

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
    $script:Labels["9"].Text = "Edit Admins.txt File: Edited"
}

function Invoke-BootMapsWizard {
    $directoryPath = Split-Path -Path $configPath
    $workingPath = Join-Path -Path $directoryPath -ChildPath "server\bootmaps.txt"
    [string[]]$workingList = Get-Content -Path $workingPath

    $textData = edit_TXT_config_files -menuTitle "Boot Map Editor: $Base_Server_ID"  -returnType 3 -workingListArray $workingList

    $textData | Set-Content -Path $workingPath
    $script:Labels["10"].Text = "Edit bootmaps.txt File: Edited"
}

function Invoke-MapCycleWizard {
    $directoryPath = Split-Path -Path $configPath
    $workingPath = Join-Path -Path $directoryPath -ChildPath "server\mapcycle.txt"
    [string[]]$workingList = Get-Content -Path $workingPath

    $textData = edit_TXT_config_files -menuTitle "Map Cycle Editor: $Base_Server_ID"  -returnType 3 -workingListArray $workingList

    $textData | Set-Content -Path $workingPath
    $script:Labels["11"].Text = "Edit mapcycle.txt File: Edited"
}

function Invoke-GameINIWizard {
    if ($global:isNewServer -eq $false)
    {
        $directoryPath = Split-Path -Path $configPath
        $workingPath = Join-Path -Path $directoryPath -ChildPath "WindowsServer\Game.ini"
        [string[]]$workingList = Get-Content -Path $workingPath

        $textData = edit_TXT_config_files -menuTitle "Game.ini Editor: $Base_Server_ID"  -returnType 6 -workingListArray $workingList
                        
        $textData | Set-Content -Path $workingPath
    }
    $script:Labels["12"].Text = "Edit Game.ini File: Edited"
}

function Invoke-EngineINIWizard {

    if ($global:isNewServer -eq $false)
    {
        $directoryPath = Split-Path -Path $configPath
        $workingPath = Join-Path -Path $directoryPath -ChildPath "WindowsServer\Engine.ini"
        [string[]]$workingList = Get-Content -Path $workingPath

        $textData = edit_TXT_config_files -menuTitle "Engine.ini Editor: $Base_Server_ID"  -returnType 7 -workingListArray $workingList
                        
        $textData | Set-Content -Path $workingPath
    }
    $script:Labels["13"].Text = "Edit Engine.ini File: Edited"
}

function Invoke-SecurityCodeWizard {

    $UserChoice = User-Confirm -title "Security Code Check" -infoMessage "Do you need to request a new SecurityCode from mod.io?`n`n(Not needed if this is a newly IMPORTED Server)"

    if ($UserChoice -eq 'No') 
    {
        if (Get-Command save_server_configuration -ErrorAction SilentlyContinue) {
            save_server_configuration -configData $configData -configPath $configPath
        }
        if ($script:Labels -and $script:Labels["14"]) {
            $script:Labels["14"].Text = "Security Code Wizard - SecurityCode: $($configData.SecurityCode)"
        }
        return
    }

    # 1. Main Window Container (Light Theme Palette)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "mod.io Authentication Wizard"
    $form.Size = New-Object System.Drawing.Size(460, 480)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(244, 244, 247) # Soft Light Grey

    # 2. Header and Instructional Text
    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Location = New-Object System.Drawing.Point(25, 20)
    $lblHeader.Size = New-Object System.Drawing.Size(400, 25)
    $lblHeader.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblHeader.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 36)
    $lblHeader.Text = "Mod.io Security Token Setup"

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Location = New-Object System.Drawing.Point(25, 50)
    $lblInfo.Size = New-Object System.Drawing.Size(400, 40)
    $lblInfo.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblInfo.ForeColor = [System.Drawing.Color]::FromArgb(94, 100, 117)
    $lblInfo.Text = "Enter Server email to receive a 5-digit verification token. Security codes are explicitly valid for exactly 15 minutes."

    # 3. Step 1: Email Address Input Framework
    $lblEmail = New-Object System.Windows.Forms.Label
    $lblEmail.Location = New-Object System.Drawing.Point(25, 105)
    $lblEmail.Size = New-Object System.Drawing.Size(390, 18)
    $lblEmail.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lblEmail.ForeColor = [System.Drawing.Color]::FromArgb(45, 49, 66)
    $lblEmail.Text = "Registered Account Email Address:"

    $txtEmail = New-Object System.Windows.Forms.TextBox
    $txtEmail.Location = New-Object System.Drawing.Point(25, 125)
    $txtEmail.Size = New-Object System.Drawing.Size(240, 26)
    $txtEmail.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $txtEmail.BackColor = [System.Drawing.Color]::White
    $txtEmail.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)

    # API Interaction Request Button
    $btnRequest = New-Object System.Windows.Forms.Button
    $btnRequest.Location = New-Object System.Drawing.Point(275, 124)
    $btnRequest.Size = New-Object System.Drawing.Size(140, 28)
    $btnRequest.Text = "Request Code"
    $btnRequest.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnRequest.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $btnRequest.BackColor = [System.Drawing.Color]::FromArgb(225, 240, 255)
    $btnRequest.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnRequest.FlatAppearance.BorderSize = 0

    # 4. Built-in Real-time Diagnostic Console Area
    $txtConsole = New-Object System.Windows.Forms.TextBox
    $txtConsole.Location = New-Object System.Drawing.Point(25, 170)
    $txtConsole.Size = New-Object System.Drawing.Size(390, 90)
    $txtConsole.Font = New-Object System.Drawing.Font("Consolas", 9.5)
    $txtConsole.Multiline = $true
    $txtConsole.ReadOnly = $true
    $txtConsole.ScrollBars = "Vertical"
    $txtConsole.BackColor = [System.Drawing.Color]::White
    $txtConsole.ForeColor = [System.Drawing.Color]::FromArgb(55, 65, 81)
    $txtConsole.Text = "Status: Awaiting email entry input stream tracking sequence..."

    # 5. Step 2: 5-Digit PIN Input Framework
    $lblCode = New-Object System.Windows.Forms.Label
    $lblCode.Location = New-Object System.Drawing.Point(25, 280)
    $lblCode.Size = New-Object System.Drawing.Size(390, 18)
    $lblCode.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lblCode.ForeColor = [System.Drawing.Color]::FromArgb(45, 49, 66)
    $lblCode.Text = "Enter 5-Digit Email Verification Security Code:"

    $txtCode = New-Object System.Windows.Forms.TextBox
    $txtCode.Location = New-Object System.Drawing.Point(25, 300)
    $txtCode.Size = New-Object System.Drawing.Size(390, 26)
    $txtCode.Font = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Bold)
    $txtCode.CharacterCasing = [System.Windows.Forms.CharacterCasing]::Upper
    $txtCode.MaxLength = 5
    $txtCode.Text = $configData.SecurityCode

    # 6. Final Save Action Button
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Location = New-Object System.Drawing.Point(25, 360)
    $btnSave.Size = New-Object System.Drawing.Size(390, 42)
    $btnSave.Text = "Verify & Save Security Code"
    $btnSave.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnSave.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(225, 240, 255)
    $btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSave.FlatAppearance.BorderSize = 0

    # API Request Processing Click Handler
    $btnRequest.Add_Click({
        $serverEmail = $txtEmail.Text.Trim()
        
        # Regex validation to verify explicit valid email syntax rules
        $emailPattern = '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$'
        if ($serverEmail -notmatch $emailPattern) {
            $txtConsole.Text = "[VALIDATION ERROR] The email format entered is invalid. Ensure you use names@domains.com criteria formatting structural parameters."
            New_MessageBox -title "Format Error" -infoMessage "Invalid email addressing syntax parameters."
            return
        }

        $txtConsole.Text = "[CONNECTING] Dispatching request payload to mod.io API servers..."
        $btnRequest.Enabled = $false
        $form.Refresh()

        $apiKey = "bbf3af200848aef28418c032a601e7a2"
        $gameId = "254"
        $url = "https://g-$gameId.modapi.io/v1/oauth/emailrequest"

        $headers = @{
            "Accept" = "application/json"
            "Content-Type" = "application/x-www-form-urlencoded"
        }
        $body = @{
            "api_key" = $apiKey
            "email"   = $serverEmail
        }

        try {
            $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
            
            $reportLog = New-Object System.Text.StringBuilder
            [void]$reportLog.AppendLine("[SUCCESS] Token requested cleanly mod.io endpoint API.")
            [void]$reportLog.AppendLine("Message: $($response.message)")
            [void]$reportLog.AppendLine("Action required: Check '$serverEmail' for your unique temporary 5-digit verification PIN.")
            $txtConsole.Text = $reportLog.ToString()
        }
        catch {
            $txtConsole.Text = "[API TRANSIT EXCEPTION ERROR]`r`n$_"
            New_MessageBox -title "Transit Failure" -infoMessage "Failed to trigger authorization API transaction. Check networking streams details."
        }
        
        $btnRequest.Enabled = $true
    })

    Set-ControlRoundCorners -Control $btnRequest -Radius 8

    # Validation Logic and Code Verification Click Handler
    $btnSave.Add_Click({
        $codeVal = $txtCode.Text.Trim().ToUpper()

        # Enforce exact 5 character alphanumeric string patterns match bounds check
        if ($codeVal -notmatch '^[A-Z0-9]{5}$') {
            New_MessageBox -title "Validation Error" -infoMessage "Security codes must contain exactly 5 characters."
            return
        }

        # Apply parameters back to system profile schema configurations
        $configData.SecurityCode = $codeVal

        if (Get-Command save_server_configuration -ErrorAction SilentlyContinue) {
            save_server_configuration -configData $configData -configPath $configPath
        }

        if ($script:Labels -and $script:Labels["14"]) {
            $script:Labels["14"].Text = "Security Code Wizard - SecurityCode: $($configData.SecurityCode)"
        }

        New_MessageBox -title "Configuration Updated" -infoMessage "Security code updated cleanly for server context '$Base_Server_ID'.`n`nNote: This code expires in 15 minutes. Ensure the core environment instances bootstrap executes before expiration rules apply."
        $form.Close()
    })

    Set-ControlRoundCorners -Control $btnSave -Radius 8

    $form.Controls.AddRange(@($lblHeader, $lblInfo, $lblEmail, $txtEmail, $btnRequest, $txtConsole, $lblCode, $txtCode, $btnSave))
    $form.ShowDialog() | Out-Null

}

function Setup-Ports 
{ 
    Invoke-PortWizard
    Invoke-PasswordWizard
    Invoke-HostNameWizard
    Invoke-MaxPlayersWizard
    Invoke-GameStatsWizard
    Invoke-GSLTWizard
    Invoke-MutatorsWizard
    Invoke-MOTDWizard
    Invoke-AdminsWizard
    Invoke-BootMapsWizard
    Invoke-MapCycleWizard
    Invoke-SecurityCodeWizard
}

function buildRebootList
{
    param
    (
        [string]$server_ID
    )

    if ($global:rebootServerList -notmatch "$server_ID") {
        $global:rebootServerList += "$server_ID`n"
        if (-not $global:ServerButtons[$global:selectedServerID].Text.EndsWith(" (Edited)")) {
            $global:ServerButtons[$global:selectedServerID].Text += " (Edited)"
            Update-ButtonHeight -Button $global:ServerButtons[$global:selectedServerID] -TargetWidth 401 -MinHeight 20
        }
    }    
}

function server_configuration_editor
{
    param(
        [string]$Base_Server_ID,
        [string]$configPath,
        [bool]$isNewServer = $false
    )

    $global:isNewServer = $isNewServer

    $configData = load_server_configuration -configPath $configPath
    if ($configData -eq $false) {
        New_MessageBox -title "Error" -infoMessage "Configuration not found for: $Base_Server_ID"
        return
    }

    # Helper function to create uniform flat menu buttons (Light Theme Variant)
    function Create-MenuButton ([string]$text) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $text
        $btn.Size = New-Object System.Drawing.Size(120, 45)
        $btn.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $btn.FlatStyle = "Flat"
        $btn.FlatAppearance.BorderSize = 0
        $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
        $btn.BackColor = [System.Drawing.Color]::White
        $btn.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
        $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
        return $btn
    }

    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $formWidth   = 650
    $formHeight  = 905
    $screenWidth  = [int](($workingArea.Width - ($formWidth + 1152)) / 2)
    $screenHeight = [int](($workingArea.Height - $formHeight) / 2)

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "Server Configuration Wizard - $Base_Server_ID"
    $Form.Size = New-Object System.Drawing.Size(650, 905)
    $Form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $Form.FormBorderStyle = "FixedDialog"
    $Form.MaximizeBox = $false
    $Form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $Form.Location = New-Object System.Drawing.Point($screenWidth, $screenHeight)

    $HeaderPanel = New-Object System.Windows.Forms.Panel
    $HeaderPanel.Size = New-Object System.Drawing.Size(650, 60)
    $HeaderPanel.BackColor = [System.Drawing.Color]::FromArgb(230, 235, 240) # Soft slate-blue accent
    $HeaderPanel.Dock = "Top"

    $HeaderLabel = New-Object System.Windows.Forms.Label
    $HeaderLabel.Text = "SERVER CONFIGURATION WIZARD`nID: $Base_Server_ID"
    $HeaderLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $HeaderLabel.ForeColor = [System.Drawing.Color]::FromArgb(44, 62, 80) # Strong deep blue/gray text
    $HeaderLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $HeaderLabel.Dock = "Fill"
    $HeaderPanel.Controls.Add($HeaderLabel)
    $Form.Controls.Add($HeaderPanel)

    $Grid = New-Object System.Windows.Forms.TableLayoutPanel
    $Grid.Location = New-Object System.Drawing.Point(15, 75)
    $Grid.Size = New-Object System.Drawing.Size(600, 740)
    $Grid.ColumnCount = 3
    $Grid.RowCount = 14
    [VOID]$Grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 30)))   # Number index
    [VOID]$Grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 430)))  # Option Description/Values
    [VOID]$Grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 130)))  # Action Button
    
    # Track labels globally so their text can be modified live by internal script functions
    $script:Labels = @{}

    # Helper function to push rows into the layout grid sequentially
    function Add-GridRow ([int]$row, [string]$index, [string]$labelText, $actionButton, [System.Drawing.Color]$labelColor = [System.Drawing.Color]::FromArgb(40,40,40)) {
        $idxLabel = New-Object System.Windows.Forms.Label
        $idxLabel.Text = "$index"
        $idxLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $idxLabel.ForeColor = [System.Drawing.Color]::DimGray
        $idxLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $idxLabel.Dock = "Fill"

        $descLabel = New-Object System.Windows.Forms.Label
        $descLabel.Text = $labelText
        $descLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $descLabel.ForeColor = $labelColor
        $descLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $descLabel.Dock = "Fill"
        $script:Labels[$index.TrimEnd('.')] = $descLabel

        $Grid.Controls.Add($idxLabel, 0, $row)
        $Grid.Controls.Add($descLabel, 1, $row)
        if ($actionButton) { $Grid.Controls.Add($actionButton, 2, $row) }
    }

    # Check administrative privileges for display values
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $adminText = if ($isAdmin) { "Enabled: Running as Administrator" } else { "Disabled: Start Server Manager as Admin" }
    $adminColor = if ($isAdmin) { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkOrange }

    # ---- Row 1: Ports ----

    $btnPorts = Create-MenuButton -text "Edit Ports"
    $btnPorts.Enabled = $isAdmin 
    $btnPorts.Add_Click({$btnPorts.Enabled = $false; Invoke-PortWizard; $btnPorts.Enabled = $true; buildRebootList -server_ID $Base_Server_ID})
    Add-GridRow -row 0 -index "1." -labelText "Server Ports - Port: $($configData.Port), Query Port: $($configData.QueryPort), RconListenPort: $($configData.RconListenPort)`n($adminText)" -actionButton $btnPorts -labelColor $adminColor

    # ---- Row 2: Passwords ----

    $btnPass = Create-MenuButton -text "Edit Passwords"
    $btnPass.Add_Click({$btnPass.Enabled = $false; Invoke-PasswordWizard; $btnPass.Enabled = $true; buildRebootList -server_ID $Base_Server_ID})

    Add-GridRow -row 1 -index "2." -labelText "Server Passwords - Password: $($configData.Password), Rcon: $($configData.RconPassword)`n* Rcon Required for Analytics & Dashboards" -actionButton $btnPass -labelColor ([System.Drawing.Color]::Chocolate)

    # ---- Row 3: Host Name ----

    $btnHost = Create-MenuButton -text "Edit Hostname"
    $btnHost.Add_Click({$btnHost.Enabled = $false; Invoke-HostNameWizard; $btnHost.Enabled = $true; buildRebootList -server_ID $Base_Server_ID})
    Add-GridRow -row 2 -index "3." -labelText "Server Host Name - $($configData.HostName)" -actionButton $btnHost

    # ---- Row 4: Max Players ----

    $btnPlayers = Create-MenuButton -text "Edit Max Players"
    $btnPlayers.Add_Click({$btnPlayers.Enabled = $false; Invoke-MaxPlayersWizard; $btnPlayers.Enabled = $true; buildRebootList -server_ID $Base_Server_ID})
    Add-GridRow -row 3 -index "4." -labelText "Maximum Players Supported - $($configData.MaxPlayers) Players" -actionButton $btnPlayers

    # ---- Row 5: GameStats Token ----

    $btnStats = Create-MenuButton -text "Edit GameStats"
    $btnStats.Add_Click({$btnStats.Enabled = $false; Invoke-GameStatsWizard; $btnStats.Enabled = $true; buildRebootList -server_ID $Base_Server_ID})
    Add-GridRow -row 4 -index "5." -labelText "Server GameStats Token - $($configData.GameStatsToken)`n* REQUIRED" -actionButton $btnStats -labelColor ([System.Drawing.Color]::Chocolate)

    # ---- Row 6: GSLT Token ----

    $btnGslt = Create-MenuButton -text "Edit GSLT"
    $btnGslt.Add_Click({$btnGslt.Enabled = $false; Invoke-GSLTWizard; $btnGslt.Enabled = $true; buildRebootList -server_ID $Base_Server_ID}) 
    Add-GridRow -row 5 -index "6." -labelText "Server GSLT Token - $($configData.GSLTToken)`n* REQUIRED" -actionButton $btnGslt -labelColor ([System.Drawing.Color]::Chocolate)

    # ---- Row 7: Mutators ----

    $btnMutators = Create-MenuButton -text "Edit Mutators"
    $btnMutators.Add_Click({$btnMutators.Enabled = $false; Invoke-MutatorsWizard; $btnMutators.Enabled = $true; buildRebootList -server_ID $Base_Server_ID})
    Add-GridRow -row 6 -index "7." -labelText "Edit Mutators: $($configData.Mutators)" -actionButton $btnMutators

    # ---- Row 8: Motd ----

    $btnMotd = Create-MenuButton -text "Edit Motd.txt"
    $btnMotd.Add_Click({$btnMotd.Enabled = $false; Invoke-MOTDWizard; $btnMotd.Enabled = $true; buildRebootList -server_ID $Base_Server_ID})
    Add-GridRow -row 7 -index "8." -labelText "Edit Motd.txt File" -actionButton $btnMotd

    # ---- Row 9: Admins ----

    $btnAdmins = Create-MenuButton -text "Edit Admins.txt"
    $btnAdmins.Add_Click({$btnAdmins.Enabled = $false; Invoke-AdminsWizard; $btnAdmins.Enabled = $true; buildRebootList -server_ID $Base_Server_ID})
    Add-GridRow -row 8 -index "9." -labelText "Edit Admins.txt File" -actionButton $btnAdmins

    # ---- Row 10: Bootmaps ----

    $btnBootmaps = Create-MenuButton -text "Edit bootmaps.txt"
    $btnBootmaps.Add_Click({$btnBootmaps.Enabled = $false; Invoke-BootMapsWizard; $btnBootmaps.Enabled = $true; buildRebootList -server_ID $Base_Server_ID})
    Add-GridRow -row 9 -index "10." -labelText "Edit bootmaps.txt File" -actionButton $btnBootmaps

    # ---- Row 11: MapCycle ----

    $btnMapcycle = Create-MenuButton -text "Edit mapcycle.txt"
    $btnMapcycle.Add_Click({$btnMapcycle.Enabled = $false; Invoke-MapCycleWizard; $btnMapcycle.Enabled = $true; buildRebootList -server_ID $Base_Server_ID})
    Add-GridRow -row 10 -index "11." -labelText "Edit mapcycle.txt File" -actionButton $btnMapcycle

    # ---- Row 12: Game.in ----

    $btnGame = Create-MenuButton -text "Edit Game.ini"
    $btnGame.Add_Click({$btnGame.Enabled = $false; Invoke-GameINIWizard; $btnGame.Enabled = $true; buildRebootList -server_ID $Base_Server_ID})
    Add-GridRow -row 11 -index "12." -labelText "Edit Game.ini File" -actionButton $btnGame

    # ---- Row 13: Engin.ini ----

    $btnEngine = Create-MenuButton -text "Edit Engine.ini"
    $btnEngine.Add_Click({$btnEngine.Enabled = $false; Invoke-EngineINIWizard; $btnEngine.Enabled = $true; buildRebootList -server_ID $Base_Server_ID})
    Add-GridRow -row 12 -index "13." -labelText "Edit Engine.ini File" -actionButton $btnEngine

    # ---- Row 14: Security Code ----

    $btnSecurity = Create-MenuButton -text "Security Code"
    $btnSecurity.Add_Click({$btnSecurity.Enabled = $false; Invoke-SecurityCodeWizard; $btnSecurity.Enabled = $true; buildRebootList -server_ID $Base_Server_ID})
    Add-GridRow -row 13 -index "14." -labelText "Security Code Wizard - SecurityCode: $($configData.SecurityCode)" -actionButton $btnSecurity
    Add-GridRow -row 14 
    $Form.Controls.Add($Grid)

    $FooterPanel = New-Object System.Windows.Forms.Panel
    $FooterPanel.Size = New-Object System.Drawing.Size(650, 50)
    $FooterPanel.BackColor = [System.Drawing.Color]::FromArgb(230, 235, 240) # Soft slate-blue accent
    $FooterPanel.Dock = "Bottom"

    $StatusLabel = New-Object System.Windows.Forms.Label
    $StatusLabel.Text = "ℹ️ Changes Auto-Saved"
    $StatusLabel.ForeColor = [System.Drawing.Color]::Gray
    $StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Italic)
    $StatusLabel.Location = New-Object System.Drawing.Point(20, 15)
    $StatusLabel.Size = New-Object System.Drawing.Size(200, 20)
    $FooterPanel.Controls.Add($StatusLabel)

    $ExitButton = New-Object System.Windows.Forms.Button
    $ExitButton.Text = "Close Wizard"
    $ExitButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $ExitButton.Size = New-Object System.Drawing.Size(120, 40)
    $ExitButton.Location = New-Object System.Drawing.Point(478, 5)
    $ExitButton.FlatStyle = "Flat"
    $ExitButton.FlatAppearance.BorderColor = [System.Drawing.Color]::Tomato
    $ExitButton.FlatAppearance.BorderSize = 0
    $ExitButton.BackColor = [System.Drawing.Color]::MistyRose # Muted Red/Pink exit styling
    $ExitButton.ForeColor = [System.Drawing.Color]::DarkRed
    $ExitButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $ExitButton.Add_Click({ 
        $Form.Close()
    })
    $FooterPanel.Controls.Add($ExitButton)

    $Form.Add_FormClosing({
        param($sender, $e)
    
        # Check if the close action was triggered by the user clicking the 'X' or Alt+F4
        if ($e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            if (-not [string]::IsNullOrWhiteSpace($global:rebootServerList))
           {
                New_MessageBox -title "Server Reboot Required" -infoMessage "A reboot of the following servers is required (if currently running) for configuration changes to take effect:`n`n$global:rebootServerList"
           }
        }
    })

    $Form.Controls.Add($FooterPanel)

    if (Get-Command Set-ControlRoundCorners -ErrorAction SilentlyContinue) {
        $Grid.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] } | ForEach-Object { Set-ControlRoundCorners -Control $_  -Radius 8}
        Set-ControlRoundCorners -Control $ExitButton -Radius 8

    }

    $InitTimer = New-Object System.Windows.Forms.Timer
    $InitTimer.Interval = 100 # 100 milliseconds is plenty of time to render

    $InitTimer.Add_Tick({
        $InitTimer.Stop() # Stop the timer immediately so it only runs once
    
        if ($global:isNewServer -eq $true) {
            # Temporarily disable the form so the user sees it but can't click things mid-process
            $Form.Enabled = $false 
        
            Setup-Ports -closeForm $Form

            # Re-enable the fully loaded form
            $Form.Enabled = $true
            $Form.Close()
        }
    })

    $Form.Add_Load({ $InitTimer.Start() })
          
    $Form.ShowDialog() | Out-Null
}

function change_server_configuration
{
    $configPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ServerData\$global:selectedServerID\ServerStartup.json"
    server_configuration_editor -Base_Server_ID $global:selectedServerID -configPath $configPath -isNewServer $false
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
 }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Set-ControlRoundCorners {
    param(
        [ValidateNotNullOrEmpty()]
        [System.Windows.Forms.Control]$Control,

        [int]$Radius = 5,

        [System.Drawing.Color]$BorderColor = [System.Drawing.Color]::FromArgb(206, 212, 218),

        [int]$BorderThickness = 1
    )

    # Define the path calculation logic as an unlinked module
    $BuildPathModule = {
        param($w, $h, $r)
        $d = $r * 2
        $p = New-Object System.Drawing.Drawing2D.GraphicsPath
        $p.AddArc(0, 0, $d, $d, 180, 90)
        $p.AddArc(($w - $d - 1), 0, $d, $d, 270, 90)
        $p.AddArc(($w - $d - 1), ($h - $d - 1), $d, $d, 0, 90)
        $p.AddArc(0, ($h - $d - 1), $d, $d, 90, 90)
        $p.CloseAllFigures()
        return $p
    }

    # Dynamic adjustment if the control changes dimensions
    $Control.Add_Resize({
        param($sender, $e)
        $Engine = $sender.Tag.PathModule
        $Rad = $sender.Tag.Radius
        
        if ($null -ne $Engine) {
            # Extract raw item [0] to bypass PowerShell's automation collection wrapper
            $ResizePath = $Engine.Invoke($sender.Width, $sender.Height, $Rad)[0]
            $sender.Region = New-Object System.Drawing.Region($ResizePath)
            $ResizePath.Dispose()
        }
    })

    # Custom clean border tracing 
    $Control.Add_Paint({
        param($sender, $e)
        $Engine = $sender.Tag.PathModule
        $Rad = $sender.Tag.Radius
        $BColor = $sender.Tag.BorderColor
        $BThickness = $sender.Tag.BorderThickness

        if ($null -ne $Engine) {
            # Extract raw item [0] to bypass PowerShell's automation collection wrapper
            $PaintPath = $Engine.Invoke($sender.Width, $sender.Height, $Rad)[0]
            
            $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $Pen = New-Object System.Drawing.Pen($BColor, $BThickness)
            
            $e.Graphics.DrawPath($Pen, $PaintPath)
            
            $Pen.Dispose()
            $PaintPath.Dispose()
        }
    })

    # Package metadata payload directly onto the Control instance memory bank
    $Control.Tag = [PSCustomObject]@{
        PathModule      = $BuildPathModule
        Radius          = $Radius
        BorderColor     = $BorderColor
        BorderThickness = $BorderThickness
    }

    # Mask the control's structural region immediately for initialization
    $InitialPath = $BuildPathModule.Invoke($Control.Width, $Control.Height, $Radius)[0]
    $Control.Region = New-Object System.Drawing.Region($InitialPath)
    $InitialPath.Dispose()
}

<#
    Display Main Menu
#>
function Update-ButtonHeight {
    param (
        [System.Windows.Forms.Button]$Button,
        [int]$TargetWidth = 401,
        [int]$MinHeight = 20
    )
    # Define the bounding box (Fixed width, infinite height)
    $proposedSize = New-Object System.Drawing.Size($TargetWidth, 0)
    
    # Enable text wrapping formats
    $textFlags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::Left
    
    # Calculate exact text dimensions
    $measuredSize = [System.Windows.Forms.TextRenderer]::MeasureText($Button.Text, $Button.Font, $proposedSize, $textFlags)
    
    # Apply height with a small padding buffer, clamping to the minimum height baseline
    $newHeight = [Math]::Max($MinHeight, $measuredSize.Height)
    $Button.Size = New-Object System.Drawing.Size($TargetWidth, $newHeight)
}

function Show-Menu 
{
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Force high-DPI scaling configurations for sharp font rendering on Win 10 & 11
    if ([System.Windows.Forms.Application].GetMethods().Name -contains "SetHighDpiMode") {
        [System.Windows.Forms.Application]::SetHighDpiMode([System.Windows.Forms.HighDpiMode]::SystemAware)
    } else {
        # Fallback for Windows PowerShell 5.1 (Windows 10/11 native API)
        # This instructs Windows to handle DPI scaling for this PowerShell process directly
        $MethodDefinition = '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
        $User32 = Add-Type -MemberDefinition $MethodDefinition -Name "User32Dpi" -PassThru
        $User32::SetProcessDPIAware() | Out-Null
    }
    [System.Windows.Forms.Application]::EnableVisualStyles()

    # ---------------------------------------------------------
    # State Verification (Preserved from console logic)
    # ---------------------------------------------------------
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $adminAllowed = $isAdmin

    if( $isAdmin )
    {
        $InstallImportText = ""
    }
    else
    {
        $InstallImportText = "Admin Mode Required"
    }

    # ---------------------------------------------------------
    # Main Form Window Styling
    # ---------------------------------------------------------
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "Sandstorm Multi Server Manager v$Version"
    $Form.Size = New-Object System.Drawing.Size(520, 905)
    $Form.StartPosition = "CenterScreen"
    $Form.FormBorderStyle = "FixedSingle"
    $Form.MaximizeBox = $false
    $Form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)

    # ---------------------------------------------------------
    # Header & Admin Status Bar
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

    $SelectedLabel = New-Object System.Windows.Forms.Label
    $SelectedLabel.Text = "Currently Selected Server: NONE"
    $SelectedLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11, ([System.Drawing.FontStyle]::Bold -bor [System.Drawing.FontStyle]::Italic))
    $SelectedLabel.ForeColor = [System.Drawing.Color]::DarkGreen
    $SelectedLabel.Size = New-Object System.Drawing.Size(460, 30)
    $SelectedLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $SelectedLabel.Location = New-Object System.Drawing.Point(20, 250)
    $form.Controls.Add($SelectedLabel)

    # ---------------------------------------------------------
    # CONVERTED: Server Inventory Flow Layout Panel
    # ---------------------------------------------------------
    # Replaced TextBox with a Panel to neatly group and containerize dynamically generated buttons
    $ServerPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $ServerPanel.Location = New-Object System.Drawing.Point(35, 85)
    $ServerPanel.Size = New-Object System.Drawing.Size(430, 160)
    $ServerPanel.FlowDirection = "TopDown"
    $ServerPanel.AutoScroll = $true # Adds scrollbars automatically if inventory overflows 160px
    $ServerPanel.WrapContents = $false
    $ServerPanel.BackColor = [System.Drawing.Color]::White
    $ServerPanel.BorderStyle = "FixedSingle"

    # Generate a custom action button for every server instance discovered
    $ServerButton = New-Object System.Windows.Forms.Button
    $ServerButton.Text = "Clear Selected Server"
    $ServerButton.Size = New-Object System.Drawing.Size(401, 20)
    $ServerButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $ServerButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $ServerButton.Margin = New-Object System.Windows.Forms.Padding(5, 5, 5, 0)
    $ServerButton.FlatStyle = "Flat"
    $ServerButton.FlatAppearance.BorderSize = 0
    $ServerButton.BackColor = [System.Drawing.Color]::LightGreen

    # Dynamically lock scope data to each button execution block
    $ServerButton.Add_Click(({
        if (-not [string]::IsNullOrWhiteSpace($global:selectedServerID)) {
            if($global:SeverListData.$global:selectedServerID.Disabled)
            {
                $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightPink
            }
            else
            {
                $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightCyan
            }
        }
        $global:selectedServerID = ""
        $SelectedLabel.Text = "Currently Selected Server: NONE"
    }).GetNewClosure())

    Set-ControlRoundCorners -Control $ServerButton -Radius 8
    $ServerPanel.Controls.Add($ServerButton)

    $Form.Controls.Add($ServerPanel)

    $global:ServerButtons = @{}

    if (($global:SeverListData.PSObject.Properties).count -gt 0) {
        $global:Server_List_Count = 1

        foreach ($property in $global:SeverListData.psobject.Properties) {
            $server_ID = $property.Name
            $statusText = if ($property.Value.Disabled) { "DISABLED" } else { "ENABLED" }

            # Generate a custom action button for every server instance discovered
            $ServerButton = New-Object System.Windows.Forms.Button
            $ServerButton.Text = "[$global:Server_List_Count]  $server_ID  ($statusText)"

            # Explicitly tell the engine it's allowed to wrap multi-line text strings
            $ServerButton.UseCompatibleTextRendering = $true

            $ServerButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
            $ServerButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
            $ServerButton.Margin = New-Object System.Windows.Forms.Padding(5, 5, 5, 0)
            $ServerButton.FlatStyle = "Flat"
            $ServerButton.FlatAppearance.BorderSize = 0

            # ADJUST HEIGHT IMMEDIATELY BASED ON THE INITIAL TEXT
            Update-ButtonHeight -Button $ServerButton -TargetWidth 401 -MinHeight 20
             
            # Visual indicators based on state
            if ($property.Value.Disabled) {
                $ServerButton.BackColor = [System.Drawing.Color]::LightPink
            } else {
                $ServerButton.BackColor = [System.Drawing.Color]::LightCyan
            }

            # Dynamically lock scope data to each button execution block
            $currentID = $server_ID
            $ServerButton.Add_Click(({
                if (-not [string]::IsNullOrWhiteSpace($global:selectedServerID)) {
                    if($global:SeverListData.$global:selectedServerID.Disabled)
                    {
                        $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightPink
                    }
                    else
                    {
                        $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightCyan
                    }
                }
                $global:selectedServerID = $currentID
                $SelectedLabel.Text = "Currently Selected Server: $currentID"
                $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightGray
            }).GetNewClosure())
            Set-ControlRoundCorners -Control $ServerButton -Radius 8

            $ServerPanel.Controls.Add($ServerButton)

            $global:ServerButtons[$server_ID] = $ServerButton

            $global:Server_List_Count += 1
        }

        $global:Server_List_Count = $global:Server_List_Count - 1

    } else {
        $global:Server_List_Count = 0
        
        # Display fallback text label inside the control array if inventory is empty
        $EmptyLabel = New-Object System.Windows.Forms.Label
        $EmptyLabel.Text = "No active servers discovered in database inventory."
        $EmptyLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Italic)
        $EmptyLabel.ForeColor = [System.Drawing.Color]::Gray
        $EmptyLabel.Size = New-Object System.Drawing.Size(400, 30)
        $EmptyLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $ServerPanel.Controls.Add($EmptyLabel)
    }
    
    $hasServers = $global:Server_List_Count -gt 0
    $serverAllowed = $hasServers

    # Shifting focus down into layout window space smoothly
    $Form.Add_Shown({
        $Form.SelectNextControl($ServerPanel, $true, $true, $true, $true)
    })
 
    $Line1 = New-Object System.Windows.Forms.Label
    $Line1.BackColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
    $Line1.Location = New-Object System.Drawing.Point(20, 285)
    $Line1.Size = New-Object System.Drawing.Size(460, 2)
    $Form.Controls.Add($Line1)

    # ---------------------------------------------------------
    # Helper Function to Build Operational Buttons (1 - 9)
    # ---------------------------------------------------------
    $script:currentY = 300
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
        
        Set-ControlRoundCorners -Control $btn -Radius 8
        $Form.Controls.Add($btn)
        $script:currentY += 38
    }

    # ---------------------------------------------------------
    # Adding Operational Action Buttons
    # ---------------------------------------------------------
    Add-MenuButton "Install New Server $InstallImportText" $adminAllowed { 
        $resultCheck = install_server -is_New_Server $true
        If($resultCheck -eq $true)
        {
            if (-not [string]::IsNullOrWhiteSpace($global:selectedServerID)) {
                if($global:SeverListData.$global:selectedServerID.Disabled)
                {
                    $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightPink
                }
                else
                {
                    $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightCyan
                }
                $global:selectedServerID = ""
                $SelectedLabel.Text = "Currently Selected Server: NONE" 
            }
            ExitAndStartServers
            $script:ExitRequested = $true
            $this.FindForm().Close()
        }
    }
    Add-MenuButton "Import Existing Server $InstallImportText" $adminAllowed { 
        $resultCheck = install_server -is_New_Server $false
        If($resultCheck -eq $true)
        {
            if (-not [string]::IsNullOrWhiteSpace($global:selectedServerID)) {
                if($global:SeverListData.$global:selectedServerID.Disabled)
                {
                    $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightPink
                }
                else
                {
                    $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightCyan
                }
                $global:selectedServerID = ""
                $SelectedLabel.Text = "Currently Selected Server: NONE" 
            }
            ExitAndStartServers
            $script:ExitRequested = $true
            $this.FindForm().Close()
        }
    }
    Add-MenuButton "Remove Server from Server List" $serverAllowed { 
        if (-not [string]::IsNullOrWhiteSpace($global:selectedServerID)) {
            $resultAction = delete_server
            if(-not $resultAction)
            {
                if($global:SeverListData.$global:selectedServerID.Disabled)
                {
                    $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightPink
                }
                else
                {
                    $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightCyan
                }
            }
            $global:selectedServerID = ""
            $SelectedLabel.Text = "Currently Selected Server: NONE" 
        }
    } $true
    Add-MenuButton "Enable/Disable Server" $serverAllowed { 
        if (-not [string]::IsNullOrWhiteSpace($global:selectedServerID)) {
            disable_server
            if($global:SeverListData.$global:selectedServerID.Disabled)
            {
                $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightPink
            }
            else
            {
                $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightCyan
            }
            $global:selectedServerID = ""
            $SelectedLabel.Text = "Currently Selected Server: NONE" 
        }
    }
    Add-MenuButton "Change Server Configuration" $serverAllowed { 
        if (-not [string]::IsNullOrWhiteSpace($global:selectedServerID)) {
            change_server_configuration
            if($global:SeverListData.$global:selectedServerID.Disabled)
            {
                $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightPink
            }
            else
            {
                $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightCyan
            }
            $global:selectedServerID = ""
            $SelectedLabel.Text = "Currently Selected Server: NONE" 
        }
    }
    Add-MenuButton "Unsubscribe/Delete Mods" $serverAllowed { 
        if (-not [string]::IsNullOrWhiteSpace($global:selectedServerID)) {
            unsubscribe_mods
            if($global:SeverListData.$global:selectedServerID.Disabled)
            {
                $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightPink
            }
            else
            {
                $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightCyan
            }
            $global:selectedServerID = ""
            $SelectedLabel.Text = "Currently Selected Server: NONE" 
        }
    } $true
    Add-MenuButton "Restore Backup Server user.json" $serverAllowed { 
        if (-not [string]::IsNullOrWhiteSpace($global:selectedServerID)) {
            restore_server_userjson
            if($global:SeverListData.$global:selectedServerID.Disabled)
            {
                $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightPink
            }
            else
            {
                $global:ServerButtons[$global:selectedServerID].BackColor = [System.Drawing.Color]::LightCyan
            }
            $global:selectedServerID = ""
            $SelectedLabel.Text = "Currently Selected Server: NONE" 
        }
    }
    Add-MenuButton "Exit and Start Servers" $serverAllowed { 
        ExitAndStartServers
        $script:ExitRequested = $true
        $this.FindForm().Close()
    }
    Add-MenuButton "Exit Application" $true { 
        $script:ExitRequested = $true
        $this.FindForm().Close()
    }

    $Line2 = New-Object System.Windows.Forms.Label
    $Line2.BackColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
    $Line2.Location = New-Object System.Drawing.Point(20, ($script:currentY + 5))
    $Line2.Size = New-Object System.Drawing.Size(460, 2)
    $Form.Controls.Add($Line2)
    
    $script:currentY += 15

    $SettingsHeaderLabel = New-Object System.Windows.Forms.Label
    $SettingsHeaderLabel.Text = "ACTIVE SETTINGS && CONFIGURATION"
    $SettingsHeaderLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $SettingsHeaderLabel.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    $SettingsHeaderLabel.Location = New-Object System.Drawing.Point(35, ($script:currentY))
    $SettingsHeaderLabel.Size = New-Object System.Drawing.Size(430, 20)
    $Form.Controls.Add($SettingsHeaderLabel)
    
    $script:currentY += 25

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

    # Calculate and set initial text using local variables
    $dynamicStatus = . $GetTextScript
    $btn.Text = "  $Prefix $dynamicStatus"

    # Apply rounding FIRST (Prevents handle recreation from wiping property data)
    Set-ControlRoundCorners -Control $btn -Radius 8

    # NOW safely bind metadata to the Tag property
    $btn.Tag = @{
        Prefix  = $Prefix
        GetText = $GetTextScript
        Action  = $ActionScript
    }

    # Register the Click Event (Using $this and explicit property subexpressions)
    $btn.Add_Click({
        $cfg = $this.Tag
        
        # Fire setting toggle securely
        . ($cfg.Action)
        
        # Pull updated text string back onto canvas
        $updatedStatus = . ($cfg.GetText)
        $this.Text = "  " + $cfg.Prefix + " " + $updatedStatus
    })

    # Add to Form canvas
    $Form.Controls.Add($btn)
}

    # ---------------------------------------------------------
    # Creating the 4 Settings Toggles Independently
    # ---------------------------------------------------------
# Toggle [S]
Create-ConfigButton -Prefix "Reboot Schedule:" -GetTextScript {
$scheduledTimes = @()
$rebootTimes = ""
foreach ($time in $global:ManagerConfig.scheduledTimes) {
    $scheduledTimes += $time
    $rebootTimes = $rebootTimes + $time  + " : "
}
if ($scheduledTimes.count -gt 0) { return "➡ " + ($rebootTimes -replace ' : $') } else { return "➡ No Schedule Reboot Time" }
} -ActionScript { Schedule_Server_Reboot } -YPosition $script:currentY
$script:currentY += 40

# Toggle [I]
Create-ConfigButton -Prefix "Dashboard Windows:" -GetTextScript {
if ($global:ManagerConfig.closeAllWindows -eq 0) { "➡ Leave Open After All Launched" } else { "➡ Minimize After All Launched" }
} -ActionScript {
if ($global:ManagerConfig.closeAllWindows -eq 0) { $global:ManagerConfig.closeAllWindows = 1 } else { $global:ManagerConfig.closeAllWindows = 0 }
$global:ManagerConfig | ConvertTo-Json -Depth 10 | Set-Content $ManagerConfigPath
} -YPosition $script:currentY
$script:currentY += 40

# Toggle [W]
Create-ConfigButton -Prefix "Server Windows:" -GetTextScript {
if ($global:ManagerConfig.closeServerWindows -eq 0) { "➡ Leave Server Windows Open" } else { "➡ Minimized Server Windows" }
} -ActionScript {
if ($global:ManagerConfig.closeServerWindows -eq 0) { $global:ManagerConfig.closeServerWindows = 1 } else { $global:ManagerConfig.closeServerWindows = 0 }
$global:ManagerConfig | ConvertTo-Json -Depth 10 | Set-Content $ManagerConfigPath
} -YPosition $script:currentY
$script:currentY += 40

# Toggle [T]
Create-ConfigButton -Prefix "Sandstorm Taskbar:" -GetTextScript {
if ($global:ManagerConfig.closeTaskbar -eq 0) { "➡ Leave Sandstorm Taskbar Open" } else { "➡ Minimize Sandstorm Taskbar" }
} -ActionScript {
if ($global:ManagerConfig.closeTaskbar -eq 0) { $global:ManagerConfig.closeTaskbar = 1 } else { $global:ManagerConfig.closeTaskbar = 0 }
$global:ManagerConfig | ConvertTo-Json -Depth 10 | Set-Content $ManagerConfigPath
} -YPosition $script:currentY

    # ---------------------------------------------------------
    # Render Canvas Window Frame
    # ---------------------------------------------------------
    [void]$Form.ShowDialog()

    if ($script:ExitRequested) {
        exit
    }
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

Show-Menu


