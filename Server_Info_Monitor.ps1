<#PSScriptInfo
.NAME Server_Info_Monitor
.VERSION 1.0.0
.AUTHOR Joanna Wick
.TAGS Sandstorm, Mods
.PROJECTURI https://github.com/JoannaWick/Sandstorm-Server-Manager
#>

param 
(
    $infoMonitorPosition
)

if ( $infoMonitorPosition -gt 0) 
{
    $windows_to_move = $infoMonitorPosition
}
else
{
    $windows_to_move = 3
}

$Host.UI.RawUI.WindowTitle = "Server_Info_Monitor"

# Force PowerShell 5.1 to treat internal output pipeline as UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Setup paths relative to the script location for LiteDB
$DllPath = Join-Path $PSScriptRoot "db\LiteDB.dll"
$DllPath2 = Join-Path $PSScriptRoot "db\System.Buffers.dll"
$DbFolder = Join-Path $PSScriptRoot "db"
$DbPath = Join-Path $DbFolder "PlayerLogs.db"
$DbPath = "Filename='" + $DbPath + "'; Connection=shared;"

# Place this at the very top of this ps1 file
$OnAssemblyResolve = [System.ResolveEventHandler] {
    param($sender, $e)
    $name = New-Object System.Reflection.AssemblyName($e.Name)
    
    # If ANY component asks for System.Buffers, give it the file you have regardless of requested version
    if ($name.Name -eq "System.Buffers") {
         if (Test-Path $dllPath2) {
            return [System.Reflection.Assembly]::LoadFrom($dllPath2)
        }
    }
    return $null
}
[System.AppDomain]::CurrentDomain.add_AssemblyResolve($OnAssemblyResolve)

# Now load the System.Buffers.dll assembly safely
Add-Type -Path $DllPath2
# 4. Load the LiteDB Assembly
Add-Type -Path $DllPath

# Define all the servers you want to poll. 
# Copy and paste an entire [PSCustomObject] block to add another server.
$Servers = @(
)

$ServerLogs = @{}

$ServerListJsonPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ServerList.json"

$ServerListData=Get-Content $ServerListJsonPath | ConvertFrom-Json


foreach ($item in $ServerListData) {

    # Get each dynamic top element name and value
    foreach ($property in $item.PSObject.Properties) {
        $Server_ID = $property.Name
        $isDisabled = $property.Value.Disabled

        if(-not $isDisabled)
        {
            $logPath = Join-Path -Path $PSScriptRoot -ChildPath "InsurgencySandstorm\steamapps\common\sandstorm_server\Insurgency\Saved\Logs\$Server_ID.log"
            $configPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ServerData\$Server_ID\ServerStartup.json"
            $configData = Get-Content -Path $configPath -Raw | ConvertFrom-Json

            $Servers += [PSCustomObject]@{ 
                Name = $Server_ID
                Ip = "127.0.0.1"
                RconPort = $configData.RconListenPort
                QueryPort = $configData.QueryPort
                Pass = $configData.RconPassword
                Client = $null; Stream = $null; Active = $false 
            }

            $ServerLogs[$Server_ID] = [PSCustomObject]@{ 
                logPath = $logPath
                StreamReader = $null; FileStream = $null; logActive = $false 
            }
        }
    }
}
 
# Load required assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class Win32Console {
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    // FIX FOR WINDOWS 11 WINDOW OFFSET: Gets real visible window bounds ignoring invisible border/shadow padding
    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);
}

public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}
"@

# 1. Resilient Window Handle Locator Engine (Works in Console, Terminal, ISE, & VSCode)
$hwnd = [IntPtr]::Zero

# Attempt 1: Standard process tracking
$hwnd = (Get-Process -Id $PID).MainWindowHandle

# Attempt 2: Window Title Matching Fallback (Crucial for deep Windows Terminal/Tabs architectures)
if ($hwnd -eq [IntPtr]::Zero) {
    $OriginalTitle = $Host.UI.RawUI.WindowTitle
    $UniqueGuid = [Guid]::NewGuid().ToString()
    
    # Temporarily rename window to find it uniquely
    $Host.UI.RawUI.WindowTitle = $UniqueGuid
    Start-Sleep -Milliseconds 50 # Let the OS update the window frame
    
    # Look up the process owning this specific title
    $TerminalProcess = Get-Process | Where-Object { $_.MainWindowTitle -eq $UniqueGuid }
    if ($TerminalProcess) {
        $hwnd = $TerminalProcess.MainWindowHandle
    }
    
    # Restore original title
    $Host.UI.RawUI.WindowTitle = $OriginalTitle
}

# Attempt 3: Parent Process Tree Crawl (If running inside a sub-shell or nested runner)
if ($hwnd -eq [IntPtr]::Zero) {
    try {
        $CurrentProcess = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $PID"
        if ($CurrentProcess -and $CurrentProcess.ParentProcessId) {
            $hwnd = (Get-Process -Id $CurrentProcess.ParentProcessId).MainWindowHandle
        }
    } catch {}
}

# Step 2: Validate and extract dimensions
if ($hwnd -ne [IntPtr]::Zero) {
    $rect = New-Object RECT
    
    # Try getting modern visible bounds first (DWMWA_EXTENDED_FRAME_BOUNDS = 9)
    if (([Win32Console]::DwmGetWindowAttribute($hwnd, 9, [ref]$rect, 16) -ne 0) -and !([Win32Console]::GetWindowRect($hwnd, [ref]$rect))) {
        Write-Error "Failed to fetch terminal window coordinates."
        pause
        return
    }

    # Calculate dimensions
    $ConsoleWidth  = $rect.Right - $rect.Left
    $ConsoleHeight = $rect.Bottom - $rect.Top
} else {
    # Ultimate fail-safe: If completely headless, default to a safe standard center-screen size
    Write-Warning "Running in an environment without a direct window handle (e.g. VS Code / ISE). Defaulting to fallback sizes."
    $ConsoleWidth  = 800
    $ConsoleHeight = 600
    $rect = New-Object RECT
    $rect.Left = [System.Windows.SystemParameters]::PrimaryScreenWidth / 2 - 400
    $rect.Top  = [System.Windows.SystemParameters]::PrimaryScreenHeight / 2 - 300
}


# --- SOURCE QUERY (UDP A2S_INFO) FUNCTIONS ---
function Get-ServerInfo {
    param($Ip, $QueryPort)
    # --- CONFIGURATION ---
    $TimeoutMs  = 2000            # Time to wait for a response in milliseconds

    while ($true) {
        # --- BUILD THE A2S_INFO PACKET ---
        # Header: 4 bytes of 0xFF (indicated by -1) followed by the 'T' character (0x54)
        # Payload: The string "Source Engine Query" followed by a null byte (0x00)
        $packetHeader = @(0xFF, 0xFF, 0xFF, 0xFF, 0x54)
        $packetString = [System.Text.Encoding]::ASCII.GetBytes("Source Engine Query")
        $packetFooter = @(0x00)
        $requestBytes = $packetHeader + $packetString + $packetFooter

        # --- SEND THE REQUEST OVER UDP ---
        $udpClient = New-Object System.Net.Sockets.UdpClient
        $udpClient.Client.ReceiveTimeout = $TimeoutMs

        try {
            # Connect and send packet
            $udpClient.Connect($Ip, $QueryPort)
            [void]$udpClient.Send($requestBytes, $requestBytes.Length)

            # Set up endpoint tracking object to receive data back
            $remoteEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
            $responseBytes  = $udpClient.Receive([ref]$remoteEndpoint)

            # --- PARSE THE BYTE STREAM ---
            # Stream cursor (skip past the initial 4-byte header and the 1-byte payload indicator)
            $cursor = 4 

            # Helper function to read null-terminated strings from the byte array
            function Read-NullTerminatedString([byte[]]$bytes, [ref]$idx) {
                $start = $idx.Value
                while ($bytes[$idx.Value] -ne 0 -and $idx.Value -lt $bytes.Length) { $idx.Value++ }
                $str = [System.Text.Encoding]::UTF8.GetString($bytes, $start, ($idx.Value - $start))
                $idx.Value++ # Skip past the null byte
                return $str
            }
            
            # Read the data strings sequentially from the byte response
            $Protocol   = $responseBytes[$cursor++]; $cursor++ # Protocol byte + Type byte (0x49)
            $ServerName = Read-NullTerminatedString $responseBytes ([ref]$cursor)
            $MapName    = Read-NullTerminatedString $responseBytes ([ref]$cursor)
            $Folder     = Read-NullTerminatedString $responseBytes ([ref]$cursor)
            $GameMode   = Read-NullTerminatedString $responseBytes ([ref]$cursor)

            # Read remaining numerical bytes
            $AppID       = [System.BitConverter]::ToInt16($responseBytes, $cursor); $cursor += 2
            $PlayerCount = $responseBytes[$cursor++]
            $MaxPlayers  = $responseBytes[$cursor++]
            $BotCount    = $responseBytes[$cursor++]

            return [PSCustomObject]@{
                ServerName  = $ServerName
                MapName     = $MapName
                PlayerCount = $MaxPlayers
            }
        } catch {
            $udpClient.Close()
            return $null
        } finally {
            # Close socket and clean up memory
            $udpClient.Close()
        }
    }
}

# --- RCON (TCP) FUNCTIONS ---
function Send-RconPacket {
    param($Stream, $RequestId, $Type, $Body)
    $BodyBytes = [System.Text.Encoding]::ASCII.GetBytes($Body)
    $NullByte  = [byte]0x00
    
    $PacketSize = 4 + 4 + $BodyBytes.Length + 1 + 1
    $SizeBytes  = [System.BitConverter]::GetBytes($PacketSize)
    $IdBytes    = [System.BitConverter]::GetBytes($RequestId)
    $TypeBytes  = [System.BitConverter]::GetBytes($Type)
    
    $Packet = $SizeBytes + $IdBytes + $TypeBytes + $BodyBytes + $NullByte + $NullByte
    $Stream.Write($Packet, 0, $Packet.Length)
    $Stream.Flush()
}

function Read-RconPacket {
    param($Stream)
    $SizeBuf = New-Object byte[] 4
    $Read = $Stream.Read($SizeBuf, 0, 4)
    if ($Read -lt 4) { return $null }
    
    $PacketSize = [System.BitConverter]::ToInt32($SizeBuf, 0)
    $RestBuf = New-Object byte[] $PacketSize
    $ReadTotal = 0
    
    while ($ReadTotal -lt $PacketSize) {
        $ReadTotal += $Stream.Read($RestBuf, $ReadTotal, ($PacketSize - $ReadTotal))
    }
    
    return [PSCustomObject]@{
        Id   = [System.BitConverter]::ToInt32($RestBuf, 0)
        Type = [System.BitConverter]::ToInt32($RestBuf, 4)
        Body = [System.Text.Encoding]::ASCII.GetString($RestBuf, 8, $PacketSize - 10)
    }
}

function Close-ServerConnection {
    param($Server)

    if ($Server.Stream) { try { $Server.Stream.Close() } catch {} ; $Server.Stream = $null }
    if ($Server.Client) { try { $Server.Client.Close() } catch {} ; $Server.Client = $null }

    if ($ServerLogs[$server.Name].StreamReader) { try { $ServerLogs[$server.Name].StreamReader.Close() } catch {} ; $ServerLogs[$server.Name].StreamReader = $null }
    if ($ServerLogs[$server.Name].FileStream) { try { $ServerLogs[$server.Name].FileStream.Close() } catch {} ; $ServerLogs[$server.Name].FileStream = $null }

    $Server.Active = $false
    $ServerLogs[$server.Name].logActive = $false
}

function Connect-Server {
    param($Server)

    Close-ServerConnection -Server $Server
    try {
        Write-Host "Connecting to RCON: $($Server.Name) ($($Server.Ip):$($Server.RconPort))..." -ForegroundColor Yellow
        $Server.Client = New-Object System.Net.Sockets.TcpClient
        $ConnectTask = $Server.Client.ConnectAsync($Server.Ip, $Server.RconPort)
        if (-not $ConnectTask.Wait(3000)) { throw "RCON Connection timed out." }
        
        $Server.Stream = $Server.Client.GetStream()
        Send-RconPacket -Stream $Server.Stream -RequestId 1 -Type 3 -Body $Server.Pass
        $AuthResp = Read-RconPacket -Stream $Server.Stream
        
        if ($AuthResp -eq $null -or $AuthResp.Id -eq -1) {
            Write-Warning "[$($Server.Name)] RCON Authentication failed!"
            Close-ServerConnection -Server $Server
        } else {
            Write-Host "[$($Server.Name)] RCON Authenticated successfully!" -ForegroundColor Green
            $Server.Active = $true
        }
    }
    catch {
        Write-Warning "[$($Server.Name)] RCON Connection failed: $_"
        Close-ServerConnection -Server $Server
    }

    $ServerLogs[$server.Name].FileStream = [System.IO.File]::Open($ServerLogs[$server.Name].logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $ServerLogs[$server.Name].StreamReader = [System.IO.StreamReader]::New($ServerLogs[$server.Name].FileStream)

    $ServerLogs[$server.Name].logActive = $true
}

# Persistant Player Logs
function Add-PlayerSessionLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object]$Database,
        [Parameter(Mandatory = $true)] [hashtable]$SessionData,
        [Parameter(Mandatory = $false)] [string]$CollectionName = "PlayerLogs"
    )
    process {
        try {
            # Get the collection from the open database connection
            $col = $Database.GetCollection($CollectionName)

            if (-not $SessionData.ContainsKey('NetworkID') -or [string]::IsNullOrWhiteSpace($SessionData.NetworkID)) {
                throw "NetworkID required to log a player session."
            }

            # Check if a document with the exact same LastPlayed date exists
            # If checking per player, use: "$.PlayerId = @0 AND $.LastPlayed = @1"
            $exists = $col.Exists("$.LastPlayed = @0", [LiteDB.BsonValue]::new($SessionData.LastPlayed))

            # Insert only if no match is found
            if (-not $exists) {
    
                # Clone data so we don't mutate your runtime script variables
                $record = $SessionData.Clone()

                # CRITICAL CHANGE: Generate a completely unique tracking ID for this session.
                # This allows multiple entries for the same player instead of overwriting them.
                $record["_id"] = [LiteDB.ObjectId]::NewObjectId()

                # Map the hashtable to a LiteDB BsonDocument
                $bsonDoc = [LiteDB.BsonMapper]::Global.ToDocument($record)
            
                # Insert the new log entry into the history
                [void]$col.Insert([LiteDB.BsonDocument]$bsonDoc)
            
                return [PSCustomObject]@{
                    SessionID = $record["_id"].ToString()
                    Name      = $record.Name
                    Success   = $true
                }
            } 
        }
        catch {
            Write-Error "Failed to append log for $($SessionData.NetworkID): $_"
            return [PSCustomObject]@{ Success = $false }
        }
    }
}

# 3. XAML LAYOUT WITH SCALING (Windows 10 & 11 Compliant)
$inputXAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Multi-Server Status Dashboard (Live Updates)" Height="1000" Width="1024" MinWidth="250" MinHeight="150">
    <!-- Viewbox Uniform stretch preserves layout ratios perfectly without warping text -->
    <Viewbox Stretch="Fill" StretchDirection="Both">
        <!-- Removed hardcoded Grid Width to allow fluid layout scaling -->
        <Grid Margin="15">
            <ItemsControl Name="ServerItemsControl" Grid.Row="0">
                <ItemsControl.ItemsPanel>
                    <ItemsPanelTemplate>
                        <StackPanel Orientation="Vertical"/>
                    </ItemsPanelTemplate>
                </ItemsControl.ItemsPanel>
                <ItemsControl.ItemTemplate>
                    <DataTemplate>
                        <Border BorderBrush="#DDDDDD" BorderThickness="1" CornerRadius="4" Padding="10" Margin="0,0,0,10" Background="#F9F9F9">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>

                                <!-- Server Name -->
                                <StackPanel Grid.Row="0" HorizontalAlignment="Center" Margin="0,0,0,5">
                                    <TextBlock Text="{Binding ServerName}" HorizontalAlignment="Center" FontWeight="Bold" FontSize="28" TextWrapping="Wrap"/>
                                </StackPanel>

                                <!-- Map Name -->
                                <StackPanel Grid.Row="1" HorizontalAlignment="Center" Margin="0,5,0,5">
                                    <TextBlock Text="{Binding MapName}" HorizontalAlignment="Center" FontSize="28" FontWeight="SemiBold" Foreground="#0056b3" TextWrapping="Wrap"/>
                                </StackPanel>

                                <!-- Player List Header & Rows with Proportional Grid Layout -->
                                <StackPanel Grid.Row="2" Margin="0,5,0,0">
                                    <!-- Structured Column Header -->
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="4.38*"/>
                                            <ColumnDefinition Width="3.6*"/>
                                            <ColumnDefinition Width="2*"/>
                                            <ColumnDefinition Width="1*"/>
                                            <ColumnDefinition Width="1*"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="PLAYER" FontFamily="Consolas" FontSize="24" Foreground="Gray" FontWeight="Bold"/>
                                        <TextBlock Grid.Column="1" Text="ID" FontFamily="Consolas" FontSize="24" Foreground="Gray" FontWeight="Bold"/>
                                        <TextBlock Grid.Column="2" Text="IP ADDRESS" FontFamily="Consolas" FontSize="24" Foreground="Gray" FontWeight="Bold"/>
                                        <TextBlock Grid.Column="3" Text=" SCORE" FontFamily="Consolas" FontSize="24" Foreground="Gray" FontWeight="Bold"/>
                                        <TextBlock Grid.Column="4" Text="ONLINE" FontFamily="Consolas" FontSize="24" Foreground="Gray" FontWeight="Bold"/>
                                    </Grid>
                                    
                                    <!-- Dynamic Items Binding Container -->
                                    <ItemsControl ItemsSource="{Binding Players}">
                                        <ItemsControl.ItemTemplate>
                                            <DataTemplate>
                                                <!-- Each player item string can be structured inside this matching row grid if bound to properties, 
                                                     or left as a fallback TextBlock. Preserving your current template look below: -->
                                                <TextBlock Text="{Binding}" FontFamily="Cascadia Mono, Consolas, Segoe UI Emoji" FontSize="26" Foreground="#333333"/>
                                            </DataTemplate>
                                        </ItemsControl.ItemTemplate>
                                    </ItemsControl>
                                </StackPanel>
                            </Grid>
                        </Border>
                    </DataTemplate>
                </ItemsControl.ItemTemplate>
            </ItemsControl>
        </Grid>
    </Viewbox>
</Window>
"@

# PARSE XAML SAFELY
# Cleanses any compiler-breaking namespaces and ignores system artifacts
$inputXAML = $inputXAML -replace 'x:Name', 'Name'
$inputXAML = $inputXAML -replace '^<span.*?</span>$', ''
[xml]$xaml = $inputXAML
$reader = New-Object System.Xml.XmlNodeReader $xaml

try {
    $window = [Windows.Markup.XamlReader]::Load($reader)
} catch {
    Write-Error "Failed to load XAML layout engine: $_"
    return
}

# Find named framework elements
$itemsControl = $window.FindName("ServerItemsControl")

# Create a live tracking collection and bind it
$data = New-Object System.Collections.ObjectModel.ObservableCollection[psobject]
$itemsControl.ItemsSource = $data

# Initialize the global ordered hashtable
$ServerIdleTime = [ordered]@{ }
$LiveConnections = @{}
$PendingConnectionSig = @{}
$DisconnectedPlayerList = @{}

# Initial Connection Pass
foreach ($Server in $Servers) { 
    $startTime = [DateTime]::Now
    $ServerIdleTime[$server.Name] = $startTime

    $dataelement = [PSCustomObject]@{
        ServerName = $Server.Name
        MapName    = "No Map"
        Players    = @(("{0,-33} {1,-27} {2,-16} {3,-5} {4,8}" -f "No Players", "No ID", "No IP", "0", "00:00:00"))
    }
    $data.Add($dataelement)

    $LiveConnections[$server.Name] = @{}
    $DisconnectedPlayerList[$server.Name] = @{}

    Connect-Server -Server $Server
}

$ManagerConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ManagerConfig.json"
$ManagerConfig=Get-Content $ManagerConfigPath -Raw | ConvertFrom-Json

$scheduledTimes = @()
foreach ($time in $ManagerConfig.scheduledTimes) { 
    $scheduledTimes += $time
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

Add-Type -AssemblyName System.Windows.Forms
$workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

# Extract clean area spacing bounds
$targetWidth  = $WorkingArea.Width
$targetHeight = $WorkingArea.Height - 40

# Math calculation engine for grid layout
$Cols       = [Math]::Ceiling([Math]::Sqrt($windows_to_move))
$Rows       = [Math]::Ceiling($windows_to_move / $Cols)
$TileWidth  = [Math]::Floor($targetWidth / $Cols)
$TileHeight = [Math]::Floor($targetHeight / $Rows)
$row = 0
$col = 1 % $Cols

$xPos = $col * $TileWidth
$yPos = $row * $TileHeight

# Apply positioning constraints to match the console layout
$window.Left   = $xPos
$window.Top    = $yPos
$window.Width  = $TileWidth
$window.Height = $TileHeight

# Render GUI interactively
$window.Topmost = $false
$window.Show()

# 1. Define Win32 bindings targeting the active parent terminal console host window
$Win32Console = Add-Type -MemberDefinition @'
    // GetConsoleWindow retrieves the window handle used by the parent console (CMD)
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    // ShowWindowAsync minimizes the window without causing OS resource throttling
    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
'@ -Name "WinConsole" -Namespace "WinAPI" -PassThru

# 2. Get the handle of the parent CMD window
$cmdHwnd = [WinAPI.WinConsole]::GetConsoleWindow()

# 3. Minimize it asynchronously if a valid window is detected
if ($cmdHwnd -ne [IntPtr]::Zero) {
    # 2 = SW_SHOWMINIMIZED (Folds window cleanly but keeps the thread priority alive)
    [void][WinAPI.WinConsole]::ShowWindowAsync($cmdHwnd, 2)
}

# CRITICAL: Allow WPF to process clicks, dragging, and redrawing
[System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

# Main Execution Loop
try {
    while ($true) {

        # Initialize and connect to the Database
        $global:SandstormDB = [LiteDB.LiteDatabase]::new($DbPath)

        $servercount = 0
        foreach ($Server in $Servers) {
            $now = Get-Date
            # Try to grab the live map and server name via UDP Query Port first
            $Info = Get-ServerInfo -Ip $Server.Ip -QueryPort $Server.QueryPort
            $DisplayTitle = if ($Info) { "$($Info.ServerName) [Map: $($Info.MapName)] [Player Count: $($Info.PlayerCount)]" } else { "$($Server.Name) (Query Offline)" }

            # Check and handle RCON link (TCP) stability
            if (-not $Server.Active -or $Server.Client -eq $null -or -not $Server.Client.Connected) {
                Write-Host "[$now] [$($Server.Name)] RCON link down. Attempting reconnect..." -ForegroundColor Yellow
                Connect-Server -Server $Server
            }
            
            if (-not $Server.Active) {
                Write-Warning "-> Skipping player command for $DisplayTitle due to offline RCON link."
                continue
            }
            
            $allPlayers = @()
            $playerCount = 0
            $CurrentTime = [DateTime]::Now
            $CurrentPlayers = @()
            # Request player list via active RCON connection
            try {
                Send-RconPacket -Stream $Server.Stream -RequestId 2 -Type 2 -Body "listplayers"
                $Response = Read-RconPacket -Stream $Server.Stream

                if ($Response -eq $null) { throw "Empty payload or RCON socket severed." }

                # Split response by newlines and skip the header and spacer
                $lines = $Response.Body -split "`n" | Where-Object { $_ -match '^\d' }

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

                            if ($LiveConnections -and 
                                $LiveConnections.ContainsKey($Server.Name) -and 
                                $LiveConnections[$Server.Name].ContainsKey($UniqueId)) 
                            {
                                if ($LiveConnections[$Server.Name][$UniqueId].IP -eq "0.0.0.0")
                                {
                                    $LiveConnections[$Server.Name][$UniqueId].IP = $playerIp
                                }
                                $LiveConnections[$Server.Name][$UniqueId].Score = $playerScore
                            }
                            else
                            {
                                if($playerScore -eq 0)
                                {
                                    $LiveConnections[$Server.Name][$UniqueId] = @{
                                        PlayerName = $displayName
                                        IP         = $playerIp
                                        Score      = $playerScore
                                        LoginTime  = [DateTime]::Now
                                    }
                                }
                            }

                            $ServerIdleTime[$server.Name] = 0
                        }
                    }

                    foreach ($PlayerID in $LiveConnections[$server.Name].Keys) {
                        $Details = $LiveConnections[$server.Name][$PlayerID]

                        $PlayTime = $CurrentTime - $Details.LoginTime
                        $DurationStr = "{0:d2}:{1:d2}:{2:d2}" -f [int]$PlayTime.TotalHours, $PlayTime.Minutes, $PlayTime.Seconds
                        $allPlayers += ("{0,-33} {1,-27} {2,-16} {3,-5} {4,8}" -f "$($Details.PlayerName)", $PlayerID.Substring(0, 26), "$($Details.IP)", "$($Details.Score)", "$DurationStr")
                        $playerCount += 1
                    }

                    if ($playerCount -eq 0)
                    {
                        if ($ServerIdleTime[$server.Name] -eq 0)
                        {
                            # Force save directly into the root tracking table
                            $ServerIdleTime[$server.Name] = [DateTime]::Now
                        }

                        $JoinTime = $ServerIdleTime[$server.Name]
                        $PlayTime = [DateTime]::Now - $JoinTime
                        $DurationStr = "{0:d2}:{1:d2}:{2:d2}" -f [int]$PlayTime.TotalHours, $PlayTime.Minutes, $PlayTime.Seconds

                        $allPlayers += ("{0,-33} {1,-27} {2,-16} {3,-5} {4,8}" -f "No Players", "No ID", "No IP", "0", "$DurationStr")
                    }
                }
                else
                {
                    if ($ServerIdleTime[$server.Name] -eq 0)
                    {
                        # Force save directly into the root tracking table
                        $ServerIdleTime[$server.Name] = [DateTime]::Now
                    }

                    $JoinTime = $ServerIdleTime[$server.Name]
                    $PlayTime = [DateTime]::Now - $JoinTime
                    $DurationStr = "{0:d2}:{1:d2}:{2:d2}" -f [int]$PlayTime.TotalHours, $PlayTime.Minutes, $PlayTime.Seconds
                    
                    $allPlayers += ("{0,-33} {1,-27} {2,-16} {3,-5} {4,8}" -f "No Players", "No ID", "No IP", "0", "$DurationStr")
                }
            }
            catch {
                Write-Warning "[$($Server.Name)] RCON session dropped during command execution: $_"
                Close-ServerConnection -Server $Server
            }

            # Parse logins and log outs from Insurgency.log
        
#            do {
#                $Line = $ServerLogs[$server.Name].StreamReader.ReadLine()
            while (($Line = $ServerLogs[$server.Name].StreamReader.ReadLine()) -ne $null) 
            {
#                if ($null -ne $Line) {
            
                    # Check for Login request
                    if ($line -match 'LogNet:\s*Login request:\s*\?Name=(?<Name>.*?)\s+userId:\s*(?<Id>.*?)\s+platform:') 
                    {
                        $UserID = $Matches['Id'].Trim()
                        $PlayerName = $Matches['Name'].Trim()
                        $PlayerName = $PlayerName -replace '\?\?Password.*', ''

                        # Clean any trailing punctuation from the network ID string
                        $UserID = $UserID -replace '[,\}\]]', ''

                        # 1. Isolate the text between '[' and the first ':'
                        $start = $line.IndexOf('[') + 1
                        $end   = $line.IndexOf(':')
                        $CleanedString = $line.Substring($start, $end - $start) # "2026.08.31-01.07.49"

                        # 2. Parse the string into a real DateTime object
                        $DateTime = [datetime]::ParseExact($CleanedString, 'yyyy.MM.dd-HH.mm.ss', $null)

                        # 2. Get the system's local time zone object
                        $tz = Get-TimeZone

                        # 3. Check if that specific date is in Daylight Saving Time
                        $isDST = $tz.IsDaylightSavingTime($DateTime)

                        # 4. Get the REAL offset for that specific date (accounts for DST)
                        $currentOffset = $tz.GetUtcOffset($DateTime)

                        # 5. Local Login Time
                        $Timestamp = $DateTime.AddHours($currentOffset.Hours)

                        $LiveConnections[$Server.Name][$UserID] = @{
                            PlayerName = $PlayerName
                            IP         = "0.0.0.0"
                            Score      = 0
                            LoginTime  = $Timestamp
                        }
                    }
            
                    # Check for UChannel Close and match Player ID.  Save player data to PlayerLogs DB
                    elseif ($line -like '*LogNet: UChannel::Close:*') {
                        # Extracts the UniqueId value
                        if ($line -match 'RemoteAddr:\s*(?<RemoteAddr>[^,]+),.*?UniqueId:\s*(?<UniqueId>[^\s,]+)') 
                        {
                            $RemoteAddr = ($Matches['RemoteAddr'].Trim() -split ':')[0]
                            $UniqueId = $Matches['UniqueId'].Trim()

                            # Clean off any potential trailing commas or formatting brackets
                            $UniqueId = $UniqueId -replace '[,\}\]]', ''
                                 
                            if ($UniqueId -ne "INVALID")
                            {
#                                if ($LiveConnections[$Server.Name].Keys -contains $UniqueId) {
                                    if ($LiveConnections -and 
                                    $LiveConnections.ContainsKey($Server.Name) -and 
                                    $LiveConnections[$Server.Name].ContainsKey($UniqueId)) {
                                        $playerInformation = $LiveConnections[$Server.Name][$UniqueId]
                                            
                                        $CurrentTime = [DateTime]::Now
                                        $PlayTime = $CurrentTime - $playerInformation.LoginTime
                                        $DurationStr = "{0:d2}:{1:d2}:{2:d2}" -f [int]$PlayTime.TotalHours, $PlayTime.Minutes, $PlayTime.Seconds

                                        $MatchEndedPayload = @{
                                            NetworkID    = $UniqueId
                                            Name         = $playerInformation.PlayerName
                                            LastPlayed   = $playerInformation.LoginTime
                                            Duration     = $DurationStr
                                            LastServer   = $Info.ServerName
                                            LastServerID = $Server.Name
                                            Ip           = $RemoteAddr
                                            Score        = $playerInformation.Score
                                        }
                                        $null = Add-PlayerSessionLog -Database $global:SandstormDB -SessionData $MatchEndedPayload

                                        $LiveConnections[$Server.Name].Remove($UniqueId)
                                    }
#                                }
                            }
                        }
                    }
            
                    # Check for UNetConnection Close and match Player ID.  Save player data to PlayerLogs DB
                    elseif ($Line -match "LogNet: UNetConnection::Cleanup:.*RemoteAddr:\s*(?:\[::ffff:)?(?<IPPort>[^,\]\s]+).*UniqueId:\s*(?<UID>\S+)") 
                    {
                        $RemoteAddr = ($Matches['IPPort'].Trim() -split ':')[0]
                        $UniqueId = $Matches['UID'].Trim()

                        # Clean off any potential trailing commas or formatting brackets
                        $UniqueId = $UniqueId -replace '[,\}\]]', ''
                            
                        if ($UniqueId -ne "INVALID")
                        {
#                            if ($LiveConnections[$Server.Name].Keys -contains $UniqueId) {
                                if ($LiveConnections -and 
                                    $LiveConnections.ContainsKey($Server.Name) -and 
                                    $LiveConnections[$Server.Name].ContainsKey($UniqueId)) {
                                    $playerInformation = $LiveConnections[$Server.Name][$UniqueId]

                                    $CurrentTime = [DateTime]::Now
                                    $PlayTime = $CurrentTime - $playerInformation.LoginTime
                                    $DurationStr = "{0:d2}:{1:d2}:{2:d2}" -f [int]$PlayTime.TotalHours, $PlayTime.Minutes, $PlayTime.Seconds
                                                
                                    $MatchEndedPayload = @{
                                        NetworkID    = $UniqueId
                                        Name         = $playerInformation.PlayerName
                                        LastPlayed   = $playerInformation.LoginTime
                                        Duration     = $DurationStr
                                        LastServer   = $Info.ServerName
                                        LastServerID = $Server.Name
                                        Ip           = $RemoteAddr
                                        Score        = $playerInformation.Score
                                    }
                                    $null = Add-PlayerSessionLog -Database $global:SandstormDB -SessionData $MatchEndedPayload

                                    $LiveConnections[$Server.Name].Remove($UniqueId)
                            }
#                            }
                        }
                    }
                    # Check for UNetConnection Close and match Player ID.  Save player data to PlayerLogs DB
                    elseif ($Line -match "LogNet: UNetConnection::Close:.*RemoteAddr:\s*(?:\[::ffff:)?(?<IPPort>[^,\]\s]+).*UniqueId:\s*(?<UID>\S+)") 
                    {
                        $RemoteAddr = ($Matches['IPPort'].Trim() -split ':')[0]
                        $UniqueId = $Matches['UID'].Trim()

                        # Clean off any potential trailing commas or formatting brackets
                        $UniqueId = $UniqueId -replace '[,\}\]]', ''
                            
                        if ($UniqueId -ne "INVALID")
                        {
#                            if ($LiveConnections[$Server.Name].Keys -contains $UniqueId) {
                                if ($LiveConnections -and 
                                    $LiveConnections.ContainsKey($Server.Name) -and 
                                    $LiveConnections[$Server.Name].ContainsKey($UniqueId)) {
                                    $playerInformation = $LiveConnections[$Server.Name][$UniqueId]

                                    $CurrentTime = [DateTime]::Now
                                    $PlayTime = $CurrentTime - $playerInformation.LoginTime
                                    $DurationStr = "{0:d2}:{1:d2}:{2:d2}" -f [int]$PlayTime.TotalHours, $PlayTime.Minutes, $PlayTime.Seconds
                                                
                                    $MatchEndedPayload = @{
                                        NetworkID    = $UniqueId
                                        Name         = $playerInformation.PlayerName
                                        LastPlayed   = $playerInformation.LoginTime
                                        Duration     = $DurationStr
                                        LastServer   = $Info.ServerName
                                        LastServerID = $Server.Name
                                        Ip           = $RemoteAddr
                                        Score        = $playerInformation.Score
                                    }
                                    $null = Add-PlayerSessionLog -Database $global:SandstormDB -SessionData $MatchEndedPayload

                                    $LiveConnections[$Server.Name].Remove($UniqueId)
                            }
#                            }
                        }
                    }
#                   # Check for UNetConnection Close and match Player ID.  Save player data to PlayerLogs DB
                    elseif ($Line -match "LogNet: Error: UEngine::BroadcastNetworkFailure:.*RemoteAddr:\s*(?:\[::ffff:)?(?<IPPort>[^,\]\s]+).*UniqueId:\s*(?<UID>\S+)") 
                    {
                        $RemoteAddr = ($Matches['IPPort'].Trim() -split ':')[0]
                        $UniqueId = $Matches['UID'].Trim()

                        # Clean off any potential trailing commas or formatting brackets
                        $UniqueId = $UniqueId -replace '[,\}\]]', ''
                            
                        if ($UniqueId -ne "INVALID")
                        {
#                            if ($LiveConnections[$Server.Name].Keys -contains $UniqueId) {
                                if ($LiveConnections -and 
                                    $LiveConnections.ContainsKey($Server.Name) -and 
                                    $LiveConnections[$Server.Name].ContainsKey($UniqueId)) {
                                    $playerInformation = $LiveConnections[$Server.Name][$UniqueId]

                                    $CurrentTime = [DateTime]::Now
                                    $PlayTime = $CurrentTime - $playerInformation.LoginTime
                                    $DurationStr = "{0:d2}:{1:d2}:{2:d2}" -f [int]$PlayTime.TotalHours, $PlayTime.Minutes, $PlayTime.Seconds
                                                
                                    $MatchEndedPayload = @{
                                        NetworkID    = $UniqueId
                                        Name         = $playerInformation.PlayerName
                                        LastPlayed   = $playerInformation.LoginTime
                                        Duration     = $DurationStr
                                        LastServer   = $Info.ServerName
                                        LastServerID = $Server.Name
                                        Ip           = $RemoteAddr
                                        Score        = $playerInformation.Score
                                    }
                                    $null = Add-PlayerSessionLog -Database $global:SandstormDB -SessionData $MatchEndedPayload

                                    $LiveConnections[$Server.Name].Remove($UniqueId)
                            }
#                            }
                        }
                    }
#                }
            }# while ($ServerLogs[$server.Name].StreamReader.Peek() -ge 0)

            $rebootMSG = "" 

            if ($scheduledTimes.count -gt 0)
            {
                $now = Get-Date
                foreach ($timeStr in $scheduledTimes) {
                    # Convert string to a full DateTime object for today
                    $targetTime = [DateTime]$timeStr
        
                    # Calculate the warning start window (5 minutes before target)
                    $warningStart = $targetTime.AddMinutes(-5)

                    # CHECK 1: Are we inside the 5-minute warning window?
                    if ($now -ge $warningStart -and $now -lt $targetTime) {
            
                        # Run the warning loop until the exact target time hits
                        if ((Get-Date) -lt $targetTime) {
                            # Calculate minutes/seconds remaining for the warning message
                            $timeLeft = $targetTime - (Get-Date)
                            if ($timeLeft.Minutes -ne 1)
                            {
                                $addS = "s"
                            }
                            else
                            {
                                $addS = ""
                            }
                            $msg = "WARNING: Server will restart in {0} minute$addS and {1} seconds!" -f $timeLeft.Minutes, $timeLeft.Seconds
                            $rebootMSG = " - Reboot: {0}:{1:D2}" -f $timeLeft.Minutes, $timeLeft.Seconds
                
                            Send-RconPacket -Stream $Server.Stream -RequestId 3 -Type 2 -Body "say $($msg)"
                            $MsgResponse = Read-RconPacket -Stream $Server.Stream
                        }
                    }
                }
            }

            $dataelement = [PSCustomObject]@{
                ServerName = $Info.ServerName
                MapName    = "Current Map : $($Info.MapName) - Player Count: $playerCount \ $($Info.PlayerCount)$rebootMSG"
                Players    = $allPlayers
            }
            $data[$servercount] = $dataelement

            # CRITICAL: Allow WPF to process clicks, dragging, and redrawing
            [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

            $servercount += 1
        }

        # Safe cleanup block to unlock the database when the script stops
        if ($global:SandstormDB) {
            $global:SandstormDB.Dispose()
            Remove-Variable -Name SandstormDB -Scope Global -ErrorAction SilentlyContinue
        }

        $delay = Get-Random -Minimum 10 -Maximum 31
        Start-Sleep -Seconds $delay
    }
}
finally {
    Write-Host "`nTerminating script, severing all persistent TCP links..." -ForegroundColor Red
    foreach ($Server in $Servers) { Close-ServerConnection -Server $Server }
}

pause