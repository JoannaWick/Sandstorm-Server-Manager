<#PSScriptInfo
.NAME Server_Taskbar
.VERSION 1.0.0
.AUTHOR Joanna Wick
.TAGS Sandstorm, Mods
.PROJECTURI https://github.com/JoannaWick/Sandstorm-Server-Manager
#>

param
(
    [string]$serverOverrideButtons
)

$Host.UI.RawUI.WindowTitle = "Server_Taskbar"

$ManagerConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ManagerConfig.json"
$ManagerConfig=Get-Content $ManagerConfigPath -Raw | ConvertFrom-Json

$closeAllWindows = $ManagerConfig.closeAllWindows
$closeServerWindows = $ManagerConfig.closeServerWindows
$closeTaskbar = $ManagerConfig.closeTaskbar


# Run the Override GUI completely in the background
$guiBlock = {
param
(
    [string]$serverOverrideButtons,
    [int]$closeAllWindows,
    [int]$closeServerWindows,
    [int]$closeTaskbar,
    [string]$thisScriptRoot
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Create main form
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.TopMost = $true 
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)

# Screen sizing
$workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Width = $workingArea.Width
$form.Height = 40
$form.Left = $workingArea.Left
$form.Top = $workingArea.Bottom - $form.Height
$form.Text = "Sandstorm_Taskbar"

# Main Layout Container
$mainBarLayout = New-Object System.Windows.Forms.Panel
$mainBarLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$form.Controls.Add($mainBarLayout)

# --- Left Brand Text ---
$brandLabel = New-Object System.Windows.Forms.Label
$brandLabel.Text = "Sandstorm Taskbar"
$brandLabel.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41) 
$brandLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$brandLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$brandLabel.AutoSize = $true
$brandLabel.Location = New-Object System.Drawing.Point(15, 10)
$brandLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Left
$mainBarLayout.Controls.Add($brandLabel)

# --- Right Container: Brand + Toggle Button (FIXED: Placed on Right) ---
$rightContainer = New-Object System.Windows.Forms.FlowLayoutPanel
$rightContainer.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
$rightContainer.Size = New-Object System.Drawing.Size(250, 40)
$rightContainer.Location = New-Object System.Drawing.Point(($form.Width - 255), 0)
$rightContainer.Anchor = [System.Windows.Forms.AnchorStyles]::Right

$toggleButton = New-Object System.Windows.Forms.Button
$toggleButton.Text = "X" # Arrow pointing into the screen margin when closing
$toggleButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$toggleButton.Size = New-Object System.Drawing.Size(30, 30)
$toggleButton.Margin = New-Object System.Windows.Forms.Padding(0, 5, 5, 0)
$toggleButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$toggleButton.FlatAppearance.BorderSize = 0
$toggleButton.Cursor = [System.Windows.Forms.Cursors]::Hand

$rightBrandLabel = New-Object System.Windows.Forms.Label
$rightBrandLabel.Text = "Sandstorm Taskbar"
$rightBrandLabel.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41) 
$rightBrandLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$rightBrandLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$rightBrandLabel.AutoSize = $true
$rightBrandLabel.Margin = New-Object System.Windows.Forms.Padding(0, 10, 10, 0)

$rightContainer.Controls.Add($toggleButton)
$rightContainer.Controls.Add($rightBrandLabel)
$mainBarLayout.Controls.Add($rightContainer)

# --- Center Layout: Button Panel ---
$centerContainer = New-Object System.Windows.Forms.Panel
$centerContainer.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainBarLayout.Controls.Add($centerContainer)

$buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$buttonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$buttonPanel.AutoSize = $true
$buttonPanel.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$buttonPanel.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)

# Mathematical formula to force horizontal centering layout logic
$buttonPanel.Add_Layout({
    param($sender, $e)
    $sender.Location = New-Object System.Drawing.Point((($centerContainer.Width - $sender.Width) / 2), 0)
})
$centerContainer.Controls.Add($buttonPanel)

# --- Toggle Logic (FIXED: Relocates to Bottom-Right Corner) ---
$toggleButton.Add_Click({
    if ($script:isExpanded) {
        # --- COLLAPSE STATE ---
        # 1. Safely remove button from its parent panel so it doesn't get destroyed
        $rightContainer.Controls.Remove($toggleButton)
        
        # 2. Hide and disconnect the main background layout
        $mainBarLayout.Visible = $false
        $form.Controls.Remove($mainBarLayout)
        
        # 3. Size and drop the toggle button cleanly directly into the main form bounds
        $toggleButton.Location = New-Object System.Drawing.Point(0, 0)
        $toggleButton.Size = New-Object System.Drawing.Size(100, 40) # Fills the 40x40 form perfectly
        $form.Controls.Add($toggleButton)
        
        # 4. Snap form down to bottom-right screen edge
        $form.Width = 100
        $form.Height = 40
        $form.Left = $workingArea.Right - 100
        $form.Top = $workingArea.Bottom - $form.Height
        
        $toggleButton.Text = "Sandstorm Taskbar" 
        $script:isExpanded = $false
    } else {
        # --- EXPAND STATE ---
        # 1. Cleanly pull button back out of the root form canvas
        $form.Controls.Remove($toggleButton)
        
        # 2. Restore full screen-width monitor geometry
        $form.Width = $workingArea.Width
        $form.Height = 40
        $form.Left = $workingArea.Left
        $form.Top = $workingArea.Bottom - $form.Height
        
        # 3. Bring layout container tree back online
        $form.Controls.Add($mainBarLayout)
        $mainBarLayout.Visible = $true
        
        # 4. Put the toggle button back into the Right-To-Left panel context
        $toggleButton.Size = New-Object System.Drawing.Size(30, 30)
        $toggleButton.Margin = New-Object System.Windows.Forms.Padding(0, 5, 5, 0)
        $rightContainer.Controls.Add($toggleButton)
        $rightContainer.Controls.SetChildIndex($toggleButton, 0) # Snap back to outer right margin edge
        
        $toggleButton.Text = "X"
        $script:isExpanded = $true
    }
})

if ($closeTaskbar -eq 0)
{
    $script:isExpanded = $true
}
else
{
        # --- COLLAPSE STATE ---
        # 1. Safely remove button from its parent panel so it doesn't get destroyed
        $rightContainer.Controls.Remove($toggleButton)
        
        # 2. Hide and disconnect the main background layout
        $mainBarLayout.Visible = $false
        $form.Controls.Remove($mainBarLayout)
        
        # 3. Size and drop the toggle button cleanly directly into the main form bounds
        $toggleButton.Location = New-Object System.Drawing.Point(0, 0)
        $toggleButton.Size = New-Object System.Drawing.Size(100, 40) # Fills the 40x40 form perfectly
        $form.Controls.Add($toggleButton)
        
        # 4. Snap form down to bottom-right screen edge
        $form.Width = 100
        $form.Height = 40
        $form.Left = $workingArea.Right - 100
        $form.Top = $workingArea.Bottom - $form.Height
        
        $toggleButton.Text = "Sandstorm Taskbar" 
        $script:isExpanded = $false
}

# --- Helper Function: Add-MenuButton ---
function Add-MenuButton ($text, $action) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $btn.Text = $text
    $btn.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)         
    $btn.BackColor = [System.Drawing.Color]::FromArgb(233, 236, 239)     
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.MinimumSize = New-Object System.Drawing.Size(90, 28)
    $btn.AutoSize = $true
    $btn.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $btn.Padding = New-Object System.Windows.Forms.Padding(8, 0, 8, 0)
    $btn.Margin = New-Object System.Windows.Forms.Padding(4, 2, 4, 2)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.Add_Click($action)
    
    $btn.Add_Paint({
        param($sender, $e)
        $width = $sender.Width
        $height = $sender.Height
        $radius = 5 
        $diameter = $radius * 2

        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
        $path.AddArc(($width - $diameter - 1), 0, $diameter, $diameter, 270, 90)
        $path.AddArc(($width - $diameter - 1), ($height - $diameter - 1), $diameter, $diameter, 0, 90)
        $path.AddArc(0, ($height - $diameter - 1), $diameter, $diameter, 90, 90)
        $path.CloseAllFigures()
    
        $sender.Region = New-Object System.Drawing.Region($path)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(206, 212, 218), 1)
        $e.Graphics.DrawPath($pen, $path)
        $pen.Dispose()
    })

    $buttonPanel.Controls.Add($btn)
}
# Helper function to dynamically add a button
function show-Menu 
{
    param (
        $ButtonList = @(),
        [string]$windowTitle
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    # Form Setup
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $windowTitle
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $form.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)

    # Layout math variables
    $spacing = 40
    $currentY = 20
    $btnHeight = 50
    $windowWidth = 450
    $centerX = ($windowWidth - 180) / 2

    # Dynamically generate buttons from the array
    foreach ($item in $ButtonList) {
        $btn = New-Object System.Windows.Forms.Button

        $btn.Location = New-Object System.Drawing.Point($centerX, $currentY)
        $btn.AutoSize = $true
        $btn.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
        $btn.MinimumSize = New-Object System.Drawing.Size(180, 33)
        $btn.Text = $item.Text
        $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

        $btn.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
        $btn.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)
        $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btn.FlatAppearance.BorderSize = 0
        $btn.Tag = $item.Action
        $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    
        # Combined action: Run the code block, then close the window
        $btn.Add_Click({
            $action = $this.Tag
            & $action
        
            $form.Close()
        })
    
        $btn.Add_Paint({
            param($sender, $e)
    
            $width = $sender.Width
            $height = $sender.Height
            $radius = 5 # Change this to make it more or less round
            $diameter = $radius * 2

            $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    
            # Construct the curved shape path
            $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
            $path.AddArc(($width - $diameter - 1), 0, $diameter, $diameter, 270, 90)
            $path.AddArc(($width - $diameter - 1), ($height - $diameter - 1), $diameter, $diameter, 0, 90)
            $path.AddArc(0, ($height - $diameter - 1), $diameter, $diameter, 90, 90)
            $path.CloseAllFigures()
    
            # Apply the mask directly to the active control region
            $sender.Region = New-Object System.Drawing.Region($path)

            $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(206, 212, 218), 1)
            $e.Graphics.DrawPath($pen, $path)
            $pen.Dispose()
        })
        $form.Controls.Add($btn)
        $currentY += $spacing
    }

    # Add the Cancel button at the bottom
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Location = New-Object System.Drawing.Point($centerX, $currentY)
    $btnCancel.AutoSize = $true
    $btnCancel.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $btnCancel.MinimumSize = New-Object System.Drawing.Size(180, 30)
    $btnCancel.Text = "Cancel"
    $btnCancel.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    $btnCancel.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)
    $btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancel.FlatAppearance.BorderSize = 0
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Add_Click({ $form.Close() })

        $btnCancel.Add_Paint({
            param($sender, $e)
    
            $width = $sender.Width
            $height = $sender.Height
            $radius = 5 # Change this to make it more or less round
            $diameter = $radius * 2

            $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    
            # Construct the curved shape path
            $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
            $path.AddArc(($width - $diameter - 1), 0, $diameter, $diameter, 270, 90)
            $path.AddArc(($width - $diameter - 1), ($height - $diameter - 1), $diameter, $diameter, 0, 90)
            $path.AddArc(0, ($height - $diameter - 1), $diameter, $diameter, 90, 90)
            $path.CloseAllFigures()
    
            # Apply the mask directly to the active control region
            $sender.Region = New-Object System.Drawing.Region($path)

            $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(206, 212, 218), 1)
            $e.Graphics.DrawPath($pen, $path)
            $pen.Dispose()
        })
    $form.Controls.Add($btnCancel)

    # Automatically scale form height based on button count
    $formHeight = $currentY + $btnHeight + 50
    $form.Size = New-Object System.Drawing.Size($windowWidth, $formHeight)
    $form.CancelButton = $btnCancel

    # Show the GUI
    [void]$form.ShowDialog()
}

$version = "1.1.0"

# About Server Manager

Add-MenuButton " About " {
    # Load the required presentation framework assembly
    Add-Type -AssemblyName PresentationFramework

    # Define the window properties
    $Title = "Sandstorm Server Launcher"
    $Message = "Script Version: $version (2026-08-20)`nAuthor: Joanna Wick (Sandy D)`n`nSandstorm Server Manager for Windows`n`nServer Manager: Create, Import and Manage multiple servers`n`nServer Launcher: Launch, Monitor and Schedule Reboot Multiple Servers`n`nServer Info Monitor: Server Dashboard for displaying all players on each server (Player Name, ID, Score and Time on Server`n`nServer Analytics: Server Anaylitics Dashboard diplaying Last 7 Days and Hourly uniquie players, Players for the last 24 Hours on all servers combined, Top 10 Players per server with most time online and Player Search`n`nRcon Dashboard: Full control of all servers through one Dashboard with all Sandstorm Rcon commands supported.  Each server's MapCycle is used for Travel and Travel Scenario commands.`n`nServer Taskbar: Easy access to all Sandstorm Server Manager Controls"
    $Buttons = [System.Windows.MessageBoxButton]::OK
    $Icon = [System.Windows.MessageBoxImage]::Information

    # Show the popup window
    [System.Windows.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
}.GetNewClosure()


# Reboot Server List

Add-MenuButton "Reboot Server" {

    $ButtonList = @()

    # --- DYNAMICALLY ADD AS MANY BUTTONS AS YOU WANT ---
    $buttonarray = $($serverOverrideButtons).Split(';')

    for ($i = 0; $i -lt $buttonarray.Count; $i += 2) 
    {
        $serverName = $buttonarray[$i]
        $serverPID = $buttonarray[$i + 1]

        $actionBlock = {
            Add-Type -AssemblyName System.Windows.Forms
            Add-Type -AssemblyName System.Drawing
            [System.Windows.Forms.Application]::EnableVisualStyles()

            # Base Dialog Form
            $msgForm = New-Object System.Windows.Forms.Form
            $msgForm.Text = "Confirmation"
            $msgForm.Size = New-Object System.Drawing.Size(360, 180)
            $msgForm.StartPosition = "CenterParent"
            $msgForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
            $msgForm.MaximizeBox = $false
            $msgForm.MinimizeBox = $false
            $msgForm.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250) # Dark Theme

            # Message Label
            $label = New-Object System.Windows.Forms.Label
            $label.Text = "Are you sure you want to Reboot: $serverName ?"
            $label.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

            $label.ForeColor = [System.Drawing.Color]::FromArgb(197, 34, 31)
            $label.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)
            $label.Location = New-Object System.Drawing.Point(25, 25)
            $label.Size = New-Object System.Drawing.Size(300, 50)
            $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $msgForm.Controls.Add($label)

            # Create the button
            $btnYes = New-Object System.Windows.Forms.Button
            $btnYes.Text = "Yes"
            $btnYes.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

            $btnYes.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
            $btnYes.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)
            $btnYes.Size = New-Object System.Drawing.Size(95, 35)
            $btnYes.Location = New-Object System.Drawing.Point(65, 85)
            $btnYes.DialogResult = [System.Windows.Forms.DialogResult]::Yes

            # CRITICAL STYLE SETTINGS: 
            # If these two lines are missing, Windows draws a sharp fallback border over the curve.
            $btnYes.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $btnYes.FlatAppearance.BorderSize = 0

            # FORCE ROUNDING VIA PAINT EVENT (Fixes the non-rounding issue)
            $btnYes.Add_Paint({
                param($sender, $e)
    
                $width = $sender.Width
                $height = $sender.Height
                $radius = 5 # Change this to make it more or less round
                $diameter = $radius * 2

                $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    
                # Construct the curved shape path
                $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
                $path.AddArc(($width - $diameter - 1), 0, $diameter, $diameter, 270, 90)
                $path.AddArc(($width - $diameter - 1), ($height - $diameter - 1), $diameter, $diameter, 0, 90)
                $path.AddArc(0, ($height - $diameter - 1), $diameter, $diameter, 90, 90)
                $path.CloseAllFigures()
    
                # Apply the mask directly to the active control region
                $sender.Region = New-Object System.Drawing.Region($path)

                $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(206, 212, 218), 1)
                $e.Graphics.DrawPath($pen, $path)
                $pen.Dispose()
            })

            $msgForm.Controls.Add($btnYes)

            # Create the button
            $btnNo = New-Object System.Windows.Forms.Button
            $btnNo.Text = "No"
            $btnNo.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

            $btnNo.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
            $btnNo.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)
            $btnNo.Size = New-Object System.Drawing.Size(95, 35)
            $btnNo.Location = New-Object System.Drawing.Point(185, 85)
            $btnNo.DialogResult = [System.Windows.Forms.DialogResult]::No

            # CRITICAL STYLE SETTINGS: 
            # If these two lines are missing, Windows draws a sharp fallback border over the curve.
            $btnNo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $btnNo.FlatAppearance.BorderSize = 0

            # FORCE ROUNDING VIA PAINT EVENT (Fixes the non-rounding issue)
            $btnNo.Add_Paint({
                param($sender, $e)
    
                $width = $sender.Width
                $height = $sender.Height
                $radius = 5 # Change this to make it more or less round
                $diameter = $radius * 2

                $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        
                # Construct the curved shape path
                $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
                $path.AddArc(($width - $diameter - 1), 0, $diameter, $diameter, 270, 90)
                $path.AddArc(($width - $diameter - 1), ($height - $diameter - 1), $diameter, $diameter, 0, 90)
                $path.AddArc(0, ($height - $diameter - 1), $diameter, $diameter, 90, 90)
                $path.CloseAllFigures()
    
                # Apply the mask directly to the active control region
                $sender.Region = New-Object System.Drawing.Region($path)

                $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(206, 212, 218), 1)
                $e.Graphics.DrawPath($pen, $path)
                $pen.Dispose()
            })

            $msgForm.Controls.Add($btnNo)

            # Assign default confirmation buttons for accessibility
            $msgForm.AcceptButton = $btnYes  # Pressing 'Enter' fires Yes
            $msgForm.CancelButton = $btnNo  # Pressing 'Escape' fires No
    
            $response = $msgForm.ShowDialog()

            if ($response -eq "Yes") {
                taskkill /f /t /pid $serverPID
                Get-Process | Where-Object { $_.MainWindowTitle -like '*$serverName*' } | Stop-Process -Force
                taskkill /fi "windowtitle eq $serverName*" /f
                Add-Type -AssemblyName System.Windows.Forms
                Add-Type -AssemblyName System.Drawing
                [System.Windows.Forms.Application]::EnableVisualStyles()

                # Create the Form
                $form = New-Object System.Windows.Forms.Form
                $form.Text = "Rebooting $serverName"
                $form.Size = New-Object System.Drawing.Size(350,150)
                $form.StartPosition = "CenterScreen"
                $form.FormBorderStyle = "FixedDialog"
                $form.MaximizeBox = $false
                $form.MinimizeBox = $false
                $form.TopMost = $true # Keeps it on top of other windows
                $form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)

                # Create the Text Label
                $label = New-Object System.Windows.Forms.Label
                $label.Location = New-Object System.Drawing.Point(20,30)
                $label.Size = New-Object System.Drawing.Size(300,50)
                $label.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

                $label.ForeColor = [System.Drawing.Color]::FromArgb(19, 115, 51)
                $label.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)
                $label.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
                $label.FlatAppearance.BorderSize = 0
                $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
                $form.Controls.Add($label)

                # Setup Countdown Timer Variables
                $script:countdown = 40
                $label.Text = "Server restarting in less than $script:countdown seconds..."

                # Create the Live Timer Object
                $timer = New-Object System.Windows.Forms.Timer
                $timer.Interval = 1000 # 1 second tick rate

                $timer.Add_Tick({
                    if ($script:countdown -gt 0) {
                        $label.Text = "Server restarting in less than $script:countdown seconds..."
                        $script:countdown--
                    } else {
                        $timer.Stop()
                        $form.Close()
                    }
                })

                # Start the timer when the window loads
                $form.Add_Load({ $timer.Start() })

                # Display the Form
                [void]$form.ShowDialog()
            }
        }.GetNewClosure()

        $ButtonList += @{ Text = $serverName;    Action = $actionBlock }
    }

    $serverName = "Reboot All Servers"

    $actionBlock = {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        [System.Windows.Forms.Application]::EnableVisualStyles()

        # Base Dialog Form
        $msgForm = New-Object System.Windows.Forms.Form
        $msgForm.Text = "Confirmation"
        $msgForm.Size = New-Object System.Drawing.Size(360, 180)
        $msgForm.StartPosition = "CenterParent"
        $msgForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $msgForm.MaximizeBox = $false
        $msgForm.MinimizeBox = $false
        $msgForm.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250) # Dark Theme

        # Message Label
        $label = New-Object System.Windows.Forms.Label
        $label.Text = "Are you sure you want to $serverName ?"
        $label.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

        $label.ForeColor = [System.Drawing.Color]::FromArgb(197, 34, 31)
        $label.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)
        $label.Location = New-Object System.Drawing.Point(25, 25)
        $label.Size = New-Object System.Drawing.Size(300, 50)
        $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $msgForm.Controls.Add($label)

        # Create the button
        $btnYes = New-Object System.Windows.Forms.Button
        $btnYes.Text = "Yes"
        $btnYes.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

        $btnYes.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
        $btnYes.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)
        $btnYes.Size = New-Object System.Drawing.Size(95, 35)
        $btnYes.Location = New-Object System.Drawing.Point(65, 85)
        $btnYes.DialogResult = [System.Windows.Forms.DialogResult]::Yes

        # CRITICAL STYLE SETTINGS: 
        # If these two lines are missing, Windows draws a sharp fallback border over the curve.
        $btnYes.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btnYes.FlatAppearance.BorderSize = 0

        # FORCE ROUNDING VIA PAINT EVENT (Fixes the non-rounding issue)
        $btnYes.Add_Paint({
            param($sender, $e)
    
            $width = $sender.Width
            $height = $sender.Height
            $radius = 5 # Change this to make it more or less round
            $diameter = $radius * 2

            $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    
            # Construct the curved shape path
            $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
            $path.AddArc(($width - $diameter - 1), 0, $diameter, $diameter, 270, 90)
            $path.AddArc(($width - $diameter - 1), ($height - $diameter - 1), $diameter, $diameter, 0, 90)
            $path.AddArc(0, ($height - $diameter - 1), $diameter, $diameter, 90, 90)
            $path.CloseAllFigures()
    
            # Apply the mask directly to the active control region
            $sender.Region = New-Object System.Drawing.Region($path)

            $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(206, 212, 218), 1)
            $e.Graphics.DrawPath($pen, $path)
            $pen.Dispose()
        })

        $msgForm.Controls.Add($btnYes)

        # Create the button
        $btnNo = New-Object System.Windows.Forms.Button
        $btnNo.Text = "No"
        $btnNo.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

        $btnNo.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
        $btnNo.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)
        $btnNo.Size = New-Object System.Drawing.Size(95, 35)
        $btnNo.Location = New-Object System.Drawing.Point(185, 85)
        $btnNo.DialogResult = [System.Windows.Forms.DialogResult]::No

        # CRITICAL STYLE SETTINGS: 
        # If these two lines are missing, Windows draws a sharp fallback border over the curve.
        $btnNo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btnNo.FlatAppearance.BorderSize = 0

        # FORCE ROUNDING VIA PAINT EVENT (Fixes the non-rounding issue)
        $btnNo.Add_Paint({
            param($sender, $e)
    
            $width = $sender.Width
            $height = $sender.Height
            $radius = 5 # Change this to make it more or less round
            $diameter = $radius * 2

            $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    
            # Construct the curved shape path
            $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
            $path.AddArc(($width - $diameter - 1), 0, $diameter, $diameter, 270, 90)
            $path.AddArc(($width - $diameter - 1), ($height - $diameter - 1), $diameter, $diameter, 0, 90)
            $path.AddArc(0, ($height - $diameter - 1), $diameter, $diameter, 90, 90)
            $path.CloseAllFigures()
    
            # Apply the mask directly to the active control region
            $sender.Region = New-Object System.Drawing.Region($path)

            $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(206, 212, 218), 1)
            $e.Graphics.DrawPath($pen, $path)
            $pen.Dispose()
        })

        $msgForm.Controls.Add($btnNo)

        # Assign default confirmation buttons for accessibility
        $msgForm.AcceptButton = $btnYes  # Pressing 'Enter' fires Yes
        $msgForm.CancelButton = $btnNo  # Pressing 'Escape' fires No
    
        $response = $msgForm.ShowDialog()

        if ($response -eq "Yes") {
            Stop-Process -Name "InsurgencyServer-Win64-Shipping" -Force
            Add-Type -AssemblyName System.Windows.Forms
            Add-Type -AssemblyName System.Drawing
            [System.Windows.Forms.Application]::EnableVisualStyles()

            # Create the Form
            $form = New-Object System.Windows.Forms.Form
            $form.Text = "Rebooting All Servers"
            $form.Size = New-Object System.Drawing.Size(350,150)
            $form.StartPosition = "CenterScreen"
            $form.FormBorderStyle = "FixedDialog"
            $form.MaximizeBox = $false
            $form.MinimizeBox = $false
            $form.TopMost = $true # Keeps it on top of other windows
            $form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)

            # Create the Text Label
            $label = New-Object System.Windows.Forms.Label
            $label.Location = New-Object System.Drawing.Point(20,30)
            $label.Size = New-Object System.Drawing.Size(300,50)
            $label.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

            $label.ForeColor = [System.Drawing.Color]::FromArgb(19, 115, 51)
            $label.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)
            $label.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $label.FlatAppearance.BorderSize = 0
            $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $form.Controls.Add($label)

            # Setup Countdown Timer Variables
            $script:countdown = 40
            $label.Text = "Servers restarting in less than $script:countdown seconds..."

            # Create the Live Timer Object
            $timer = New-Object System.Windows.Forms.Timer
            $timer.Interval = 1000 # 1 second tick rate

            $timer.Add_Tick({
                if ($script:countdown -gt 0) {
                    $label.Text = "Servers restarting in less than $script:countdown seconds..."
                    $script:countdown--
                } else {
                    $timer.Stop()
                    $form.Close()
                }
            })

            # Start the timer when the window loads
            $form.Add_Load({ $timer.Start() })

            # 5. Display the Form
            [void]$form.ShowDialog()
        }
    }.GetNewClosure()

    $ButtonList += @{ Text = $serverName;    Action = $actionBlock }

    show-Menu -ButtonList $ButtonList -windowTitle "Reboot Server List"
}

# Disable Server List

Add-MenuButton "Disable Server" {

    $ButtonList = @()

    # --- DYNAMICALLY ADD AS MANY BUTTONS AS YOU WANT ---
    $buttonarray = $($serverOverrideButtons).Split(';')

    for ($i = 0; $i -lt $buttonarray.Count; $i += 2) 
    {
        $serverName = $buttonarray[$i]
        $serverPID = $buttonarray[$i + 1]

        $actionBlock = {
            Add-Type -AssemblyName System.Windows.Forms
            Add-Type -AssemblyName System.Drawing
            [System.Windows.Forms.Application]::EnableVisualStyles()

            # Base Dialog Form
            $msgForm = New-Object System.Windows.Forms.Form
            $msgForm.Text = "Confirmation"
            $msgForm.Size = New-Object System.Drawing.Size(360, 180)
            $msgForm.StartPosition = "CenterParent"
            $msgForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
            $msgForm.MaximizeBox = $false
            $msgForm.MinimizeBox = $false
            $msgForm.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250) # Dark Theme

            # Message Label
            $label = New-Object System.Windows.Forms.Label
            $label.Text = "Are you sure you want to Disable: $serverName ?"
            $label.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

            $label.ForeColor = [System.Drawing.Color]::FromArgb(197, 34, 31)
            $label.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)
            $label.Location = New-Object System.Drawing.Point(25, 25)
            $label.Size = New-Object System.Drawing.Size(300, 50)
            $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $msgForm.Controls.Add($label)

            # Create the button
            $btnYes = New-Object System.Windows.Forms.Button
            $btnYes.Text = "Yes"
            $btnYes.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

            $btnYes.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
            $btnYes.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)
            $btnYes.Size = New-Object System.Drawing.Size(95, 35)
            $btnYes.Location = New-Object System.Drawing.Point(65, 85)
            $btnYes.DialogResult = [System.Windows.Forms.DialogResult]::Yes

            # CRITICAL STYLE SETTINGS: 
            # If these two lines are missing, Windows draws a sharp fallback border over the curve.
            $btnYes.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $btnYes.FlatAppearance.BorderSize = 0

            # FORCE ROUNDING VIA PAINT EVENT (Fixes the non-rounding issue)
            $btnYes.Add_Paint({
                param($sender, $e)
    
                $width = $sender.Width
                $height = $sender.Height
                $radius = 5 # Change this to make it more or less round
                $diameter = $radius * 2

                $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    
                # Construct the curved shape path
                $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
                $path.AddArc(($width - $diameter - 1), 0, $diameter, $diameter, 270, 90)
                $path.AddArc(($width - $diameter - 1), ($height - $diameter - 1), $diameter, $diameter, 0, 90)
                $path.AddArc(0, ($height - $diameter - 1), $diameter, $diameter, 90, 90)
                $path.CloseAllFigures()
    
                # Apply the mask directly to the active control region
                $sender.Region = New-Object System.Drawing.Region($path)

                $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(206, 212, 218), 1)
                $e.Graphics.DrawPath($pen, $path)
                $pen.Dispose()
            })

            $msgForm.Controls.Add($btnYes)

            # Create the button
            $btnNo = New-Object System.Windows.Forms.Button
            $btnNo.Text = "No"
            $btnNo.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

            $btnNo.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
            $btnNo.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)
            $btnNo.Size = New-Object System.Drawing.Size(95, 35)
            $btnNo.Location = New-Object System.Drawing.Point(185, 85)
            $btnNo.DialogResult = [System.Windows.Forms.DialogResult]::No

            # CRITICAL STYLE SETTINGS: 
            # If these two lines are missing, Windows draws a sharp fallback border over the curve.
            $btnNo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $btnNo.FlatAppearance.BorderSize = 0

            # FORCE ROUNDING VIA PAINT EVENT (Fixes the non-rounding issue)
            $btnNo.Add_Paint({
                param($sender, $e)
    
                $width = $sender.Width
                $height = $sender.Height
                $radius = 5 # Change this to make it more or less round
                $diameter = $radius * 2

                $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        
                # Construct the curved shape path
                $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
                $path.AddArc(($width - $diameter - 1), 0, $diameter, $diameter, 270, 90)
                $path.AddArc(($width - $diameter - 1), ($height - $diameter - 1), $diameter, $diameter, 0, 90)
                $path.AddArc(0, ($height - $diameter - 1), $diameter, $diameter, 90, 90)
                $path.CloseAllFigures()
    
                # Apply the mask directly to the active control region
                $sender.Region = New-Object System.Drawing.Region($path)

                $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(206, 212, 218), 1)
                $e.Graphics.DrawPath($pen, $path)
                $pen.Dispose()
            })

            $msgForm.Controls.Add($btnNo)

            # Assign default confirmation buttons for accessibility
            $msgForm.AcceptButton = $btnYes  # Pressing 'Enter' fires Yes
            $msgForm.CancelButton = $btnNo  # Pressing 'Escape' fires No
    
            $response = $msgForm.ShowDialog()

            if ($response -eq "Yes") {
                taskkill /f /t /pid $serverPID
                Get-Process | Where-Object { $_.MainWindowTitle -like '*$serverName*' } | Stop-Process -Force
                taskkill /fi "windowtitle eq $serverName*" /f

                $ServerListJsonPath = Join-Path -Path $thisScriptRoot -ChildPath "config\ServerList.json"
                $ServerListData=Get-Content $ServerListJsonPath | ConvertFrom-Json

                $isDisabled = $ServerListData.$serverName.Disabled

                if ($isDisabled)
                {
                    $isDisabled = $false
                }
                else
                {
                    $isDisabled = $true
                }

                $ServerListData.$serverName.Disabled = $isDisabled
                $ServerListData | ConvertTo-Json | Set-Content -Path $ServerListJsonPath
            }
        }.GetNewClosure()

        $ButtonList += @{ Text = $serverName;    Action = $actionBlock }
    }

    show-Menu -ButtonList $ButtonList -windowTitle "Disable Server List"
}

# Minimize InsurgencyServer-Win64-Shipping windows

if($closeServerWindows -eq 0)
{
    # Initialize the state tracking variable at the start of your script
    $global:closeServerWindows = 0
}
else
{
    # Initialize the state tracking variable at the start of your script
    $global:closeServerWindows = 1
}

Add-MenuButton "Toggle Server Windows" {
    if ($global:closeServerWindows -eq 0)
    {
        $code = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
        $type = Add-Type -MemberDefinition $code -Name "Win32ShowWindowAsync" -Namespace "Win32" -PassThru
        Get-Process -Name "InsurgencyServer-Win64-Shipping" -ErrorAction SilentlyContinue | ForEach-Object {
            $type::ShowWindowAsync($_.MainWindowHandle, 2)
        }
    }
    else
    {
        $code = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
        $type = Add-Type -MemberDefinition $code -Name "Win32ShowWindowAsync" -Namespace "Win32" -PassThru
        Get-Process -Name "InsurgencyServer-Win64-Shipping" -ErrorAction SilentlyContinue | ForEach-Object {
            $type::ShowWindowAsync($_.MainWindowHandle, 9)
        }
    }

    $global:closeServerWindows = 1 - $global:closeServerWindows
}.GetNewClosure()

# Minimize all Windows

if($closeAllWindows -ne 0)
{
    # Define the Windows API functions needed for true state detection
    $WinAPICode = @"
using System;
using System.Runtime.InteropServices;

public class WindowsAPI {
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);

    public struct POINT {
        public int X;
        public int Y;
    }

    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public struct WINDOWPLACEMENT {
        public int length;
        public int flags;
        public int showCmd;
        public POINT ptMinPosition;
        public POINT ptMaxPosition;
        public RECT rcNormalPosition;
    }
}
"@

    # Add the type if it hasn't been added in this session yet
    if (-not ([System.Management.Automation.PSTypeName]'WindowsAPI').Type) {
        Add-Type -TypeDefinition $WinAPICode
    }

    # Find the target process matching your exact window title
    $TargetProcess = Get-Process | Where-Object { $_.MainWindowTitle -eq 'Sandstorm_Multi_Server' }

    foreach ($proc in $TargetProcess) {
        $hWnd = $proc.MainWindowHandle
        if ($hWnd -eq [IntPtr]::Zero) { continue } # Skip if no window handle

        # Initialize the placement structure
        $placement = New-Object WindowsAPI+WINDOWPLACEMENT
        $placement.length = [Marshal]::SizeOf($placement)

        # Fetch the REAL state of the window from the OS
        if ([WindowsAPI]::GetWindowPlacement($hWnd, [ref]$placement)) {
        
            # showCmd values: 1 = Normal/Restored, 2 = Minimized, 3 = Maximized
            if ($placement.showCmd -eq 2) {
                # Window is CURRENTLY MINIMIZED -> Restore it (9 = SW_RESTORE)
                [WindowsAPI]::ShowWindowAsync($hWnd, 9) | Out-Null
            } else {
                # Window is CURRENTLY VISIBLE -> Minimize it (2 = SW_SHOWMINIMIZED)
                [WindowsAPI]::ShowWindowAsync($hWnd, 2) | Out-Null
            }
        }
    }

    Start-Sleep -Milliseconds 100

    # Find the target process matching your exact window title
    $TargetProcess = Get-Process | Where-Object { $_.MainWindowTitle -eq 'Multi-Server Status Dashboard (Live Updates)' }

    foreach ($proc in $TargetProcess) {
        $hWnd = $proc.MainWindowHandle
        if ($hWnd -eq [IntPtr]::Zero) { continue } # Skip if no window handle

        # Initialize the placement structure
        $placement = New-Object WindowsAPI+WINDOWPLACEMENT
        $placement.length = [Marshal]::SizeOf($placement)

        # Fetch the REAL state of the window from the OS
        if ([WindowsAPI]::GetWindowPlacement($hWnd, [ref]$placement)) {
        
            # showCmd values: 1 = Normal/Restored, 2 = Minimized, 3 = Maximized
            if ($placement.showCmd -eq 2) {
                # Window is CURRENTLY MINIMIZED -> Restore it (9 = SW_RESTORE)
                [WindowsAPI]::ShowWindowAsync($hWnd, 9) | Out-Null
            } else {
                # Window is CURRENTLY VISIBLE -> Minimize it (2 = SW_SHOWMINIMIZED)
                [WindowsAPI]::ShowWindowAsync($hWnd, 2) | Out-Null
            }
        }
    }
}

Add-MenuButton "Toggle Info Windows" {

    # Define the Windows API functions needed for true state detection
    $WinAPICode = @"
using System;
using System.Runtime.InteropServices;

public class WindowsAPI {
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);

    public struct POINT {
        public int X;
        public int Y;
    }

    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public struct WINDOWPLACEMENT {
        public int length;
        public int flags;
        public int showCmd;
        public POINT ptMinPosition;
        public POINT ptMaxPosition;
        public RECT rcNormalPosition;
    }
}
"@

    # Add the type if it hasn't been added in this session yet
    if (-not ([System.Management.Automation.PSTypeName]'WindowsAPI').Type) {
        Add-Type -TypeDefinition $WinAPICode
    }

    # Find the target process matching your exact window title
    $TargetProcess = Get-Process | Where-Object { $_.MainWindowTitle -eq 'Sandstorm_Multi_Server' }

    foreach ($proc in $TargetProcess) {
        $hWnd = $proc.MainWindowHandle
        if ($hWnd -eq [IntPtr]::Zero) { continue } # Skip if no window handle

        # Initialize the placement structure
        $placement = New-Object WindowsAPI+WINDOWPLACEMENT
        $placement.length = [Marshal]::SizeOf($placement)

        # Fetch the REAL state of the window from the OS
        if ([WindowsAPI]::GetWindowPlacement($hWnd, [ref]$placement)) {
        
            # showCmd values: 1 = Normal/Restored, 2 = Minimized, 3 = Maximized
            if ($placement.showCmd -eq 2) {
                # Window is CURRENTLY MINIMIZED -> Restore it (9 = SW_RESTORE)
                [WindowsAPI]::ShowWindowAsync($hWnd, 9) | Out-Null
            } else {
                # Window is CURRENTLY VISIBLE -> Minimize it (2 = SW_SHOWMINIMIZED)
                [WindowsAPI]::ShowWindowAsync($hWnd, 2) | Out-Null
            }
        }
    }

    Start-Sleep -Milliseconds 100

    # Find the target process matching your exact window title
    $TargetProcess = Get-Process | Where-Object { $_.MainWindowTitle -eq 'Multi-Server Status Dashboard (Live Updates)' }

    foreach ($proc in $TargetProcess) {
        $hWnd = $proc.MainWindowHandle
        if ($hWnd -eq [IntPtr]::Zero) { continue } # Skip if no window handle

        # Initialize the placement structure
        $placement = New-Object WindowsAPI+WINDOWPLACEMENT
        $placement.length = [Marshal]::SizeOf($placement)

        # Fetch the REAL state of the window from the OS
        if ([WindowsAPI]::GetWindowPlacement($hWnd, [ref]$placement)) {
        
            # showCmd values: 1 = Normal/Restored, 2 = Minimized, 3 = Maximized
            if ($placement.showCmd -eq 2) {
                # Window is CURRENTLY MINIMIZED -> Restore it (9 = SW_RESTORE)
                [WindowsAPI]::ShowWindowAsync($hWnd, 9) | Out-Null
            } else {
                # Window is CURRENTLY VISIBLE -> Minimize it (2 = SW_SHOWMINIMIZED)
                [WindowsAPI]::ShowWindowAsync($hWnd, 2) | Out-Null
            }
        }
    }
}

# Open the Server Analytics

Add-MenuButton "Server Analytics" {
    Start-Process -FilePath "cmd.exe" -ArgumentList '/c Start_Server_Analytics.bat' -WindowStyle Hidden
}.GetNewClosure()

# Open the Rcon Dashboard

Add-MenuButton "Rcon Dashboard" {
    Start-Process -FilePath "cmd.exe" -ArgumentList '/c Start_Server_RconControlPanel.bat' -WindowStyle Hidden
}.GetNewClosure()

# Open the Server Manager

Add-MenuButton "Server Manager" {
    Start-Process -FilePath "cmd.exe" -ArgumentList '/c Start_Server_Manager.bat'
}.GetNewClosure()

# Open Windows Task Manager

Add-MenuButton "Task Manager" {
    taskmgr
}.GetNewClosure()

# Stop all game servers and powershell processes

Add-MenuButton "Kill All Servers" {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    # Base Dialog Form
    $msgForm = New-Object System.Windows.Forms.Form
    $msgForm.Text = "Confirmation"
    $msgForm.Size = New-Object System.Drawing.Size(360, 180)
    $msgForm.StartPosition = "CenterScreen"
    $msgForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $msgForm.MaximizeBox = $false
    $msgForm.MinimizeBox = $false
    $msgForm.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250) # Dark Theme

    # Message Label
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Are you sure you want to Kill ALL Servers?"
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    $label.ForeColor = [System.Drawing.Color]::FromArgb(197, 34, 31)
    $label.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)
    $label.Location = New-Object System.Drawing.Point(25, 25)
    $label.Size = New-Object System.Drawing.Size(300, 50)
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $msgForm.Controls.Add($label)

    # Create the button
    $btnYes = New-Object System.Windows.Forms.Button
    $btnYes.Text = "Yes"
    $btnYes.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    $btnYes.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $btnYes.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)
    $btnYes.Size = New-Object System.Drawing.Size(95, 35)
    $btnYes.Location = New-Object System.Drawing.Point(65, 85)
    $btnYes.DialogResult = [System.Windows.Forms.DialogResult]::Yes

    # CRITICAL STYLE SETTINGS: 
    # If these two lines are missing, Windows draws a sharp fallback border over the curve.
    $btnYes.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnYes.FlatAppearance.BorderSize = 0

    # FORCE ROUNDING VIA PAINT EVENT (Fixes the non-rounding issue)
    $btnYes.Add_Paint({
        param($sender, $e)
    
        $width = $sender.Width
        $height = $sender.Height
        $radius = 5 # Change this to make it more or less round
        $diameter = $radius * 2

        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    
        # Construct the curved shape path
        $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
        $path.AddArc(($width - $diameter - 1), 0, $diameter, $diameter, 270, 90)
        $path.AddArc(($width - $diameter - 1), ($height - $diameter - 1), $diameter, $diameter, 0, 90)
        $path.AddArc(0, ($height - $diameter - 1), $diameter, $diameter, 90, 90)
        $path.CloseAllFigures()
    
        # Apply the mask directly to the active control region
        $sender.Region = New-Object System.Drawing.Region($path)

        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(206, 212, 218), 1)
        $e.Graphics.DrawPath($pen, $path)
        $pen.Dispose()
    })

    $msgForm.Controls.Add($btnYes)

    # Create the button
    $btnNo = New-Object System.Windows.Forms.Button
    $btnNo.Text = "No"
    $btnNo.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    $btnNo.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $btnNo.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)
    $btnNo.Size = New-Object System.Drawing.Size(95, 35)
    $btnNo.Location = New-Object System.Drawing.Point(185, 85)
    $btnNo.DialogResult = [System.Windows.Forms.DialogResult]::No

    # CRITICAL STYLE SETTINGS: 
    # If these two lines are missing, Windows draws a sharp fallback border over the curve.
    $btnNo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnNo.FlatAppearance.BorderSize = 0

    # FORCE ROUNDING VIA PAINT EVENT (Fixes the non-rounding issue)
    $btnNo.Add_Paint({
        param($sender, $e)
    
        $width = $sender.Width
        $height = $sender.Height
        $radius = 5 # Change this to make it more or less round
        $diameter = $radius * 2

        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    
        # Construct the curved shape path
        $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
        $path.AddArc(($width - $diameter - 1), 0, $diameter, $diameter, 270, 90)
        $path.AddArc(($width - $diameter - 1), ($height - $diameter - 1), $diameter, $diameter, 0, 90)
        $path.AddArc(0, ($height - $diameter - 1), $diameter, $diameter, 90, 90)
        $path.CloseAllFigures()
    
        # Apply the mask directly to the active control region
        $sender.Region = New-Object System.Drawing.Region($path)

        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(206, 212, 218), 1)
        $e.Graphics.DrawPath($pen, $path)
        $pen.Dispose()
    })

    $msgForm.Controls.Add($btnNo)
   
    # Assign default confirmation buttons for accessibility
    $msgForm.AcceptButton = $btnYes  # Pressing 'Enter' fires Yes
    $msgForm.CancelButton = $btnNo  # Pressing 'Escape' fires No
    
    $response = $msgForm.ShowDialog()

    if ($response -eq "Yes") {
        Stop-Process -Name "InsurgencyServer-Win64-Shipping" -Force
        Start-Sleep -Milliseconds 100
        Get-Process | Where-Object { $_.MainWindowTitle -like '*Server_Info_Monitor*' } | Stop-Process -Force
        taskkill /fi "windowtitle eq Server_Info_Monitor*" /f
        Start-Sleep -Milliseconds 100
        Get-Process | Where-Object { $_.MainWindowTitle -like '*Sandstorm_Multi_Server*' } | Stop-Process -Force
        taskkill /fi "windowtitle eq Sandstorm_Multi_Server*" /f
        Start-Sleep -Milliseconds 100
        Get-Process | Where-Object { $_.MainWindowTitle -like '*Multi-Server Status Dashboard (Live Updates)*' } | Stop-Process -Force
        taskkill /fi "windowtitle eq Multi-Server Status Dashboard (Live Updates)*" /f

        $form.close()
    }
}.GetNewClosure()

$form.Add_Shown({
    $form.Activate()
    $form.Focus()
})

[void]$form.ShowDialog((New-Object System.Windows.Forms.Form -Property @{TopMost = $true}))
}

# Fire and forget the GUI block
$rs = [RunspaceFactory]::CreateRunspace()
$rs.Open()
$ps = [PowerShell]::Create().AddScript($guiBlock)
$null = $ps.AddParameter('serverOverrideButtons', $serverOverrideButtons)
$null = $ps.AddParameter('closeAllWindows', $closeAllWindows)
$null = $ps.AddParameter('closeServerWindows', $closeServerWindows)
$null = $ps.AddParameter('closeTaskbar', $closeTaskbar)
$null = $ps.AddParameter('thisScriptRoot', $PSScriptRoot)
$ps.Runspace = $rs
$handle = $ps.BeginInvoke()

pause
