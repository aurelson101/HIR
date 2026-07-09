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

Export-ModuleMember -Function Get-HIRAppSettings, Get-HIRConnections, Get-HIRReportCatalog, Get-HIRJsonFile
