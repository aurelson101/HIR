Set-StrictMode -Version Latest

function Get-HIRJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Configuration file not found: $Path"
    }

    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-HIRAppSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    Get-HIRJsonFile -Path (Join-Path $RootPath 'Config\appsettings.json')
}

function Get-HIRConnections {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    Get-HIRJsonFile -Path (Join-Path $RootPath 'Config\connections.json')
}

function Get-HIRReportCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    Get-HIRJsonFile -Path (Join-Path $RootPath 'Config\reports.json')
}

function Get-HIRPlannedReportSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    $path = Join-Path $RootPath 'Config\planned-reports.json'
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{
            ShowPlannedReports   = $true
            AllowRunPlannedReports = $false
            PlannedReports       = @()
        }
    }

    Get-HIRJsonFile -Path $path
}

function Merge-HIRPlannedReportSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Reports,

        [AllowNull()]
        [object]$Settings
    )

    if (-not $Settings) {
        return $Reports
    }

    $plannedOverrides = @{}
    if ($Settings.PSObject.Properties.Name -contains 'PlannedReports') {
        foreach ($planned in @($Settings.PlannedReports)) {
            if ($planned.Id) {
                $plannedOverrides[$planned.Id] = $planned
            }
        }
    }

    $merged = foreach ($report in $Reports) {
        if ($report.Implemented -eq $true) {
            $report
            continue
        }

        $override = if ($plannedOverrides.ContainsKey($report.Id)) { $plannedOverrides[$report.Id] } else { $null }
        $visible = $true
        if ($override -and $override.PSObject.Properties.Name -contains 'Visible') {
            $visible = [bool]$override.Visible
        }
        if (-not $visible) {
            continue
        }

        foreach ($propertyName in @('Priority', 'RiskLevel', 'Note')) {
            if ($override -and $override.PSObject.Properties.Name -contains $propertyName -and $override.$propertyName) {
                $report.$propertyName = $override.$propertyName
            }
        }

        $report
    }

    @($merged)
}

Export-ModuleMember -Function Get-HIRAppSettings, Get-HIRConnections, Get-HIRReportCatalog, Get-HIRPlannedReportSettings, Merge-HIRPlannedReportSettings, Get-HIRJsonFile
