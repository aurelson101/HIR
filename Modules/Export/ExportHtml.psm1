Set-StrictMode -Version Latest

function Export-HIRReportHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ReportName,

        [Parameter(Mandatory)]
        [object[]]$Data,

        [Parameter(Mandatory)]
        [string]$RootPath
    )

    Invoke-HIRSafeCommand -Module Export -Action 'HTML export' -ScriptBlock {
        $appSettings = Get-HIRAppSettings -RootPath $RootPath
        $toolVersion = if ($appSettings.PSObject.Properties.Name -contains 'Version') { [string]$appSettings.Version } else { 'Unknown' }
        $reportDirectory = Join-Path $RootPath 'Reports'
        if (-not (Test-Path -LiteralPath $reportDirectory)) { New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null }
        $safeName = New-HIRSafeFileName -Name $ReportName
        Copy-HIRExistingReportsToArchive -RootPath $RootPath -SafeReportName $safeName -Extension html
        $path = Join-Path $reportDirectory ('{0}-{1}.html' -f $safeName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $templatePath = Join-Path $RootPath 'Templates\report-template.html'

        $resultCount = @($Data).Count
        $table = if ($resultCount -gt 0) {
            $Data | ConvertTo-Html -Fragment | Out-String
        }
        else {
            '<div class="empty">No result returned.</div>'
        }

        $template = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
        $html = $template.Replace('{{ReportName}}', [System.Net.WebUtility]::HtmlEncode($ReportName)).
            Replace('{{ToolName}}', [System.Net.WebUtility]::HtmlEncode('Hybrid Identity Reporter')).
            Replace('{{ToolVersion}}', [System.Net.WebUtility]::HtmlEncode($toolVersion)).
            Replace('{{ExecutionDate}}', [System.Net.WebUtility]::HtmlEncode((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))).
            Replace('{{ResultCount}}', [System.Net.WebUtility]::HtmlEncode($resultCount.ToString())).
            Replace('{{ComputerName}}', [System.Net.WebUtility]::HtmlEncode($env:COMPUTERNAME)).
            Replace('{{UserName}}', [System.Net.WebUtility]::HtmlEncode([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)).
            Replace('{{RootPath}}', [System.Net.WebUtility]::HtmlEncode($RootPath)).
            Replace('{{Table}}', $table)

        Set-Content -LiteralPath $path -Value $html -Encoding UTF8
        $path
    }
}

Export-ModuleMember -Function Export-HIRReportHtml
