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
        $appSettings = Get-HIRAppSettings -RootPath $RootPath
        $toolVersion = if ($appSettings.PSObject.Properties.Name -contains 'Version') { [string]$appSettings.Version } else { 'Unknown' }
        $reportDirectory = Join-Path $RootPath 'Reports'
        if (-not (Test-Path -LiteralPath $reportDirectory)) { New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null }
        $safeName = New-HIRSafeFileName -Name $ReportName
        Copy-HIRExistingReportsToArchive -RootPath $RootPath -SafeReportName $safeName -Extension csv
        $path = Join-Path $reportDirectory ('{0}-{1}.csv' -f $safeName, (Get-Date -Format 'yyyyMMdd-HHmmss'))

        @($Data) | Export-Csv -LiteralPath $path -NoTypeInformation -Delimiter $Delimiter -Encoding UTF8
        if (-not ($appSettings.PSObject.Properties.Name -contains 'Exports') -or
            -not ($appSettings.Exports.PSObject.Properties.Name -contains 'WriteMetadataSidecar') -or
            $appSettings.Exports.WriteMetadataSidecar) {
            $metadataPath = [System.IO.Path]::ChangeExtension($path, '.metadata.json')
            [ordered]@{
                SchemaVersion = 1
                ReportName = $ReportName
                ToolVersion = $toolVersion
                ExecutionDate = (Get-Date).ToString('o')
                ResultCount = @($Data).Count
                DataFile = [System.IO.Path]::GetFileName($path)
            } | ConvertTo-Json | Set-Content -LiteralPath $metadataPath -Encoding UTF8
        }
        $path
    }
}

Export-ModuleMember -Function Export-HIRReportCsv
