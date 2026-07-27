Set-StrictMode -Version Latest

function Export-HIRReportExcel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ReportName,

        [Parameter(Mandatory)]
        [object[]]$Data,

        [Parameter(Mandatory)]
        [string]$RootPath
    )

    Invoke-HIRSafeCommand -Module Export -Action 'Excel export' -ScriptBlock {
        Assert-HIRModule -Name ImportExcel
        Import-Module ImportExcel -ErrorAction Stop
        $appSettings = Get-HIRAppSettings -RootPath $RootPath
        $toolVersion = if ($appSettings.PSObject.Properties.Name -contains 'Version') { [string]$appSettings.Version } else { 'Unknown' }

        $reportDirectory = Join-Path $RootPath 'Reports'
        if (-not (Test-Path -LiteralPath $reportDirectory)) { New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null }
        $safeName = New-HIRSafeFileName -Name $ReportName
        Copy-HIRExistingReportsToArchive -RootPath $RootPath -SafeReportName $safeName -Extension xlsx
        $path = Join-Path $reportDirectory ('{0}-{1}.xlsx' -f $safeName, (Get-Date -Format 'yyyyMMdd-HHmmss'))

        $metadata = @(
            [pscustomobject]@{ Property = 'ReportName'; Value = $ReportName }
            [pscustomobject]@{ Property = 'ToolVersion'; Value = $toolVersion }
            [pscustomobject]@{ Property = 'ExecutionDate'; Value = (Get-Date).ToString('s') }
            [pscustomobject]@{ Property = 'ResultCount'; Value = @($Data).Count }
        )

        $metadata | Export-Excel -Path $path -WorksheetName Metadata -AutoSize -TableName Metadata
        $Data | Export-Excel -Path $path -WorksheetName Data -AutoSize -TableName ReportData -Append
        $path
    }
}

Export-ModuleMember -Function Export-HIRReportExcel
