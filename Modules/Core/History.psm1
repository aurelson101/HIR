Set-StrictMode -Version Latest

function Get-HIRHistoryDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RootPath)

    $path = Join-Path $RootPath 'Reports\History'
    if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    $path
}

function Register-HIRRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$ReportId,
        [Parameter(Mandatory)][string]$ReportName,
        [Parameter(Mandatory)][object[]]$Data,
        [Parameter(Mandatory)][datetime]$StartedAt,
        [ValidateSet('Completed', 'Error', 'Cancelled')][string]$Status = 'Completed',
        [string]$RiskLevel = 'Unknown',
        [string]$ErrorMessage = ''
    )

    $historyPath = Get-HIRHistoryDirectory -RootPath $RootPath
    $runId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $snapshotName = "$runId.data.json"
    ConvertTo-Json -InputObject @($Data) -Depth 8 | Set-Content -LiteralPath (Join-Path $historyPath $snapshotName) -Encoding UTF8
    $completedAt = Get-Date
    $manifest = [ordered]@{
        SchemaVersion = 1
        RunId = $runId
        ReportId = $ReportId
        ReportName = $ReportName
        RiskLevel = $RiskLevel
        StartedAt = $StartedAt.ToString('o')
        CompletedAt = $completedAt.ToString('o')
        DurationSeconds = [Math]::Round(($completedAt - $StartedAt).TotalSeconds, 3)
        Status = $Status
        ResultCount = @($Data).Count
        ErrorMessage = $ErrorMessage
        SnapshotFile = $snapshotName
        ComputerName = $env:COMPUTERNAME
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $historyPath "$runId.manifest.json") -Encoding UTF8
    [pscustomobject]$manifest
}

function Get-HIRRunHistory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RootPath, [string]$ReportId)

    $items = foreach ($file in Get-ChildItem -LiteralPath (Get-HIRHistoryDirectory -RootPath $RootPath) -Filter '*.manifest.json' -File -ErrorAction SilentlyContinue) {
        try { Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { Write-Warning "Ignoring invalid history manifest '$($file.Name)': $($_.Exception.Message)" }
    }
    @($items | Where-Object { -not $ReportId -or $_.ReportId -eq $ReportId } | Sort-Object CompletedAt -Descending)
}

function Compare-HIRReportExports {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RootPath, [string]$ReportId)

    if (-not $ReportId) {
        $candidate = Get-HIRRunHistory -RootPath $RootPath | Where-Object Status -eq 'Completed' |
            Group-Object ReportId | Where-Object Count -ge 2 |
            ForEach-Object { $_.Group | Sort-Object CompletedAt -Descending | Select-Object -First 1 } |
            Sort-Object CompletedAt -Descending | Select-Object -First 1
        if ($candidate) { $ReportId = [string]$candidate.ReportId }
    }
    $runs = @(Get-HIRRunHistory -RootPath $RootPath -ReportId $ReportId | Where-Object Status -eq 'Completed' | Select-Object -First 2)
    if ($runs.Count -lt 2) { throw 'At least two completed runs are required for comparison.' }
    $historyPath = Get-HIRHistoryDirectory -RootPath $RootPath
    $current = @(Get-Content -LiteralPath (Join-Path $historyPath $runs[0].SnapshotFile) -Raw -Encoding UTF8 | ConvertFrom-Json)
    $previous = @(Get-Content -LiteralPath (Join-Path $historyPath $runs[1].SnapshotFile) -Raw -Encoding UTF8 | ConvertFrom-Json)
    $currentJson = @($current | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress })
    $previousJson = @($previous | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress })
    @(
        foreach ($entry in $currentJson | Where-Object { $_ -notin $previousJson }) {
            [pscustomobject]@{ Change = 'AddedOrChanged'; CurrentRun = $runs[0].RunId; PreviousRun = $runs[1].RunId; Record = $entry }
        }
        foreach ($entry in $previousJson | Where-Object { $_ -notin $currentJson }) {
            [pscustomobject]@{ Change = 'RemovedOrChanged'; CurrentRun = $runs[0].RunId; PreviousRun = $runs[1].RunId; Record = $entry }
        }
    )
}

function Get-HIRReportRiskScore {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RootPath)

    $weights = @{ Critical = 10; High = 6; Medium = 3; Low = 1; Unknown = 1 }
    $latest = Get-HIRRunHistory -RootPath $RootPath | Where-Object Status -eq 'Completed' |
        Group-Object ReportId | ForEach-Object { $_.Group | Sort-Object CompletedAt -Descending | Select-Object -First 1 }
    @($latest | ForEach-Object {
        $weight = if ($weights.ContainsKey([string]$_.RiskLevel)) { $weights[[string]$_.RiskLevel] } else { 1 }
        [pscustomobject]@{
            Report = $_.ReportName
            Risk = $_.RiskLevel
            Findings = [int]$_.ResultCount
            Weight = $weight
            Score = ([int]$_.ResultCount * $weight)
            LastRun = $_.CompletedAt
            Method = 'Findings x risk weight (Critical=10, High=6, Medium=3, Low=1).'
        }
    } | Sort-Object Score -Descending)
}

function Export-HIRExecutiveSummaryHtml {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RootPath)

    $scores = @(Get-HIRReportRiskScore -RootPath $RootPath)
    Export-HIRReportHtml -ReportName 'Executive Summary' -Data $scores -RootPath $RootPath
}

Export-ModuleMember -Function Register-HIRRun, Get-HIRRunHistory, Compare-HIRReportExports, Get-HIRReportRiskScore, Export-HIRExecutiveSummaryHtml
