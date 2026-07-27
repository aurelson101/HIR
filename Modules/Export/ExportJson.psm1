Set-StrictMode -Version Latest

function Export-HIRReportJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ReportName,
        [Parameter(Mandatory)][object[]]$Data,
        [Parameter(Mandatory)][string]$RootPath
    )

    Invoke-HIRSafeCommand -Module Export -Action 'JSON export' -ScriptBlock {
        $settings = Get-HIRAppSettings -RootPath $RootPath
        $safeName = New-HIRSafeFileName -Name $ReportName
        $reportDirectory = Join-Path $RootPath 'Reports'
        if (-not (Test-Path -LiteralPath $reportDirectory)) { New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null }
        Copy-HIRExistingReportsToArchive -RootPath $RootPath -SafeReportName $safeName -Extension json
        $path = Join-Path $reportDirectory ('{0}-{1}.json' -f $safeName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
        [ordered]@{
            schemaVersion = 1
            reportName = $ReportName
            toolVersion = [string]$settings.Version
            executionDate = (Get-Date).ToString('o')
            resultCount = @($Data).Count
            data = @($Data)
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
        $path
    }
}

Export-ModuleMember -Function Export-HIRReportJson
