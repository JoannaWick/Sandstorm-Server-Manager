<#PSScriptInfo
.NAME Server_Analytics
.VERSION 1.0.0
.AUTHOR Joanna Wick
.TAGS Sandstorm, Mods
.PROJECTURI https://github.com/JoannaWick/Sandstorm-Server-Manager
#>

# Force PowerShell 5.1 to treat internal output pipeline as UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create the Form (Popup Window)
$formOpening = New-Object System.Windows.Forms.Form
$formOpening.Text = "Status"
$formOpening.Size = New-Object System.Drawing.Size(317, 110)
$formOpening.StartPosition = "CenterScreen"
$formOpening.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$formOpening.TopMost = $true          # Keeps it on top of other windows
$formOpening.MaximizeBox = $false
$formOpening.MinimizeBox = $false
$formOpening.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)

# Create the Label (Text inside)
$label = New-Object System.Windows.Forms.Label
$label.Text = "Scanning Database..."
$label.Font = New-Object System.Drawing.Font("Arial", 14, [System.Drawing.FontStyle]::Bold)
$label.Size = New-Object System.Drawing.Size(280, 50)
$label.Location = New-Object System.Drawing.Point(10, 10)
$label.TextAlign = "MiddleCenter"
$label.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)         # Accessible Dark Text
$label.BackColor = [System.Drawing.Color]::FromArgb(233, 236, 239)     # Soft Light Gray Fill
$formOpening.Controls.Add($label)

# Show the form asynchronously so the script keeps running
$formOpening.Show()
[System.Windows.Forms.Application]::DoEvents() # Forces Windows to paint the window immediately

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

# Create Main Window
$window = New-Object System.Windows.Window
$window.Title = "Multi-Server Analytics Dashboard"
$window.Height = 790
$window.Width = 1150
$window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen

$brushConverter = New-Object System.Windows.Media.BrushConverter
$window.Background = $brushConverter.ConvertFromString("#F4F4F6")

# Main Grid Layout
$mainGrid = New-Object System.Windows.Controls.Grid
$mainGrid.Margin = New-Object System.Windows.Thickness(15)

# Add Columns (Left Panel: 540px, Space: 15px, Right panel: Flexible)
$col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = New-Object System.Windows.GridLength(540)
$col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = New-Object System.Windows.GridLength(15)
$col3 = New-Object System.Windows.Controls.ColumnDefinition; $col3.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
$mainGrid.ColumnDefinitions.Add($col1)
$mainGrid.ColumnDefinitions.Add($col2)
$mainGrid.ColumnDefinitions.Add($col3)

# Left Panel Layout Wrapper (Separates Search Row from Content Row)
$leftPanelGrid = New-Object System.Windows.Controls.Grid
[System.Windows.Controls.Grid]::SetColumn($leftPanelGrid, 0)
$mainGrid.Children.Add($leftPanelGrid) | Out-Null

$lpRow0 = New-Object System.Windows.Controls.RowDefinition; $lpRow0.Height = [System.Windows.GridLength]::Auto
$lpRow1 = New-Object System.Windows.Controls.RowDefinition; $lpRow1.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
$leftPanelGrid.RowDefinitions.Add($lpRow0)
$leftPanelGrid.RowDefinitions.Add($lpRow1)

# Interactive Search Bar Component
$searchBarGrid = New-Object System.Windows.Controls.Grid
$searchBarGrid.Margin = New-Object System.Windows.Thickness(0, 0, 0, 15) # Spacing below search bar
[System.Windows.Controls.Grid]::SetRow($searchBarGrid, 0)
$leftPanelGrid.Children.Add($searchBarGrid) | Out-Null

# Split Search Bar into TextBox (Fluid), Clear (Fixed), Gap (Fixed), Search Button (Fixed)
$sbCol1 = New-Object System.Windows.Controls.ColumnDefinition; $sbCol1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
$sbCol2 = New-Object System.Windows.Controls.ColumnDefinition; $sbCol2.Width = New-Object System.Windows.GridLength(32) # Clear Button Width
$sbCol3 = New-Object System.Windows.Controls.ColumnDefinition; $sbCol3.Width = New-Object System.Windows.GridLength(10) # Gap
$sbCol4 = New-Object System.Windows.Controls.ColumnDefinition; $sbCol4.Width = New-Object System.Windows.GridLength(90) # Search Button width
$searchBarGrid.ColumnDefinitions.Add($sbCol1)
$searchBarGrid.ColumnDefinitions.Add($sbCol2)
$searchBarGrid.ColumnDefinitions.Add($sbCol3)
$searchBarGrid.ColumnDefinitions.Add($sbCol4)

# Search Input TextBox
$searchBox = New-Object System.Windows.Controls.TextBox
$searchBox.Height = 32
$searchBox.VerticalContentAlignment = [System.Windows.VerticalAlignment]::Center

# Give the right padding extra space (26px) so long typed text doesn't go under the clear button
$searchBox.Padding = New-Object System.Windows.Thickness(8, 0, 26, 0) 
$searchBox.BorderBrush = $brushConverter.ConvertFromString("#D1D1D6")
[System.Windows.Controls.Grid]::SetColumn($searchBox, 0)

# Span it across column 0 and 1 so the clear button sits visually inside the right edge of the text box
[System.Windows.Controls.Grid]::SetColumnSpan($searchBox, 2) 
$searchBarGrid.Children.Add($searchBox) | Out-Null

# Inline Clear Search Text Button ---
$clearButton = New-Object System.Windows.Controls.Button
$clearButton.Content = "✕" # Standard cross symbol
$clearButton.Height = 28   # Slightly shorter than the textbox to fit neatly inside borders
$clearButton.Width = 28
$clearButton.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
$clearButton.Background = [System.Windows.Media.Brushes]::Transparent
$clearButton.Foreground = $brushConverter.ConvertFromString("#8E8E93") # Soft gray look
$clearButton.BorderThickness = New-Object System.Windows.Thickness(0)
$clearButton.FontSize = 11
$clearButton.Cursor = [System.Windows.Input.Cursors]::Hand
$clearButton.Margin = New-Object System.Windows.Thickness(0, 0, 2, 0) # Small offset from right edge
[System.Windows.Controls.Grid]::SetColumn($clearButton, 1)

# Click logic to wipe text box and return cursor focus
$clearButton.Add_Click({
    $searchBox.Text = ""
    $searchBox.Focus() | Out-Null
})
$searchBarGrid.Children.Add($clearButton) | Out-Null

# Search Button
$searchButton = New-Object System.Windows.Controls.Button
$searchButton.Content = "Player Search"
$searchButton.Height = 32
$searchButton.Background = $brushConverter.ConvertFromString("#007AFF") # Standard UI Blue
$searchButton.Foreground = [System.Windows.Media.Brushes]::White
$searchButton.FontWeight = [System.Windows.FontWeights]::SemiBold
$searchButton.BorderThickness = New-Object System.Windows.Thickness(0)
[System.Windows.Controls.Grid]::SetColumn($searchButton, 3) # Moved to Column 3 due to new grid layout
$searchBarGrid.Children.Add($searchButton) | Out-Null

# Left Panel ScrollViewer (Targeted to Row 1 of leftPanelGrid)
$serverScroll = New-Object System.Windows.Controls.ScrollViewer
$serverScroll.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
[System.Windows.Controls.Grid]::SetRow($serverScroll, 1) # Positioned under Search
$leftPanelGrid.Children.Add($serverScroll) | Out-Null

$serverStackContainer = New-Object System.Windows.Controls.StackPanel
$serverScroll.Content = $serverStackContainer

# --- DYNAMIC SERVER CHART COMPONENT ---
Function Create-LiveServerChart {
    param (
        [Parameter(Mandatory=$true)] $DbConnection,
        [Parameter(Mandatory=$true)] [string]$ServerName,
        [Parameter(Mandatory=$true)] [string]$ServerID,
        [Parameter(Mandatory=$true)] [DateTime]$TargetDate
    )
    
    $border = New-Object System.Windows.Controls.Border
    $border.Background = [System.Windows.Media.Brushes]::White
    $border.CornerRadius = New-Object System.Windows.CornerRadius(5)
    $border.Padding = New-Object System.Windows.Thickness(12)
    $border.Margin = New-Object System.Windows.Thickness(0, 0, 0, 15)
    
    $bConverter = New-Object System.Windows.Media.BrushConverter
    $border.BorderBrush = $bConverter.ConvertFromString("#D1D1D6")
    $border.BorderThickness = New-Object System.Windows.Thickness(1)
    
    $innerGrid = New-Object System.Windows.Controls.Grid
    $r1 = New-Object System.Windows.Controls.RowDefinition; $r1.Height = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Auto)
    $r2 = New-Object System.Windows.Controls.RowDefinition; $r2.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $innerGrid.RowDefinitions.Add($r1)
    $innerGrid.RowDefinitions.Add($r2)
    
    $header = New-Object System.Windows.Controls.TextBlock
    $header.Text = "SERVER: $ServerName"
    $header.FontWeight = [System.Windows.FontWeights]::Bold
    $header.FontSize = 13
    $header.Margin = New-Object System.Windows.Thickness(0,0,0,5)
    $header.Foreground = $bConverter.ConvertFromString("#1C1C1E")
    [System.Windows.Controls.Grid]::SetRow($header, 0)
    $innerGrid.Children.Add($header) | Out-Null
    
    $graphsGrid = New-Object System.Windows.Controls.Grid
    $cg1 = New-Object System.Windows.Controls.ColumnDefinition; $cg1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $cg2 = New-Object System.Windows.Controls.ColumnDefinition; $cg2.Width = New-Object System.Windows.GridLength(20)
    $cg3 = New-Object System.Windows.Controls.ColumnDefinition; $cg3.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $graphsGrid.ColumnDefinitions.Add($cg1)
    $graphsGrid.ColumnDefinitions.Add($cg2)
    $graphsGrid.ColumnDefinitions.Add($cg3)
    [System.Windows.Controls.Grid]::SetRow($graphsGrid, 1)
    $innerGrid.Children.Add($graphsGrid) | Out-Null
    
    # 24 HOUR CHART PANEL
    $panel24 = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($panel24, 0)
    
    # Visual anchor to show users it is clickable
    $panel24.Cursor = [System.Windows.Input.Cursors]::Hand 
    $panel24.ToolTip = "Server Name: $ServerName`n`nClick to open window to view the number of`nTotal Unique Players during past days."

    $lbl24 = New-Object System.Windows.Controls.TextBlock
    $lbl24.Text = "Hourly Unique Players (Last 24h)"
    $lbl24.FontSize = 12
    $lbl24.Foreground = [System.Windows.Media.Brushes]::Gray
    $lbl24.Margin = New-Object System.Windows.Thickness(0,0,0,5)
    $panel24.Children.Add($lbl24) | Out-Null
    
    $uGrid24 = New-Object System.Windows.Controls.Primitives.UniformGrid
    $uGrid24.Rows = 1; $uGrid24.VerticalAlignment = [System.Windows.VerticalAlignment]::Bottom; $uGrid24.Height = 85

    # Ensure it handles clicks even if empty by giving it a transparent background
    $uGrid24.Background = [System.Windows.Media.Brushes]::Transparent 

    $panel24.Children.Add($uGrid24) | Out-Null
    $graphsGrid.Children.Add($panel24) | Out-Null
    
    # 7 DAY CHART PANEL
    $panel7 = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($panel7, 2)

    # Visual anchor to show users it is clickable
    $panel7.Cursor = [System.Windows.Input.Cursors]::Hand 
    $panel7.ToolTip = "Server Name: $ServerName`n`nClick to open windows to view more`n Days with Total Unique Players."
    
    $lbl7 = New-Object System.Windows.Controls.TextBlock
    $lbl7.Text = "Daily Unique Players (Last 7 Days)"
    $lbl7.FontSize = 12
    $lbl7.Foreground = [System.Windows.Media.Brushes]::Gray
    $lbl7.Margin = New-Object System.Windows.Thickness(0,0,0,5)
    $panel7.Children.Add($lbl7) | Out-Null
    
    $uGrid7 = New-Object System.Windows.Controls.Primitives.UniformGrid
    $uGrid7.Rows = 1; $uGrid7.VerticalAlignment = [System.Windows.VerticalAlignment]::Bottom; $uGrid7.Height = 85

    # Ensure it handles clicks even if empty by giving it a transparent background
    $uGrid7.Background = [System.Windows.Media.Brushes]::Transparent 

    $panel7.Children.Add($uGrid7) | Out-Null
    $graphsGrid.Children.Add($panel7) | Out-Null
    
    # --- CLICK EVENT FOR MODAL WITH STEPPING BUTTONS ---
    $panel24.Add_MouseLeftButtonDown(({
        Param($sender, $e)
        
        # Create Modal Window
        $modal = New-Object System.Windows.Window
        $modal.Title = "Player Activity Logs: $ServerName"
        $modal.Width = 540
        $modal.Height = 400
        $modal.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
        $modal.Owner = $window
        $modal.ResizeMode = [System.Windows.ResizeMode]::NoResize
        
        if ($global:MainWindow) { $modal.Owner = $global:MainWindow }

        # Layout Framework
        $modalBorder = New-Object System.Windows.Controls.Border
        $modalBorder.Padding = New-Object System.Windows.Thickness(15)

        $modalGrid = New-Object System.Windows.Controls.Grid
        
        $mRow1 = New-Object System.Windows.Controls.RowDefinition; $mRow1.Height = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Auto)
        $mRow2 = New-Object System.Windows.Controls.RowDefinition; $mRow2.Height = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Auto)
        $mRow3 = New-Object System.Windows.Controls.RowDefinition; $mRow3.Height = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Auto)
        $mRow4 = New-Object System.Windows.Controls.RowDefinition; $mRow4.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $modalGrid.RowDefinitions.Add($mRow1)
        $modalGrid.RowDefinitions.Add($mRow2)
        $modalGrid.RowDefinitions.Add($mRow3)
        $modalGrid.RowDefinitions.Add($mRow4)

        # Title Label
        $modalTitle = New-Object System.Windows.Controls.TextBlock
        $modalTitle.Text = "Hourly Player Breakdown for ID: $ServerID"
        $modalTitle.FontWeight = [System.Windows.FontWeights]::Bold
        $modalTitle.FontSize = 14
        $modalTitle.Margin = New-Object System.Windows.Thickness(0,0,0,10)
        [System.Windows.Controls.Grid]::SetRow($modalTitle, 0)
        $modalGrid.Children.Add($modalTitle) | Out-Null

        # Date Control Navigation Row ---
        $dateGrid = New-Object System.Windows.Controls.Grid
        $dateGrid.Margin = New-Object System.Windows.Thickness(0, 0, 0, 15)
        
        # Define 5 columns: Label (Auto), Back Button (Auto), DatePicker (Star), Forward Button (Auto), Padding (Auto)
        $dc1 = New-Object System.Windows.Controls.ColumnDefinition; $dc1.Width = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Auto)
        $dc2 = New-Object System.Windows.Controls.ColumnDefinition; $dc2.Width = New-Object System.Windows.GridLength(30) # Fixed size for square button
        $dc3 = New-Object System.Windows.Controls.ColumnDefinition; $dc3.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $dc4 = New-Object System.Windows.Controls.ColumnDefinition; $dc4.Width = New-Object System.Windows.GridLength(30) # Fixed size for square button
        $dateGrid.ColumnDefinitions.Add($dc1)
        $dateGrid.ColumnDefinitions.Add($dc2)
        $dateGrid.ColumnDefinitions.Add($dc3)
        $dateGrid.ColumnDefinitions.Add($dc4)

        # Text Label
        $dateLabel = New-Object System.Windows.Controls.TextBlock
        $dateLabel.Text = "Select History Date: "
        $dateLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $dateLabel.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        [System.Windows.Controls.Grid]::SetColumn($dateLabel, 0)
        $dateGrid.Children.Add($dateLabel) | Out-Null

        # BACK BUTTON (<)
        $btnBack = New-Object System.Windows.Controls.Button
        $btnBack.Content = "‹"
        $btnBack.FontSize = 14
        $btnBack.FontWeight = [System.Windows.FontWeights]::Bold
        $btnBack.Margin = New-Object System.Windows.Thickness(0, 0, 4, 0)
        [System.Windows.Controls.Grid]::SetColumn($btnBack, 1)
        $dateGrid.Children.Add($btnBack) | Out-Null

        # DATE PICKER (Main Display)
        $datePicker = New-Object System.Windows.Controls.DatePicker
        $datePicker.SelectedDate = $TargetDate
        [System.Windows.Controls.Grid]::SetColumn($datePicker, 2)
        $dateGrid.Children.Add($datePicker) | Out-Null

        # FORWARD BUTTON (>)
        $btnForward = New-Object System.Windows.Controls.Button
        $btnForward.Content = "›"
        $btnForward.FontSize = 14
        $btnForward.FontWeight = [System.Windows.FontWeights]::Bold
        $btnForward.Margin = New-Object System.Windows.Thickness(4, 0, 0, 0)
        [System.Windows.Controls.Grid]::SetColumn($btnForward, 3)
        $dateGrid.Children.Add($btnForward) | Out-Null

        [System.Windows.Controls.Grid]::SetRow($dateGrid, 1)
        $modalGrid.Children.Add($dateGrid) | Out-Null

        # Graph Container
        $hourlyGraphGrid = New-Object System.Windows.Controls.Primitives.UniformGrid
        $hourlyGraphGrid.Rows = 1
        $hourlyGraphGrid.Columns = 24
        $hourlyGraphGrid.Height = 200
        $hourlyGraphGrid.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#F2F2F7")
        [System.Windows.Controls.Grid]::SetRow($hourlyGraphGrid, 3)
        $modalGrid.Children.Add($hourlyGraphGrid) | Out-Null

        # Dynamic Render Engine
        $UpdateModalGraph = {
            Param($SelectedDateString)
            $hourlyGraphGrid.Children.Clear()

            $maxBarHeight = 170 

            $hourRecords = Get-ServerHourlyLog -DbConnection $global:SandstormDB -ServerName $serverName -ServerID $serverId  -TargetDate $SelectedDateString
                
            $maxPlayers = ($hourRecords | Measure-Object -Property uniquePlayers -Maximum).Maximum
            $formattedDate = ([datetime]$SelectedDateString).ToString("MMM d")

            foreach ($hours in $hourRecords) {
                $PlayerCount = $hours.uniquePlayers
                $percentage = ($hours.uniquePlayers / $maxPlayers) * 100
                $calculatedHeight = [Math]::Max(2.0, ($percentage / 100) * ($maxBarHeight - 1))

                $columnSlotGrid = New-Object System.Windows.Controls.Grid
                $sr1 = New-Object System.Windows.Controls.RowDefinition; $sr1.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
                $sr2 = New-Object System.Windows.Controls.RowDefinition; $sr2.Height = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Auto)
                $columnSlotGrid.RowDefinitions.Add($sr1)
                $columnSlotGrid.RowDefinitions.Add($sr2)

                $barGroupStack = New-Object System.Windows.Controls.StackPanel
                $barGroupStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Bottom
                [System.Windows.Controls.Grid]::SetRow($barGroupStack, 0)

                $txtCount = New-Object System.Windows.Controls.TextBlock
                $txtCount.Text = "$PlayerCount"
                $txtCount.FontSize = 9
                $txtCount.FontWeight = [System.Windows.FontWeights]::SemiBold
                $txtCount.Foreground = [System.Windows.Media.Brushes]::DimGray
                $txtCount.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
                $txtCount.Margin = New-Object System.Windows.Thickness(0, 0, 0, 1)
                $barGroupStack.Children.Add($txtCount) | Out-Null

                $bar = New-Object System.Windows.Controls.Border
                $bar.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#007AFF")
                $bar.Margin = New-Object System.Windows.Thickness(1, 0, 1, 0)
                $bar.CornerRadius = New-Object System.Windows.CornerRadius(2, 2, 0, 0)
                $bar.Height = $calculatedHeight
                $bar.ToolTip = "Server Name: $ServerName`n`nDate: $formattedDate`n`nHour: ${hour}:00`n`nPlayers: $PlayerCount"
                $bar.Cursor = [System.Windows.Input.Cursors]::Hand 
                $barGroupStack.Children.Add($bar) | Out-Null

                $columnSlotGrid.Children.Add($barGroupStack) | Out-Null

                $txtHour = New-Object System.Windows.Controls.TextBlock
                $txtHour.Text = $hours.hourString
                $txtHour.FontSize = 9
                $txtHour.Foreground = [System.Windows.Media.Brushes]::SlateGray
                $txtHour.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
                $txtHour.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
                [System.Windows.Controls.Grid]::SetRow($txtHour, 1)
                $columnSlotGrid.Children.Add($txtHour) | Out-Null

                $hourlyGraphGrid.Children.Add($columnSlotGrid) | Out-Null
            }
        }

        # --- BUTTON LOGIC EVENTS ---
        
        # Click Back Button: Subtract 1 day
        $btnBack.Add_Click({
            if ($datePicker.SelectedDate) {
                $datePicker.SelectedDate = $datePicker.SelectedDate.AddDays(-1)
            }
        })

        # Click Forward Button: Add 1 day
        $btnForward.Add_Click({
            if ($datePicker.SelectedDate) {
                if($datePicker.SelectedDate -lt $TargetDate)
                {
                    $datePicker.SelectedDate = $datePicker.SelectedDate.AddDays(1)
                }
            }
        })

        # --- TRIGGER GRAPH RE-RENDER ON DATE CHANGE ---
        $datePicker.Add_SelectedDateChanged({
            Param($sender, $e)
            if ($datePicker.SelectedDate) {
                $UpdateModalGraph.Invoke($datePicker.SelectedDate.ToString("yyyy/MM/dd"))
            }
        })

        # Initialize
        $UpdateModalGraph.Invoke($datePicker.SelectedDate.ToString("yyyy/MM/dd"))

        $modalBorder.Child = $modalGrid
        $modal.Content = $modalBorder
        [void]$modal.ShowDialog()

    }).GetNewClosure())

    # --- CLICK EVENT FOR MODAL WITH STEPPING BUTTONS ---
    $panel7.Add_MouseLeftButtonDown(({
        Param($sender, $e)
        
        # Create Modal Window
        $modal7 = New-Object System.Windows.Window
        $modal7.Title = "7 Day Activity Logs: $ServerName"
        $modal7.Width = 540
        $modal7.Height = 400
        $modal7.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
        $modal7.Owner = $window
        $modal7.ResizeMode = [System.Windows.ResizeMode]::NoResize
        
        if ($global:MainWindow) { $modal7.Owner = $global:MainWindow }

        # Layout Framework
        $modal7Border = New-Object System.Windows.Controls.Border
        $modal7Border.Padding = New-Object System.Windows.Thickness(15)

        $modal7Grid = New-Object System.Windows.Controls.Grid
        
        $mRow1 = New-Object System.Windows.Controls.RowDefinition; $mRow1.Height = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Auto)
        $mRow2 = New-Object System.Windows.Controls.RowDefinition; $mRow2.Height = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Auto)
        $mRow3 = New-Object System.Windows.Controls.RowDefinition; $mRow3.Height = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Auto)
        $mRow4 = New-Object System.Windows.Controls.RowDefinition; $mRow4.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $modal7Grid.RowDefinitions.Add($mRow1)
        $modal7Grid.RowDefinitions.Add($mRow2)
        $modal7Grid.RowDefinitions.Add($mRow3)
        $modal7Grid.RowDefinitions.Add($mRow4)

        # Title Label
        $modal7Title = New-Object System.Windows.Controls.TextBlock
        $modal7Title.Text = "7 Day Breakdown for ID: $ServerID"
        $modal7Title.FontWeight = [System.Windows.FontWeights]::Bold
        $modal7Title.FontSize = 14
        $modal7Title.Margin = New-Object System.Windows.Thickness(0,0,0,10)
        [System.Windows.Controls.Grid]::SetRow($modal7Title, 0)
        $modal7Grid.Children.Add($modal7Title) | Out-Null

        # Date Control Navigation Row ---
        $date7Grid = New-Object System.Windows.Controls.Grid
        $date7Grid.Margin = New-Object System.Windows.Thickness(0, 0, 0, 15)
        
        # Define 5 columns: Label (Auto), Back Button (Auto), DatePicker (Star), Forward Button (Auto), Padding (Auto)
        $dc1 = New-Object System.Windows.Controls.ColumnDefinition; $dc1.Width = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Auto)
        $dc2 = New-Object System.Windows.Controls.ColumnDefinition; $dc2.Width = New-Object System.Windows.GridLength(30) # Fixed size for square button
        $dc3 = New-Object System.Windows.Controls.ColumnDefinition; $dc3.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $dc4 = New-Object System.Windows.Controls.ColumnDefinition; $dc4.Width = New-Object System.Windows.GridLength(30) # Fixed size for square button
        $date7Grid.ColumnDefinitions.Add($dc1)
        $date7Grid.ColumnDefinitions.Add($dc2)
        $date7Grid.ColumnDefinitions.Add($dc3)
        $date7Grid.ColumnDefinitions.Add($dc4)

        # Text Label
        $date7Label = New-Object System.Windows.Controls.TextBlock
        $date7Label.Text = "Select History Date: "
        $date7Label.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $date7Label.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        [System.Windows.Controls.Grid]::SetColumn($date7Label, 0)
        $date7Grid.Children.Add($date7Label) | Out-Null

        # BACK BUTTON (<)
        $btn7Back = New-Object System.Windows.Controls.Button
        $btn7Back.Content = "‹"
        $btn7Back.FontSize = 14
        $btn7Back.FontWeight = [System.Windows.FontWeights]::Bold
        $btn7Back.Margin = New-Object System.Windows.Thickness(0, 0, 4, 0)
        [System.Windows.Controls.Grid]::SetColumn($btn7Back, 1)
        $date7Grid.Children.Add($btn7Back) | Out-Null

        # DATE PICKER (Main Display)
        $date7Picker = New-Object System.Windows.Controls.DatePicker
        $date7Picker.SelectedDate = $TargetDate
        [System.Windows.Controls.Grid]::SetColumn($date7Picker, 2)
        $date7Grid.Children.Add($date7Picker) | Out-Null

        # FORWARD BUTTON (>)
        $btn7Forward = New-Object System.Windows.Controls.Button
        $btn7Forward.Content = "›"
        $btn7Forward.FontSize = 14
        $btn7Forward.FontWeight = [System.Windows.FontWeights]::Bold
        $btn7Forward.Margin = New-Object System.Windows.Thickness(4, 0, 0, 0)
        [System.Windows.Controls.Grid]::SetColumn($btn7Forward, 3)
        $date7Grid.Children.Add($btn7Forward) | Out-Null

        [System.Windows.Controls.Grid]::SetRow($date7Grid, 1)
        $modal7Grid.Children.Add($date7Grid) | Out-Null

        # Graph Container
        $7dayGraphGrid = New-Object System.Windows.Controls.Primitives.UniformGrid
        $7dayGraphGrid.Rows = 1
        $7dayGraphGrid.Columns = 7
        $7dayGraphGrid.Height = 200
        $7dayGraphGrid.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#F2F2F7")
        [System.Windows.Controls.Grid]::SetRow($7dayGraphGrid, 3)
        $modal7Grid.Children.Add($7dayGraphGrid) | Out-Null

        # Dynamic Render Engine
        $UpdateModal7Graph = {
            Param($SelectedDateString)
            $7dayGraphGrid.Children.Clear()

            $maxBarHeight = 170 

            $days7 = Get-Server7DayLog -DbConnection $global:SandstormDB -ServerName $serverName -ServerID $serverId  -TargetDate $SelectedDateString
                
            $maxPlayers = ($days7 | Measure-Object -Property TotalPlayers -Maximum).Maximum

            foreach ($oneDay in $days7) {
                $formattedDate = ([datetime]$oneDay.LogDate).ToString("MMM d")
                $percentage = ($oneDay.TotalPlayers / $maxPlayers) * 100 
                $PlayerCount = $oneDay.TotalPlayers

                $calculatedHeight = [Math]::Max(2.0, ($percentage / 100) * ($maxBarHeight - 1))

                $columnSlotGrid = New-Object System.Windows.Controls.Grid
                $sr1 = New-Object System.Windows.Controls.RowDefinition; $sr1.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
                $sr2 = New-Object System.Windows.Controls.RowDefinition; $sr2.Height = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Auto)
                $columnSlotGrid.RowDefinitions.Add($sr1)
                $columnSlotGrid.RowDefinitions.Add($sr2)

                $barGroupStack = New-Object System.Windows.Controls.StackPanel
                $barGroupStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Bottom
                [System.Windows.Controls.Grid]::SetRow($barGroupStack, 0)

                $txtCount = New-Object System.Windows.Controls.TextBlock
                $txtCount.Text = "$PlayerCount"
                $txtCount.FontSize = 9
                $txtCount.FontWeight = [System.Windows.FontWeights]::SemiBold
                $txtCount.Foreground = [System.Windows.Media.Brushes]::DimGray
                $txtCount.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
                $txtCount.Margin = New-Object System.Windows.Thickness(0, 0, 0, 1)
                $barGroupStack.Children.Add($txtCount) | Out-Null

                $bar = New-Object System.Windows.Controls.Border
                $bar.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#007AFF")
                $bar.Margin = New-Object System.Windows.Thickness(1, 0, 1, 0)
                $bar.CornerRadius = New-Object System.Windows.CornerRadius(2, 2, 0, 0)
                $bar.Height = $calculatedHeight
                $bar.ToolTip = "Server Name: $ServerName`n`nDay: ${formattedDate}`n`nPlayers: $PlayerCount"
                $bar.Cursor = [System.Windows.Input.Cursors]::Hand 
                $barGroupStack.Children.Add($bar) | Out-Null

                $columnSlotGrid.Children.Add($barGroupStack) | Out-Null

                $txtday = New-Object System.Windows.Controls.TextBlock
                $txtday.Text = $formattedDate
                $txtday.FontSize = 9
                $txtday.Foreground = [System.Windows.Media.Brushes]::SlateGray
                $txtday.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
                $txtday.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
                [System.Windows.Controls.Grid]::SetRow($txtday, 1)
                $columnSlotGrid.Children.Add($txtday) | Out-Null

                $7dayGraphGrid.Children.Add($columnSlotGrid) | Out-Null
            }
        }

        # --- BUTTON LOGIC EVENTS ---
        
        # Click Back Button: Subtract 1 day
        $btn7Back.Add_Click({
            if ($date7Picker.SelectedDate) {
                $date7Picker.SelectedDate = $date7Picker.SelectedDate.AddDays(-1)
            }
        })

        # Click Forward Button: Add 1 day
        $btn7Forward.Add_Click({
            if ($date7Picker.SelectedDate) {
                if($date7Picker.SelectedDate -lt $TargetDate)
                {
                    $date7Picker.SelectedDate = $date7Picker.SelectedDate.AddDays(1)
                }
            }
        })

        # --- TRIGGER GRAPH RE-RENDER ON DATE CHANGE ---
        $date7Picker.Add_SelectedDateChanged({
            Param($sender, $e)
            if ($date7Picker.SelectedDate) {
                $UpdateModal7Graph.Invoke($date7Picker.SelectedDate.ToString("yyyy/MM/dd"))
            }
        })

        # Initialize
        $UpdateModal7Graph.Invoke($date7Picker.SelectedDate.ToString("yyyy/MM/dd"))

        $modal7Border.Child = $modal7Grid
        $modal7.Content = $modal7Border
        [void]$modal7.ShowDialog()

    }).GetNewClosure())

    $border.Child = $innerGrid
    $serverStackContainer.Children.Add($border) | Out-Null
    
    return ,($uGrid24, $uGrid7)
}


# Right Panel Master Stack
$rightGrid = New-Object System.Windows.Controls.Grid
[System.Windows.Controls.Grid]::SetColumn($rightGrid, 2)
$mainGrid.Children.Add($rightGrid) | Out-Null

# Split Right layout into two adaptive rows (Top: Current session, Bottom: Leaderboards)
$rightRow1 = New-Object System.Windows.Controls.RowDefinition; $rightRow1.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
$rightRowSplit = New-Object System.Windows.Controls.RowDefinition; $rightRowSplit.Height = New-Object System.Windows.GridLength(15)
$rightRow2 = New-Object System.Windows.Controls.RowDefinition; $rightRow2.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
$rightGrid.RowDefinitions.Add($rightRow1)
$rightGrid.RowDefinitions.Add($rightRowSplit)
$rightGrid.RowDefinitions.Add($rightRow2)

# --- TOP RIGHT: Active Session ListView Container ---
$topRightBorder = New-Object System.Windows.Controls.Border
$topRightBorder.Background = [System.Windows.Media.Brushes]::White
$topRightBorder.CornerRadius = New-Object System.Windows.CornerRadius(5)
$topRightBorder.Padding = New-Object System.Windows.Thickness(10)
$topRightBorder.BorderBrush = $brushConverter.ConvertFromString("#D1D1D6")
$topRightBorder.BorderThickness = New-Object System.Windows.Thickness(1)
[System.Windows.Controls.Grid]::SetRow($topRightBorder, 0)
$rightGrid.Children.Add($topRightBorder) | Out-Null

$topInnerGrid = New-Object System.Windows.Controls.Grid
$tr1 = New-Object System.Windows.Controls.RowDefinition; $tr1.Height = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Auto)
$tr2 = New-Object System.Windows.Controls.RowDefinition; $tr2.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
$topInnerGrid.RowDefinitions.Add($tr1)
$topInnerGrid.RowDefinitions.Add($tr2)

$listHeader = New-Object System.Windows.Controls.TextBlock
$listHeader.Text = "Active Player Details Last 24 Hours (Double-Click for Profile)"
$listHeader.FontWeight = [System.Windows.FontWeights]::Bold
$listHeader.FontSize = 13
$listHeader.Margin = New-Object System.Windows.Thickness(0,0,0,10)
$listHeader.Foreground = $brushConverter.ConvertFromString("#1C1C1E")
[System.Windows.Controls.Grid]::SetRow($listHeader, 0)
$topInnerGrid.Children.Add($listHeader) | Out-Null

$listView = New-Object System.Windows.Controls.ListView
$listView.BorderThickness = New-Object System.Windows.Thickness(0)
[System.Windows.Controls.Grid]::SetRow($listView, 1)
$topInnerGrid.Children.Add($listView) | Out-Null
$topRightBorder.Child = $topInnerGrid

# Bind Active Grid columns
$gridView = New-Object System.Windows.Controls.GridView
$cols = @(
    @("Player Name", "Name", 110),
    @("Last Played", "LastPlayed", 130),
    @("Duration", "Duration", 58),
    @("Last Server", "LastServer", 350)
)
foreach ($c in $cols) {
    $gvCol = New-Object System.Windows.Controls.GridViewColumn
    $gvCol.Header = $c[0]
    $gvCol.Width = $c[2]
    $gvCol.DisplayMemberBinding = New-Object System.Windows.Data.Binding($c[1])
    $gridView.Columns.Add($gvCol)
}
$listView.View = $gridView

# --- BOTTOM RIGHT: Most Active Players ListView Container ---
$bottomRightBorder = New-Object System.Windows.Controls.Border
$bottomRightBorder.Background = [System.Windows.Media.Brushes]::White
$bottomRightBorder.CornerRadius = New-Object System.Windows.CornerRadius(5)
$bottomRightBorder.Padding = New-Object System.Windows.Thickness(10)
$bottomRightBorder.BorderBrush = $brushConverter.ConvertFromString("#D1D1D6")
$bottomRightBorder.BorderThickness = New-Object System.Windows.Thickness(1)
[System.Windows.Controls.Grid]::SetRow($bottomRightBorder, 2)
$rightGrid.Children.Add($bottomRightBorder) | Out-Null

$bottomInnerGrid = New-Object System.Windows.Controls.Grid
$br1 = New-Object System.Windows.Controls.RowDefinition; $br1.Height = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Auto)
$br2 = New-Object System.Windows.Controls.RowDefinition; $br2.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
$bottomInnerGrid.RowDefinitions.Add($br1)
$bottomInnerGrid.RowDefinitions.Add($br2)

$activeHeader = New-Object System.Windows.Controls.TextBlock
$activeHeader.Text = "Top 10 Most Active Players by Server (Double-Click for Profile)"
$activeHeader.FontWeight = [System.Windows.FontWeights]::Bold
$activeHeader.FontSize = 13
$activeHeader.Margin = New-Object System.Windows.Thickness(0,0,0,10)
$activeHeader.Foreground = $brushConverter.ConvertFromString("#1C1C1E")

[System.Windows.Controls.Grid]::SetRow($activeHeader, 0)
$bottomInnerGrid.Children.Add($activeHeader) | Out-Null

$activityListView = New-Object System.Windows.Controls.ListView
$activityListView.BorderThickness = New-Object System.Windows.Thickness(0)
[System.Windows.Controls.Grid]::SetRow($activityListView, 1)
$bottomInnerGrid.Children.Add($activityListView) | Out-Null
$bottomRightBorder.Child = $bottomInnerGrid

# Bind Leaderboard Columns

$activityGridView = New-Object System.Windows.Controls.GridView
$leaderCols = @(
    @("Server", "ServerName", 265),
    @("Top 10 Per Server", "TopPlayer", 120),
    @("Playtime", "Playtime", 80),
    @("Joins", "SessionsCount", 38)
)

foreach ($lc in $leaderCols) {
    $lgvCol = New-Object System.Windows.Controls.GridViewColumn
    $lgvCol.Header = $lc[0]
    $lgvCol.Width = $lc[2]
    $lgvCol.DisplayMemberBinding = New-Object System.Windows.Data.Binding($lc[1])
    $activityGridView.Columns.Add($lgvCol)
}
$activityListView.View = $activityGridView

# Search Event Handler with Right Panel ListView Binding
$ExecuteSearchFiltering = {
    $searchTerm = $searchBox.Text
    
    # Check if the user cleared the search or it's empty
    if ([string]::IsNullOrWhiteSpace($searchTerm)) {
        # Reset the ListView to show ALL player records
        $activityListView.ItemsSource = $mostActiveData
        $activeHeader.Text = "Top 10 Most Active Players by Server (Double-Click for Profile)"
    } 
    else {

        $activeHeader.Text = "Player Search: $searchTerm (Double-Click for Profile)"
        # Filter the Right Panel Player ListView Dataset
        # Filters rows where "LastServer" property contains the search query

        $results = Search-Players -Database $global:SandstormDB -searchTerm $searchTerm -propertyName "Name"

        $filteredData = @()
        foreach ($player in $results) 
        {
            $globalPlayerDatabase[$player.ID] = $player

            $playerData =[PSCustomObject]@{ 
                ServerName = $player.LastServer
                TopPlayer = $player.Name
                ID = $player.ID
                Playtime = $player.TotalTimePlayed
                SessionsCount =  $player.TotalSessions
            }

            $filteredData += $playerData

        }

        # Bind the freshly isolated subset data straight to the list container
        $activityListView.ItemsSource = $filteredData
    }
}

# Attach the real-time processing block directly to text string modifications
$searchBox.Add_TextChanged($ExecuteSearchFiltering)

# Optional: Keep the search button clickable as a fallback interaction point
$searchButton.Add_Click($ExecuteSearchFiltering)

# Helper Function to Populate Graph Bars

Function Add-ChartBar {
    Param(
        $ChartContainer, 
        [double]$PercentageHeight, 
        [string]$LabelText, 
        [string]$HourDate, 
        $FillColor, 
        [double]$MaxPixelHeight = 65
    )
    $BarHeight = [Math]::Max(2.0, ($PercentageHeight / 100) * ($MaxPixelHeight - 1))
    
    $ColPanel = New-Object System.Windows.Controls.StackPanel
    $ColPanel.VerticalAlignment = [System.Windows.VerticalAlignment]::Bottom
    $ColPanel.Margin = New-Object System.Windows.Thickness(1,0,1,0)
    
    $Rect = New-Object System.Windows.Shapes.Rectangle
    $Rect.Height = $BarHeight
    $Rect.Fill = $FillColor
    $Rect.RadiusX = 1; $Rect.RadiusY = 1
    
    $Label = New-Object System.Windows.Controls.TextBlock
    $Label.Text = $HourDate
    $Label.FontSize = 9
    $Label.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $Label.Foreground = [System.Windows.Media.Brushes]::DimGray

    $LabelTime = New-Object System.Windows.Controls.TextBlock
    $LabelTime.Text = $LabelText
    $LabelTime.FontSize = 9
    $LabelTime.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $LabelTime.Foreground = [System.Windows.Media.Brushes]::DimGray
    
    [void]$ColPanel.Children.Add($LabelTime)
    [void]$ColPanel.Children.Add($Rect)
    [void]$ColPanel.Children.Add($Label)
    
    $ChartContainer.Dispatcher.Invoke({ [void]$ChartContainer.Children.Add($ColPanel) })
}

# --- SHARABLE WINDOW PROFILE FACTORY FUNCTION ---

Function Open-PlayerProfileModal {
    Param(
        $PlayerObject
    )
    
    # Build Modal Window Surface
    
    $detailWindow = New-Object System.Windows.Window
    $detailWindow.Title = "Player Profile: $($PlayerObject.Name)"
    $detailWindow.Height = 460
    $detailWindow.Width = 460
    $detailWindow.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
    $detailWindow.Owner = $window
    
    $conv = New-Object System.Windows.Media.BrushConverter
    $detailWindow.Background = $conv.ConvertFromString("#F4F4F6")
    
    $modalGrid = New-Object System.Windows.Controls.Grid
    $modalGrid.Margin = New-Object System.Windows.Thickness(15)
    
    $mr1 = New-Object System.Windows.Controls.RowDefinition; $mr1.Height = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Auto)
    $mr2 = New-Object System.Windows.Controls.RowDefinition; $mr2.Height = New-Object System.Windows.GridLength(15)
    $mr3 = New-Object System.Windows.Controls.RowDefinition; $mr3.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $modalGrid.RowDefinitions.Add($mr1); $modalGrid.RowDefinitions.Add($mr2); $modalGrid.RowDefinitions.Add($mr3)
    
    # Meta Fields Border Panel
    
    $metaBorder = New-Object System.Windows.Controls.Border
    $metaBorder.Background = [System.Windows.Media.Brushes]::White
    $metaBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
    $metaBorder.Padding = New-Object System.Windows.Thickness(12)
    $metaBorder.BorderBrush = $conv.ConvertFromString("#D1D1D6")
    $metaBorder.BorderThickness = New-Object System.Windows.Thickness(1)
    [System.Windows.Controls.Grid]::SetRow($metaBorder, 0)
    
    $metaStack = New-Object System.Windows.Controls.StackPanel
    
    $fn1 = New-Object System.Windows.Controls.TextBlock; $fn1.Text = "Player Name:  $($PlayerObject.Name)"; $fn1.FontWeight = [System.Windows.FontWeights]::Bold; $fn1.FontSize = 13; $fn1.Margin = "0,0,0,4"
    $fn2 = New-Object System.Windows.Controls.TextBlock; $fn2.Text = "Network ID :  $($PlayerObject.ID)"; $fn2.Foreground = [System.Windows.Media.Brushes]::DimGray; $fn2.Margin = "0,0,0,2"
    $fn3 = New-Object System.Windows.Controls.TextBlock; $fn3.Text = "IP Address  :  $($PlayerObject.IPAddress)"; $fn3.Foreground = [System.Windows.Media.Brushes]::DimGray; $fn3.Margin = "0,0,0,2"
    $fn4 = New-Object System.Windows.Controls.TextBlock; $fn4.Text = "Last Played :  $($PlayerObject.LastPlayed)"; $fn4.Foreground = [System.Windows.Media.Brushes]::DimGray; $fn4.Margin = "0,0,0,2"
    $fn5 = New-Object System.Windows.Controls.TextBlock; $fn5.Text = "Server         :  $($PlayerObject.LastServer)"; $fn5.Foreground = [System.Windows.Media.Brushes]::DimGray
    
    $metaStack.Children.Add($fn1) | Out-Null
    $metaStack.Children.Add($fn2) | Out-Null
    $metaStack.Children.Add($fn3) | Out-Null
    $metaStack.Children.Add($fn4) | Out-Null
    $metaStack.Children.Add($fn5) | Out-Null
    $metaBorder.Child = $metaStack
    $modalGrid.Children.Add($metaBorder) | Out-Null
    
    # Time breakdown sublist grid area
    
    $timeBorder = New-Object System.Windows.Controls.Border
    $timeBorder.Background = [System.Windows.Media.Brushes]::White
    $timeBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
    $timeBorder.Padding = New-Object System.Windows.Thickness(10)
    $timeBorder.BorderBrush = $conv.ConvertFromString("#D1D1D6")
    $timeBorder.BorderThickness = New-Object System.Windows.Thickness(1)
    [System.Windows.Controls.Grid]::SetRow($timeBorder, 2)
    
    $timeGrid = New-Object System.Windows.Controls.Grid
    $trw1 = New-Object System.Windows.Controls.RowDefinition; $trw1.Height = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Auto)
    $trw2 = New-Object System.Windows.Controls.RowDefinition; $trw2.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $timeGrid.RowDefinitions.Add($trw1); $timeGrid.RowDefinitions.Add($trw2)
    
    $lblBreakdown = New-Object System.Windows.Controls.TextBlock; $lblBreakdown.Text = "Total Playtime Breakdown by Server Instance:"; $lblBreakdown.FontWeight = [System.Windows.FontWeights]::SemiBold; $lblBreakdown.Margin = "0,0,0,6"; $lblBreakdown.FontSize = 11
    [System.Windows.Controls.Grid]::SetRow($lblBreakdown, 0)
    $timeGrid.Children.Add($lblBreakdown) | Out-Null
    
    $subListView = New-Object System.Windows.Controls.ListView
    $subListView.BorderThickness = New-Object System.Windows.Thickness(0)
    [System.Windows.Controls.Grid]::SetRow($subListView, 1)
    
    $subGridView = New-Object System.Windows.Controls.GridView
    $sc1 = New-Object System.Windows.Controls.GridViewColumn; $sc1.Header = "Server Instance"; $sc1.Width = 300; $sc1.DisplayMemberBinding = New-Object System.Windows.Data.Binding("Server")
    $sc2 = New-Object System.Windows.Controls.GridViewColumn; $sc2.Header = "Time In Game"; $sc2.Width = 85; $sc2.DisplayMemberBinding = New-Object System.Windows.Data.Binding("Time")
    $subGridView.Columns.Add($sc1); $subGridView.Columns.Add($sc2)
    $subListView.View = $subGridView
    
    # Bind server playtime configuration data map
    
    $subListView.ItemsSource = $PlayerObject.ServerTimeMap
    $timeGrid.Children.Add($subListView) | Out-Null
    
    $timeBorder.Child = $timeGrid
    $modalGrid.Children.Add($timeBorder) | Out-Null
    
    $detailWindow.Content = $modalGrid
    $detailWindow.ShowDialog() | Out-Null
}

# Setup paths relative to the script location
$DllPath = Join-Path $PSScriptRoot "db\LiteDB.dll"
$DllPath2 = Join-Path $PSScriptRoot "db\System.Buffers.dll"
$DbFolder = Join-Path $PSScriptRoot "db"
$DbPath = Join-Path $DbFolder "PlayerLogs.db"

# Place this at the very top of z_database.ps1
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

# Now load your assemblies safely
Add-Type -Path $DllPath2
# 4. Load the LiteDB Assembly
Add-Type -Path $DllPath

# Define the Daily Aggregation and Logging Function

function Get-Server7DayLog {
    param (
        [Parameter(Mandatory=$true)] $DbConnection,
        [Parameter(Mandatory=$true)] [string]$ServerName,
        [Parameter(Mandatory=$true)] [string]$ServerID,
        [Parameter(Mandatory=$true)] [DateTime]$TargetDate
    )

    # Resolve target collection hooks
    $playerLogsCol = $DbConnection.GetCollection("PlayerLogs")
    $playerLogsCol.EnsureIndex("LastPlayed") | Out-Null

    $days7 = @(for ($i = -6; $i -le 0; $i++) {

        # Establish clean 00:00:00 to 23:59:59 time boundaries for the target date
        $startTime = $TargetDate.Date.AddDays($i)
        $endTime   = $TargetDate.Date.AddDays($i + 1).AddTicks(-1)

        # Fetch player records belonging to this server inside the time window
        $records = @($playerLogsCol.Query().
            Where("LastServerID = @0 AND LastPlayed >= @1 AND LastPlayed <= @2", $ServerID, $startTime, $endTime).
            OrderByDescending("LastPlayed").
            ToEnumerable() | ForEach-Object {
        
                # Parse the pre-filtered results
                $parsedDate = [DateTime]::MinValue
                $JsonString = [LiteDB.JsonSerializer]::Serialize($_, $true)
                $Object = $JsonString | ConvertFrom-Json

                $RawDateStr = $Object.LastPlayed.'$date'
                $LastPlayedDate = if ($RawDateStr) { [DateTime]$RawDateStr } else { [DateTime]::MinValue }

                if ($LastPlayedDate -and [DateTime]::TryParse($LastPlayedDate, [ref]$parsedDate)) {
                    [PSCustomObject]@{ NetworkID = $Object.NetworkID; PlayDateTime = $parsedDate }
                }
            })

        if ([string]::IsNullOrWhiteSpace($records.count))
        {
            $totalUniquePlayers = 1
        }
        else
        {
            # Isolate unique active players
            $totalUniquePlayers = $records | Sort-Object NetworkID -Unique | Measure-Object | Select-Object -ExpandProperty Count
        }

        # Create a deterministic, unique string ID for this specific day and server
        $uniqueId = "$ServerID|$($TargetDate.Date.ToString('yyyy-MM-dd'))"

        [PSCustomObject]@{
            ServerID     = $ServerID
            LogDate      = $startTime.ToString("yyyy-MM-dd")
            ServerName   = $ServerName
            TotalPlayers = $totalUniquePlayers
        }
    })

    return $days7
}

# Define the Hourly Aggregation and Logging Function
function Add-ServerHourlyLog {
    param (
        [Parameter(Mandatory=$true)] $DbConnection,
        [Parameter(Mandatory=$true)] [string]$ServerName,
        [Parameter(Mandatory=$true)] [string]$ServerID,
        [Parameter(Mandatory=$true)] [DateTime]$TargetDate
    )

    $playerLogsCol = $DbConnection.GetCollection("PlayerLogs")
    $playerLogsCol.EnsureIndex("LastPlayed") | Out-Null
    $hourlyLogCol  = $DbConnection.GetCollection("ServerHourlyLog")
    $hourlyLogCol.EnsureIndex("LastServerID") | Out-Null

    # Filter bounds for the target day
    $dayStart = $TargetDate.Date
    $dayEnd   = $TargetDate.Date.AddDays(1).AddTicks(-1)
    
    # Fetch and calculate play session time-spans upfront
    $dayRecords = @($playerLogsCol.Query().
        Where("LastServerID = @0 AND LastPlayed >= @1 AND LastPlayed <= @2", $ServerID, $dayStart, $dayEnd).
        OrderByDescending("LastPlayed").
        ToEnumerable() | ForEach-Object {
            $JsonString = [LiteDB.JsonSerializer]::Serialize($_, $true)
            $Object = $JsonString | ConvertFrom-Json

            $RawDateStr = $Object.LastPlayed.'$date'
            $parsedStart = [DateTime]::MinValue

            if ($RawDateStr -and [DateTime]::TryParse([DateTime]$RawDateStr, [ref]$parsedStart)) {
                
                # --- PARSE AND ADD DURATION TO LASTPLAYED ---
                $timeSpan = [TimeSpan]::Zero
                if ($Object.Duration -and [TimeSpan]::TryParse($Object.Duration, [ref]$timeSpan)) {
                    # Add duration to LastPlayed to find when they finished playing
                    $parsedEnd = $parsedStart.Add($timeSpan)
                } else {
                    # Fallback if duration is missing or corrupt
                    $parsedEnd = $parsedStart 
                }

                [PSCustomObject]@{ 
                    NetworkID = $Object.NetworkID
                    StartTime = $parsedStart
                    EndTime   = $parsedEnd
                }
            }
        } | Where-Object { 
            # Capture any session that overlaps with our target day
            $_.StartTime -le $dayEnd -and $_.EndTime -ge $dayStart 
        })

    # Loop through every hour index (0 to 23)
    $hourRecords = foreach ($hour in 0..23) {
        
        # Define the exact start and end bounds of this specific hour bracket
        $hourStart = $dayStart.AddHours($hour)
        $hourEnd   = $hourStart.AddHours(1).AddTicks(-1)

        # A player spanned this hour if their session started before the hour ended 
        # AND their session ended after the hour started.
        $hourlyRecords = $dayRecords | Where-Object { 
            $_.StartTime -le $hourEnd -and $_.EndTime -ge $hourStart 
        }

        $uniquePlayers = ($hourlyRecords | Group-Object -Property NetworkID).Count

        # Format string keys for precise tracking indices
        $dateString = $TargetDate.Date.ToString("yyyy-MM-dd")
        $hourString = "{0:d2}" -f $hour

        # Create a deterministic, unique string ID for this specific hour and server
        $uniqueId = "$ServerID|$dateString|$hourString"

        if ([string]::IsNullOrWhiteSpace($uniquePlayers)) 
        {
            $uniquePlayers = 0
        }

        $hourlyDoc = [LiteDB.BsonDocument]::new()
        $hourlyDoc["_id"]          = [LiteDB.BsonValue]::new($uniqueId)
        $hourlyDoc["ServerName"]   = [LiteDB.BsonValue]::new($ServerName)
        $hourlyDoc["ServerID"]     = [LiteDB.BsonValue]::new($ServerID)
        $hourlyDoc["LogDate"]      = [LiteDB.BsonValue]::new($dateString)
        $hourlyDoc["LogHour"]      = [LiteDB.BsonValue]::new($hourString)
        $hourlyDoc["TotalPlayers"] = [LiteDB.BsonValue]::new($uniquePlayers)

        # Upsert the row into the hourly collection framework
        $null = $hourlyLogCol.Upsert($hourlyDoc)

        [PSCustomObject]@{ hourString = $hour; uniquePlayers = $uniquePlayers }
    }

    return $hourRecords
}

function Get-ServerHourlyLog {
    param (
        [Parameter(Mandatory=$true)] $DbConnection,
        [Parameter(Mandatory=$true)] [string]$ServerName,
        [Parameter(Mandatory=$true)] [string]$ServerID,
        [Parameter(Mandatory=$true)] [DateTime]$TargetDate
    )

    $hourlyLogCol  = $DbConnection.GetCollection("ServerHourlyLog")
    $hourlyLogCol.EnsureIndex("ServerID") | Out-Null

    # Filter bounds for the target day
    $dateString = $TargetDate.Date.ToString("yyyy-MM-dd")
    
    # Fetch and calculate play session time-spans upfront
    $hourRecords = @($hourlyLogCol.Query().
        Where("ServerID = @0 AND LogDate = @1", $ServerID, $dateString).
        ToEnumerable() | ForEach-Object {
            $JsonString = [LiteDB.JsonSerializer]::Serialize($_, $true)
            $Object = $JsonString | ConvertFrom-Json

            $hour = $Object.LogHour
            $TotalPlayers = $Object.TotalPlayers

            [PSCustomObject]@{ hourString = $hour; uniquePlayers = $TotalPlayers }
        })

    return $hourRecords
}

# Get Top 10 Players who have played the most on each server

function Get-PlayerAggregatedTotals {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Database,

        [Parameter(Mandatory = $false)]
        [string]$CollectionName = "PlayerLogs"
    )

    process {
        try {
            # Retrieve the lazy enumerable stream from the database
            $col = $Database.GetCollection($CollectionName)
            $query = $col.Query()
            $bsonResults = $query.ToEnumerable()

            # Use a nested Hash Table to accumulate stats in real-time
            $tracker = @{}

            # FIRST PASS: Stream and aggregate data. Keep database interactions single-threaded.
            foreach ($row in $bsonResults) {
                $serverId   = $row['LastServerID'].RawValue
                $playerName = $row['Name'].RawValue

                if ([string]::IsNullOrEmpty($serverId) -or [string]::IsNullOrEmpty($playerName)) { continue }

                # Safely convert Duration string to total seconds
                $durationString = $row['Duration'].RawValue
                $seconds = 0
    
                if (-not [string]::IsNullOrEmpty($durationString)) {
                    $timeSpan = [TimeSpan]::Zero
                    if ([TimeSpan]::TryParse($durationString, [ref]$timeSpan)) {
                        $seconds = $timeSpan.TotalSeconds
                    }
                }

                if (-not $tracker.ContainsKey($serverId)) {
                    $tracker[$serverId] = @{}
                }

                if (-not $tracker[$serverId].ContainsKey($playerName)) {
                    $tracker[$serverId][$playerName] = [PSCustomObject]@{
                        LastServerID    = $serverId
                        LastServer      = $row['LastServer'].RawValue
                        Name            = $playerName
                        TotalSessions   = 1
                        ID              = $row['NetworkID'].RawValue
                        LastPlayed      = $row['LastPlayed'].RawValue
                        Duration        = $durationString
                        IPAddress       = $row['IP'].RawValue
                        ServerTimeMap   = @()
                        TotalSeconds    = $seconds
                        TotalTimePlayed = "00:00:00" # FIX: Added missing property here
                    }
                } else {
                    $p = $tracker[$serverId][$playerName]
                    $p.TotalSessions += 1
                    $p.TotalSeconds  += $seconds
                }
            }

            # SECOND PASS: Process the top 10 winners and safely make nested database queries
            $objects = foreach ($serverId in $tracker.Keys) {
    
                $serverPlayers = $tracker[$serverId].Values
                $topTenPlayers = $serverPlayers | Sort-Object TotalSeconds -Descending | Select-Object -First 10

                [PSCustomObject]@{
                    LastServerID    = $serverId
                    LastServer      = "                       Top 10 Players for "
                    Name            = $serverId
                    TotalSessions   = 0
                    TotalTimePlayed = "00:00:00"
                    ID              = $serverId
                    LastPlayed      = [DateTime]::Now
                    Duration        = "00:00:00"
                    IPAddress       = "127.0.0.1"
                    ServerTimeMap   = @()
                    TotalSeconds    = 999999999
                }

                foreach ($player in $topTenPlayers) {
                    $totalDuration = [TimeSpan]::FromSeconds($player.TotalSeconds)
            
                    $player.TotalTimePlayed = if ($totalDuration.Days -gt 0) {
                        "{0}d {1:d2}:{2:d2}:{3:d2}" -f $totalDuration.Days, $totalDuration.Hours, $totalDuration.Minutes, $totalDuration.Seconds
                    } else {
                        "{0:d2}:{1:d2}:{2:d2}" -f $totalDuration.Hours, $totalDuration.Minutes, $totalDuration.Seconds
                    }

                    $Leaderboard = Get-PlayerInfoTotals -Database $Database -targetNetworkID $player.ID
                    $timeMapList = [System.Collections.Generic.List[Object]]::new()
            
                    foreach ($item in $Leaderboard) {
                        $timeMapList.Add([PSCustomObject]@{
                            Server = $item.LastServerName
                            Time   = $item.formattedTotal
                        })
                    }
                    $player.ServerTimeMap = $timeMapList.ToArray()

                    $player
                }
            }

            return $objects
        }
        catch {
            Write-Error "Failed to aggregate player log data: $_"
        }
    }
}

function Get-PlayerAggregatedTotalsold {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Database,

        [Parameter(Mandatory = $false)]
        [string]$CollectionName = "PlayerLogs"
    )

    process {
        try {
            # Retrieve all raw log entries from the database
            $col = $Database.GetCollection($CollectionName)
            $query = $col.Query()
            $bsonResults = $query.ToEnumerable()

            # Extract and parse BSON fields into PowerShell objects
            $allRecords = $bsonResults | ForEach-Object {
                $durationString = $_['Duration'].RawValue
    
                # Safely convert the "00:00:00" string into a TimeSpan object
                $timeSpan = [TimeSpan]::Zero
                if (-not [string]::IsNullOrEmpty($durationString)) {
                    [TimeSpan]::TryParse($durationString, [ref]$timeSpan) | Out-Null
                }

                [PSCustomObject]@{
                    LastServer     = $_['LastServer'].RawValue
                    LastServerID   = $_['LastServerID'].RawValue
                    PlayerName     = $_['Name'].RawValue
                    NetworkID      = $_['NetworkID'].RawValue
                    LastPlayed     = $_['LastPlayed'].RawValue
                    Duration       = $_['Duration'].RawValue
                    IPAddress      = $_['IP'].RawValue
                    TimeSpanObject = $timeSpan
                }
            }

            # Group everything by LastServerID
            $serverGroups = $allRecords | Group-Object -Property LastServerID

            # Process each server group and perform a nested group by Player
            $objects = foreach ($server in $serverGroups) {

                $serverId = $server.Name
                $playerGroups = $server.Group | Group-Object -Property PlayerName

                $serverPlayerStats = @(foreach ($player in $playerGroups) {
                    # Initialize a base TimeSpan to accumulate the total duration
                    $totalDuration = [TimeSpan]::Zero
                    foreach ($record in $player.Group) {
                        $totalDuration = $totalDuration.Add($record.TimeSpanObject)
                    }

                    # Format the final aggregated TimeSpan back to a standard string (Includes days if > 24 hours)
                    $formattedTotal = if ($totalDuration.Days -gt 0) {
                        "{0}d {1:d2}:{2:d2}:{3:d2}" -f $totalDuration.Days, $totalDuration.Hours, $totalDuration.Minutes, $totalDuration.Seconds
                    } else {
                        "{0:d2}:{1:d2}:{2:d2}" -f $totalDuration.Hours, $totalDuration.Minutes, $totalDuration.Seconds
                    }
        
                    [PSCustomObject]@{
                        LastServerID    = $serverId
                        LastServer      = $player.Group[0].LastServer
                        Name            = $player.Name
                        TotalSessions   = $player.Count
                        TotalTimePlayed = $formattedTotal
                        ID              = $player.Group[0].NetworkID
                        LastPlayed      = $player.Group[0].LastPlayed
                        Duration        = $player.Group[0].Duration
                        IPAddress       = $player.Group[0].IPAddress
                        ServerTimeMap   = @()
                        TotalSeconds    = $totalDuration.TotalSeconds # Hidden numeric key for sorting
                    }
                }) + [PSCustomObject]@{
                    LastServerID    = $serverId
                    LastServer      = "                       Top 10 Players for "
                    Name            = $server.Name
                    TotalSessions   = 0
                    TotalTimePlayed = "00:00:00"
                    ID              = $server.Name
                    LastPlayed      = [DateTime]::Now
                    Duration        = "00:00:00"
                    IPAddress       = "127.0.0.1"
                    ServerTimeMap   = @()
                    TotalSeconds    = 999999999
                }

                $serverPlayerStats | Sort-Object TotalSeconds -Descending | Select-Object -First 11

                foreach ($player in $serverPlayerStats) {
                    $Leaderboard = Get-PlayerInfoTotals -Database $Database -targetNetworkID $player.ID

                    foreach ($item in $Leaderboard) {
                        $newTimeEntry = [PSCustomObject]@{
                            Server = $item.LastServerName
                            Time = $item.formattedTotal
                        }
                        $player.ServerTimeMap += $newTimeEntry
                    }
                }
            }
            return $objects
        }
        catch {
            Write-Error "Failed to aggregate player log data: $_"
        }
    }
}

# Get one most recent player by LastServerID or get the top ## most recent players by LastServerID

function Get-RecentPlayerLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Database,

        [Parameter(Mandatory = $false)]
        [string]$CollectionName = "PlayerLogs"
    )

    process {
        try {
            # Open the collection
            $col = $Database.GetCollection($CollectionName)
            # Ensure index fields exist to make 'OrderBy' queries instantaneous
            $col.EnsureIndex("LastPlayed")
            $cutoffDate = [DateTime]::Now.AddHours(-24)
            $results = $col.Query().Where("LastPlayed >= @0", $cutoffDate).OrderByDescending("LastPlayed").ToEnumerable()

            # Output or process the logs
            $object = $results | ForEach-Object {
                [PSCustomObject]@{
                    LastServerID    = $_["LastServerID"].RawValue
                    LastServer      = $_["LastServer"].RawValue
                    Name            = $_["Name"].RawValue
                    TotalSessions   = 0
                    TotalTimePlayed = "00:00:00"
                    ID              = $_["NetworkID"].RawValue
                    LastPlayed      = $_["LastPlayed"].RawValue
                    Duration        = $_["Duration"].RawValue
                    IPAddress       = $_["Ip"].RawValue
                    ServerTimeMap   = @()
                }
            }

            foreach ($player in $object) {

                $Leaderboard = Get-PlayerInfoTotals -Database $Database -targetNetworkID $player.ID

                foreach ($item in $Leaderboard) {
                    $newTimeEntry = [PSCustomObject]@{
                        Server = $item.LastServerName
                        Time = $item.formattedTotal
                    }
                    $player.ServerTimeMap += $newTimeEntry
                }
            }

            return $object
        }
        catch {
            Write-Error "Failed to retrieve player logs: $_"
        }
    }
}

# Get Player totals

function Get-PlayerInfoTotals {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Database,

        [Parameter(Mandatory = $true)]
        [object]$targetNetworkID,

        [Parameter(Mandatory = $false)]
        [string]$CollectionName = "PlayerLogs"
    )

    process {
        try {
            # Retrieve all raw log entries from the database

            $col = $Database.GetCollection("PlayerLogs")

            # Fetch matching records using the native fluent query builder
            $rawRecords = $col.Query().
                Where([LiteDB.BsonExpression]::Create("$.NetworkID = @0", $targetNetworkID)).
                ToEnumerable() | ForEach-Object {
                        $LastPlayed   = if ($_['LastPlayed']) { [DateTime]$_['LastPlayed'].RawValue } else { $null }
                        $DurationStr  = if ($_['Duration'])   { $_['Duration'].RawValue }   else { "00:00:00" }

                    [PSCustomObject]@{
                        LastServerID = $_['LastServerID'].RawValue
                        LastServer   = $_['LastServer'].RawValue
                        LastPlayed   = if ($_['LastPlayed']) { [DateTime]$_['LastPlayed'].RawValue } else { $null }
                        DurationStr  = if ($_['Duration'])   { $_['Duration'].RawValue }   else { "00:00:00" }
                    }
                }

            # Group by LastServerID and accumulate the TimeSpans in PowerShell memory
            $serverHoursReport = $rawRecords | Group-Object -Property LastServerID | ForEach-Object {
                $groupItems = $_.Group

                # Initialize a baseline zero TimeSpan
                $totalTimeSpan = [TimeSpan]::Zero
    
                # Add up each duration string
                foreach ($item in $groupItems) {
                    if ($item.DurationStr -match '^\d{2}:\d{2}:\d{2}$') {
                        $totalTimeSpan = $totalTimeSpan.Add([TimeSpan]$item.DurationStr)
                    }
                }

                # Find the most recent session timestamp
                $latestPlay = ($groupItems | Measure-Object -Property LastPlayed -Maximum).Maximum
                $LastServerName = ($groupItems | Measure-Object -Property LastServer -Maximum).Maximum

                # Format the calculated TimeSpan back into an arbitrary or total format
                # Using TotalHours keeps track of scales exceeding 24 hours seamlessly
                $totalHours = [Math]::Round($totalTimeSpan.TotalHours, 2)

                # Format the final aggregated TimeSpan back to a standard string (Includes days if > 24 hours)
                $formattedTotal = if ($totalTimeSpan.Days -gt 0) {
                    "{0}d {1:d2}:{2:d2}:{3:d2}" -f $totalTimeSpan.Days, $totalTimeSpan.Hours, $totalTimeSpan.Minutes, $totalTimeSpan.Seconds
                } else {
                    "{0:d2}:{1:d2}:{2:d2}" -f $totalTimeSpan.Hours, $totalTimeSpan.Minutes, $totalTimeSpan.Seconds
                }

                [PSCustomObject]@{
                    NetworkID       = $targetNetworkID
                    LastServerID    = $_.Name
                    LastServerName  = $LastServerName
                    formattedTotal      = $formattedTotal
                    LastPlayed      = $latestPlay
                }
            }

            return $serverHoursReport
        }
        catch {
            Write-Error "Failed to aggregate player log data: $_"
        }
    }
}

<#
    Search for players using property
        Name
        NetworkID
        LastServerID
        LastServer
        LastPlayed
        Suration
        IP
#>

function Search-Players {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Database,

        [Parameter(Mandatory = $true)]
        [object]$searchTerm,

        [Parameter(Mandatory = $true)]
        [object]$propertyName,

        [Parameter(Mandatory = $false)]
        [string]$CollectionName = "PlayerLogs"
    )

    process {
        try {

            # Format for SQL-like match: %Term%
            $likePattern = "%$searchTerm%"

            $col = $Database.GetCollection("PlayerLogs")

            # Fetch only the matching data from LiteDB first
            $rawRows = @($col.Query().Where("$propertyName LIKE @0", $likePattern).ToEnumerable())

            # Use a native dictionary to handle the grouping manually by string name
            $playerGroups = @{}

            foreach ($row in $rawRows) {
                # Extract the raw string name
                $name = [string]$row["Name"].RawValue
                if ([string]::IsNullOrWhiteSpace($name)) { continue }

                # If the player name isn't tracked yet, create a new list for their sessions
                if (-not $playerGroups.ContainsKey($name)) {
                    $playerGroups[$name] = [System.Collections.Generic.List[object]]::new()
                }
    
                # Append this raw row to the player's group list
                $playerGroups[$name].Add($row)
            }

            $playersFound = [System.Collections.Generic.List[PSCustomObject]]::new()

            foreach ($name in $playerGroups.Keys) {
                $sessions = $playerGroups[$name]

                # Sort the group entries by date to find the most recent session info
                $latestSession = $sessions | Sort-Object { $_["LastPlayed"].RawValue } -Descending | Select-Object -First 1

                # Initialize a baseline zero TimeSpan
                $totalTimeSpan = [TimeSpan]::Zero
    
                # Add up each duration string
                foreach ($item in $sessions) {
                    if ($item["Duration"].RawValue -match '^\d{2}:\d{2}:\d{2}$') {
                        $totalTimeSpan = $totalTimeSpan.Add([TimeSpan]$item["Duration"].RawValue)
                    }
                }

                $totalHours = [Math]::Round($totalTimeSpan.TotalHours, 2)

                $formattedTotal = if ($totalTimeSpan.Days -gt 0) {
                    "{0}d {1:d2}:{2:d2}:{3:d2}" -f $totalTimeSpan.Days, $totalTimeSpan.Hours, $totalTimeSpan.Minutes, $totalTimeSpan.Seconds
                } else {
                    "{0:d2}:{1:d2}:{2:d2}" -f $totalTimeSpan.Hours, $totalTimeSpan.Minutes, $totalTimeSpan.Seconds
                }

                # 3. Output your exact custom [PSCustomObject] layout
                 $newPlayerObject = [PSCustomObject]@{ 
                    LastServerID    = $latestSession["LastServerID"].RawValue
                    LastServer      = $latestSession["LastServer"].RawValue
                    Name            = $latestSession["Name"].RawValue
                    TotalSessions   = $sessions.Count
                    TotalTimePlayed = $formattedTotal
                    ID              = $latestSession["NetworkID"].RawValue
                    LastPlayed      = $latestSession["LastPlayed"].RawValue
                    Duration        = $latestSession["Duration"]  # Replaces raw double with the summed string format
                    IPAddress       = $latestSession["Ip"].RawValue
                    ServerTimeMap   = @()
                }
                $playersFound.Add($newPlayerObject)
            }

            foreach ($player in $playersFound) {

                $Leaderboard = Get-PlayerInfoTotals -Database $Database -targetNetworkID $player.ID

                foreach ($item in $Leaderboard) {
                    $newTimeEntry = [PSCustomObject]@{
                        Server = $item.LastServerName
                        Time = $item.formattedTotal
                    }
                    $player.ServerTimeMap += $newTimeEntry
                }
            }
            return $playersFound
        }
        catch {
            Write-Error "Failed to aggregate player log data: $_"
        }
    }
}

# --- GLOBAL DATABANK RELATION DICTIONARY ---

# Tracks the full profile objects behind the scenes

$globalPlayerDatabase = @{}

# --- DOUBLE-CLICK EVENTS ---
# Action listener for top "Active Session" list

$listView.Add_MouseDoubleClick({
    $selected = $listView.SelectedItem
    if ($null -ne $selected) {
        $fullProfileObj = $globalPlayerDatabase[$selected.ID]
        if ($null -ne $fullProfileObj) { 
            Open-PlayerProfileModal -PlayerObject $fullProfileObj 
        }
    }
})

# Action listener for bottom "Most Active Leaderboard" list

$activityListView.Add_MouseDoubleClick({
    $selectedLeader = $activityListView.SelectedItem
    if ($null -ne $selectedLeader) {
        # Select player profile matching the leaderboard row's top player name string
        $fullProfileObj = $globalPlayerDatabase[$selectedLeader.ID]
        if ($null -ne $fullProfileObj) { 
            Open-PlayerProfileModal -PlayerObject $fullProfileObj 
        }
    }
})

# Establish your primary DB instance connection hook
# Initialize and connect to the Database
$DbPath = "Filename='" + $DbPath + "'; Connection=shared;"

$global:SandstormDB = [LiteDB.LiteDatabase]::new($DbPath)

$playerLogs = $global:SandstormDB.GetCollection("PlayerLogs")

# --- GENERATING CHARTS BY SERVER LIST LOOP ---

$blueBrush = [System.Windows.Media.Brushes]::DodgerBlue
$purpleBrush = [System.Windows.Media.Brushes]::BlueViolet

$ServerListJsonPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ServerList.json"
$ServerListData=Get-Content $ServerListJsonPath | ConvertFrom-Json

$activeServerIDs = foreach ($item in $ServerListData) 
{
    # Get each dynamic top element name and value
    foreach ($property in $item.PSObject.Properties) {
        [PSCustomObject]@{
            ID   = $property.Name
            Name = $property.Value
        }
    }
}

# Set the reporting window target date (Today)
$reportingDate = [DateTime]::Today

# Process records server by server
foreach ($serverId in $activeServerIDs) {
    if (-not [string]::IsNullOrEmpty($serverId.ID )) {

        $collection = $global:SandstormDB.GetCollection("PlayerLogs")

        $targetID = $serverId.ID
        $matchedDoc = $collection.FindOne([LiteDB.Query]::EQ("LastServerID", $targetID))

        if ($null -ne $matchedDoc) {
            $serverName = $matchedDoc["LastServer"].AsString
        } else {
            $serverName = $serverId.ID  # No entry matched the ID
        }

        $chartTargets = Create-LiveServerChart -ServerName $serverName -serverID $serverId.ID -DbConnection $global:SandstormDB  -TargetDate $reportingDate

        $target24h = $chartTargets[0]
        $target7d  = $chartTargets[1]

        # Execute calculations and populate collections
        $days7 = Get-Server7DayLog -DbConnection $global:SandstormDB -ServerName $serverName -ServerID $serverId.ID  -TargetDate $reportingDate

        $maxPlayers = ($days7 | Measure-Object -Property TotalPlayers -Maximum).Maximum

        foreach ($oneDay in $days7) {
            $formattedDate = ([datetime]$oneDay.LogDate).ToString("MMM d")
            $percentage = ($oneDay.TotalPlayers / $maxPlayers) * 100 
            Add-ChartBar -ChartContainer $target7d -PercentageHeight $percentage -LabelText "$($oneDay.TotalPlayers)" -HourDate $formattedDate -FillColor $blueBrush
        }

        $hourRecords = Add-ServerHourlyLog -DbConnection $global:SandstormDB -ServerName $serverName -ServerID $serverId.ID  -TargetDate $reportingDate

        $maxPlayers = ($hourRecords | Measure-Object -Property uniquePlayers -Maximum).Maximum

        foreach ($hours in $hourRecords) {
            $percentage = ($hours.uniquePlayers / $maxPlayers) * 100 
            Add-ChartBar -ChartContainer $target24h -PercentageHeight $percentage -LabelText "$($hours.uniquePlayers)" -HourDate $hours.hourString -FillColor $blueBrush
        }
    }
}

# --- Run Aggregation Dashboard ---
$Leaderboard = Get-PlayerAggregatedTotals -Database $global:SandstormDB

$mostActiveData = @()
foreach ($player in $Leaderboard) 
{
    $globalPlayerDatabase[$player.ID] = $player

    $playerData =[PSCustomObject]@{ 
        ServerName = $player.LastServer
        TopPlayer = $player.Name
        ID = $player.ID
        Playtime = $player.TotalTimePlayed
        SessionsCount =  $player.TotalSessions
    }

    $mostActiveData += $playerData
}

$activityListView.ItemsSource = $mostActiveData

# --- Players Last 24 Hours Dashboard ---
$MostRecentPlayers = Get-RecentPlayerLog -Database $global:SandstormDB

$mostRecentData = @()
foreach ($player in $MostRecentPlayers) 
{
    if($player.ID -ne $null)
    {
        $globalPlayerDatabase[$player.ID] = $player
        $mostRecentData += $player
    }
}

$listView.ItemsSource = $mostRecentData

$formOpening.Close()
$formOpening.Dispose()

$window.Content = $mainGrid
$window.ShowDialog() | Out-Null



