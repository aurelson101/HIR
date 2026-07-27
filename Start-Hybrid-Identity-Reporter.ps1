#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Console,
    [switch]$HealthCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$isWindowsPlatform = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
if (-not $isWindowsPlatform) {
    throw 'Hybrid Identity Reporter requires Windows because it uses WPF.'
}

if (-not $Console -and [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $pwsh = (Get-Process -Id $PID).Path
    $relaunchArgs = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($HealthCheck) {
        $relaunchArgs += '-HealthCheck'
    }
    Start-Process -FilePath $pwsh -ArgumentList $relaunchArgs
    return
}

$script:RootPath = Split-Path -Parent $PSCommandPath

$modulePaths = @(
    'Modules\Core\Logging.psm1',
    'Modules\Core\Config.psm1',
    'Modules\Core\Helpers.psm1',
    'Modules\AD\ADConnection.psm1',
    'Modules\AD\ADUsers.psm1',
    'Modules\AD\ADGroups.psm1',
    'Modules\AD\ADComputers.psm1',
    'Modules\Entra\GraphConnection.psm1',
    'Modules\Entra\EntraUsers.psm1',
    'Modules\Entra\EntraGroups.psm1',
    'Modules\Entra\EntraRoles.psm1',
    'Modules\Exchange\ExchangeConnection.psm1',
    'Modules\Exchange\ExchangeReports.psm1',
    'Modules\Hybrid\HybridReports.psm1',
    'Modules\Export\ExportCsv.psm1',
    'Modules\Export\ExportExcel.psm1',
    'Modules\Export\ExportHtml.psm1'
)

foreach ($relativePath in $modulePaths) {
    Import-Module (Join-Path $script:RootPath $relativePath) -Force -ErrorAction Stop
}

Initialize-HIRLogging -RootPath $script:RootPath
try {
    Enable-HIRTls12 | Out-Null
    Write-HIRLog -Module Core -Action Startup -Level INFO -Message 'TLS 1.2 enabled for this PowerShell session.'
}
catch {
    Write-HIRLog -Module Core -Action Startup -Level WARNING -Message $_.Exception.Message
}
$script:AppSettings = Get-HIRAppSettings -RootPath $script:RootPath
$script:Connections = Get-HIRConnections -RootPath $script:RootPath
$script:PlannedReportSettings = Get-HIRPlannedReportSettings -RootPath $script:RootPath
$script:ReportCatalog = @(Merge-HIRPlannedReportSettings -Reports @(Get-HIRReportCatalog -RootPath $script:RootPath) -Settings $script:PlannedReportSettings)
$script:CurrentResults = @()
$script:CurrentReportName = $null
$script:IsBusy = $false
$script:LastExportPath = $null
$script:InstallTimeoutMinutes = if ($script:AppSettings.PSObject.Properties.Name -contains 'Runtime' -and $script:AppSettings.Runtime.PSObject.Properties.Name -contains 'InstallTimeoutMinutes') { [Math]::Max(1, [int]$script:AppSettings.Runtime.InstallTimeoutMinutes) } else { 30 }
$script:MaxUiLogCharacters = if ($script:AppSettings.PSObject.Properties.Name -contains 'Runtime' -and $script:AppSettings.Runtime.PSObject.Properties.Name -contains 'MaxUiLogCharacters') { [Math]::Max(5000, [int]$script:AppSettings.Runtime.MaxUiLogCharacters) } else { 60000 }
$script:LargeResultWarningThreshold = if ($script:AppSettings.PSObject.Properties.Name -contains 'Runtime' -and $script:AppSettings.Runtime.PSObject.Properties.Name -contains 'LargeResultWarningThreshold') { [Math]::Max(100, [int]$script:AppSettings.Runtime.LargeResultWarningThreshold) } else { 10000 }
$script:LastNavigationSection = $null

function Get-HIRHealthCheckData {
    [CmdletBinding()]
    param(
        [string]$AdStatusText = 'AD: Not loaded',
        [string]$ExchangeStatusText = 'Exchange Online: Not loaded'
    )

    $paths = @(
        @{ Name = 'Config'; Path = Join-Path $script:RootPath 'Config' }
        @{ Name = 'Reports'; Path = Join-Path $script:RootPath 'Reports' }
        @{ Name = 'Logs'; Path = Join-Path $script:RootPath 'Logs' }
        @{ Name = 'Archive'; Path = Join-Path $script:RootPath 'Archive' }
        @{ Name = 'Templates'; Path = Join-Path $script:RootPath 'Templates' }
    )

    $checks = @()
    $checks += [pscustomobject]@{ Area = 'Runtime'; Check = 'PowerShell Version'; Status = $PSVersionTable.PSVersion.ToString(); Recommendation = if ($PSVersionTable.PSVersion.Major -eq 5) { 'OK for WPF GUI and RSAT modules.' } else { 'Windows PowerShell 5.1 is recommended for the WPF launcher.' } }
    $checks += [pscustomobject]@{ Area = 'Runtime'; Check = 'STA Mode'; Status = [System.Threading.Thread]::CurrentThread.GetApartmentState().ToString(); Recommendation = 'WPF requires STA.' }
    $checks += [pscustomobject]@{ Area = 'Runtime'; Check = 'TLS'; Status = [Net.ServicePointManager]::SecurityProtocol.ToString(); Recommendation = if (([Net.ServicePointManager]::SecurityProtocol -band [Net.SecurityProtocolType]::Tls12) -eq [Net.SecurityProtocolType]::Tls12) { 'OK' } else { 'Enable TLS 1.2 before PSGallery operations.' } }

    foreach ($moduleName in @('ActiveDirectory', 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Users', 'Microsoft.Graph.Groups', 'Microsoft.Graph.Identity.DirectoryManagement', 'ExchangeOnlineManagement', 'ImportExcel')) {
        $installed = Test-HIRModuleInstalled -Name $moduleName
        $checks += [pscustomobject]@{ Area = 'Module'; Check = $moduleName; Status = if ($installed) { 'Installed' } else { 'Missing' }; Recommendation = if ($installed) { 'OK' } else { 'Use the relevant Connect or Export button to install on demand.' } }
    }

    foreach ($pathInfo in $paths) {
        $exists = Test-Path -LiteralPath $pathInfo.Path
        $checks += [pscustomobject]@{ Area = 'Path'; Check = $pathInfo.Name; Status = if ($exists) { 'OK' } else { 'Missing' }; Recommendation = $pathInfo.Path }
    }

    foreach ($jsonFile in @('appsettings.json', 'connections.json', 'reports.json', 'planned-reports.json')) {
        $path = Join-Path $script:RootPath "Config\$jsonFile"
        try {
            Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
            $checks += [pscustomobject]@{ Area = 'Config'; Check = $jsonFile; Status = 'Valid JSON'; Recommendation = 'OK' }
        }
        catch {
            $checks += [pscustomobject]@{ Area = 'Config'; Check = $jsonFile; Status = 'Invalid'; Recommendation = $_.Exception.Message }
        }
    }

    $implemented = @($script:ReportCatalog | Where-Object { $_.Implemented -eq $true }).Count
    $planned = @($script:ReportCatalog | Where-Object { $_.Implemented -ne $true }).Count
    $checks += [pscustomobject]@{ Area = 'Catalog'; Check = 'Reports'; Status = "$($script:ReportCatalog.Count) total"; Recommendation = "$implemented implemented, $planned planned." }
    $checks += [pscustomobject]@{ Area = 'Catalog'; Check = 'Planned report configuration'; Status = if ($script:PlannedReportSettings.ShowPlannedReports) { 'Visible' } else { 'Hidden' }; Recommendation = 'Edit Config\planned-reports.json to show, hide or annotate planned reports.' }

    $missingFunctions = @($script:ReportCatalog | Where-Object { $_.Implemented -eq $true } | Where-Object { -not (Get-Command -Name $_.Function -ErrorAction SilentlyContinue) })
    $checks += [pscustomobject]@{ Area = 'Catalog'; Check = 'Implemented functions'; Status = if ($missingFunctions.Count -eq 0) { 'OK' } else { 'Missing functions' }; Recommendation = if ($missingFunctions.Count -eq 0) { 'All implemented reports resolve to a function.' } else { ($missingFunctions.Function -join ', ') } }

    $checks += [pscustomobject]@{ Area = 'Suggestion'; Check = 'Startup folder'; Status = 'Portable'; Recommendation = "Current root: $script:RootPath" }
    $checks += [pscustomobject]@{ Area = 'Suggestion'; Check = 'Graph reports'; Status = $null; Recommendation = 'Connect Entra ID before running Graph user, group or role reports.' }
    $checks += [pscustomobject]@{ Area = 'Suggestion'; Check = 'Hybrid reports'; Status = ('{0} | {1}' -f $AdStatusText, $ExchangeStatusText); Recommendation = 'Hybrid reports need AD plus Exchange Online context.' }

    return @($checks)
}

function Get-HIRHealthCheckSeverity {
    param(
        [AllowNull()][string]$Status,
        [AllowNull()][string]$Area
    )

    if ([string]::IsNullOrWhiteSpace($Status)) {
        return 'Info'
    }

    if ($Area -eq 'Module' -and $Status -eq 'Missing') {
        return 'Warning'
    }

    switch -Regex ($Status) {
        '(Invalid|Error)' { return 'Error' }
        '(Missing)' { return 'Error' }
        '(Hidden|Disconnected|Warning)' { return 'Warning' }
        '(OK|Installed|Visible|Valid JSON|Connected|Portable)' { return 'OK' }
        default { return 'Info' }
    }
}

function Update-HealthCheckVisual {
    param(
        [Parameter(Mandatory)]
        [object[]]$Checks
    )

    $total = @($Checks).Count
    $okCount = 0
    $warningCount = 0
    $errorCount = 0

    foreach ($check in @($Checks)) {
        switch (Get-HIRHealthCheckSeverity -Status ([string]$check.Status) -Area ([string]$check.Area)) {
            'OK' { $okCount++ }
            'Warning' { $warningCount++ }
            'Error' { $errorCount++ }
        }
    }

    $controls.SectionDescriptionText.Text = 'Health check completed: {0} OK, {1} warnings, {2} errors.' -f $okCount, $warningCount, $errorCount
    $controls.SectionMetricsText.Text = "Health check summary`nTotal checks: $total`nOK: $okCount`nWarnings: $warningCount`nErrors: $errorCount"
    $controls.SectionActionsText.Text = "Suggested next steps:`n- Open Logs if any error is present`n- Install missing modules before running reports`n- Re-run Health Check after remediation"

    $controls.LegendPanel.Children.Clear()
    Add-LegendItem -Label "OK: $okCount" -Brush ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(39, 174, 96)))
    Add-LegendItem -Label "Warnings: $warningCount" -Brush ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(243, 156, 18)))
    Add-LegendItem -Label "Errors: $errorCount" -Brush ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(192, 57, 43)))
    Add-LegendItem -Label "Total checks: $total" -Brush ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(52, 152, 219)))
}

function Invoke-HIRConsoleMode {
    [CmdletBinding()]
    param()

    Write-Host ('{0} v{1}' -f $script:AppSettings.ApplicationName, $script:AppSettings.Version)
    Write-Host ('Root: {0}' -f $script:RootPath)
    Write-Host ('Reports: {0} total, {1} implemented, {2} planned' -f $script:ReportCatalog.Count, @($script:ReportCatalog | Where-Object { $_.Implemented -eq $true }).Count, @($script:ReportCatalog | Where-Object { $_.Implemented -ne $true }).Count)
    Write-Host ''

    $checks = @(Get-HIRHealthCheckData)
    $summary = [pscustomobject]@{
        OK       = @($checks | Where-Object { (Get-HIRHealthCheckSeverity -Status ([string]$_.Status) -Area ([string]$_.Area)) -eq 'OK' }).Count
        Warning  = @($checks | Where-Object { (Get-HIRHealthCheckSeverity -Status ([string]$_.Status) -Area ([string]$_.Area)) -eq 'Warning' }).Count
        Error    = @($checks | Where-Object { (Get-HIRHealthCheckSeverity -Status ([string]$_.Status) -Area ([string]$_.Area)) -eq 'Error' }).Count
        Total    = $checks.Count
    }

    Write-Host 'Health check summary:'
    $summary | Format-List | Out-String | Write-Host
    Write-Host 'Health check details:'
    $checks | Sort-Object Area, Check | Format-Table Area, Check, Status, Recommendation -AutoSize | Out-String -Width 220 | Write-Host

    if ($summary.Error -gt 0) {
        Write-Host 'Console health check completed with errors.'
        return 1
    }

    if ($summary.Warning -gt 0) {
        Write-Host 'Console health check completed with warnings.'
        return 0
    }

    Write-Host 'Console health check completed successfully.'
    return 0
}

if ($Console) {
    $exitCode = Invoke-HIRConsoleMode
    exit $exitCode
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
[xml]$xaml = Get-Content -LiteralPath (Join-Path $script:RootPath 'GUI\MainWindow.xaml') -Raw -Encoding UTF8
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$reader.Close()
if ($script:AppSettings.PSObject.Properties.Name -contains 'Version') {
    $window.Title = '{0} v{1}' -f $script:AppSettings.ApplicationName, $script:AppSettings.Version
}

function Get-Control {
    param([Parameter(Mandatory)][string]$Name)
    $window.FindName($Name)
}

function Show-HIRMessageBox {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Title = $script:AppSettings.ApplicationName,

        [System.Windows.MessageBoxButton]$Button = [System.Windows.MessageBoxButton]::OK,

        [System.Windows.MessageBoxImage]$Image = [System.Windows.MessageBoxImage]::None
    )

    [System.Windows.MessageBox]::Show($window, $Message, $Title, $Button, $Image)
}

$controls = @{
    ReportsList         = Get-Control -Name ReportsList
    NavigationList      = Get-Control -Name NavigationList
    ResultsGrid         = Get-Control -Name ResultsGrid
    ExecutionLogTextBox = Get-Control -Name ExecutionLogTextBox
    ApplicationTitleText = Get-Control -Name ApplicationTitleText
    SectionTitleText    = Get-Control -Name SectionTitleText
    SectionDescriptionText = Get-Control -Name SectionDescriptionText
    DependencySummaryText = Get-Control -Name DependencySummaryText
    BusyIndicatorPanel  = Get-Control -Name BusyIndicatorPanel
    BusyStatusText      = Get-Control -Name BusyStatusText
    BusyProgressBar     = Get-Control -Name BusyProgressBar
    ConnectADButton     = Get-Control -Name ConnectADButton
    ConnectEntraButton  = Get-Control -Name ConnectEntraButton
    ConnectExchangeButton = Get-Control -Name ConnectExchangeButton
    RunReportButton     = Get-Control -Name RunReportButton
    RunMenuReportsButton = Get-Control -Name RunMenuReportsButton
    ExportCsvButton     = Get-Control -Name ExportCsvButton
    ExportExcelButton   = Get-Control -Name ExportExcelButton
    ExportHtmlButton    = Get-Control -Name ExportHtmlButton
    ClearResultsButton  = Get-Control -Name ClearResultsButton
    OpenReportsButton   = Get-Control -Name OpenReportsButton
    OpenLastExportButton = Get-Control -Name OpenLastExportButton
    OpenLogsButton      = Get-Control -Name OpenLogsButton
    HealthCheckButton   = Get-Control -Name HealthCheckButton
    ReportSearchBox     = Get-Control -Name ReportSearchBox
    ReportStatusFilter  = Get-Control -Name ReportStatusFilter
    ReportRiskFilter    = Get-Control -Name ReportRiskFilter
    ShowPlannedReportsCheckBox = Get-Control -Name ShowPlannedReportsCheckBox
    ADStatusText        = Get-Control -Name ADStatusText
    EntraStatusText     = Get-Control -Name EntraStatusText
    ExchangeStatusText  = Get-Control -Name ExchangeStatusText
    LastRunText         = Get-Control -Name LastRunText
    ResultCountText     = Get-Control -Name ResultCountText
    ReportLogGrid       = Get-Control -Name ReportLogGrid
    ReportsGroup        = Get-Control -Name ReportsGroup
    OverviewGroup       = Get-Control -Name OverviewGroup
    OverviewContentGrid = Get-Control -Name OverviewContentGrid
    OverviewTextPanel   = Get-Control -Name OverviewTextPanel
    PieColumn           = Get-Control -Name PieColumn
    PieHost             = Get-Control -Name PieHost
    PieCanvas           = Get-Control -Name PieCanvas
    SectionMetricsText  = Get-Control -Name SectionMetricsText
    SectionActionsText  = Get-Control -Name SectionActionsText
    LegendPanel         = Get-Control -Name LegendPanel
    LogGroup            = Get-Control -Name LogGroup
    ReportsColumn       = Get-Control -Name ReportsColumn
    OverviewColumn      = Get-Control -Name OverviewColumn
    LogColumn           = Get-Control -Name LogColumn
    ReportLogContainerRow = Get-Control -Name ReportLogContainerRow
    ReportsRow          = Get-Control -Name ReportsRow
    OverviewRow         = Get-Control -Name OverviewRow
    LogRow              = Get-Control -Name LogRow
    SidebarColumn       = Get-Control -Name SidebarColumn
}

if ($controls.ApplicationTitleText) {
    $controls.ApplicationTitleText.Text = $script:AppSettings.ApplicationName
}

function Add-UiLog {
    param([Parameter(Mandatory)][string]$Message)
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $controls.ExecutionLogTextBox.AppendText("[$timestamp] $Message`r`n")
    if ($controls.ExecutionLogTextBox.Text.Length -gt $script:MaxUiLogCharacters) {
        $trimmedText = $controls.ExecutionLogTextBox.Text.Substring($controls.ExecutionLogTextBox.Text.Length - $script:MaxUiLogCharacters)
        $controls.ExecutionLogTextBox.Text = "... older UI log entries trimmed; full history is available in Logs ...`r`n$trimmedText"
    }
    $controls.ExecutionLogTextBox.ScrollToEnd()
}

function Set-BusyState {
    param(
        [Parameter(Mandatory)]
        [bool]$Busy,

        [bool]$RefreshNavigationView = $true,

        [string]$Message = ''
    )

    $script:IsBusy = $Busy
    $isEnabled = -not $Busy
    foreach ($buttonName in @('ConnectADButton', 'ConnectEntraButton', 'ConnectExchangeButton', 'RunReportButton', 'RunMenuReportsButton', 'ExportCsvButton', 'ExportExcelButton', 'ExportHtmlButton', 'ClearResultsButton', 'OpenReportsButton', 'OpenLastExportButton', 'OpenLogsButton', 'HealthCheckButton')) {
        if ($controls[$buttonName]) {
            $controls[$buttonName].IsEnabled = $isEnabled
        }
    }

    $controls.NavigationList.IsEnabled = $isEnabled
    foreach ($controlName in @('ReportSearchBox', 'ReportStatusFilter', 'ReportRiskFilter', 'ShowPlannedReportsCheckBox')) {
        if ($controls[$controlName]) {
            $controls[$controlName].IsEnabled = $isEnabled
        }
    }

    if ($controls.BusyIndicatorPanel) {
        $controls.BusyIndicatorPanel.Visibility = if ($Busy) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    }
    if ($controls.BusyStatusText) {
        $controls.BusyStatusText.Text = if ($Message) { $Message } else { if ($Busy) { 'Working...' } else { 'Ready' } }
    }
    $window.Cursor = if ($Busy) { [System.Windows.Input.Cursors]::Wait } else { $null }
    if ($Message) {
        $controls.LastRunText.Text = $Message
    }

    if (-not $Busy -and $RefreshNavigationView) {
        Update-NavigationView
    }
}

function Set-Results {
    param(
        [object[]]$Data,
        [string]$ReportName
    )

    $script:CurrentResults = @($Data)
    $script:CurrentReportName = $ReportName
    if ($script:CurrentResults.Count -gt $script:LargeResultWarningThreshold) {
        Add-UiLog "WARNING: large result set detected ($($script:CurrentResults.Count) rows). UI rendering may be slower; exports remain available."
        Write-HIRLog -Module GUI -Action SetResults -Level WARNING -Message "Large result set loaded in UI: $($script:CurrentResults.Count) rows."
    }
    $controls.ResultsGrid.ItemsSource = $null
    $controls.ResultsGrid.ItemsSource = $script:CurrentResults
    $controls.LastRunText.Text = 'Last run: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    $controls.ResultCountText.Text = 'Results: {0}' -f $script:CurrentResults.Count
    $hasResults = $script:CurrentResults.Count -gt 0
    $controls.ExportCsvButton.IsEnabled = $hasResults
    $controls.ExportExcelButton.IsEnabled = $hasResults
    $controls.ExportHtmlButton.IsEnabled = $hasResults
}

function Set-PreviewRows {
    param(
        [object[]]$Data
    )

    $script:CurrentResults = @()
    $script:CurrentReportName = $null
    $controls.ResultsGrid.ItemsSource = $null
    $controls.ResultsGrid.ItemsSource = @($Data)
    $controls.ResultCountText.Text = 'Results: 0'
    $controls.ExportCsvButton.IsEnabled = $false
    $controls.ExportExcelButton.IsEnabled = $false
    $controls.ExportHtmlButton.IsEnabled = $false
}

function Get-SectionManagementRows {
    param([Parameter(Mandatory)][string]$Section)

    switch ($Section) {
        'Dashboard' {
            @(
                [pscustomobject]@{ Menu = 'Active Directory'; Purpose = 'Pilot on-premises identity inventory and hygiene reports.'; NextStep = 'Click the green pie slice or select Active Directory.' }
                [pscustomobject]@{ Menu = 'Executive Summary'; Purpose = 'Review high-level roadmap, risk and audit score items.'; NextStep = 'Filter Critical/High risks and track planned reports.' }
                [pscustomobject]@{ Menu = 'Entra ID'; Purpose = 'Run Microsoft Graph identity, guest, sync and license reports.'; NextStep = 'Connect Entra ID, then choose a report.' }
                [pscustomobject]@{ Menu = 'Exchange Online'; Purpose = 'Audit mailbox inventory, forwarding and GAL visibility.'; NextStep = 'Connect Exchange Online, then run mailbox reports.' }
                [pscustomobject]@{ Menu = 'Hybrid Reports'; Purpose = 'Compare AD and cloud/Exchange attributes for hybrid inconsistencies.'; NextStep = 'Connect required services, then run hybrid checks.' }
                [pscustomobject]@{ Menu = 'Security / IAM'; Purpose = 'Review privileged access, roles and identity hygiene.'; NextStep = 'Use IAM reports for evidence and remediation planning.' }
                [pscustomobject]@{ Menu = 'Exports'; Purpose = 'Export current report results to CSV, Excel or HTML.'; NextStep = 'Run any report first, then export.' }
                [pscustomobject]@{ Menu = 'Settings'; Purpose = 'Review JSON configuration files.'; NextStep = 'Open Config files from the project folder.' }
                [pscustomobject]@{ Menu = 'Debug / Health'; Purpose = 'Validate modules, TLS, config files and local runtime state.'; NextStep = 'Run Health Check after installation or errors.' }
            )
        }
        'Active Directory' {
            @(
                [pscustomobject]@{ Action = 'Connect AD'; Scope = 'Connection'; Notes = 'Validate ActiveDirectory module and domain controller access.' }
                [pscustomobject]@{ Action = 'Audit disabled users'; Scope = 'Users'; Notes = 'Run Disabled AD Users report.' }
                [pscustomobject]@{ Action = 'Audit locked/inactive accounts'; Scope = 'Users'; Notes = 'Use Locked AD Users and Inactive AD Users reports.' }
                [pscustomobject]@{ Action = 'Review privileged groups'; Scope = 'Security'; Notes = 'Run Domain Admins Members and AdminCount reports.' }
                [pscustomobject]@{ Action = 'Export evidence'; Scope = 'Reports'; Notes = 'Export current report to CSV, Excel or HTML.' }
            )
        }
        'Executive Summary' {
            @(
                [pscustomobject]@{ Action = 'Review critical risks'; Scope = 'Summary'; Notes = 'Filter Critical and High risk reports.' }
                [pscustomobject]@{ Action = 'Track planned reports'; Scope = 'Roadmap'; Notes = 'Use status filter Planned to see next audit additions.' }
                [pscustomobject]@{ Action = 'Generate evidence'; Scope = 'Exports'; Notes = 'Executive summary HTML and risk scoring are planned.' }
            )
        }
        'Hybrid Reports' {
            @(
                [pscustomobject]@{ Action = 'Connect AD'; Scope = 'Prerequisite'; Notes = 'Required for on-premises attributes.' }
                [pscustomobject]@{ Action = 'Connect Exchange Online'; Scope = 'Prerequisite'; Notes = 'Required for recipient and GAL visibility checks.' }
                [pscustomobject]@{ Action = 'Check disabled users visible in GAL'; Scope = 'Identity lifecycle'; Notes = 'Run hybrid GAL visibility report.' }
                [pscustomobject]@{ Action = 'Check Exchange attributes'; Scope = 'Directory hygiene'; Notes = 'Review missing mailNickname and proxyAddresses.' }
            )
        }
        'Entra ID' {
            @(
                [pscustomobject]@{ Action = 'Connect Entra ID'; Scope = 'Connection'; Notes = 'Authenticate with Microsoft Graph read scopes.' }
                [pscustomobject]@{ Action = 'Audit cloud-only users'; Scope = 'Users'; Notes = 'Identify accounts managed only in Entra ID.' }
                [pscustomobject]@{ Action = 'Audit guests'; Scope = 'External identities'; Notes = 'Review guest users and external state.' }
                [pscustomobject]@{ Action = 'Audit licensing'; Scope = 'Licenses'; Notes = 'Review licensed and unlicensed users.' }
            )
        }
        'Exchange Online' {
            @(
                [pscustomobject]@{ Action = 'Connect Exchange Online'; Scope = 'Connection'; Notes = 'Start Exchange Online PowerShell session.' }
                [pscustomobject]@{ Action = 'Review mailbox inventory'; Scope = 'Mailboxes'; Notes = 'Run user/shared mailbox reports.' }
                [pscustomobject]@{ Action = 'Audit forwarding'; Scope = 'Security'; Notes = 'Find mailboxes with forwarding enabled.' }
                [pscustomobject]@{ Action = 'Audit GAL visibility'; Scope = 'Recipients'; Notes = 'Review recipients hidden from address lists.' }
            )
        }
        'Security / IAM' {
            @(
                [pscustomobject]@{ Action = 'Review privileged AD accounts'; Scope = 'AD'; Notes = 'Domain Admins and AdminCount reports.' }
                [pscustomobject]@{ Action = 'Review Entra admin roles'; Scope = 'Entra ID'; Notes = 'Run Entra Admin Role Members report.' }
                [pscustomobject]@{ Action = 'Audit password hygiene'; Scope = 'AD'; Notes = 'Run Password Never Expires report.' }
                [pscustomobject]@{ Action = 'Export IAM evidence'; Scope = 'Compliance'; Notes = 'Export reports for review.' }
            )
        }
        'Exports' {
            @(
                [pscustomobject]@{ Action = 'Export CSV'; Scope = 'Reports'; Notes = 'No extra module required.' }
                [pscustomobject]@{ Action = 'Export Excel'; Scope = 'Reports'; Notes = 'Requires ImportExcel module.' }
                [pscustomobject]@{ Action = 'Export HTML'; Scope = 'Reports'; Notes = 'Uses Templates\\report-template.html.' }
            )
        }
        'Settings' {
            @(
                [pscustomobject]@{ Action = 'Edit connections.json'; Scope = 'Configuration'; Notes = Join-Path $script:RootPath 'Config\connections.json' }
                [pscustomobject]@{ Action = 'Edit appsettings.json'; Scope = 'Configuration'; Notes = Join-Path $script:RootPath 'Config\appsettings.json' }
                [pscustomobject]@{ Action = 'Configure reports.json'; Scope = 'Catalog'; Notes = Join-Path $script:RootPath 'Config\reports.json' }
                [pscustomobject]@{ Action = 'Configure planned reports'; Scope = 'Catalog'; Notes = Join-Path $script:RootPath 'Config\planned-reports.json' }
            )
        }
        'Debug / Health' {
            @(
                [pscustomobject]@{ Action = 'Run Health Check'; Scope = 'Diagnostics'; Notes = 'Validate local prerequisites, config files and report catalog.' }
                [pscustomobject]@{ Action = 'Open Logs'; Scope = 'Troubleshooting'; Notes = Join-Path $script:RootPath 'Logs' }
                [pscustomobject]@{ Action = 'Open Reports'; Scope = 'Evidence'; Notes = Join-Path $script:RootPath 'Reports' }
                [pscustomobject]@{ Action = 'Check modules'; Scope = 'Dependencies'; Notes = 'ActiveDirectory, Microsoft.Graph, ExchangeOnlineManagement, ImportExcel.' }
            )
        }
        default {
            @(
                [pscustomobject]@{ Action = 'Select a menu'; Scope = 'Navigation'; Notes = 'Choose AD, Entra, Exchange, Hybrid or Security.' }
                [pscustomobject]@{ Action = 'Connect services'; Scope = 'Prerequisites'; Notes = 'Use the connection buttons before cloud/on-prem reports.' }
                [pscustomobject]@{ Action = 'Run report'; Scope = 'Audit'; Notes = 'Select a report and click Run Report.' }
            )
        }
    }
}

function Invoke-HealthCheck {
    [CmdletBinding()]
    param()
    $checks = @(Get-HIRHealthCheckData -AdStatusText $controls.ADStatusText.Text -ExchangeStatusText $controls.ExchangeStatusText.Text)
    Set-Results -Data $checks -ReportName 'Health Check'
    Update-HealthCheckVisual -Checks $checks
    Add-UiLog "Health check completed. Checks: $($checks.Count)"
}

function Open-HIRFolder {
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $script:RootPath $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }

    Start-Process -FilePath explorer.exe -ArgumentList "`"$path`""
    Add-UiLog "Opened folder: $path"
}

function Get-FlatReportItems {
    param(
        [AllowNull()]
        [object]$InputObject
    )

    foreach ($entry in @($InputObject)) {
        if ($null -eq $entry) {
            continue
        }

        if ($entry -is [System.Array]) {
            foreach ($nestedEntry in $entry) {
                Get-FlatReportItems -InputObject $nestedEntry
            }
            continue
        }

        if ($entry.PSObject.Properties.Name -contains 'Id') {
            $entry
        }
    }
}

function Initialize-ReportCatalog {
    $flatCatalog = @(Get-FlatReportItems -InputObject $script:ReportCatalog)
    foreach ($report in $flatCatalog) {
        $label = if ($report.Implemented -eq $true) {
            $report.DisplayName
        }
        else {
            '{0} (planned)' -f $report.DisplayName
        }

        if ($report.PSObject.Properties.Name -contains 'DisplayLabel') {
            $report.DisplayLabel = $label
        }
        else {
            $report | Add-Member -MemberType NoteProperty -Name DisplayLabel -Value $label
        }
    }

    $script:ReportCatalog = @($flatCatalog)
    Write-HIRLog -Module GUI -Action Catalog -Level INFO -Message "Report catalog normalized with $($script:ReportCatalog.Count) reports."
}

function New-ReportListItem {
    param(
        [Parameter(Mandatory)]
        [object]$Report
    )

    $item = New-Object System.Windows.Controls.ListBoxItem
    $displayLabel = if ($Report.PSObject.Properties.Name -contains 'DisplayLabel') {
        $Report.DisplayLabel
    }
    elseif ($Report.PSObject.Properties.Name -contains 'DisplayName') {
        $Report.DisplayName
    }
    else {
        $Report.ToString()
    }

    $risk = if ($Report.PSObject.Properties.Name -contains 'RiskLevel' -and $Report.RiskLevel) { $Report.RiskLevel } else { 'Low' }
    $priority = if ($Report.PSObject.Properties.Name -contains 'Priority' -and $Report.Priority) { $Report.Priority } else { 'Low' }
    $item.Content = '[{0}/{1}] {2}' -f $risk, $priority, $displayLabel
    $item.Tag = $Report
    $item.Padding = [System.Windows.Thickness]::new(8, 5, 8, 5)
    if ($risk -eq 'Critical') {
        $item.FontWeight = [System.Windows.FontWeights]::SemiBold
        $item.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(192, 57, 43))
    }
    if ($Report.Implemented -ne $true) {
        if ($risk -ne 'Critical') {
            $item.Foreground = [System.Windows.Media.Brushes]::Gray
        }
        $item.ToolTip = 'Planned report. Not executable yet. Risk={0}; Priority={1}; Note={2}' -f $risk, $priority, $Report.Note
    }
    else {
        $item.ToolTip = '{0} | {1} | Risk={2}; Priority={3}; Note={4}' -f $Report.Category, $Report.Id, $risk, $priority, $Report.Note
    }

    $item
}

function Get-ComboBoxContent {
    param([AllowNull()][object]$ComboBox)

    if (-not $ComboBox -or -not $ComboBox.SelectedItem) {
        return ''
    }

    if ($ComboBox.SelectedItem.PSObject.Properties.Name -contains 'Content') {
        return $ComboBox.SelectedItem.Content.ToString()
    }

    $ComboBox.SelectedItem.ToString()
}

function Save-PlannedReportVisibility {
    param([Parameter(Mandatory)][bool]$Visible)

    $script:PlannedReportSettings.ShowPlannedReports = $Visible
    $path = Join-Path $script:RootPath 'Config\planned-reports.json'
    $script:PlannedReportSettings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Initialize-PlannedReportToggle {
    $visible = if ($script:PlannedReportSettings.PSObject.Properties.Name -contains 'ShowPlannedReports') {
        [bool]$script:PlannedReportSettings.ShowPlannedReports
    }
    else {
        $true
    }

    $controls.ShowPlannedReportsCheckBox.IsChecked = $visible
}

function Test-HIRReportCanRun {
    param([AllowNull()][object]$Report)

    if (-not $Report) {
        return $false
    }

    if ($Report.Implemented -eq $true) {
        return $true
    }

    $allowPlanned = if ($script:PlannedReportSettings.PSObject.Properties.Name -contains 'AllowRunPlannedReports') {
        [bool]$script:PlannedReportSettings.AllowRunPlannedReports
    }
    else {
        $false
    }

    if (-not $allowPlanned) {
        return $false
    }

    [bool](Get-Command -Name $Report.Function -ErrorAction SilentlyContinue)
}

function Get-FilteredReports {
    param(
        [AllowNull()]
        [object]$Reports
    )

    $items = @(Get-FlatReportItems -InputObject $Reports)
    $search = if ($controls.ReportSearchBox -and $null -ne $controls.ReportSearchBox.Text) { $controls.ReportSearchBox.Text.Trim() } else { '' }
    $statusFilter = Get-ComboBoxContent -ComboBox $controls.ReportStatusFilter
    $riskFilter = Get-ComboBoxContent -ComboBox $controls.ReportRiskFilter
    $showPlanned = [bool]$controls.ShowPlannedReportsCheckBox.IsChecked

    if (-not $showPlanned) {
        $items = @($items | Where-Object { $_.Implemented -eq $true })
    }

    if ($statusFilter -eq 'Implemented') {
        $items = @($items | Where-Object { $_.Implemented -eq $true })
    }
    elseif ($statusFilter -eq 'Planned') {
        $items = @($items | Where-Object { $_.Implemented -ne $true })
    }

    if ($riskFilter -and $riskFilter -ne 'All risks') {
        $items = @($items | Where-Object { $_.PSObject.Properties.Name -contains 'RiskLevel' -and $_.RiskLevel -eq $riskFilter })
    }

    if ($search) {
        $items = @($items | Where-Object {
            $haystack = @(
                $_.Id
                $_.DisplayName
                $_.Category
                $_.Function
                if ($_.PSObject.Properties.Name -contains 'RiskLevel') { $_.RiskLevel }
                if ($_.PSObject.Properties.Name -contains 'Priority') { $_.Priority }
                if ($_.PSObject.Properties.Name -contains 'Note') { $_.Note }
            ) -join ' '
            $haystack.IndexOf($search, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        })
    }

    $items
}

function Set-ReportList {
    param(
        [AllowNull()]
        [object]$Reports
    )

    $controls.ReportsList.Items.Clear()
    $flatReports = @(Get-FlatReportItems -InputObject $Reports)

    foreach ($report in $flatReports) {
        $controls.ReportsList.Items.Add((New-ReportListItem -Report $report)) | Out-Null
    }

    if ($controls.ReportsList.Items.Count -gt 0) {
        $implementedIndex = -1
        for ($index = 0; $index -lt $controls.ReportsList.Items.Count; $index++) {
            $item = $controls.ReportsList.Items[$index]
            if ($item.Tag -and $item.Tag.Implemented -eq $true) {
                $implementedIndex = $index
                break
            }
        }
        $controls.ReportsList.SelectedIndex = if ($implementedIndex -ge 0) { $implementedIndex } else { 0 }
    }
    else {
        $controls.ReportsList.SelectedIndex = -1
    }
}

function Update-ReportActionState {
    $selectedItem = $controls.ReportsList.SelectedItem
    $selectedReport = if ($selectedItem -and $selectedItem.Tag) { $selectedItem.Tag } else { $null }
    $selectedImplemented = Test-HIRReportCanRun -Report $selectedReport

    if (-not $script:IsBusy) {
        $controls.RunReportButton.IsEnabled = $selectedImplemented
    }

    if ($selectedReport -and $selectedReport.Implemented -ne $true) {
        $controls.LastRunText.Text = 'Selected report is planned and not executable yet.'
    }
}

function New-PieSlice {
    param(
        [double]$StartAngle,
        [double]$SweepAngle,
        [double]$Radius,
        [double]$Center,
        [System.Windows.Media.Brush]$Fill,
        [string]$ToolTip
    )

    if ($SweepAngle -ge 359.99) {
        $ellipse = New-Object System.Windows.Shapes.Ellipse
        $ellipse.Width = $Radius * 2
        $ellipse.Height = $Radius * 2
        $ellipse.Fill = $Fill
        $ellipse.Stroke = [System.Windows.Media.Brushes]::White
        $ellipse.StrokeThickness = 1
        $ellipse.ToolTip = $ToolTip
        [System.Windows.Controls.Canvas]::SetLeft($ellipse, $Center - $Radius)
        [System.Windows.Controls.Canvas]::SetTop($ellipse, $Center - $Radius)
        return $ellipse
    }

    $startRadians = [Math]::PI * $StartAngle / 180
    $endRadians = [Math]::PI * ($StartAngle + $SweepAngle) / 180
    $startPoint = [System.Windows.Point]::new($Center + $Radius * [Math]::Cos($startRadians), $Center + $Radius * [Math]::Sin($startRadians))
    $endPoint = [System.Windows.Point]::new($Center + $Radius * [Math]::Cos($endRadians), $Center + $Radius * [Math]::Sin($endRadians))
    $isLargeArc = $SweepAngle -gt 180

    $figure = New-Object System.Windows.Media.PathFigure
    $figure.StartPoint = [System.Windows.Point]::new($Center, $Center)
    $figure.Segments.Add((New-Object -TypeName System.Windows.Media.LineSegment -ArgumentList $startPoint, $true)) | Out-Null
    $figure.Segments.Add((New-Object -TypeName System.Windows.Media.ArcSegment -ArgumentList $endPoint, ([System.Windows.Size]::new($Radius, $Radius)), 0, ([bool]$isLargeArc), ([System.Windows.Media.SweepDirection]::Clockwise), $true)) | Out-Null
    $figure.Segments.Add((New-Object -TypeName System.Windows.Media.LineSegment -ArgumentList ([System.Windows.Point]::new($Center, $Center)), $true)) | Out-Null
    $figure.IsClosed = $true

    $geometry = New-Object System.Windows.Media.PathGeometry
    $geometry.Figures.Add($figure) | Out-Null

    $path = New-Object System.Windows.Shapes.Path
    $path.Data = $geometry
    $path.Fill = $Fill
    $path.Stroke = [System.Windows.Media.Brushes]::White
    $path.StrokeThickness = 1
    $path.ToolTip = $ToolTip
    $path
}

function Add-LegendItem {
    param(
        [string]$Label,
        [System.Windows.Media.Brush]$Brush,
        [string]$TargetSection
    )

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $row.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
    if ($TargetSection) {
        $row.Tag = $TargetSection
        $row.Cursor = [System.Windows.Input.Cursors]::Hand
        $row.ToolTip = "Open $TargetSection"
        $row.Add_MouseLeftButtonUp({
            param($sender, $eventArgs)
            if ($sender.Tag) {
                Select-NavigationSection -Section $sender.Tag.ToString()
            }
        })
    }

    $swatch = New-Object System.Windows.Shapes.Rectangle
    $swatch.Width = 10
    $swatch.Height = 10
    $swatch.Fill = $Brush
    $swatch.Margin = [System.Windows.Thickness]::new(0, 3, 6, 0)

    $text = New-Object System.Windows.Controls.TextBlock
    $text.Text = $Label
    $text.TextWrapping = [System.Windows.TextWrapping]::Wrap

    $row.Children.Add($swatch) | Out-Null
    $row.Children.Add($text) | Out-Null
    $controls.LegendPanel.Children.Add($row) | Out-Null
}

function Get-DashboardMenuSlices {
    $menuColors = @{
        'Hybrid Reports' = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(52, 152, 219))
        'Active Directory' = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(39, 174, 96))
        'Entra ID' = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(155, 89, 182))
        'Exchange Online' = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(22, 160, 133))
        'Security / IAM' = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(231, 76, 60))
        'Exports' = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(241, 196, 15))
        'Settings' = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(127, 140, 141))
        'Debug / Health' = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(52, 73, 94))
    }

    $sections = @(
        'Active Directory',
        'Executive Summary',
        'Entra ID',
        'Exchange Online',
        'Hybrid Reports',
        'Security / IAM',
        'Exports',
        'Settings',
        'Debug / Health'
    )

    foreach ($sectionName in $sections) {
        $sectionReports = @($script:ReportCatalog | Where-Object { $_.Category -eq $sectionName })
        $implemented = @($sectionReports | Where-Object { $_.Implemented -eq $true }).Count
        $planned = @($sectionReports | Where-Object { $_.Implemented -ne $true }).Count
        $weight = switch ($sectionName) {
            'Exports' { [Math]::Max(1, @($script:ReportCatalog | Where-Object { $_.Implemented -eq $true }).Count) }
            'Settings' { 1 }
            'Debug / Health' { 1 }
            default { [Math]::Max(1, $sectionReports.Count) }
        }

        [pscustomobject]@{
            Label = $sectionName
            Section = $sectionName
            Count = $weight
            Reports = $sectionReports.Count
            Implemented = $implemented
            Planned = $planned
            Brush = $menuColors[$sectionName]
        }
    }
}

function Update-SectionOverview {
    param(
        [Parameter(Mandatory)]
        [string]$Section,

        [object[]]$Reports
    )

    $reports = @($Reports | Where-Object { $null -ne $_ -and $_.PSObject.Properties.Name -contains 'Id' })
    $implemented = @($reports | Where-Object { $_.Implemented -eq $true }).Count
    $planned = @($reports | Where-Object { $_.Implemented -ne $true }).Count
    $critical = @($reports | Where-Object { $_.PSObject.Properties.Name -contains 'RiskLevel' -and $_.RiskLevel -eq 'Critical' }).Count
    $high = @($reports | Where-Object { $_.PSObject.Properties.Name -contains 'RiskLevel' -and $_.RiskLevel -eq 'High' }).Count
    $total = $reports.Count

    $controls.PieCanvas.Children.Clear()
    $controls.LegendPanel.Children.Clear()

    if ($Section -eq 'Dashboard') {
        $rootSlices = @(Get-DashboardMenuSlices)
        $rootTotal = ($rootSlices | Measure-Object -Property Count -Sum).Sum
        $startAngle = -90.0
        $radius = 52.0
        $center = 58.0

        foreach ($slice in $rootSlices | Where-Object { $_.Count -gt 0 }) {
            $sweep = 360.0 * $slice.Count / $rootTotal
            $tooltip = '{0}: {1} reports, {2} implemented, {3} planned' -f $slice.Label, $slice.Reports, $slice.Implemented, $slice.Planned
            $shape = New-PieSlice -StartAngle $startAngle -SweepAngle $sweep -Radius $radius -Center $center -Fill $slice.Brush -ToolTip $tooltip
            $shape.Tag = $slice.Section
            $shape.Cursor = [System.Windows.Input.Cursors]::Hand
            $shape.Add_MouseLeftButtonUp({
                param($sender, $eventArgs)
                if ($sender.Tag) {
                    Select-NavigationSection -Section $sender.Tag.ToString()
                }
            })
            $controls.PieCanvas.Children.Add($shape) | Out-Null

            $legendText = if ($slice.Reports -gt 0) {
                '{0}: {1} reports' -f $slice.Label, $slice.Reports
            }
            else {
                '{0}: tools' -f $slice.Label
            }
            Add-LegendItem -Label $legendText -Brush $slice.Brush -TargetSection $slice.Section
            $startAngle += $sweep
        }

        $controls.SectionMetricsText.Text = "Dashboard root menus`nMenus: $($rootSlices.Count)`nReports: $total`nImplemented: $implemented`nPlanned: $planned`nCritical/High: $critical/$high"
        $controls.SectionActionsText.Text = "Click a pie slice or legend row to open that menu.`nUse the left navigation for the same roots."
        return
    }

    if ($total -eq 0) {
        $controls.SectionMetricsText.Text = "Section: $Section`nNo report catalog entries for this section."
        $controls.SectionActionsText.Text = Get-SectionManagementOptions -Section $Section
        Add-LegendItem -Label 'No reports' -Brush ([System.Windows.Media.Brushes]::LightGray)
        $empty = New-Object System.Windows.Shapes.Ellipse
        $empty.Width = 104
        $empty.Height = 104
        $empty.Fill = [System.Windows.Media.Brushes]::LightGray
        $empty.Stroke = [System.Windows.Media.Brushes]::White
        $empty.StrokeThickness = 1
        [System.Windows.Controls.Canvas]::SetLeft($empty, 6)
        [System.Windows.Controls.Canvas]::SetTop($empty, 6)
        $controls.PieCanvas.Children.Add($empty) | Out-Null
        return
    }

    $implementedBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(39, 174, 96))
    $plannedBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(149, 165, 166))
    $startAngle = -90.0
    $radius = 52.0
    $center = 58.0

    $slices = @(
        [pscustomobject]@{ Label = 'Implemented'; Count = $implemented; Brush = $implementedBrush }
        [pscustomobject]@{ Label = 'Planned'; Count = $planned; Brush = $plannedBrush }
    ) | Where-Object { $_.Count -gt 0 }

    foreach ($slice in $slices) {
        $sweep = 360.0 * $slice.Count / $total
        $shape = New-PieSlice -StartAngle $startAngle -SweepAngle $sweep -Radius $radius -Center $center -Fill $slice.Brush -ToolTip ('{0}: {1}' -f $slice.Label, $slice.Count)
        $controls.PieCanvas.Children.Add($shape) | Out-Null
        Add-LegendItem -Label ('{0}: {1}' -f $slice.Label, $slice.Count) -Brush $slice.Brush
        $startAngle += $sweep
    }

    $connectionHint = switch ($Section) {
        'Active Directory' { $controls.ADStatusText.Text }
        'Entra ID' { $controls.EntraStatusText.Text }
        'Exchange Online' { $controls.ExchangeStatusText.Text }
        'Hybrid Reports' { '{0} | {1}' -f $controls.ADStatusText.Text, $controls.ExchangeStatusText.Text }
        default { 'Read-only reporting catalog' }
    }

    $controls.SectionMetricsText.Text = "Section: $Section`nReports: $total`nImplemented: $implemented`nPlanned: $planned`nCritical/High: $critical/$high`nStatus: $connectionHint"
    $controls.SectionActionsText.Text = Get-SectionManagementOptions -Section $Section
}

function Get-SectionManagementOptions {
    param([Parameter(Mandatory)][string]$Section)

    switch ($Section) {
        'Active Directory' {
            "Options:`n- Connect AD`n- Audit disabled/locked/inactive users`n- Review groups and privileged accounts`n- Export AD reports"
        }
        'Hybrid Reports' {
            "Options:`n- Connect AD + Exchange Online`n- Check GAL visibility mismatches`n- Review missing mailNickname/proxyAddresses`n- Export hybrid inconsistencies"
        }
        'Entra ID' {
            "Options:`n- Connect Entra ID`n- Audit synced/cloud-only/guest users`n- Review licensing and disabled accounts`n- Export Graph reports"
        }
        'Exchange Online' {
            "Options:`n- Connect Exchange Online`n- Audit mailbox types`n- Review forwarding and GAL visibility`n- Export mailbox reports"
        }
        'Security / IAM' {
            "Options:`n- Review Domain Admins/AdminCount`n- Audit privileged Entra roles`n- Check password and license hygiene`n- Export IAM evidence"
        }
        'Exports' {
            "Options:`n- Run a report`n- Export CSV / Excel / HTML`n- Reports folder: $((Join-Path $script:RootPath 'Reports'))"
        }
        'Settings' {
            "Options:`n- Edit appsettings.json`n- Edit connections.json`n- Configure tenant/search base/default days"
        }
        'Debug / Health' {
            "Suggestions:`n- Run Health Check after module installs`n- Open Logs after any error`n- Validate reports.json after adding reports`n- Confirm TLS 1.2 and PSGallery access"
        }
        'Executive Summary' {
            "Options:`n- Filter Critical/High risks`n- Track planned executive reports`n- Use exports for evidence`n- Planned: HTML summary, comparisons and run history"
        }
        default {
            "Options:`n- Select a section`n- Connect required services`n- Run read-only reports`n- Export evidence"
        }
    }
}

function Invoke-WpfDoEvents {
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [System.Windows.Threading.DispatcherOperationCallback]{
            param($dispatcherFrame)
            $dispatcherFrame.Continue = $false
            return $null
        },
        $frame
    ) | Out-Null
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

function New-InstallProgressWindow {
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$InitialMessage
    )

    $safeTitle = [System.Security.SecurityElement]::Escape($Title)
    $safeInitialMessage = [System.Security.SecurityElement]::Escape($InitialMessage)

    [xml]$progressXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$safeTitle"
        Height="300"
        Width="620"
        MinHeight="260"
        MinWidth="520"
        WindowStartupLocation="CenterOwner"
        WindowStyle="SingleBorderWindow"
        ResizeMode="CanResizeWithGrip"
        Background="#F5F7FA">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0">
            <TextBlock x:Name="ProgressTitleText" Text="$safeTitle" FontSize="18" FontWeight="SemiBold" Foreground="#102A43" TextWrapping="Wrap" />
            <TextBlock x:Name="ProgressStatusText" Text="$safeInitialMessage" Foreground="#52606D" Margin="0,6,0,0" TextWrapping="Wrap" />
        </StackPanel>
        <ProgressBar x:Name="InstallProgressBar" Grid.Row="1" Height="18" Margin="0,14,0,12" IsIndeterminate="True" />
        <TextBox x:Name="InstallLogTextBox" Grid.Row="2" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Background="White" BorderBrush="#D9E2EC" />
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button x:Name="CancelProgressButton" Content="Cancel" Width="100" Padding="10,6" Margin="0,0,8,0" />
            <Button x:Name="CloseProgressButton" Content="Close" Width="100" Padding="10,6" IsEnabled="False" />
        </StackPanel>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $progressXaml
    $progressWindow = [Windows.Markup.XamlReader]::Load($reader)
    $reader.Close()
    $progressWindow.Owner = $window

    [pscustomobject]@{
        Window      = $progressWindow
        StatusText  = $progressWindow.FindName('ProgressStatusText')
        ProgressBar = $progressWindow.FindName('InstallProgressBar')
        LogTextBox  = $progressWindow.FindName('InstallLogTextBox')
        CancelButton = $progressWindow.FindName('CancelProgressButton')
        CloseButton = $progressWindow.FindName('CloseProgressButton')
    }
}

function Add-InstallProgressLog {
    param(
        [Parameter(Mandatory)]
        [object]$Progress,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $timestamp = Get-Date -Format 'HH:mm:ss'
    $Progress.LogTextBox.AppendText("[$timestamp] $Message`r`n")
    if ($Progress.LogTextBox.Text.Length -gt $script:MaxUiLogCharacters) {
        $trimmedText = $Progress.LogTextBox.Text.Substring($Progress.LogTextBox.Text.Length - $script:MaxUiLogCharacters)
        $Progress.LogTextBox.Text = "... older install log entries trimmed ...`r`n$trimmedText"
    }
    $Progress.LogTextBox.ScrollToEnd()
}

function Invoke-InstallWithProgress {
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,

        [Parameter(Mandatory)]
        [string]$FriendlyName,

        [Parameter(Mandatory)]
        [ValidateSet('PowerShellGallery', 'WindowsCapability')]
        [string]$Source
    )

    if ($script:IsBusy) {
        Add-UiLog "Action ignored because another operation is already running."
        return $false
    }

    Set-BusyState -Busy $true -Message "Installing: $FriendlyName"
    $progress = New-InstallProgressWindow -Title "Installing $FriendlyName" -InitialMessage 'Preparing installation...'
    $installState = [pscustomobject]@{
        Completed = $false
        Success   = $false
        Message   = ''
        Tick      = 0
    }
    $deadline = (Get-Date).AddMinutes($script:InstallTimeoutMinutes)
    $helperModulePath = Join-Path $script:RootPath 'Modules\Core\Helpers.psm1'
    $job = $null
    try {
        $job = Start-Job -ArgumentList $helperModulePath, $ModuleName, $Source -ScriptBlock {
            param($HelperModulePath, $ModuleName, $Source)

            $ErrorActionPreference = 'Stop'
            Import-Module $HelperModulePath -Force -ErrorAction Stop

            if ($Source -eq 'WindowsCapability') {
                Install-HIRActiveDirectoryTools | Out-Null
            }
            else {
                Install-HIRPowerShellGalleryModule -Name $ModuleName | Out-Null
            }

            "Installation completed for $ModuleName."
        }
    }
    catch {
        Set-BusyState -Busy $false
        Add-UiLog "INSTALL ERROR: failed to start installation job: $($_.Exception.Message)"
        Write-HIRLog -Module GUI -Action InstallModule -Level ERROR -Message "Failed to start installation job: $($_.Exception.Message)"
        Show-HIRMessageBox -Message $_.Exception.Message -Title 'Installation job error' -Image Error | Out-Null
        return $false
    }

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)

    $finishInstall = {
        param(
            [bool]$Success,
            [string]$Message
        )

        if ($installState.Completed) {
            return
        }

        $installState.Completed = $true
        $installState.Success = $Success
        $installState.Message = $Message
        $timer.Stop()

        if ($job) {
            if ($job.State -in @('NotStarted', 'Running')) {
                Stop-Job -Job $job -ErrorAction SilentlyContinue
            }
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }

        $progress.ProgressBar.IsIndeterminate = $false
        $progress.ProgressBar.Value = if ($Success) { 100 } else { 0 }
        $progress.CancelButton.IsEnabled = $false
        $progress.CloseButton.IsEnabled = $true

        if ($Success) {
            $progress.StatusText.Text = "$FriendlyName installed successfully."
            Add-InstallProgressLog -Progress $progress -Message 'Installation finished successfully.'
            Add-UiLog "$FriendlyName installed successfully."
            Write-HIRLog -Module GUI -Action InstallModule -Level INFO -Message "$FriendlyName installed successfully."
        }
        else {
            $progress.StatusText.Text = "Installation failed for $FriendlyName."
            Add-InstallProgressLog -Progress $progress -Message "ERROR: $Message"
            Add-UiLog "INSTALL ERROR: $Message"
            Write-HIRLog -Module GUI -Action InstallModule -Level ERROR -Message $Message
        }
    }

    $progress.CancelButton.Add_Click({
        & $finishInstall $false 'Installation cancelled by user.'
    })
    $progress.CloseButton.Add_Click({ $progress.Window.Close() })
    $progress.Window.Add_Closing({
        param($sender, $eventArgs)

        if (-not $installState.Completed) {
            $eventArgs.Cancel = $true
            & $finishInstall $false 'Installation cancelled because the progress window was closed.'
        }
    })

    Add-InstallProgressLog -Progress $progress -Message 'Starting dependency installation.'
    Add-InstallProgressLog -Progress $progress -Message "Component: $FriendlyName"
    Add-InstallProgressLog -Progress $progress -Message "Source: $Source"

    $timer.Add_Tick({
        try {
            if ($installState.Completed) {
                return
            }

            $installState.Tick++
            $dots = '.' * (($installState.Tick % 4) + 1)
            $progress.StatusText.Text = "Installing $FriendlyName$dots"

            $partialOutput = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
            foreach ($line in $partialOutput) {
                Add-InstallProgressLog -Progress $progress -Message $line
            }

            if ((Get-Date) -gt $deadline) {
                & $finishInstall $false "Installation timed out after $script:InstallTimeoutMinutes minutes."
                return
            }

            if ($installState.Tick % 20 -eq 0) {
                Add-InstallProgressLog -Progress $progress -Message 'Installation still running. Waiting for PowerShellGet or Windows servicing...'
            }

            if ($job.State -in @('NotStarted', 'Running')) {
                return
            }

            $output = @()
            $errors = @()
            try {
                $output = @(Receive-Job -Job $job -ErrorAction Stop)
            }
            catch {
                $errors += $_.Exception.Message
            }

            if ($job.ChildJobs.Count -gt 0 -and $job.ChildJobs[0].Error.Count -gt 0) {
                $errors += @($job.ChildJobs[0].Error | ForEach-Object { $_.Exception.Message })
            }

            foreach ($line in $output) {
                Add-InstallProgressLog -Progress $progress -Message $line
            }

            if ($job.State -eq 'Completed' -and $errors.Count -eq 0) {
                & $finishInstall $true "$FriendlyName installed successfully."
                return
            }

            $errorMessage = if ($errors.Count -gt 0) { $errors -join ' | ' } else { "Installation job ended with state '$($job.State)'." }
            & $finishInstall $false $errorMessage
        }
        catch {
            & $finishInstall $false $_.Exception.Message
        }
    })

    $timer.Start()
    try {
        $progress.Window.ShowDialog() | Out-Null
    }
    finally {
        if (-not $installState.Completed) {
            & $finishInstall $false 'Installation interrupted.'
        }
        Set-BusyState -Busy $false
    }

    if ($installState.Success) {
        Show-HIRMessageBox -Message "$FriendlyName installed successfully." -Title 'Installation completed' -Image Information | Out-Null
        return $true
    }

    Show-HIRMessageBox -Message $installState.Message -Title 'Installation error' -Image Error | Out-Null
    return $false
}

function Install-RequiredFeature {
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,

        [string]$FriendlyName = $ModuleName,

        [ValidateSet('PowerShellGallery', 'WindowsCapability')]
        [string]$Source = 'PowerShellGallery'
    )

    if (Test-HIRModuleInstalled -Name $ModuleName) {
        Update-DependencySummary
        return $true
    }

    $commandPreview = if ($Source -eq 'WindowsCapability') {
        'Install-WindowsFeature RSAT-AD-PowerShell or Add-WindowsCapability Rsat.ActiveDirectory.DS-LDS.Tools'
    }
    else {
        "Install-Module -Name $ModuleName -Scope CurrentUser -Repository PSGallery -Force -AllowClobber"
    }

    $message = @"
The required component is not installed:

$FriendlyName

Proposed command:
$commandPreview

Administrative rights may be required for Windows capabilities.

Do you want $($script:AppSettings.ApplicationName) to install it now?
"@

    $answer = Show-HIRMessageBox -Message $message -Title 'Install required module' -Button YesNo -Image Question
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) {
        Add-UiLog "Installation skipped for $FriendlyName."
        return $false
    }

    Add-UiLog "Installation approved for $FriendlyName."
    Write-HIRLog -Module GUI -Action InstallModule -Level INFO -Message "Installation approved for $FriendlyName."
    $installed = Invoke-InstallWithProgress -ModuleName $ModuleName -FriendlyName $FriendlyName -Source $Source
    Update-DependencySummary
    return $installed
}

function Ensure-ReportDependencies {
    param(
        [Parameter(Mandatory)]
        [object]$Report
    )

    switch -Wildcard ($Report.Id) {
        'AD.*' {
            return Install-RequiredFeature -ModuleName ActiveDirectory -FriendlyName 'RSAT Active Directory PowerShell tools' -Source WindowsCapability
        }
        'Hybrid.*' {
            if (-not (Install-RequiredFeature -ModuleName ActiveDirectory -FriendlyName 'RSAT Active Directory PowerShell tools' -Source WindowsCapability)) { return $false }
            if (-not (Install-RequiredFeature -ModuleName ExchangeOnlineManagement -FriendlyName 'Exchange Online PowerShell module')) { return $false }
            return $true
        }
        'Entra.AdminRoleMembers' {
            return Install-RequiredFeature -ModuleName Microsoft.Graph.Identity.DirectoryManagement -FriendlyName 'Microsoft Graph Directory Management module'
        }
        'Entra.Groups' {
            return Install-RequiredFeature -ModuleName Microsoft.Graph.Groups -FriendlyName 'Microsoft Graph Groups module'
        }
        'Entra.*' {
            return Install-RequiredFeature -ModuleName Microsoft.Graph.Users -FriendlyName 'Microsoft Graph Users module'
        }
        'Exchange.*' {
            return Install-RequiredFeature -ModuleName ExchangeOnlineManagement -FriendlyName 'Exchange Online PowerShell module'
        }
        default {
            return $true
        }
    }
}

function Update-ResponsiveLayout {
    $width = $window.ActualWidth
    if ($width -lt 900) {
        $controls.SidebarColumn.Width = [System.Windows.GridLength]::new(165)
        $controls.ReportLogContainerRow.Height = [System.Windows.GridLength]::new(430)
        $controls.ReportsColumn.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $controls.OverviewColumn.Width = [System.Windows.GridLength]::new(0)
        $controls.LogColumn.Width = [System.Windows.GridLength]::new(0)
        $controls.ReportsRow.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $controls.OverviewRow.Height = [System.Windows.GridLength]::new(185)
        $controls.LogRow.Height = [System.Windows.GridLength]::new(120)
        [System.Windows.Controls.Grid]::SetColumn($controls.OverviewGroup, 0)
        [System.Windows.Controls.Grid]::SetRow($controls.OverviewGroup, 1)
        [System.Windows.Controls.Grid]::SetColumn($controls.LogGroup, 0)
        [System.Windows.Controls.Grid]::SetRow($controls.LogGroup, 2)
        $controls.ReportsGroup.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
        $controls.OverviewGroup.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
        $controls.PieColumn.Width = [System.Windows.GridLength]::new(120)
        $controls.PieHost.MinWidth = 92
        $controls.PieHost.MinHeight = 92
        $controls.OverviewTextPanel.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
    }
    else {
        $controls.ReportLogContainerRow.Height = if ($width -ge 1250) {
            [System.Windows.GridLength]::new(325)
        }
        else {
            [System.Windows.GridLength]::new(300)
        }
        $controls.ReportsColumn.Width = [System.Windows.GridLength]::new(2, [System.Windows.GridUnitType]::Star)
        $controls.OverviewColumn.Width = [System.Windows.GridLength]::new(1.2, [System.Windows.GridUnitType]::Star)
        $controls.LogColumn.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $controls.ReportsRow.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $controls.OverviewRow.Height = [System.Windows.GridLength]::new(0)
        $controls.LogRow.Height = [System.Windows.GridLength]::new(0)
        [System.Windows.Controls.Grid]::SetColumn($controls.OverviewGroup, 1)
        [System.Windows.Controls.Grid]::SetRow($controls.OverviewGroup, 0)
        [System.Windows.Controls.Grid]::SetColumn($controls.LogGroup, 2)
        [System.Windows.Controls.Grid]::SetRow($controls.LogGroup, 0)
        $controls.ReportsGroup.Margin = [System.Windows.Thickness]::new(0, 0, 14, 0)
        $controls.OverviewGroup.Margin = [System.Windows.Thickness]::new(0, 0, 14, 0)
        $controls.PieColumn.Width = [System.Windows.GridLength]::new(0.9, [System.Windows.GridUnitType]::Star)
        $controls.PieHost.MinWidth = 110
        $controls.PieHost.MinHeight = 110
        $controls.OverviewTextPanel.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    }
}

function Get-SelectedNavigationName {
    $selectedItem = $controls.NavigationList.SelectedItem
    if (-not $selectedItem) {
        return 'Dashboard'
    }

    $content = $selectedItem.Content
    if ($content) { return $content.ToString() }
    return 'Dashboard'
}

function Select-NavigationSection {
    param([Parameter(Mandatory)][string]$Section)

    for ($index = 0; $index -lt $controls.NavigationList.Items.Count; $index++) {
        $item = $controls.NavigationList.Items[$index]
        if ($item.Content -and $item.Content.ToString() -eq $Section) {
            if ($controls.NavigationList.SelectedIndex -eq $index) {
                Update-NavigationView
            }
            else {
                $controls.NavigationList.SelectedIndex = $index
            }
            $item.BringIntoView()
            return
        }
    }

    Add-UiLog "Navigation target not found: $Section"
}

function Get-SectionDescription {
    param([Parameter(Mandatory)][string]$Section)

    switch ($Section) {
        'Dashboard' { 'Root menu map. Click a pie slice to open the corresponding reporting area.' }
        'Hybrid Reports' { 'Cross-platform checks comparing on-premises Active Directory attributes with cloud and Exchange Online state.' }
        'Active Directory' { 'Read-only Active Directory user, group and computer reports.' }
        'Entra ID' { 'Microsoft Graph based reports for synced, cloud-only, guest, disabled and licensed users.' }
        'Exchange Online' { 'Exchange Online mailbox and recipient reports, including forwarding and GAL visibility checks.' }
        'Security / IAM' { 'Privileged access, administrative role and identity hygiene reports.' }
        'Exports' { 'Run a report first, then export current results to CSV, Excel or HTML in the Reports folder.' }
        'Settings' { 'Configuration is currently file based. Edit Config\\connections.json and Config\\appsettings.json as needed.' }
        'Debug / Health' { 'Local diagnostics, dependency checks, configuration validation and troubleshooting shortcuts.' }
        'Executive Summary' { 'High-level audit roadmap, planned risk scoring, run history and executive reporting.' }
        default { 'Select a report, connect to the required service, then run and export the results.' }
    }
}

function Get-ReportsForSection {
    param([Parameter(Mandatory)][string]$Section)

    if ($Section -eq 'Settings') {
        return
    }

    $selectedReports = if ($Section -eq 'Dashboard') {
        $script:ReportCatalog | Sort-Object Category, DisplayName
    }
    elseif ($Section -eq 'Executive Summary') {
        $script:ReportCatalog | Where-Object { $_.Category -eq 'Executive Summary' -or $_.RiskLevel -in @('Critical', 'High') } | Sort-Object RiskLevel, Priority, Category, DisplayName
    }
    elseif ($Section -eq 'Exports') {
        $script:ReportCatalog | Where-Object { $_.Implemented -eq $true -or $_.Category -eq 'Exports' } | Sort-Object Category, DisplayName
    }
    else {
        $script:ReportCatalog | Where-Object { $_.Category -eq $Section } | Sort-Object DisplayName
    }

    Get-FlatReportItems -InputObject $selectedReports
}

function Update-DependencySummary {
    $dependencyState = @(
        'AD={0}' -f ($(if (Test-HIRModuleInstalled -Name ActiveDirectory) { 'OK' } else { 'Missing' }))
        'Graph={0}' -f ($(if (Test-HIRModuleInstalled -Name Microsoft.Graph.Authentication) { 'OK' } else { 'Missing' }))
        'EXO={0}' -f ($(if (Test-HIRModuleInstalled -Name ExchangeOnlineManagement) { 'OK' } else { 'Missing' }))
        'Excel={0}' -f ($(if (Test-HIRModuleInstalled -Name ImportExcel) { 'OK' } else { 'Missing' }))
    )
    $controls.DependencySummaryText.Text = 'Dependencies: {0}' -f ($dependencyState -join ' | ')
}

function Update-NavigationView {
    $section = Get-SelectedNavigationName
    $rawReports = @(Get-FlatReportItems -InputObject (Get-ReportsForSection -Section $section))
    $reports = @(Get-FilteredReports -Reports $rawReports)
    $sectionChanged = $script:LastNavigationSection -ne $section
    $script:LastNavigationSection = $section

    $controls.SectionTitleText.Text = $section
    $controls.SectionDescriptionText.Text = Get-SectionDescription -Section $section
    $controls.ReportsGroup.Header = if ($rawReports.Count -gt 0) { "Reports ($($reports.Count)/$($rawReports.Count))" } else { 'Reports' }
    Set-ReportList -Reports $reports
    Update-SectionOverview -Section $section -Reports $reports

    $hasImplementedReports = @($reports | Where-Object { Test-HIRReportCanRun -Report $_ }).Count -gt 0
    $controls.RunMenuReportsButton.IsEnabled = $hasImplementedReports
    $controls.ExportCsvButton.IsEnabled = ($script:CurrentResults.Count -gt 0)
    $controls.ExportExcelButton.IsEnabled = ($script:CurrentResults.Count -gt 0)
    $controls.ExportHtmlButton.IsEnabled = ($script:CurrentResults.Count -gt 0)
    $controls.OpenLastExportButton.IsEnabled = [bool]($script:LastExportPath -and (Test-Path -LiteralPath $script:LastExportPath))

    if ($sectionChanged) {
        Add-UiLog "Navigation: $section"
        Set-PreviewRows -Data (Get-SectionManagementRows -Section $section)
    }

    Update-DependencySummary
    Update-ReportActionState
}

function Invoke-VisibleMenuReports {
    if ($script:IsBusy) {
        Add-UiLog 'Menu report run ignored because another operation is already running.'
        return
    }

    $selectedReports = @(
        foreach ($item in $controls.ReportsList.Items) {
            if ($item.Tag -and (Test-HIRReportCanRun -Report $item.Tag)) {
                $item.Tag
            }
        }
    )

    if ($selectedReports.Count -eq 0) {
        Show-HIRMessageBox -Message 'No executable report is visible with the current menu/filter selection.' -Image Information | Out-Null
        return
    }

    $answer = Show-HIRMessageBox -Message "Run $($selectedReports.Count) executable reports visible in this menu?`n`nThe result grid will show an execution summary." -Title 'Run menu reports' -Button YesNo -Image Question
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) {
        return
    }

    $summary = New-Object System.Collections.Generic.List[object]
    try {
        Set-BusyState -Busy $true -Message 'Running visible menu reports'
        foreach ($report in $selectedReports) {
            $started = Get-Date
            Add-UiLog "Running menu report: $($report.DisplayName)"
            try {
                if (-not (Ensure-ReportDependencies -Report $report)) {
                    $summary.Add([pscustomobject]@{ Report = $report.DisplayName; Status = 'Skipped'; Count = 0; DurationSeconds = 0; Risk = $report.RiskLevel; Note = 'Dependency missing or installation cancelled.' }) | Out-Null
                    continue
                }

                $command = Get-Command -Name $report.Function -ErrorAction Stop
                $params = @{}
                if ($command.Parameters.ContainsKey('SearchBase') -and $script:Connections.ActiveDirectory.SearchBase) { $params.SearchBase = $script:Connections.ActiveDirectory.SearchBase }
                if ($command.Parameters.ContainsKey('Server') -and $script:Connections.ActiveDirectory.Server) { $params.Server = $script:Connections.ActiveDirectory.Server }
                if ($command.Parameters.ContainsKey('Days') -and $script:AppSettings.PSObject.Properties.Name -contains 'DefaultInactiveDays') { $params.Days = [int]$script:AppSettings.DefaultInactiveDays }

                $results = @(& $command @params)
                $summary.Add([pscustomobject]@{ Report = $report.DisplayName; Status = 'Completed'; Count = $results.Count; DurationSeconds = [int]((Get-Date) - $started).TotalSeconds; Risk = $report.RiskLevel; Note = $report.Note }) | Out-Null
            }
            catch {
                $summary.Add([pscustomobject]@{ Report = $report.DisplayName; Status = 'Error'; Count = 0; DurationSeconds = [int]((Get-Date) - $started).TotalSeconds; Risk = $report.RiskLevel; Note = $_.Exception.Message }) | Out-Null
                Write-HIRLog -Module GUI -Action RunMenuReports -Level ERROR -Message "$($report.DisplayName): $($_.Exception.Message)"
            }
        }

        Set-Results -Data @($summary) -ReportName ('Menu Reports Summary - {0}' -f (Get-SelectedNavigationName))
        Add-UiLog "Menu report run completed. Reports: $($summary.Count)"
    }
    finally {
        Set-BusyState -Busy $false
    }
}

function Invoke-SelectedReport {
    if ($script:IsBusy) {
        Add-UiLog 'Report start ignored because another operation is already running.'
        return
    }

    $selectedItem = $controls.ReportsList.SelectedItem
    $selectedReport = if ($selectedItem -and $selectedItem.Tag) { $selectedItem.Tag } else { $null }
    if (-not $selectedReport) {
        Show-HIRMessageBox -Message 'Select a report first.' -Image Information | Out-Null
        return
    }

    if (-not (Test-HIRReportCanRun -Report $selectedReport)) {
        Show-HIRMessageBox -Message 'This report is planned but not implemented yet.' -Image Information | Out-Null
        return
    }

    if (-not (Get-Command -Name $selectedReport.Function -ErrorAction SilentlyContinue)) {
        Show-HIRMessageBox -Message "The selected report function is not implemented yet:`n$($selectedReport.Function)" -Title 'Report not available' -Image Information | Out-Null
        return
    }

    try {
        if (-not (Ensure-ReportDependencies -Report $selectedReport)) {
            Add-UiLog "Report cancelled because a dependency is missing: $($selectedReport.DisplayName)"
            return
        }

        Set-BusyState -Busy $true -Message "Running: $($selectedReport.DisplayName)"
        Add-UiLog "Running report: $($selectedReport.DisplayName)"
        Invoke-WpfDoEvents
        $functionName = $selectedReport.Function
        $command = Get-Command -Name $functionName -ErrorAction Stop
        $params = @{}

        if ($command.Parameters.ContainsKey('SearchBase') -and $script:Connections.ActiveDirectory.SearchBase) {
            $params.SearchBase = $script:Connections.ActiveDirectory.SearchBase
        }
        if ($command.Parameters.ContainsKey('Server') -and $script:Connections.ActiveDirectory.Server) {
            $params.Server = $script:Connections.ActiveDirectory.Server
        }
        if ($command.Parameters.ContainsKey('Days') -and $script:AppSettings.PSObject.Properties.Name -contains 'DefaultInactiveDays') {
            $params.Days = [int]$script:AppSettings.DefaultInactiveDays
        }

        $results = @(& $command @params)
        Set-Results -Data $results -ReportName $selectedReport.DisplayName
        Add-UiLog "Report completed. Results: $($results.Count)"
        Write-HIRLog -Module GUI -Action RunReport -Level INFO -Message "Report '$($selectedReport.DisplayName)' completed with $($results.Count) results."
    }
    catch {
        Add-UiLog "ERROR: $($_.Exception.Message)"
        Write-HIRLog -Module GUI -Action RunReport -Level ERROR -Message $_.Exception.Message
        Show-HIRMessageBox -Message $_.Exception.Message -Title 'Report error' -Image Error | Out-Null
    }
    finally {
        Set-BusyState -Busy $false
    }
}

function Export-CurrentReport {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Csv', 'Excel', 'Html')]
        [string]$Format
    )

    if ($script:IsBusy) {
        Add-UiLog 'Export ignored because another operation is already running.'
        return
    }

    if (-not $script:CurrentReportName) {
        Show-HIRMessageBox -Message 'Run a report before exporting.' -Image Information | Out-Null
        return
    }

    if ($Format -eq 'Excel' -and -not (Install-RequiredFeature -ModuleName ImportExcel -FriendlyName 'ImportExcel module')) {
        return
    }

    try {
        Set-BusyState -Busy $true -Message "Exporting: $Format"
        Invoke-WpfDoEvents
        $path = switch ($Format) {
            Csv {
                Export-HIRReportCsv -ReportName $script:CurrentReportName -Data $script:CurrentResults -RootPath $script:RootPath -Delimiter $script:AppSettings.Exports.CsvDelimiter
            }
            Excel {
                Export-HIRReportExcel -ReportName $script:CurrentReportName -Data $script:CurrentResults -RootPath $script:RootPath
            }
            Html {
                Export-HIRReportHtml -ReportName $script:CurrentReportName -Data $script:CurrentResults -RootPath $script:RootPath
            }
        }

        Add-UiLog "Export $Format completed: $path"
        $script:LastExportPath = $path
        $controls.OpenLastExportButton.IsEnabled = $true
        Show-HIRMessageBox -Message "Export completed:`n$path" -Title 'Export completed' -Image Information | Out-Null
    }
    catch {
        Add-UiLog "ERROR: $($_.Exception.Message)"
        Write-HIRLog -Module GUI -Action Export -Level ERROR -Message $_.Exception.Message
        Show-HIRMessageBox -Message $_.Exception.Message -Title 'Export error' -Image Error | Out-Null
    }
    finally {
        Set-BusyState -Busy $false
    }
}

$controls.NavigationList.Add_SelectionChanged({ Update-NavigationView })
$controls.ReportsList.Add_SelectionChanged({ Update-ReportActionState })
$controls.ReportSearchBox.Add_TextChanged({ Update-NavigationView })
$controls.ReportStatusFilter.Add_SelectionChanged({ Update-NavigationView })
$controls.ReportRiskFilter.Add_SelectionChanged({ Update-NavigationView })
$controls.ShowPlannedReportsCheckBox.Add_Checked({
    Save-PlannedReportVisibility -Visible $true
    Add-UiLog 'Planned reports are now visible.'
    Update-NavigationView
})
$controls.ShowPlannedReportsCheckBox.Add_Unchecked({
    Save-PlannedReportVisibility -Visible $false
    if ((Get-ComboBoxContent -ComboBox $controls.ReportStatusFilter) -eq 'Planned') {
        $controls.ReportStatusFilter.SelectedIndex = 0
    }
    Add-UiLog 'Planned reports are now hidden.'
    Update-NavigationView
})
$window.Add_SizeChanged({ Update-ResponsiveLayout })
$window.Dispatcher.Add_UnhandledException({
    param($sender, $eventArgs)

    $message = if ($eventArgs.Exception) { $eventArgs.Exception.Message } else { 'Unhandled WPF dispatcher error.' }
    Add-UiLog "ERROR: $message"
    Write-HIRLog -Module GUI -Action DispatcherUnhandledException -Level ERROR -Message $message
    try {
        Show-HIRMessageBox -Message $message -Title 'Application error' -Image Error | Out-Null
    }
    catch {
        # Avoid recursive dispatcher failures if the dialog subsystem is involved.
    }
    $eventArgs.Handled = $true
})
Initialize-ReportCatalog
Initialize-PlannedReportToggle
Update-ResponsiveLayout
Update-NavigationView

$controls.ConnectADButton.Add_Click({
    if ($script:IsBusy) {
        Add-UiLog 'AD connection ignored because another operation is already running.'
        return
    }

    try {
        if (-not (Install-RequiredFeature -ModuleName ActiveDirectory -FriendlyName 'RSAT Active Directory PowerShell tools' -Source WindowsCapability)) { return }
        Set-BusyState -Busy $true -Message 'Connecting AD'
        Invoke-WpfDoEvents
        Connect-HIRAD -Server $script:Connections.ActiveDirectory.Server | Out-Null
        $controls.ADStatusText.Text = 'AD: Connected'
        Add-UiLog 'Active Directory connection validated.'
    }
    catch {
        $controls.ADStatusText.Text = 'AD: Error'
        Add-UiLog "AD ERROR: $($_.Exception.Message)"
        Show-HIRMessageBox -Message $_.Exception.Message -Title 'AD connection error' -Image Error | Out-Null
    }
    finally {
        Set-BusyState -Busy $false -RefreshNavigationView $false
    }
})

$controls.ConnectEntraButton.Add_Click({
    if ($script:IsBusy) {
        Add-UiLog 'Entra connection ignored because another operation is already running.'
        return
    }

    try {
        if (-not (Install-RequiredFeature -ModuleName Microsoft.Graph.Authentication -FriendlyName 'Microsoft Graph Authentication module')) { return }
        Set-BusyState -Busy $true -Message 'Connecting Entra ID'
        Invoke-WpfDoEvents
        Connect-HIREntra -TenantId $script:Connections.MicrosoftGraph.TenantId -Scopes $script:Connections.MicrosoftGraph.Scopes | Out-Null
        $controls.EntraStatusText.Text = 'Entra ID: Connected'
        Add-UiLog 'Microsoft Graph connection established.'
    }
    catch {
        $controls.EntraStatusText.Text = 'Entra ID: Error'
        Add-UiLog "ENTRA ERROR: $($_.Exception.Message)"
        Show-HIRMessageBox -Message $_.Exception.Message -Title 'Entra connection error' -Image Error | Out-Null
    }
    finally {
        Set-BusyState -Busy $false
    }
})

$controls.ConnectExchangeButton.Add_Click({
    if ($script:IsBusy) {
        Add-UiLog 'Exchange connection ignored because another operation is already running.'
        return
    }

    try {
        if (-not (Install-RequiredFeature -ModuleName ExchangeOnlineManagement -FriendlyName 'Exchange Online PowerShell module')) { return }
        Set-BusyState -Busy $true -Message 'Connecting Exchange Online'
        Invoke-WpfDoEvents
        Connect-HIRExchangeOnline -UserPrincipalName $script:Connections.ExchangeOnline.UserPrincipalName -ShowBanner ([bool]$script:Connections.ExchangeOnline.ShowBanner) | Out-Null
        $controls.ExchangeStatusText.Text = 'Exchange Online: Connected'
        Add-UiLog 'Exchange Online connection established.'
    }
    catch {
        $controls.ExchangeStatusText.Text = 'Exchange Online: Error'
        Add-UiLog "EXCHANGE ERROR: $($_.Exception.Message)"
        Show-HIRMessageBox -Message $_.Exception.Message -Title 'Exchange connection error' -Image Error | Out-Null
    }
    finally {
        Set-BusyState -Busy $false
    }
})

$controls.RunReportButton.Add_Click({ Invoke-SelectedReport })
$controls.RunMenuReportsButton.Add_Click({ Invoke-VisibleMenuReports })
$controls.ExportCsvButton.Add_Click({ Export-CurrentReport -Format Csv })
$controls.ExportExcelButton.Add_Click({ Export-CurrentReport -Format Excel })
$controls.ExportHtmlButton.Add_Click({ Export-CurrentReport -Format Html })
$controls.ClearResultsButton.Add_Click({
    Set-Results -Data @() -ReportName $null
    Add-UiLog 'Results cleared.'
})
$controls.OpenReportsButton.Add_Click({ Open-HIRFolder -RelativePath 'Reports' })
$controls.OpenLastExportButton.Add_Click({
    if ($script:LastExportPath -and (Test-Path -LiteralPath $script:LastExportPath)) {
        Start-Process -FilePath $script:LastExportPath
        Add-UiLog "Opened last export: $script:LastExportPath"
    }
    else {
        Show-HIRMessageBox -Message 'No export has been generated in this session yet.' -Image Information | Out-Null
    }
})
$controls.OpenLogsButton.Add_Click({ Open-HIRFolder -RelativePath 'Logs' })
$controls.HealthCheckButton.Add_Click({
    param($sender, $eventArgs)

    if ($script:IsBusy) {
        Add-UiLog 'Health check ignored because another operation is already running.'
        return
    }

    try {
        Set-BusyState -Busy $true -Message 'Running health check'
        Invoke-WpfDoEvents
        Invoke-HealthCheck
    }
    catch {
        $message = $_.Exception.Message
        Add-UiLog "ERROR: Health check failed: $message"
        Write-HIRLog -Module GUI -Action HealthCheck -Level ERROR -Message $message
        Set-PreviewRows -Data @([pscustomobject]@{
            Area = 'Health Check'
            Check = 'Execution'
            Status = 'Error'
            Recommendation = $message
        })
        Show-HIRMessageBox -Message $message -Title 'Health check error' -Image Error | Out-Null
    }
    finally {
        Set-BusyState -Busy $false
    }
})

$window.Add_Closing({
    param($sender, $eventArgs)

    if ($script:IsBusy) {
        $answer = Show-HIRMessageBox -Message 'An operation is still running. Closing now can interrupt the current action. Do you want to close anyway?' -Title 'Operation in progress' -Button YesNo -Image Warning

        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) {
            $eventArgs.Cancel = $true
        }
    }
})

$window.Add_Closed({
    try {
        Write-HIRLog -Module GUI -Action Shutdown -Level INFO -Message 'Application closing. Releasing UI references.'
        $controls.ResultsGrid.ItemsSource = $null
        $controls.ReportsList.Items.Clear()
        $script:CurrentResults = @()
        $script:CurrentReportName = $null
        $script:ReportCatalog = @()
    }
    catch {
        # Best effort cleanup during process shutdown.
    }
})

Write-HIRLog -Module GUI -Action Startup -Level INFO -Message 'Application started.'
Add-UiLog "Application ready. Catalog loaded: $(@(Get-FlatReportItems -InputObject $script:ReportCatalog).Count) reports. Connect to the required services, select a report, then run it."
if ($HealthCheck) {
    Select-NavigationSection -Section 'Debug / Health'
    Invoke-HealthCheck
}
try {
    $window.ShowDialog() | Out-Null
}
catch {
    $messages = New-Object System.Collections.Generic.List[string]
    $exception = $_.Exception
    while ($exception) {
        $messages.Add($exception.Message) | Out-Null
        $exception = $exception.InnerException
    }

    $fullMessage = $messages -join ' | '
    Write-HIRLog -Module GUI -Action ShowDialog -Level ERROR -Message $fullMessage
    throw
}
