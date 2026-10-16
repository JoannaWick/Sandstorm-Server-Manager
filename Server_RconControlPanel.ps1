Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

# ==========================================
# SERVER INVENTORY LIST (DYNAMIC MATRIX)
# ==========================================
$ServerList = @()

$ServerListJsonPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ServerList.json"
$ServerListData = Get-Content $ServerListJsonPath | ConvertFrom-Json

foreach ($item in $ServerListData) 
{
    # Get each dynamic top element name and value
    foreach ($property in $item.PSObject.Properties) {
        $Server_ID = $property.Name
        $isDisabled = $property.Value.Disabled

        if(-not $isDisabled)
        {
            $logPath = Join-Path -Path $PSScriptRoot -ChildPath "InsurgencySandstorm\steamapps\common\sandstorm_server\Insurgency\Saved\Logs\$Server_ID.log"
            $configPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ServerData\$Server_ID\ServerStartup.json"
            $configData = Get-Content -Path $configPath -Raw | ConvertFrom-Json

            $ServerList += [PSCustomObject]@{ Name = $configData.HostName; IP = "127.0.0.1"; RconPort = $configData.RconListenPort; Pass = $configData.RconPassword; Path = $serverPath }
        }
    }
}

# Global runtime targets (populated automatically by the combobox selector)
$global:ServerName     = ""
$global:RconIP         = ""
$global:RconPort       = 0
$global:RconPassword   = ""
$global:RconResponse   = ""
$global:scenario       = ""
$global:travelArgument = ""
$global:restartRound   = 0

# ==========================================
# RAW TCP SOCKET RCON ENGINE (GLOBAL SCOPE)
# ==========================================
Function global:Invoke-RconCommand {
    Param(
        [Parameter(Mandatory=$true)]
        [String]$CommandString
    )
    
    if ($null -eq $global:OutputBox) { return }
    if ([String]::IsNullOrWhiteSpace($global:RconIP)) {
        $global:OutputBox.AppendText("[ERROR] No target server selected. Please choose a server from the dropdown first.`n`n")
        return
    }
    
    $LogTime = (Get-Date).ToString("HH:mm:ss")
    $global:OutputBox.AppendText("[$LogTime] Sending to [$global:RconIP`:$global:RconPort]: $CommandString`n")
    
    Function Build-RconPacket ([Int32]$PacketId, [Int32]$PacketType, [String]$Payload) {
        $PayloadBytes = [System.Text.Encoding]::ASCII.GetBytes($Payload)
        $PacketSize   = 4 + 4 + $PayloadBytes.Length + 2 
        
        $MemoryStream = [System.IO.MemoryStream]::new()
        $Writer       = [System.IO.BinaryWriter]::new($MemoryStream)
        
        $Writer.Write([Int32]$PacketSize)
        $Writer.Write([Int32]$PacketId)
        $Writer.Write([Int32]$PacketType)
        $Writer.Write($PayloadBytes)
        $Writer.Write([Byte]0) 
        $Writer.Write([Byte]0) 
        
        $Bytes = $MemoryStream.ToArray()
        $Writer.Close(); $MemoryStream.Close()
        return ,$Bytes
    }

    $TcpClient = $null
    $Stream    = $null

    try {
        $TcpClient = [System.Net.Sockets.TcpClient]::new()
        $TcpClient.Connect($global:RconIP, $global:RconPort)
        $Stream = $TcpClient.GetStream()
        $Stream.ReadTimeout  = 2000 
        $Stream.WriteTimeout = 2000
        
        $AuthPacket = Build-RconPacket -PacketId 99 -PacketType 3 -Payload $global:RconPassword
        $Stream.Write($AuthPacket, 0, $AuthPacket.Length)
        
        $ReadBuffer = [Byte[]]::new(4096)
        $BytesRead  = $Stream.Read($ReadBuffer, 0, $ReadBuffer.Length)
        
        $ResponseId   = [System.BitConverter]::ToInt32($ReadBuffer, 4)
        if ($ResponseId -eq -1) {
            $global:OutputBox.AppendText("[$LogTime] SERVER ERROR: RCON Authentication Failed.`n`n")
            return
        }
        
        $CmdPacket = Build-RconPacket -PacketId 100 -PacketType 2 -Payload $CommandString
        $Stream.Write($CmdPacket, 0, $CmdPacket.Length)
        
        Start-Sleep -Milliseconds 150 
        $BytesRead = $Stream.Read($ReadBuffer, 0, $ReadBuffer.Length)
        
        if ($BytesRead -gt 12) {
            $PayloadSize  = [System.BitConverter]::ToInt32($ReadBuffer, 0) - 10
            if ($PayloadSize -gt 0) {
                $ServerOutput = [System.Text.Encoding]::ASCII.GetString($ReadBuffer, 12, $PayloadSize).Trim()
                $global:RconResponse = $ServerOutput
            } else {
                $global:RconResponse = 1
            }
        } else {
            $global:RconResponse = 2
        }
    } catch {
        $global:RconResponse = 3
    } finally {
        if ($null -ne $Stream)    { $Stream.Close(); $Stream.Dispose() }
        if ($null -ne $TcpClient) { $TcpClient.Close(); $TcpClient.Dispose() }
    }
}

Function global:parse-RconResponse {
    Param(
        [Parameter(Mandatory=$true)]
        [String]$rconCommand,
        [string]$rconValue
    )

    $LogTime = (Get-Date).ToString("HH:mm:ss")

    if ($global:RconResponse -eq 1)
    {
        $global:OutputBox.AppendText("[$LogTime] Server executed command successfully.`n`n")
        $global:OutputBox.ScrollToEnd()
        return
    } 
    elseif ($global:RconResponse -eq 2)
    {
        $global:OutputBox.AppendText("[$LogTime] Command dispatched cleanly.`n`n")
        $global:OutputBox.ScrollToEnd()
        return
    }
    elseif ($global:RconResponse -eq 3)
    {
        $global:OutputBox.AppendText("[$LogTime] NETWORK CONNECTION ERROR: $_`n`n")
        $global:OutputBox.ScrollToEnd()
        return
    }

    if ($rconCommand -eq "listplayers")
    {
        $global:OutputBox.AppendText("[$LogTime] List of Players and Bot Count.`n")
        # Split response by newlines and skip the header and spacer
        $lines = $global:RconResponse -split "`n" | Where-Object { $_ -match '^\d' }

        if (-not ([string]::IsNullOrWhiteSpace($lines))) 
        {
            # Master Structural Regex Strategy:
            # 1. (?<ID>\d+)\s*\|\s*                              -> Pulls out player numeric ID
            # 2. (?<Name>.*?)\s*\|\s*                            -> Non-greedy capture of everything up to network marker
            # 3. (?<Network>(?:SteamNWI:|None:|WinGDK:|EOS:).*?)\s*\|\s*       -> Captures network prefix and dynamic info strings
            # 4. (?<IP>[^|]*?)\s*\|\s*                           -> Captures EVERYTHING (even space gaps) up until the final segment pipe divider
            # 5. (?<Score>\d+)\s*(?:\||$)                        -> Finishes record extraction at trailing Score digits
            $masterPattern = '(?<ID>\d+)\s*\|\s*(?<Name>.*?)\s*\|\s*(?<Network>(?:SteamNWI:|None:|WinGDK:|EOS:).*?)\s*\|\s*(?<IP>[^|]*?)\s*\|\s*(?<Score>\d+)\s*(?:\||$)'

            # Find all matching blocks safely across the text layout without breaking lines or cutting scopes
            $matchArray = @([regex]::Matches($lines, $masterPattern))
            $playerCount = 0
            $totalBotCount = 0

            for ($i = 0; $i -lt $matchArray.Count; $i++) {
                $match = $matchArray[$i]
                $rawName = $match.Groups['Name'].Value
                $playerId = [int]$match.Groups['ID'].Value

                # Filter: Skip any match groups where the ID is exactly 0
                if ($playerId -gt 0)
                {
                    $displayName    = $match.Groups['Name'].Value
                    $networkStr = $match.Groups['Network'].Value.Trim()
                    # Clean off any potential trailing commas or formatting brackets
                    $UniqueId = $networkStr -replace '[,\}\]]', ''

                    $playerIp   = $match.Groups['IP'].Value
                    $playerScore = $match.Groups['Score'].Value

                    $formattedText = "`n{0,-33} {1,-27} {2,-16} {3,-5}" -f $displayName, $UniqueId.Substring(0, 26), $playerIp, $playerScore
                    $global:OutputBox.AppendText($formattedText)
                    $playerCount += 1
                 }
                else
                {
                    $totalBotCount += 1
                }
            }

            if ($playerCount -eq 0)
            {
                $formattedText = "`n{0,-33} {1,-27} {2,-16} {3,-5}" -f "No Players", "No ID", "No IP", "0"
                $global:OutputBox.AppendText($formattedText)
            }
            $global:OutputBox.AppendText("`n`nTotal Players: $playerCount")
            $global:OutputBox.AppendText("`nTotal Bots: $totalBotCount")
            $global:OutputBox.AppendText("`n`n")
        }
        $LogTime = (Get-Date).ToString("HH:mm:ss")
        $global:OutputBox.AppendText("[$LogTime] End of Player List`n`n")
    }
    elseif ($rconCommand -eq "maps ")
    {
        if ([string]::IsNullOrEmpty($rconValue))
        {
            $mapSearch = "All"
        }
        else
        {
            $mapSearch = $rconValue
        }

        $global:OutputBox.AppendText("[$LogTime] List Server Maps matching: $mapSearch`n")

        $serverConfigDir = Join-Path -Path $global:Path -ChildPath "Insurgency\Config\server"

        if (Test-Path (Join-Path $serverConfigDir "mapcycle.txt")) {
            $mapCyclePath = Join-Path $serverConfigDir "mapcycle.txt"
        } 
        elseif (Test-Path (Join-Path $serverConfigDir "mapcycle.ini")) {
            $mapCyclePath = Join-Path $serverConfigDir "mapcycle.ini"
        } 
        else {
            Write-Warning "Neither mapcycle.txt nor mapcycle.ini was found in $serverConfigDir"
            $mapCyclePath = $null
        }

        $mapCycle = @(Get-Content $mapCyclePath) -split "`r?`n"

        $uniqueScenarios = $(foreach ($line in $mapCycle) {
            if ($line -match '^\(Scenario="([^"]+)"') {
                $Matches[1] # Returns the text captured inside the parentheses
            }
        }) | Select-Object -Unique

        $global:OutputBox.AppendText("`n")
        $uniqueScenarios | ForEach-Object {
            if ([string]::IsNullOrEmpty($rconValue) -or $_ -like "*$rconValue*") {
                $global:OutputBox.AppendText("$_`n")
            }
        }
        $global:OutputBox.AppendText("`n")
        $LogTime = (Get-Date).ToString("HH:mm:ss")
        $global:OutputBox.AppendText("[$LogTime] End of Map List`n`n")
    }
    elseif ($rconCommand -eq "scenarios ")
    {
        if ([string]::IsNullOrEmpty($rconValue))
        {
            $mapSearch = "All"
        }
        else
        {
            $mapSearch = $rconValue
        }

        $global:OutputBox.AppendText("[$LogTime] List of Server Scenarios matching: $mapSearch`n")

        $serverConfigDir = Join-Path -Path $global:Path -ChildPath "Insurgency\Config\server"

        if (Test-Path (Join-Path $serverConfigDir "mapcycle.txt")) {
            $mapCyclePath = Join-Path $serverConfigDir "mapcycle.txt"
        } 
        elseif (Test-Path (Join-Path $serverConfigDir "mapcycle.ini")) {
            $mapCyclePath = Join-Path $serverConfigDir "mapcycle.ini"
        } 
        else {
            Write-Warning "Neither mapcycle.txt nor mapcycle.ini was found in $serverConfigDir"
            $mapCyclePath = $null
        }

        $mapCycle = @(Get-Content $mapCyclePath) -split "`r?`n"
        $global:OutputBox.AppendText("`n")
        $mapCycle | ForEach-Object {
            if ([string]::IsNullOrEmpty($rconValue) -or $_ -like "*$rconValue*") {
                $global:OutputBox.AppendText("$_`n")
            }
        }
        $global:OutputBox.AppendText("`n")
        $LogTime = (Get-Date).ToString("HH:mm:ss")
        $global:OutputBox.AppendText("[$LogTime] End of Scenario List`n`n")
    }
    else
    {
        $global:OutputBox.AppendText("`n")
        $global:OutputBox.AppendText($global:RconResponse)
        $global:OutputBox.AppendText("`n`n")
        $LogTime = (Get-Date).ToString("HH:mm:ss")
        $global:OutputBox.AppendText("[$LogTime] End of $rconCommand Command`n`n")
        $global:OutputBox.AppendText("`n`n")
    }

    $global:OutputBox.ScrollToEnd()
}

function get-travelArgument
{
    # Interactive ComboBox construction
    $travelDropdown = [System.Windows.Controls.ComboBox]::new()
    $travelDropdown.Height = 26 # Slightly lower height to fit beautifully inside the 28px border container
    $travelDropdown.Foreground = [System.Windows.Media.Brushes]::Black
    $travelDropdown.BorderThickness = "0" # Remove standard sharp border
    $travelDropdown.Background = [System.Windows.Media.Brushes]::Transparent # Let container background show through
    $travelDropdown.VerticalContentAlignment = "Center"
    $travelDropdown.Padding = "8,0,0,0" # Adjust text position inside the dropdown

    # Rounded Border Container for the Dropdown
    $travelDropdownBorder = [System.Windows.Controls.Border]::new()
    $travelDropdownBorder.Height = 28 # Matches your original intended height
    $travelDropdownBorder.CornerRadius = "6" # Adjust for more/less roundness
    $travelDropdownBorder.BorderThickness = "1"
    $travelDropdownBorder.BorderBrush = [System.Windows.Media.Brushes]::LightGray
    $travelDropdownBorder.Background = [System.Windows.Media.Brushes]::WhiteSmoke # Moved background color here
    $travelDropdownBorder.Margin = "8,0,4,0"

    # Nest the ComboBox inside the Border
    $travelDropdownBorder.Child = $travelDropdown

    # Add the Border wrapper to your DockPanel instead of the raw ComboBox
    [void]$Dock.Children.Add($travelDropdownBorder)

    $travelDropdown.SelectedIndex = -1
    [void]$travelDropdown.Items.Clear()

    # Variable Injection Click Trigger Routine
    $travelDropdown.Add_SelectionChanged({
        if ($travelDropdown.SelectedIndex -ne -1) {
            $travel = $travelDropdown.SelectedItem.ToString()
        }
    }.GetNewClosure())

    return $travelArgument
}

#

function Show-TravelGUI
{
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName System.Windows.Forms

    $Window = [System.Windows.Window]::new()
    $Window.Title = "Sandstorm Travel Argument Wizard"

    # Hook into the Window's native Win32 Source Initialized event
    $Window.add_SourceInitialized({
        # Get the visual window handle (HWND)
        $helper = [System.Windows.Interop.WindowInteropHelper]::new($Window)
        $hwnd = $helper.Handle

        # Define the Windows API method signatures dynamically
        $signature = @'
    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
'@
        $type = Add-Type -MemberDefinition $signature -Name "Win32Utils" -Namespace "WPFUtils" -PassThru

        # Window Styles constants
        $GWL_STYLE = -16
        $WS_SYSMENU = 0x00080000

        # Read current window style, remove the System Menu (which hosts the X button), and re-apply
        $currentStyle = $type::GetWindowLong($hwnd, $GWL_STYLE)
        [void]$type::SetWindowLong($hwnd, $GWL_STYLE, ($currentStyle -band -bnot $WS_SYSMENU))
    })

    $Window.Width = 600
    $Window.Height = 850
    $Window.MinWidth = 400
    $Window.MinHeight = 500
    $Window.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#F8F9FA")
    $Window.Foreground = [System.Windows.Media.Brushes]::Black
    $Window.WindowStartupLocation = "CenterScreen"

    # Main Layout Grid Setup (Single Column Split Vertically)
    $MainGrid = [System.Windows.Controls.Grid]::new()
    $MainGrid.Margin = [System.Windows.Thickness]::new(20)

    # Define Rows (Header, Inputs, Console)
    $Row1 = [System.Windows.Controls.RowDefinition]::new(); $Row1.Height = [System.Windows.GridLength]::Auto
    $Row2 = [System.Windows.Controls.RowDefinition]::new(); $Row2.Height = [System.Windows.GridLength]::Auto
    $Row3 = [System.Windows.Controls.RowDefinition]::new(); $Row3.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $MainGrid.RowDefinitions.Add($Row1)
    $MainGrid.RowDefinitions.Add($Row2)
    $MainGrid.RowDefinitions.Add($Row3)

    # Header TextBlock Element
    $Header = [System.Windows.Controls.TextBlock]::new()
    $Header.Text = "Travel Map Argument Configuration"
    $Header.FontSize = 20
    $Header.FontWeight = [System.Windows.FontWeights]::Bold
    $Header.Margin = [System.Windows.Thickness]::new(0,0,0,20)
    $Header.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#333333")
    [System.Windows.Controls.Grid]::SetRow($Header, 0)
    [void]$MainGrid.Children.Add($Header)

    # Row 1: Input Stack Panel
    $InputStack = [System.Windows.Controls.StackPanel]::new()
    $InputStack.Margin = [System.Windows.Thickness]::new(0,0,0,20)
    [System.Windows.Controls.Grid]::SetRow($InputStack, 1)
    [void]$MainGrid.Children.Add($InputStack)

    # Helper function to generate clean input titles
    function New-FormLabel ($Text) {
        $Label = [System.Windows.Controls.TextBlock]::new()
        $Label.Text = $Text
        $Label.FontWeight = [System.Windows.FontWeights]::SemiBold
        $Label.Margin = [System.Windows.Thickness]::new(0,0,0,5)
        return $Label
    }

    function New-RoundedWrapper ($Control) {
        $Wrapper = [System.Windows.Controls.Border]::new()
        $Wrapper.CornerRadius = [System.Windows.CornerRadius]::new(5)
        $Wrapper.BorderThickness = [System.Windows.Thickness]::new(1)
        $Wrapper.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#CCCCCC")
        $Wrapper.Background = [System.Windows.Media.Brushes]::White
        $Wrapper.Height = 30
        $Wrapper.Margin = [System.Windows.Thickness]::new(0,0,0,15)
    
        # SAFE CHECK: Only strip native borders if the control explicitly supports these properties
        if ($Control.GetType().GetProperty("BorderThickness")) {
            $Control.BorderThickness = [System.Windows.Thickness]::new(0)
        }
        if ($Control.GetType().GetProperty("Background")) {
            $Control.Background = [System.Windows.Media.Brushes]::Transparent
        }
    
        $Control.Height = 28 # Slightly shorter to nest perfectly inside the 30px container
        $Control.VerticalContentAlignment = [System.Windows.VerticalAlignment]::Center
    
        # FIX: Use ($this.Parent) to safely reach and modify the wrapper container during events
        $Control.add_GotFocus({ 
            $this.Parent.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#007ACC") 
        })
        $Control.add_LostFocus({ 
            $this.Parent.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#CCCCCC") 
        })

        $Wrapper.Child = $Control
        return $Wrapper
    }

    # --- Build out input fields ---
    [void]$InputStack.Children.Add((New-FormLabel "Map Name (Capitalization Matters - Reverts to Farmhouse on bad Map Name):"))
    $txtMapName = [System.Windows.Controls.TextBox]::new()
    $txtMapName.Padding = [System.Windows.Thickness]::new(5,0,0,0)
    [void]$InputStack.Children.Add((New-RoundedWrapper $txtMapName))

    [void]$InputStack.Children.Add((New-FormLabel "Scenario:"))

    $cmbScenario = [System.Windows.Controls.ComboBox]::new()
    $cmbScenario.BorderThickness = [System.Windows.Thickness]::new(0)
    $cmbScenario.Background = [System.Windows.Media.Brushes]::Transparent
    $cmbScenario.Height = 28
    $cmbScenario.Padding = [System.Windows.Thickness]::new(5,0,0,0)
    $cmbScenario.VerticalContentAlignment = [System.Windows.VerticalAlignment]::Center

    # Set solid white background on the individual list items
    $scenItemStyle = [System.Windows.Style]::new([System.Windows.Controls.ComboBoxItem])
    $scenItemStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.ComboBoxItem]::BackgroundProperty, [System.Windows.Media.Brushes]::White))
    $cmbScenario.ItemContainerStyle = $scenItemStyle

    $serverConfigDir = Join-Path -Path $global:Path -ChildPath "Insurgency\Config\server"

    if (Test-Path (Join-Path $serverConfigDir "mapcycle.txt")) {
        $mapCyclePath = Join-Path $serverConfigDir "mapcycle.txt"
    } 
    elseif (Test-Path (Join-Path $serverConfigDir "mapcycle.ini")) {
        $mapCyclePath = Join-Path $serverConfigDir "mapcycle.ini"
    } 
    else {
        Write-Warning "Neither mapcycle.txt nor mapcycle.ini was found in $serverConfigDir"
        $mapCyclePath = $null
    }

    $mapCycle = @(Get-Content $mapCyclePath) -split "`r?`n"

    $uniqueScenarios = $(foreach ($line in $mapCycle) {
        if ($line -match '^\(Scenario="([^"]+)"') {
            $Matches[1] # Returns the text captured inside the parentheses
        }
    }) | Select-Object -Unique

    $global:ScenarioDropdown.SelectedIndex = -1
    [void]$cmbScenario.Items.Clear()

    $uniqueScenarios | ForEach-Object {
        [void]$cmbScenario.Items.Add($_)
    }

    # Select first item by default safely
    $cmbScenario.SelectedIndex = 0

    $cmbScenarioWrapper = [System.Windows.Controls.Border]::new()
    $cmbScenarioWrapper.CornerRadius = [System.Windows.CornerRadius]::new(5)
    $cmbScenarioWrapper.BorderThickness = [System.Windows.Thickness]::new(1)
    $cmbScenarioWrapper.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#CCCCCC")
    $cmbScenarioWrapper.Background = [System.Windows.Media.Brushes]::White
    $cmbScenarioWrapper.Height = 30
    $cmbScenarioWrapper.Margin = [System.Windows.Thickness]::new(0,0,0,15)
    $cmbScenarioWrapper.SnapsToDevicePixels = $true

    $cmbScenario.add_GotFocus({ $cmbScenarioWrapper.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#007ACC") })
    $cmbScenario.add_LostFocus({ $cmbScenarioWrapper.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#CCCCCC") })

    $cmbScenarioWrapper.Child = $cmbScenario
    [void]$InputStack.Children.Add($cmbScenarioWrapper)

    [void]$InputStack.Children.Add((New-FormLabel "Lighting (Select or type custom value):"))

    $cmbLighting = [System.Windows.Controls.ComboBox]::new()
    $cmbLighting.IsEditable = $true
    $cmbLighting.BorderThickness = [System.Windows.Thickness]::new(0)
    $cmbLighting.Background = [System.Windows.Media.Brushes]::Transparent
    $cmbLighting.Height = 28
    $cmbLighting.Padding = [System.Windows.Thickness]::new(5,0,0,0)
    $cmbLighting.VerticalContentAlignment = [System.Windows.VerticalAlignment]::Center

    # Set solid white background on the individual list items
    $lightItemStyle = [System.Windows.Style]::new([System.Windows.Controls.ComboBoxItem])
    $lightItemStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.ComboBoxItem]::BackgroundProperty, [System.Windows.Media.Brushes]::White))
    $cmbLighting.ItemContainerStyle = $lightItemStyle

    @("", "Day", "Night") | ForEach-Object { [void]$cmbLighting.Items.Add($_) }
    $cmbLighting.SelectedIndex = 0

    $cmbLightingWrapper = [System.Windows.Controls.Border]::new()
    $cmbLightingWrapper.CornerRadius = [System.Windows.CornerRadius]::new(5)
    $cmbLightingWrapper.BorderThickness = [System.Windows.Thickness]::new(1)
    $cmbLightingWrapper.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#CCCCCC")
    $cmbLightingWrapper.Background = [System.Windows.Media.Brushes]::White
    $cmbLightingWrapper.Height = 30
    $cmbLightingWrapper.Margin = [System.Windows.Thickness]::new(0,0,0,15)
    $cmbLightingWrapper.SnapsToDevicePixels = $true

    $cmbLighting.add_GotFocus({ $cmbLightingWrapper.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#007ACC") })
    $cmbLighting.add_LostFocus({ $cmbLightingWrapper.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#CCCCCC") })

    $cmbLightingWrapper.Child = $cmbLighting
    [void]$InputStack.Children.Add($cmbLightingWrapper)

    [void]$InputStack.Children.Add((New-FormLabel "Mutators (Comma separated - Validated Real Time):"))
    $txtMutators = [System.Windows.Controls.TextBox]::new()
    $txtMutators.Padding = [System.Windows.Thickness]::new(5,0,0,0)
    [void]$InputStack.Children.Add((New-RoundedWrapper $txtMutators))

    [void]$InputStack.Children.Add((New-FormLabel "Max Players (1 - 32 Players Maximum):"))
    $txtMaxPlayers = [System.Windows.Controls.TextBox]::new()
    $txtMaxPlayers.Padding = [System.Windows.Thickness]::new(5,0,0,0)
    [void]$InputStack.Children.Add((New-RoundedWrapper $txtMaxPlayers))

    [void]$InputStack.Children.Add((New-FormLabel "Game Mode Modifier (Select or type custom value):"))

    $cmbGame = [System.Windows.Controls.ComboBox]::new()
    $cmbGame.IsEditable = $true
    $cmbGame.BorderThickness = [System.Windows.Thickness]::new(0)
    $cmbGame.Background = [System.Windows.Media.Brushes]::Transparent
    $cmbGame.Height = 28
    $cmbGame.Padding = [System.Windows.Thickness]::new(5,0,0,0)
    $cmbGame.VerticalContentAlignment = [System.Windows.VerticalAlignment]::Center

    # Set solid white background on the individual list items
    $gameItemStyle = [System.Windows.Style]::new([System.Windows.Controls.ComboBoxItem])
    $gameItemStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.ComboBoxItem]::BackgroundProperty, [System.Windows.Media.Brushes]::White))
    $cmbGame.ItemContainerStyle = $gameItemStyle

    @("None", "CheckpointHardcore") | ForEach-Object { [void]$cmbGame.Items.Add($_) }
    $cmbGame.SelectedIndex = 0

    $cmbGameWrapper = [System.Windows.Controls.Border]::new()
    $cmbGameWrapper.CornerRadius = [System.Windows.CornerRadius]::new(5)
    $cmbGameWrapper.BorderThickness = [System.Windows.Thickness]::new(1)
    $cmbGameWrapper.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#CCCCCC")
    $cmbGameWrapper.Background = [System.Windows.Media.Brushes]::White
    $cmbGameWrapper.Height = 30
    $cmbGameWrapper.Margin = [System.Windows.Thickness]::new(0,0,0,15)
    $cmbGameWrapper.SnapsToDevicePixels = $true

    $cmbGame.add_GotFocus({ $cmbGameWrapper.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#007ACC") })
    $cmbGame.add_LostFocus({ $cmbGameWrapper.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#CCCCCC") })

    $cmbGameWrapper.Child = $cmbGame
    [void]$InputStack.Children.Add($cmbGameWrapper)

    # --- Button Execution Nodes (Send & Cancel) ---

    # Create a container layout grid to hold both buttons horizontally
    $ButtonContainer = [System.Windows.Controls.Primitives.UniformGrid]::new()
    $ButtonContainer.Columns = 2
    $ButtonContainer.Rows = 1
    $ButtonContainer.Height = 35
    $ButtonContainer.Width = 320 # Shared width space for both buttons
    $ButtonContainer.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center

    # --- BUTTON 1: SUBMIT ---
    $btnSubmit = [System.Windows.Controls.Button]::new()
    $btnSubmit.Content = "Send Travel Command"
    $btnSubmit.Background = [System.Windows.Media.Brushes]::Transparent
    $btnSubmit.BorderThickness = [System.Windows.Thickness]::new(0)
    $btnSubmit.Foreground = [System.Windows.Media.Brushes]::White
    $btnSubmit.FontWeight = [System.Windows.FontWeights]::Bold
    $btnSubmit.Cursor = [System.Windows.Input.Cursors]::Hand

    $btnSubmitWrapper = [System.Windows.Controls.Border]::new()
    $btnSubmitWrapper.CornerRadius = [System.Windows.CornerRadius]::new(5)
    $btnSubmitWrapper.Background = [System.Windows.Media.Brushes]::SlateGray
    $btnSubmitWrapper.Margin = [System.Windows.Thickness]::new(0,0,10,0) # Gap on the right side
    $btnSubmitWrapper.ClipToBounds = $true

    $btnSubmitWrapper.Child = $btnSubmit
    [void]$ButtonContainer.Children.Add($btnSubmitWrapper)

    # --- BUTTON 2: CANCEL ---
    $btnCancel = [System.Windows.Controls.Button]::new()
    $btnCancel.Content = "Cancel"
    $btnCancel.Background = [System.Windows.Media.Brushes]::Transparent
    $btnCancel.BorderThickness = [System.Windows.Thickness]::new(0)
    $btnCancel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#333333") # Dark text for neutral action
    $btnCancel.FontWeight = [System.Windows.FontWeights]::Bold
    $btnCancel.Cursor = [System.Windows.Input.Cursors]::Hand

    $btnCancelWrapper = [System.Windows.Controls.Border]::new()
    $btnCancelWrapper.CornerRadius = [System.Windows.CornerRadius]::new(5)
    $btnCancelWrapper.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#FCE8E6") # Light gray neutral background
    $btnCancelWrapper.Margin = [System.Windows.Thickness]::new(10,0,0,0) # Gap on the left side
    $btnCancelWrapper.ClipToBounds = $true

    $btnCancelWrapper.Child = $btnCancel
    [void]$ButtonContainer.Children.Add($btnCancelWrapper)

    # Add the dual button container assembly directly onto your form stack
    [void]$InputStack.Children.Add($ButtonContainer)

    # Row 2: Bottom Console Area Layout
    $BottomGrid = [System.Windows.Controls.Grid]::new()
    [System.Windows.Controls.Grid]::SetRow($BottomGrid, 2)

    $BottomRow1 = [System.Windows.Controls.RowDefinition]::new(); $BottomRow1.Height = [System.Windows.GridLength]::Auto
    $BottomRow2 = [System.Windows.Controls.RowDefinition]::new(); $BottomRow2.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $BottomGrid.RowDefinitions.Add($BottomRow1)
    $BottomGrid.RowDefinitions.Add($BottomRow2)

    $ConsoleLabel = [System.Windows.Controls.TextBlock]::new()
    $ConsoleLabel.Text = "Live Configuration Tracking Data String:"
    $ConsoleLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
    $ConsoleLabel.Margin = [System.Windows.Thickness]::new(0,10,0,5)
    $ConsoleLabel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#555555")
    [System.Windows.Controls.Grid]::SetRow($ConsoleLabel, 0)
    [void]$BottomGrid.Children.Add($ConsoleLabel)

    # Create the Console TextBox and strip its native borders/backgrounds
    $txtConsoleOutput = [System.Windows.Controls.TextBox]::new()
    $txtConsoleOutput.IsReadOnly = $true
    $txtConsoleOutput.Background = [System.Windows.Media.Brushes]::Transparent # Handled by wrapper
    $txtConsoleOutput.BorderThickness = [System.Windows.Thickness]::new(0)       # Removed sharp edge
    $txtConsoleOutput.Foreground = [System.Windows.Media.Brushes]::Lime
    $txtConsoleOutput.FontFamily = [System.Windows.Media.FontFamily]::new("Consolas")
    $txtConsoleOutput.FontSize = 14
    $txtConsoleOutput.AcceptsReturn = $true
    $txtConsoleOutput.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $txtConsoleOutput.Padding = [System.Windows.Thickness]::new(15)
    $txtConsoleOutput.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto

    # Create a clean Border container to handle the dark background and rounded corners
    $ConsoleWrapper = [System.Windows.Controls.Border]::new()
    $ConsoleWrapper.CornerRadius = [System.Windows.CornerRadius]::new(5) # Matches rest of application
    $ConsoleWrapper.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#1E1E1E")
    $ConsoleWrapper.ClipToBounds = $true # Essential: clips the internal scrollbar to the rounded edges

    # Attach the console to the layout row via its container wrapper
    [System.Windows.Controls.Grid]::SetRow($ConsoleWrapper, 1)
    $ConsoleWrapper.Child = $txtConsoleOutput
    [void]$BottomGrid.Children.Add($ConsoleWrapper)

    [void]$MainGrid.Children.Add($BottomGrid)
    $Window.Content = $MainGrid

    $global:travelArgument = ""

    # Real-Time Tracking Logic Data Function
    function Update-LiveConsoleOutput {
        $MapName    = if ($txtMapName.Text) { $txtMapName.Text } else { "" }
        $Scenario   = if ($cmbScenario.SelectedItem) { $cmbScenario.SelectedItem.ToString() } else { $cmbScenario.Text }
        $Lighting   = if ($cmbLighting.Text) { $cmbLighting.Text } else { if ($cmbLighting.SelectedItem) { $cmbLighting.SelectedItem.ToString() } else { "" } }
        $GameSel    = if ($cmbGame.SelectedItem) { $cmbGame.SelectedItem.ToString() } else { $cmbGame.Text }
        $Game       = if ($GameSel -eq "None") { "" } else { $GameSel }
        $Mutators   = if ($txtMutators.Text) { $txtMutators.Text } else { "" }
 
        if ($Mutators.Length -gt 0 -and $Mutators -notmatch '^[a-zA-Z0-9_-]+(?:,[a-zA-Z0-9_-]+)*$') {
            $Mutators = "Error: Spaces and Special Characters cannot be used!"
        }

       $MaxPlayers = if ($txtMaxPlayers.Text) { $txtMaxPlayers.Text } else { "" }
    
        # --- MAX PLAYERS VALIDATION LOGIC ---
        $RawMaxPlayers = if ($MaxPlayers) { $MaxPlayers.Trim() } else { "" }
        $MaxPlayers = ""
        $ValidationError = ""

        if ($RawMaxPlayers) {
            if ($RawMaxPlayers -match '^\d+$') {
                $ParsedPlayers = [int]$RawMaxPlayers

                if ($ParsedPlayers -ge 1 -and $ParsedPlayers -le 32) {
                    $MaxPlayers = $ParsedPlayers
                }
            }
        }

        $travelArgument = "travel " + $MapName + "`?Scenario=" + $Scenario
        $travelArgument = if ($Lighting) { $travelArgument + "?Lighting=$Lighting" } else { $travelArgument }
        $travelArgument = if ($Game) { $travelArgument + "?Game=$Game" } else { $travelArgument }
        $travelArgument = if ($Mutators) { $travelArgument + "?Mutators=$Mutators" } else { $travelArgument }
        $travelArgument = if ($MaxPlayers) { $travelArgument + "?MaxPlayers=$MaxPlayers" } else { $travelArgument }
        $global:travelArgument = $travelArgument
        $TrackingText = @"
1. Map Name    : $MapName
2. Scenario    : $Scenario
3. Lighting    : $Lighting
4. Mutators    : $Mutators
5. Max Players : $MaxPlayers
6. Game Mode   : $Game

[FORMATTED RCON COMMAND STRING PREVIEW]
------------------------------------------------------
$travelArgument
"@
    $txtConsoleOutput.Text = $TrackingText
}

    # Add Live Event Change Bindings
    $txtMapName.Add_TextChanged({ Update-LiveConsoleOutput })
    $txtMutators.Add_TextChanged({ Update-LiveConsoleOutput })
    $txtMaxPlayers.Add_TextChanged({ Update-LiveConsoleOutput })
    $cmbScenario.Add_SelectionChanged({ Update-LiveConsoleOutput })
    $cmbGame.Add_SelectionChanged({ Update-LiveConsoleOutput })
    $Window.Add_Loaded({
        $innerTextBox = $cmbGame.Template.FindName("PART_EditableTextBox", $cmbGame) -as [System.Windows.Controls.TextBox]
        if ($innerTextBox) { $innerTextBox.Add_TextChanged({ Update-LiveConsoleOutput }) }
        Update-LiveConsoleOutput
    })

    $cmbLighting.Add_SelectionChanged({ Update-LiveConsoleOutput })
    $Window.Add_Loaded({
        $innerTextBox = $cmbLighting.Template.FindName("PART_EditableTextBox", $cmbLighting) -as [System.Windows.Controls.TextBox]
        if ($innerTextBox) { $innerTextBox.Add_TextChanged({ Update-LiveConsoleOutput }) }
        Update-LiveConsoleOutput
    })

    # Assign actions to click loop
    $btnSubmit.Add_Click({
        if ($travelArgument -like "*Error:*" -or $travelArgument -match "^travel \?") {
            [System.Windows.Forms.MessageBox]::Show("INVALID Travel Command!!!`n`n$travelArgument", "Travel Command Failure")
            return
        }
        $Window.Close() 
    }.GetNewClosure())

    # Close the entire GUI application window when clicked
    $btnCancel.add_Click({ 
        $global:travelArgument = "Cancel"
        $Window.Close() 
    }.GetNewClosure())

    # Start application window
    $Window.ShowDialog()
}

# ==========================================
# MAIN APPLICATION GUI WINDOW (LIGHT MODE)
# ==========================================
$Window = [System.Windows.Window]::new()
$Window.Title = "Sandstorm RCON Server Control Center"
$Window.Width = 1650 # Expanded to comfortably support 3 wide columns
$Window.Height = 750
$Window.MinWidth = 1100
$Window.MinHeight = 500
$Window.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#F8F9FA")
$Window.Foreground = [System.Windows.Media.Brushes]::Black
$Window.WindowStartupLocation = "CenterScreen"

$ControlStyle = [System.Windows.Style]::new([System.Windows.Controls.Control])
$ControlStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Control]::BackgroundProperty, [System.Windows.Media.Brushes]::WhiteSmoke))
$ControlStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Control]::ForegroundProperty, [System.Windows.Media.Brushes]::Black))
$ControlStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Control]::BorderBrushProperty, [System.Windows.Media.Brushes]::LightGray))

[void]$Window.Resources.Add([System.Windows.Controls.Button], $ControlStyle)
[void]$Window.Resources.Add([System.Windows.Controls.TextBox], $ControlStyle)

# ==========================================
# SPLIT PANEL ARCHITECTURE (3-COLUMNS)
# ==========================================
$MainGrid = [System.Windows.Controls.Grid]::new()
$MainGrid.Margin = 15

# Col 0: Left Controls (400px) | Col 1: Center Console (Flexible Star) | Col 2: Right Controls (400px)
$ColLeft   = [System.Windows.Controls.ColumnDefinition]::new(); $ColLeft.Width   = [System.Windows.GridLength]::new(450)
$ColCenter = [System.Windows.Controls.ColumnDefinition]::new(); $ColCenter.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
$ColRight  = [System.Windows.Controls.ColumnDefinition]::new(); $ColRight.Width  = [System.Windows.GridLength]::new(450)

$MainGrid.ColumnDefinitions.Add($ColLeft)
$MainGrid.ColumnDefinitions.Add($ColCenter)
$MainGrid.ColumnDefinitions.Add($ColRight)
$Window.Content = $MainGrid

# --- LEFT SIDE COMMAND PANEL ---
$LeftScroll = [System.Windows.Controls.ScrollViewer]::new()
$LeftScroll.VerticalScrollBarVisibility = "Auto"
$LeftScroll.Margin = "0,0,10,0"
[System.Windows.Controls.Grid]::SetColumn($LeftScroll, 0)
[void]$MainGrid.Children.Add($LeftScroll)

$LeftPanel = [System.Windows.Controls.StackPanel]::new()
$LeftScroll.Content = $LeftPanel

# --- RIGHT SIDE COMMAND PANEL ---
$RightScroll = [System.Windows.Controls.ScrollViewer]::new()
$RightScroll.VerticalScrollBarVisibility = "Auto"
$RightScroll.Margin = "10,0,0,0"
[System.Windows.Controls.Grid]::SetColumn($RightScroll, 2)
[void]$MainGrid.Children.Add($RightScroll)

$RightPanel = [System.Windows.Controls.StackPanel]::new()
$RightScroll.Content = $RightPanel

# --- CENTER STREAM PANEL (RE-MACHINED SECTIONS) ---
$CenterPanel = [System.Windows.Controls.Grid]::new()
$CenterPanel.Margin = "10,0,10,0"
[System.Windows.Controls.Grid]::SetColumn($CenterPanel, 1)
[void]$MainGrid.Children.Add($CenterPanel)

$CenterRow1 = [System.Windows.Controls.RowDefinition]::new(); $CenterRow1.Height = [System.Windows.GridLength]::Auto # Selector
$CenterRow2 = [System.Windows.Controls.RowDefinition]::new(); $CenterRow2.Height = [System.Windows.GridLength]::Auto # Stream Label
$CenterRow3 = [System.Windows.Controls.RowDefinition]::new(); $CenterRow3.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) # Output
$CenterPanel.RowDefinitions.Add($CenterRow1)
$CenterPanel.RowDefinitions.Add($CenterRow2)
$CenterPanel.RowDefinitions.Add($CenterRow3)

# Dropdown Header layout grid row
$ServerDock = [System.Windows.Controls.DockPanel]::new()
$ServerDock.Margin = "0,0,0,10"
[System.Windows.Controls.Grid]::SetRow($ServerDock, 0)
[void]$CenterPanel.Children.Add($ServerDock)

$DropdownLabel = [System.Windows.Controls.TextBlock]::new()
$DropdownLabel.Text = "Target Host: "
$DropdownLabel.FontWeight = "Bold"
$DropdownLabel.VerticalAlignment = "Center"
$DropdownLabel.Margin = "0,0,5,0"
[System.Windows.Controls.DockPanel]::SetDock($DropdownLabel, "Left")
[void]$ServerDock.Children.Add($DropdownLabel)

# Interactive ComboBox construction
$ServerDropdown = [System.Windows.Controls.ComboBox]::new()
$ServerDropdown.Height = 26 # Slightly lower height to fit beautifully inside the 28px border container
$ServerDropdown.Foreground = [System.Windows.Media.Brushes]::Black
$ServerDropdown.BorderThickness = "0" # Remove standard sharp border
$ServerDropdown.Background = [System.Windows.Media.Brushes]::Transparent # Let container background show through
$ServerDropdown.VerticalContentAlignment = "Center"
$ServerDropdown.Padding = "4,0,0,0" # Adjust text position inside the dropdown

# Rounded Border Container for the Dropdown
$DropdownBorder = [System.Windows.Controls.Border]::new()
$DropdownBorder.Height = 28 # Matches your original intended height
$DropdownBorder.CornerRadius = "6" # Adjust for more/less roundness
$DropdownBorder.BorderThickness = "1"
$DropdownBorder.BorderBrush = [System.Windows.Media.Brushes]::LightGray
$DropdownBorder.Background = [System.Windows.Media.Brushes]::WhiteSmoke # Moved background color here

# Nest the ComboBox inside the Border
$DropdownBorder.Child = $ServerDropdown

# Add the Border wrapper to your DockPanel instead of the raw ComboBox
[void]$ServerDock.Children.Add($DropdownBorder)

# Bind Server Data to Selector
foreach ($Server in $ServerList) {
    [void]$ServerDropdown.Items.Add($Server.Name)
}

# Variable Injection Click Trigger Routine
$ServerDropdown.Add_SelectionChanged({
    $Idx = $this.SelectedIndex

    if ($Idx -ge 0) {
        $SelectedServer = $ServerList[$Idx]
        $global:RconIP       = $SelectedServer.IP
        $global:RconPort     = $SelectedServer.RconPort
        $global:RconPassword = $SelectedServer.Pass
        $global:Path         = $SelectedServer.Path
        $global:ServerName   = $SelectedServer.Name
        
        $global:OutputBox.Clear()
        $LogTime = (Get-Date).ToString("HH:mm:ss")
        $global:OutputBox.AppendText("[$LogTime] Switched Target Host -> $($SelectedServer.Name) ($($global:RconIP):$($global:RconPort))`n`n")

        $mapCyclePath = Join-Path -Path $global:Path -ChildPath "Insurgency\Config\server\mapcycle.txt"
        $mapCycle = @(Get-Content $mapCyclePath) -split "`r?`n"

        $uniqueScenarios = $(foreach ($line in $mapCycle) {
            if ($line -match '^\(Scenario="([^"]+)"') {
                $Matches[1] # Returns the text captured inside the parentheses
            }
        }) | Select-Object -Unique

        $global:ScenarioDropdown.SelectedIndex = -1
        [void]$global:ScenarioDropdown.Items.Clear()

        $uniqueScenarios | ForEach-Object {
            [void]$global:ScenarioDropdown.Items.Add($_)
        }

        # Select first item by default safely
        $global:ScenarioDropdown.SelectedIndex = 0
    }
}.GetNewClosure())

$ConsoleLabel = [System.Windows.Controls.TextBlock]::new()
$ConsoleLabel.Text = "RCON Output Stream"
$ConsoleLabel.FontWeight = "Bold"
$ConsoleLabel.Margin = "0,0,0,5"
[System.Windows.Controls.Grid]::SetRow($ConsoleLabel, 1)
[void]$CenterPanel.Children.Add($ConsoleLabel)

# Create the TextBox (remove its default border)
$global:OutputBox = [System.Windows.Controls.TextBox]::new()
$global:OutputBox.IsReadOnly = $true
$global:OutputBox.AcceptsReturn = $true
$global:OutputBox.TextWrapping = "Wrap"
$global:OutputBox.VerticalScrollBarVisibility = "Auto"
$global:OutputBox.FontFamily = "Consolas"
$global:OutputBox.BorderThickness = "0" # Hide standard sharp border
$global:OutputBox.Background = [System.Windows.Media.Brushes]::Transparent # Let container background show

# Create the Rounded Border Container
$OutputContainer = [System.Windows.Controls.Border]::new()
$OutputContainer.CornerRadius = "5" # Adjust for more/less roundness
$OutputContainer.BorderThickness = "1"
$OutputContainer.BorderBrush = [System.Windows.Media.Brushes]::LightGray
$OutputContainer.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#FFFFFF")
$OutputContainer.Padding = "5" # Padding so text doesn't touch the rounded edge
$OutputContainer.Margin = "0,10,0,0" # Optional spacing from elements above

# Nest the TextBox and add the Container to the Grid row
$OutputContainer.Child = $global:OutputBox
[System.Windows.Controls.Grid]::SetRow($OutputContainer, 2)
[void]$CenterPanel.Children.Add($OutputContainer)

# ==========================================
# COMPONENT FACTORY HOOK
# ==========================================
Function New-CommandRow {
    Param(
        [String]$ButtonText,
        [String]$CommandTemplate,
        [String[]]$ParamPlaceholders,
        [bool]$YesNoquery = $false,
        [System.Windows.Controls.StackPanel]$TargetPanel # Target specific side layout
    )
    
    $RowContainer = [System.Windows.Controls.StackPanel]::new()
    $RowContainer.Margin = "0,0,0,12"
    
    $Label = [System.Windows.Controls.TextBlock]::new()
    $Label.Text = "$ButtonText Parameters:"
    $Label.FontWeight = "SemiBold"
    $Label.Foreground = [System.Windows.Media.Brushes]::DimGray
    $Label.Margin = "0,0,0,3"
    [void]$RowContainer.Children.Add($Label)
    
    $Dock = [System.Windows.Controls.DockPanel]::new()
    $Dock.LastChildFill = $true
    
    $Btn = [System.Windows.Controls.Button]::new()
    $Btn.Content = $ButtonText
    $Btn.Width = 140
    $Btn.Height = 28
    $Btn.FontWeight = "Bold"
    [System.Windows.Controls.DockPanel]::SetDock($Btn, "Left")

    # --- DEFINE VISUAL ELEMENT FACTORIES ---
    # Create the rounded Border factory
    $borderFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.Border])
    # IMPORTANT: Give the border a Name so our trigger can specifically find and target it
    $borderFactory.Name = "ButtonBorder" 
    $borderFactory.SetValue([System.Windows.Controls.Border]::BackgroundProperty, [System.Windows.Media.Brushes]::LightGray)
    $borderFactory.SetValue([System.Windows.Controls.Border]::BorderBrushProperty, [System.Windows.Media.Brushes]::SlateGray)
    $borderFactory.SetValue([System.Windows.Controls.Border]::BorderThicknessProperty, (New-Object System.Windows.Thickness(1)))
    $borderFactory.SetValue([System.Windows.Controls.Border]::CornerRadiusProperty, (New-Object System.Windows.CornerRadius(5)))
    $borderFactory.SetValue([System.Windows.UIElement]::SnapsToDevicePixelsProperty, $true)

    # Create the ContentPresenter factory (for centered button text)
    $presenterFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.ContentPresenter])
    $presenterFactory.SetValue([System.Windows.Controls.ContentPresenter]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
    $presenterFactory.SetValue([System.Windows.Controls.ContentPresenter]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)

    # Nest text presenter inside the border
    $borderFactory.AppendChild($presenterFactory)

    # Create the ControlTemplate container
    $template = [System.Windows.Controls.ControlTemplate]::new([System.Windows.Controls.Button])
    $template.VisualTree = $borderFactory

    # --- ADD MOUSEOVER TRIGGER ---
    # Create a trigger that watches the IsMouseOver property of the Button
    $mouseOverTrigger = [System.Windows.Trigger]::new()
    $mouseOverTrigger.Property = [System.Windows.Controls.Button]::IsMouseOverProperty
    $mouseOverTrigger.Value = $true

    # Define what changes when the trigger fires (TargetName matches our border factory name)
    $hoverSetter = [System.Windows.Setter]::new()
    $hoverSetter.Property = [System.Windows.Controls.Border]::BackgroundProperty
    $hoverSetter.Value = [System.Windows.Media.Brushes]::DarkGray   # <-- Change hover background color here
    $hoverSetter.TargetName = "ButtonBorder"

    # Attach the setter rule to the trigger, and the trigger to the template
    [void]$mouseOverTrigger.Setters.Add($hoverSetter)
    [void]$template.Triggers.Add($mouseOverTrigger)

    # Apply the template to the button
    $Btn.Template = $template

    # --- ADD TO PANEL ---
    [void]$Dock.Children.Add($Btn)

    $TextBoxes = @()
    $commandString = ""
    if ($ParamPlaceholders.Count -gt 0) {
        $InputGrid = [System.Windows.Controls.Grid]::new()
        $InputGrid.Margin = "8,0,0,0"
        
        for ($i=0; $i -lt $ParamPlaceholders.Count; $i++) {
            # Ensure assembly is loaded (if not already)
            Add-Type -AssemblyName PresentationFramework

            # Your original Grid Column setup
            $ColDef = [System.Windows.Controls.ColumnDefinition]::new()
            $InputGrid.ColumnDefinitions.Add($ColDef)

            # 3. Create the TextBox (remove margin/border from it so the container handles it)
            $Box = [System.Windows.Controls.TextBox]::new()
            $Box.VerticalContentAlignment = "Center"
            $Box.Text = $ParamPlaceholders[$i]
            $Box.Foreground = [System.Windows.Media.Brushes]::Gray
            $Box.BorderThickness = "0" # Hide the default sharp text box border
            $Box.Background = [System.Windows.Media.Brushes]::Transparent # Let container background show through

            # Create the Rounded Container (Border)
            $BorderContainer = [System.Windows.Controls.Border]::new()
            $BorderContainer.CornerRadius = "5" # Adjust this value for more/less roundness
            $BorderContainer.BorderThickness = "1"
            $BorderContainer.BorderBrush = [System.Windows.Media.Brushes]::LightGray
            $BorderContainer.Background = [System.Windows.Media.Brushes]::White
            $BorderContainer.Padding = "5,2,5,2" # Inner spacing around the text box

            # Apply your margin spacing logic to the container instead of the text box
            $BorderContainer.Margin = if ($i -eq 0) { "0,0,4,0" } else { "4,0,4,0" }

            # Nest the TextBox inside the Border, and add the Border to the Grid
            $BorderContainer.Child = $Box
            [System.Windows.Controls.Grid]::SetColumn($BorderContainer, $i) # Bind to current column index
            [void]$InputGrid.Children.Add($BorderContainer)
            
            $Box.Add_GotFocus({
                if ($this.Foreground -eq [System.Windows.Media.Brushes]::Gray) {
                    $this.Text = ""
                    $this.Foreground = [System.Windows.Media.Brushes]::Black
                }
            })

            $Box.Add_LostFocus({
                param($sender, $e)
                if ([String]::IsNullOrWhiteSpace($sender.Text)) {
                    $sender.Text = $sender.Tag
                    $sender.Foreground = [System.Windows.Media.Brushes]::Gray
                }
            })

            $Box.Tag = $ParamPlaceholders[$i]
            $TextBoxes += $Box

            $Val = $ParamPlaceholders[$i]
            if ($Val.Contains(" ") -and -not $Val.StartsWith('"')) { $Val = "`"$Val`"" }
            $commandString += " " + $Val
        }

        [void]$Dock.Children.Add($InputGrid)
    } else {
        if($CommandTemplate -eq "travelscenario ")
        {
            # Interactive ComboBox construction
            $global:ScenarioDropdown = [System.Windows.Controls.ComboBox]::new()
            $global:ScenarioDropdown.Height = 26 # Slightly lower height to fit beautifully inside the 28px border container
            $global:ScenarioDropdown.Foreground = [System.Windows.Media.Brushes]::Black
            $global:ScenarioDropdown.BorderThickness = "0" # Remove standard sharp border
            $global:ScenarioDropdown.Background = [System.Windows.Media.Brushes]::Transparent # Let container background show through
            $global:ScenarioDropdown.VerticalContentAlignment = "Center"
            $global:ScenarioDropdown.Padding = "8,0,0,0" # Adjust text position inside the dropdown

            # Rounded Border Container for the Dropdown
            $ScenarioDropdownBorder = [System.Windows.Controls.Border]::new()
            $ScenarioDropdownBorder.Height = 28 # Matches your original intended height
            $ScenarioDropdownBorder.CornerRadius = "6" # Adjust for more/less roundness
            $ScenarioDropdownBorder.BorderThickness = "1"
            $ScenarioDropdownBorder.BorderBrush = [System.Windows.Media.Brushes]::LightGray
            $ScenarioDropdownBorder.Background = [System.Windows.Media.Brushes]::WhiteSmoke # Moved background color here
            $ScenarioDropdownBorder.Margin = "8,0,4,0"

            # Nest the ComboBox inside the Border
            $ScenarioDropdownBorder.Child = $global:ScenarioDropdown

            # Add the Border wrapper to your DockPanel instead of the raw ComboBox
            [void]$Dock.Children.Add($ScenarioDropdownBorder)

            # Variable Injection Click Trigger Routine
            $global:ScenarioDropdown.Add_SelectionChanged({
                if ($global:ScenarioDropdown.SelectedIndex -ne -1) {
                    $global:scenario = $global:ScenarioDropdown.SelectedItem.ToString()
                }
            }.GetNewClosure())

        }
        elseif($CommandTemplate -eq "travel ")
        {
            $Spacer = [System.Windows.Controls.TextBlock]::new()
            $Spacer.Text = " Open Travel Argument Window"
            $Spacer.FontStyle = "Italic"
            $Spacer.Foreground = [System.Windows.Media.Brushes]::DarkGray
            $Spacer.VerticalAlignment = "Center"
            $Spacer.Margin = "10,0,0,0"
            [void]$Dock.Children.Add($Spacer)
        }
        elseif($CommandTemplate -eq "restartRound ")
        {
            # Interactive ComboBox construction
            $global:restartRoundDropdown = [System.Windows.Controls.ComboBox]::new()
            $global:restartRoundDropdown.DisplayMemberPath = "DisplayText"
            $global:restartRoundDropdown.Height = 26 # Slightly lower height to fit beautifully inside the 28px border container
            $global:restartRoundDropdown.Foreground = [System.Windows.Media.Brushes]::Black
            $global:restartRoundDropdown.BorderThickness = "0" # Remove standard sharp border
            $global:restartRoundDropdown.Background = [System.Windows.Media.Brushes]::Transparent # Let container background show through
            $global:restartRoundDropdown.VerticalContentAlignment = "Center"
            $global:restartRoundDropdown.Padding = "8,0,0,0" # Adjust text position inside the dropdown

            # Rounded Border Container for the Dropdown
            $restartRoundDropdownBorder = [System.Windows.Controls.Border]::new()
            $restartRoundDropdownBorder.Height = 28 # Matches your original intended height
            $restartRoundDropdownBorder.CornerRadius = "6" # Adjust for more/less roundness
            $restartRoundDropdownBorder.BorderThickness = "1"
            $restartRoundDropdownBorder.BorderBrush = [System.Windows.Media.Brushes]::LightGray
            $restartRoundDropdownBorder.Background = [System.Windows.Media.Brushes]::WhiteSmoke # Moved background color here
            $restartRoundDropdownBorder.Margin = "8,0,4,0"

            # Nest the ComboBox inside the Border
            $restartRoundDropdownBorder.Child = $global:restartRoundDropdown

            # Add the Border wrapper to your DockPanel instead of the raw ComboBox
            [void]$Dock.Children.Add($restartRoundDropdownBorder)

            # Variable Injection Click Trigger Routine
            $global:restartRoundDropdown.Add_SelectionChanged({
                if ($global:restartRoundDropdown.SelectedIndex -ne -1) {
                    $global:restartRound = $global:restartRoundDropdown.SelectedItem.HiddenValue
                }
            }.GetNewClosure())

            $comboItem = [PSCustomObject]@{
                DisplayText = "Keep Teams"  # What the user sees
                HiddenValue = "0"   # What gets saved to $global:restartRound
            }
            [void]$global:restartRoundDropdown.Items.Add($comboItem)

            $comboItem = [PSCustomObject]@{
                DisplayText = "Swap Teams"  # What the user sees
                HiddenValue = "1"   # What gets saved to $global:restartRound
            }
            [void]$global:restartRoundDropdown.Items.Add($comboItem)

            # Select first item by default safely
            $global:restartRoundDropdown.SelectedIndex = 0

        }
        else
        {
            $Spacer = [System.Windows.Controls.TextBlock]::new()
            $Spacer.Text = " No arguments needed."
            $Spacer.FontStyle = "Italic"
            $Spacer.Foreground = [System.Windows.Media.Brushes]::DarkGray
            $Spacer.VerticalAlignment = "Center"
            $Spacer.Margin = "10,0,0,0"
            [void]$Dock.Children.Add($Spacer)
        }
    }

    $Btn.Add_Click(    {
        $FinalCommand = $CommandTemplate
        $FinalCommandCheck = $CommandTemplate + $commandString
        foreach ($TxtBox in $TextBoxes) {
            $Val = ""
            if ($TxtBox.Foreground -ne [System.Windows.Media.Brushes]::LightGray) {
                $Val = $TxtBox.Text.Trim()
            }
            if ($Val.Contains(" ") -and -not $Val.StartsWith('"')) { $Val = "`"$Val`"" }
            
           if ($FinalCommand.Contains("<placeholder>")) {
                # Ordered positional replacements
                $Index = [array]::IndexOf($TextBoxes, $TxtBox)
                if ([String]::IsNullOrEmpty($Val)) { $Val = " " }
                
                # Replace exact instances sequentially 
                $Regex = [Regex]::new("<placeholder>")
                $FinalCommand = $Regex.Replace($FinalCommand, $Val, 1)
            } else {

                $FinalCommand += " " + $Val
            }
        }
        
        # Clean double space gaps safely prior to extraction pipeline
        $FinalCommand = $FinalCommand.Trim() -replace '\s+', ' '
        $FinalCommandCheck = $FinalCommandCheck.Trim() -replace '\s+', ' '

        if ($FinalCommand -ne $FinalCommandCheck)
        {
            if ($YesNoquery)
            {
                Add-Type -AssemblyName System.Windows.Forms
                Add-Type -AssemblyName System.Drawing
                [System.Windows.Forms.Application]::EnableVisualStyles()

                # Base Dialog Form
                $msgForm = New-Object System.Windows.Forms.Form
                $msgForm.Text = "Confirmation"
                $msgForm.Size = New-Object System.Drawing.Size(360, 250)
                $msgForm.StartPosition = "CenterParent"
                $msgForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
                $msgForm.MaximizeBox = $false
                $msgForm.MinimizeBox = $false
                $msgForm.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250) # Dark Theme

                # Message Label
                $label = New-Object System.Windows.Forms.Label
                $label.Text = "$FinalCommand`n`nAre you sure you want to`nperform this Command?"
                $label.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

                $label.ForeColor = [System.Drawing.Color]::FromArgb(197, 34, 31)
                $label.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)
                $label.Location = New-Object System.Drawing.Point(25, 25)
                $label.Size = New-Object System.Drawing.Size(300, 120)
                $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
                $msgForm.Controls.Add($label)

                # Create the button
                $btnYes = New-Object System.Windows.Forms.Button
                $btnYes.Text = "Yes"
                $btnYes.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

                $btnYes.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
                $btnYes.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)
                $btnYes.Size = New-Object System.Drawing.Size(95, 35)
                $btnYes.Location = New-Object System.Drawing.Point(65, 155)
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
                $btnNo.Location = New-Object System.Drawing.Point(185, 155)
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
                    Invoke-RconCommand -CommandString $FinalCommand
                    parse-RconResponse -rconCommand $CommandTemplate
                }
                else
                {
                    $global:OutputBox.AppendText("`nAborted: $FinalCommand`n`n")
                    $global:OutputBox.ScrollToEnd()
                }
            }
            else
            {
                if($CommandTemplate -eq "maps " -or $CommandTemplate -eq "scenarios ")
                {
                    parse-RconResponse -rconCommand $CommandTemplate -rconValue $Val
                }
                else
                {
                    Invoke-RconCommand -CommandString $FinalCommand
                    parse-RconResponse -rconCommand $CommandTemplate
                }
            }
        }elseif ($FinalCommand -eq "listplayers" -or $FinalCommand -eq "listban" -or $CommandTemplate -eq "maps " -or $CommandTemplate -eq "scenarios " -or $CommandTemplate -eq "listgamemodeproperties ")
        {
            Invoke-RconCommand -CommandString $CommandTemplate
            parse-RconResponse -rconCommand $CommandTemplate
        }
        elseif($CommandTemplate -eq "travelscenario ")
        {
            $FinalCommand += " " + $global:scenario
            Invoke-RconCommand -CommandString $FinalCommand
            parse-RconResponse -rconCommand $CommandTemplate
        }
        elseif($CommandTemplate -eq "travel ")
        {
            Show-TravelGUI

            if ($global:travelArgument -ne "Cancel")
            {
                Invoke-RconCommand -CommandString $global:travelArgument
                parse-RconResponse -rconCommand $CommandTemplate
            }
            else
            {
                $LogTime = (Get-Date).ToString("HH:mm:ss")
                $global:OutputBox.AppendText("[$LogTime] Travel Canceled`n`n")
            }
        }
        elseif($CommandTemplate -eq "restartround ")
        {
            $FinalCommand += " " + $global:restartRound
            Invoke-RconCommand -CommandString $FinalCommand
            parse-RconResponse -rconCommand $CommandTemplate
        }
        elseif($CommandTemplate -eq "clearstream ")
        {
            $global:OutputBox.Clear()
            $LogTime = (Get-Date).ToString("HH:mm:ss")
            $global:OutputBox.AppendText("[$LogTime] Target Host -> $($global:ServerName) ($($global:RconIP):$($global:RconPort))`n`n")
        }

    }.GetNewClosure())
    
    [void]$RowContainer.Children.Add($Dock)
    [void]$TargetPanel.Children.Add($RowContainer)
}

#==========================================
# SPLIT DECK DISTRIBUTION MATRIX
#==========================================--- 

#LEFT SIDE CONTROLS (8 Commands) ---

New-CommandRow -TargetPanel $LeftPanel -ButtonText "List Players" -CommandTemplate "listplayers"
New-CommandRow -TargetPanel $LeftPanel -ButtonText "Kick" -CommandTemplate "kick  " -ParamPlaceholders @("id/netid/name", "[reason]") -YesNoquery $true
New-CommandRow -TargetPanel $LeftPanel -ButtonText "Ban" -CommandTemplate "ban   " -ParamPlaceholders @("id/netid/name", "duration mins", "[reason]") -YesNoquery $true
New-CommandRow -TargetPanel $LeftPanel -ButtonText "Ban ID" -CommandTemplate "banid   " -ParamPlaceholders @("netid", "duration mins", "[reason]") -YesNoquery $true
New-CommandRow -TargetPanel $LeftPanel -ButtonText "Perma Ban" -CommandTemplate "permaban  " -ParamPlaceholders @("id/netid/name", "[reason]") -YesNoquery $true
New-CommandRow -TargetPanel $LeftPanel -ButtonText "UnBan" -CommandTemplate "unban " -ParamPlaceholders @("netid") -YesNoquery $true
New-CommandRow -TargetPanel $LeftPanel -ButtonText "List Bans" -CommandTemplate "listban"
New-CommandRow -TargetPanel $LeftPanel -ButtonText "Say" -CommandTemplate "say " -ParamPlaceholders @("message")

#--- RIGHT SIDE CONTROLS (7 Commands) ---

New-CommandRow -TargetPanel $RightPanel -ButtonText "Restart Round" -CommandTemplate "restartround "
New-CommandRow -TargetPanel $RightPanel -ButtonText "List Maps" -CommandTemplate "maps " -ParamPlaceholders @("[Blank All Available Maps] or [Map filter]")
New-CommandRow -TargetPanel $RightPanel -ButtonText "List Scenarios" -CommandTemplate "scenarios " -ParamPlaceholders @("[Blank All Available Maps] or [Scenario filter]")
New-CommandRow -TargetPanel $RightPanel -ButtonText "Travel" -CommandTemplate "travel "
New-CommandRow -TargetPanel $RightPanel -ButtonText "Travel Scenario" -CommandTemplate "travelscenario "
New-CommandRow -TargetPanel $RightPanel -ButtonText "Game Mode Property" -CommandTemplate "gamemodeproperty  " -ParamPlaceholders @("property", "[new value]")
New-CommandRow -TargetPanel $RightPanel -ButtonText "List Game Mode" -CommandTemplate "listgamemodeproperties " -ParamPlaceholders @("[property filter]")
New-CommandRow -TargetPanel $RightPanel -ButtonText "Clear Output Stream" -CommandTemplate "clearstream "

# Select first item by default safely
$ServerDropdown.SelectedIndex = 0

#==========================================
# RENDER INTERACTION LAYER
#==========================================

$Window.ShowDialog() | Out-Null

