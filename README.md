# Hybrid Identity Reporter

![Hybrid Identity Reporter presentation](./HIR.png)

Current version: `0.2.0`

Hybrid Identity Reporter is a read-only PowerShell and WPF audit tool for hybrid identity environments.

It covers:

- On-premises Active Directory
- Microsoft Entra ID and Microsoft Graph
- Entra Connect synchronized identities
- Exchange Online recipients and mailboxes

## What It Does

The tool ships with a functional report catalog, a navigation-driven WPF interface, a console health-check mode, and export options for CSV, Excel, and HTML.

All implemented reports are read-only. The application does not perform remediation actions such as `Set-ADUser`, `Set-Mailbox`, or `Update-MgUser`.

## Requirements

- Windows workstation or administration server
- Windows PowerShell 5.1 for the WPF launcher
- Network access to domain controllers when using Active Directory reports
- Read-only permissions in Active Directory, Entra ID, and Exchange Online
- RSAT Active Directory PowerShell tools for AD reports

## PowerShell Dependencies

Install the modules you need from an elevated PowerShell session when required:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force -Confirm:$false
if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
    Register-PSRepository -Default
}
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
$installModuleParams = @{
    Scope = 'CurrentUser'
    Repository = 'PSGallery'
    Force = $true
    AllowClobber = $true
    Confirm = $false
}
if ((Get-Command Install-Module).Parameters.ContainsKey('AcceptLicense')) {
    $installModuleParams.AcceptLicense = $true
}
Install-Module Microsoft.Graph @installModuleParams
Install-Module ExchangeOnlineManagement @installModuleParams
Install-Module ImportExcel @installModuleParams
```

To install RSAT Active Directory tools on Windows client:

```powershell
Get-WindowsCapability -Online -Name Rsat.ActiveDirectory*
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

The first command is inventory-only. The second requires administrative rights.

The GUI checks dependencies at runtime and prompts before any installation. No module or Windows capability is installed without user confirmation.

The application enables TLS 1.2 for the current session before using PowerShell Gallery.

## Launch

From the project folder:

```cmd
launch.bat
```

Or directly from PowerShell:

```powershell
.\Start-Hybrid-Identity-Reporter.ps1
```

Additional modes:

```powershell
.\Start-Hybrid-Identity-Reporter.ps1 -Console
.\Start-Hybrid-Identity-Reporter.ps1 -HealthCheck
```

- `-Console` prints a project summary and the health check in the terminal.
- `-HealthCheck` opens the GUI and runs the health check automatically after startup.

In console mode, missing optional modules are reported as warnings so the command stays useful in lean environments.

If the script is started from a non-STA PowerShell session, it relaunches itself with STA because WPF requires it.

The project is portable. Paths are resolved from the script location, so the repository can be copied to another admin workstation without editing hardcoded paths.

## Connections

Use the top action buttons in the GUI:

- `Connect AD` validates the Active Directory connection and loads the RSAT module if needed.
- `Connect Entra ID` runs `Connect-MgGraph` with the configured read scopes.
- `Connect Exchange Online` runs `Connect-ExchangeOnline`.

Connection state appears in the status bar, and all actions are written to `Logs`.

## Navigation

The left navigation filters the catalog by area. The Dashboard is the root view and its pie chart opens the main menu sections.

- Dashboard
- Executive Summary
- Hybrid Reports
- Active Directory
- Entra ID
- Exchange Online
- Security / IAM
- Exports
- Settings
- Debug / Health

The report search box supports filtering by name, ID, category, risk, priority, and note. Status and risk filters help separate implemented reports from roadmap items.

The `Show planned` checkbox controls whether planned reports are visible in the catalog. The setting is stored in `Config/planned-reports.json`.

## Health Check

Use `Run Health Check` to validate local prerequisites without modifying any cloud or on-premises data.

It checks:

- PowerShell version and STA mode
- TLS 1.2 session status
- required modules
- project folders
- JSON configuration files
- report catalog and implemented function mapping
- portability and connection guidance

The health check view now shows a summary panel, status coloring, and a loading indicator for longer actions.

You can also run the project validation script before delivery:

```powershell
.\Tools\Test-HIRProject.ps1
```

## Reports

The current catalog includes Active Directory, Entra ID, Exchange Online, hybrid, and security/IAM reports.

The source of truth is `Config/reports.json`. Add a matching function in the appropriate `.psm1` module before marking a new report as implemented.

Planned report settings are stored in `Config/planned-reports.json`.

## Exports

After running a report, use:

- `Export CSV`
- `Export Excel`
- `Export HTML`

Exports are written to `Reports` and include:

- Report name
- Tool version
- Execution date
- Result count
- Report data

Excel export requires the `ImportExcel` module.

## Logs

Logs are written to `Logs\Hybrid-Identity-Reporter-yyyyMMdd.log`.

Each entry contains:

- Date
- Module
- Action
- Level
- Message

On-screen logs are trimmed to preserve memory during long sessions. The file logs remain the source of truth.

## Stability

Runtime safeguards are configured in `Config/appsettings.json`:

- `Runtime.InstallTimeoutMinutes`: stops a dependency installation job after the configured timeout
- `Runtime.MaxUiLogCharacters`: limits text retained in WPF text boxes
- `Runtime.LargeResultWarningThreshold`: warns when a large result set is loaded into the grid

The application also includes:

- single-operation guard to prevent duplicate executions
- busy cursor and disabled action buttons during long actions
- cancellation support for dependency installation jobs
- cleanup of installation jobs in `finally`
- cleanup of WPF item sources and in-memory results when the main window closes
- explicit STA relaunch behavior

## Project Layout

```text
Hybrid-Identity-Reporter/
|-- launch.bat
|-- Start-Hybrid-Identity-Reporter.ps1
|-- Config/
|   |-- appsettings.json
|   |-- connections.json
|   |-- planned-reports.json
|   `-- reports.json
|-- GUI/
|-- Modules/
|   |-- Core/
|   |-- AD/
|   |-- Entra/
|   |-- Exchange/
|   |-- Hybrid/
|   `-- Export/
|-- Reports/
|-- Archive/
|-- Logs/
|-- Tools/
|   `-- Test-HIRProject.ps1
|-- CHANGELOG.md
`-- Templates/
```

## Future Improvements

- Add report archive rotation based on `Config/appsettings.json`
- Add asynchronous report execution to keep the WPF UI responsive during long tenant queries
- Add application settings UI and a dedicated dependency health page
- Add Graph MFA method reporting using Microsoft Graph authentication methods endpoints
- Add optional script signing and an internal code-signing workflow
