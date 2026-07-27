#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$settings = Get-Content -LiteralPath (Join-Path $RootPath 'Config\appsettings.json') -Raw | ConvertFrom-Json
$version = [string]$settings.Version
$dist = if ($OutputPath) { $OutputPath } else { Join-Path $RootPath 'Dist' }
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("HIR-package-" + [guid]::NewGuid())
$packageRoot = Join-Path $stage "Hybrid-Identity-Reporter-$version"
$zipPath = Join-Path $dist "Hybrid-Identity-Reporter-$version.zip"

try {
    New-Item -ItemType Directory -Path $packageRoot, $dist -Force | Out-Null
    foreach ($path in @('Config', 'GUI', 'Modules', 'Templates', 'Tools', 'README.md', 'CHANGELOG.md', 'REPORTS-PAR-MENU.md', 'REPORT-PERMISSIONS.md', 'LICENSE', 'launch.bat', 'Start-Hybrid-Identity-Reporter.ps1')) {
        Copy-Item -LiteralPath (Join-Path $RootPath $path) -Destination $packageRoot -Recurse -Force
    }
    foreach ($folder in @('Reports', 'Archive', 'Logs')) {
        New-Item -ItemType Directory -Path (Join-Path $packageRoot $folder) -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $packageRoot "$folder\.gitkeep") -Value ''
    }
    Get-ChildItem -LiteralPath $packageRoot -File -Recurse |
        Sort-Object FullName |
        ForEach-Object {
            [pscustomobject]@{
                Path = $_.FullName.Substring($packageRoot.Length + 1)
                SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $packageRoot 'MANIFEST.json') -Encoding UTF8
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -LiteralPath $packageRoot -DestinationPath $zipPath -CompressionLevel Optimal
    $zipPath
}
finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
