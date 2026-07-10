#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-CheckResult {
    param(
        [System.Collections.Generic.List[object]]$Results,

        [Parameter(Mandatory)]
        [string]$Area,

        [Parameter(Mandatory)]
        [string]$Check,

        [Parameter(Mandatory)]
        [ValidateSet('OK', 'Warning', 'Error')]
        [string]$Status,

        [string]$Details = ''
    )

    $Results.Add([pscustomobject]@{
        Area    = $Area
        Check   = $Check
        Status  = $Status
        Details = $Details
    }) | Out-Null
}

function Test-HIRProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    $resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($folder in @('Config', 'GUI', 'Modules', 'Templates', 'Reports', 'Archive', 'Logs')) {
        $path = Join-Path $resolvedRoot $folder
        Add-CheckResult -Results $results -Area 'Layout' -Check $folder -Status $(if (Test-Path -LiteralPath $path) { 'OK' } else { 'Error' }) -Details $path
    }

    $psFiles = Get-ChildItem -LiteralPath $resolvedRoot -Recurse -Include *.ps1,*.psm1 -File
    foreach ($file in $psFiles) {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        Add-CheckResult -Results $results -Area 'PowerShell' -Check $file.FullName.Replace($resolvedRoot, '.').TrimStart('\') -Status $(if ($errors.Count -eq 0) { 'OK' } else { 'Error' }) -Details $(if ($errors.Count -eq 0) { 'Parsed successfully' } else { $errors[0].Message })
    }

    foreach ($jsonFile in @('appsettings.json', 'connections.json', 'reports.json', 'planned-reports.json')) {
        $path = Join-Path $resolvedRoot "Config\$jsonFile"
        try {
            Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
            Add-CheckResult -Results $results -Area 'JSON' -Check $jsonFile -Status 'OK' -Details 'Valid JSON'
        }
        catch {
            Add-CheckResult -Results $results -Area 'JSON' -Check $jsonFile -Status 'Error' -Details $_.Exception.Message
        }
    }

    try {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
        [xml]$xaml = Get-Content -LiteralPath (Join-Path $resolvedRoot 'GUI\MainWindow.xaml') -Raw -Encoding UTF8
        $reader = New-Object System.Xml.XmlNodeReader $xaml
        [Windows.Markup.XamlReader]::Load($reader) | Out-Null
        Add-CheckResult -Results $results -Area 'WPF' -Check 'MainWindow.xaml' -Status 'OK' -Details 'XAML loaded successfully'
    }
    catch {
        Add-CheckResult -Results $results -Area 'WPF' -Check 'MainWindow.xaml' -Status 'Error' -Details $_.Exception.Message
    }

    $moduleFiles = Get-ChildItem -LiteralPath (Join-Path $resolvedRoot 'Modules') -Recurse -Filter *.psm1 -File
    foreach ($moduleFile in $moduleFiles) {
        try {
            Import-Module $moduleFile.FullName -Force -ErrorAction Stop
            Add-CheckResult -Results $results -Area 'Module' -Check $moduleFile.FullName.Replace($resolvedRoot, '.').TrimStart('\') -Status 'OK' -Details 'Imported successfully'
        }
        catch {
            Add-CheckResult -Results $results -Area 'Module' -Check $moduleFile.FullName.Replace($resolvedRoot, '.').TrimStart('\') -Status 'Error' -Details $_.Exception.Message
        }
    }

    try {
        $reports = Get-Content -LiteralPath (Join-Path $resolvedRoot 'Config\reports.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $sourceText = (Get-Content -LiteralPath (Join-Path $resolvedRoot 'Start-Hybrid-Identity-Reporter.ps1') -Raw -Encoding UTF8) + "`n" + (($moduleFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n")
        $definedFunctions = [regex]::Matches($sourceText, '(?m)^\s*function\s+([A-Za-z0-9_-]+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $missing = @($reports | Where-Object { $_.Implemented -eq $true -and $_.Function -notin $definedFunctions })
        Add-CheckResult -Results $results -Area 'Catalog' -Check 'Implemented function mapping' -Status $(if ($missing.Count -eq 0) { 'OK' } else { 'Error' }) -Details $(if ($missing.Count -eq 0) { "$(@($reports | Where-Object Implemented).Count) implemented reports mapped" } else { ($missing.Function -join ', ') })

        $duplicateIds = @($reports | Group-Object Id | Where-Object Count -gt 1)
        Add-CheckResult -Results $results -Area 'Catalog' -Check 'Duplicate report IDs' -Status $(if ($duplicateIds.Count -eq 0) { 'OK' } else { 'Error' }) -Details $(if ($duplicateIds.Count -eq 0) { 'No duplicate report IDs' } else { ($duplicateIds.Name -join ', ') })

        $duplicateDisplayNames = @($reports | Group-Object DisplayName | Where-Object Count -gt 1)
        Add-CheckResult -Results $results -Area 'Catalog' -Check 'Duplicate display names' -Status $(if ($duplicateDisplayNames.Count -eq 0) { 'OK' } else { 'Error' }) -Details $(if ($duplicateDisplayNames.Count -eq 0) { 'No duplicate display names' } else { ($duplicateDisplayNames.Name -join ', ') })

        $duplicateFunctions = @($reports | Group-Object Function | Where-Object Count -gt 1)
        Add-CheckResult -Results $results -Area 'Catalog' -Check 'Duplicate function mappings' -Status $(if ($duplicateFunctions.Count -eq 0) { 'OK' } else { 'Error' }) -Details $(if ($duplicateFunctions.Count -eq 0) { 'No duplicate function mappings' } else { ($duplicateFunctions.Name -join ', ') })

        $missingMetadata = @($reports | Where-Object {
            -not ($_.PSObject.Properties.Name -contains 'Priority') -or
            -not ($_.PSObject.Properties.Name -contains 'RiskLevel') -or
            -not ($_.PSObject.Properties.Name -contains 'Note')
        })
        Add-CheckResult -Results $results -Area 'Catalog' -Check 'Report metadata' -Status $(if ($missingMetadata.Count -eq 0) { 'OK' } else { 'Warning' }) -Details $(if ($missingMetadata.Count -eq 0) { 'All reports include Priority, RiskLevel and Note' } else { ($missingMetadata.Id -join ', ') })

        $plannedWithExistingFunction = @($reports | Where-Object { $_.Implemented -ne $true -and $_.Function -in $definedFunctions })
        Add-CheckResult -Results $results -Area 'Catalog' -Check 'Planned reports with existing functions' -Status $(if ($plannedWithExistingFunction.Count -eq 0) { 'OK' } else { 'Warning' }) -Details $(if ($plannedWithExistingFunction.Count -eq 0) { 'No planned report points to an existing function' } else { ($plannedWithExistingFunction.Id -join ', ') })

        $plannedSettingsPath = Join-Path $resolvedRoot 'Config\planned-reports.json'
        if (Test-Path -LiteralPath $plannedSettingsPath) {
            $plannedSettings = Get-Content -LiteralPath $plannedSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $configuredPlannedIds = @($plannedSettings.PlannedReports | Where-Object { $_.Id } | ForEach-Object { $_.Id })
            $unknownPlannedIds = @($configuredPlannedIds | Where-Object { $_ -notin $reports.Id })
            Add-CheckResult -Results $results -Area 'Catalog' -Check 'Planned report configuration IDs' -Status $(if ($unknownPlannedIds.Count -eq 0) { 'OK' } else { 'Warning' }) -Details $(if ($unknownPlannedIds.Count -eq 0) { "$($configuredPlannedIds.Count) configured planned report IDs are valid" } else { ($unknownPlannedIds -join ', ') })
        }
    }
    catch {
        Add-CheckResult -Results $results -Area 'Catalog' -Check 'Catalog validation' -Status 'Error' -Details $_.Exception.Message
    }

    $markdownPath = Join-Path $resolvedRoot 'REPORTS-PAR-MENU.md'
    if (Test-Path -LiteralPath $markdownPath) {
        $markdown = Get-Content -LiteralPath $markdownPath -Raw -Encoding UTF8
        $reports = Get-Content -LiteralPath (Join-Path $resolvedRoot 'Config\reports.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $missingDocs = @($reports | Where-Object { $markdown -notmatch [regex]::Escape($_.DisplayName) })
        Add-CheckResult -Results $results -Area 'Docs' -Check 'REPORTS-PAR-MENU coverage' -Status $(if ($missingDocs.Count -eq 0) { 'OK' } else { 'Warning' }) -Details $(if ($missingDocs.Count -eq 0) { "$($reports.Count) reports documented" } else { ($missingDocs.DisplayName -join ', ') })
    }
    else {
        Add-CheckResult -Results $results -Area 'Docs' -Check 'REPORTS-PAR-MENU.md' -Status 'Warning' -Details 'File not found'
    }

    try {
        $appSettings = Get-Content -LiteralPath (Join-Path $resolvedRoot 'Config\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $readmePath = Join-Path $resolvedRoot 'README.md'
        $changelogPath = Join-Path $resolvedRoot 'CHANGELOG.md'
        $version = [string]$appSettings.Version
        $readme = if (Test-Path -LiteralPath $readmePath) { Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8 } else { '' }
        $changelog = if (Test-Path -LiteralPath $changelogPath) { Get-Content -LiteralPath $changelogPath -Raw -Encoding UTF8 } else { '' }
        $versionDocumented = $readme -match [regex]::Escape($version) -and $changelog -match [regex]::Escape($version)
        Add-CheckResult -Results $results -Area 'Docs' -Check 'Version documentation' -Status $(if ($versionDocumented) { 'OK' } else { 'Warning' }) -Details $(if ($versionDocumented) { "Version $version documented in README and CHANGELOG" } else { "Version $version missing from README or CHANGELOG" })
    }
    catch {
        Add-CheckResult -Results $results -Area 'Docs' -Check 'Version documentation' -Status 'Warning' -Details $_.Exception.Message
    }

    $results
}

$results = Test-HIRProject -RootPath $RootPath
$results | Format-Table -AutoSize

if ($results.Status -contains 'Error') {
    throw 'Hybrid Identity Reporter project validation failed.'
}
