Set-StrictMode -Version Latest

$script:HIRLogPath = $null

function Initialize-HIRLogging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    $logDirectory = Join-Path $RootPath 'Logs'
    if (-not (Test-Path -LiteralPath $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }

    $script:HIRLogPath = Join-Path $logDirectory ("Hybrid-Identity-Reporter-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
}

function Write-HIRLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Module,

        [Parameter(Mandatory)]
        [string]$Action,

        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $script:HIRLogPath) {
        $fallbackRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Initialize-HIRLogging -RootPath $fallbackRoot
    }

    $entry = [pscustomobject]@{
        Date    = (Get-Date).ToString('s')
        Module  = $Module
        Action  = $Action
        Level   = $Level
        Message = $Message
    }

    $line = '{0};{1};{2};{3};{4}' -f $entry.Date, $entry.Module, $entry.Action, $entry.Level, ($entry.Message -replace "`r?`n", ' ')
    Add-Content -LiteralPath $script:HIRLogPath -Value $line -Encoding UTF8
}

function Invoke-HIRSafeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Module,

        [Parameter(Mandatory)]
        [string]$Action,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    try {
        Write-HIRLog -Module $Module -Action $Action -Level INFO -Message 'Starting action.'
        & $ScriptBlock
        Write-HIRLog -Module $Module -Action $Action -Level INFO -Message 'Action completed.'
    }
    catch {
        Write-HIRLog -Module $Module -Action $Action -Level ERROR -Message $_.Exception.Message
        throw
    }
}

Export-ModuleMember -Function Initialize-HIRLogging, Write-HIRLog, Invoke-HIRSafeCommand
