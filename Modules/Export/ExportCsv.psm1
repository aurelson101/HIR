Set-StrictMode -Version Latest

function Export-HIRReportCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ReportName,

        [Parameter(Mandatory)]
        [object[]]$Data,

        [Parameter(Mandatory)]
        [string]$RootPath,

        [string]$Delimiter = ';'
    )

    Invoke-HIRSafeCommand -Module Export -Action 'CSV export' -ScriptBlock {
        $reportDirectory = Join-Path $RootPath 'Reports'
        if (-not (Test-Path -LiteralPath $reportDirectory)) { New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null }
        $safeName = New-HIRSafeFileName -Name $ReportName
        Copy-HIRExistingReportsToArchive -RootPath $RootPath -SafeReportName $safeName -Extension csv
        $path = Join-Path $reportDirectory ('{0}-{1}.csv' -f $safeName, (Get-Date -Format 'yyyyMMdd-HHmmss'))

        $metadata = @(
            [pscustomobject]@{ Metadata = 'ReportName'; Value = $ReportName }
            [pscustomobject]@{ Metadata = 'ExecutionDate'; Value = (Get-Date).ToString('s') }
            [pscustomobject]@{ Metadata = 'ResultCount'; Value = @($Data).Count }
        )

        $metadataCsv = $metadata | ConvertTo-Csv -NoTypeInformation -Delimiter $Delimiter
        Set-Content -LiteralPath $path -Value $metadataCsv -Encoding UTF8
        Add-Content -LiteralPath $path -Value '' -Encoding UTF8
        $csvData = $Data | ConvertTo-Csv -NoTypeInformation -Delimiter $Delimiter
        if ($csvData) {
            Add-Content -LiteralPath $path -Value $csvData -Encoding UTF8
        }
        $path
    }
}

Export-ModuleMember -Function Export-HIRReportCsv
