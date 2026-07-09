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
        $reportDirectory = Join-Path $RootPath 'Reports'
        if (-not (Test-Path -LiteralPath $reportDirectory)) { New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null }
        $safeName = New-HIRSafeFileName -Name $ReportName
        Copy-HIRExistingReportsToArchive -RootPath $RootPath -SafeReportName $safeName -Extension html
        $path = Join-Path $reportDirectory ('{0}-{1}.html' -f $safeName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $templatePath = Join-Path $RootPath 'Templates\report-template.html'

        $table = if (@($Data).Count -gt 0) {
            $Data | ConvertTo-Html -Fragment
        }
        else {
            '<p>No result returned.</p>'
        }

        $template = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
        $html = $template.Replace('{{ReportName}}', [System.Net.WebUtility]::HtmlEncode($ReportName)).
            Replace('{{ExecutionDate}}', [System.Net.WebUtility]::HtmlEncode((Get-Date).ToString('s'))).
            Replace('{{ResultCount}}', [System.Net.WebUtility]::HtmlEncode(@($Data).Count.ToString())).
            Replace('{{Table}}', $table)

        Set-Content -LiteralPath $path -Value $html -Encoding UTF8
        $path
    }
}

Export-ModuleMember -Function Export-HIRReportHtml
