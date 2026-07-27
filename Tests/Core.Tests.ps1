BeforeAll {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $projectRoot 'Modules\Core\Logging.psm1') -Force
    Import-Module (Join-Path $projectRoot 'Modules\Core\Config.psm1') -Force
    Import-Module (Join-Path $projectRoot 'Modules\Core\Helpers.psm1') -Force
    Import-Module (Join-Path $projectRoot 'Modules\Core\History.psm1') -Force
    Import-Module (Join-Path $projectRoot 'Modules\Export\ExportCsv.psm1') -Force
}

Describe 'HIR archive lifecycle' {
    BeforeEach {
        $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $testRoot 'Reports'), (Join-Path $testRoot 'Archive') -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'moves prior exports instead of copying them repeatedly' {
        $source = Join-Path $testRoot 'Reports\Test-20260101-000000.csv'
        Set-Content -LiteralPath $source -Value 'a;b'
        Copy-HIRExistingReportsToArchive -RootPath $testRoot -SafeReportName Test -Extension csv
        Test-Path -LiteralPath $source | Should -BeFalse
        @(Get-ChildItem -LiteralPath (Join-Path $testRoot 'Archive') -File).Count | Should -Be 1
    }

    It 'removes files older than retention' {
        $old = Join-Path $testRoot 'Archive\old.csv'
        Set-Content -LiteralPath $old -Value 'old'
        (Get-Item -LiteralPath $old).LastWriteTime = (Get-Date).AddDays(-10)
        Remove-HIRExpiredFiles -Path (Join-Path $testRoot 'Archive') -RetainDays 5 -Confirm:$false | Should -Be 1
        Test-Path -LiteralPath $old | Should -BeFalse
    }
}

Describe 'HIR CSV interoperability' {
    BeforeEach {
        $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $testRoot 'Config'), (Join-Path $testRoot 'Reports'), (Join-Path $testRoot 'Archive'), (Join-Path $testRoot 'Logs') -Force | Out-Null
        '{"Version":"test","Exports":{"WriteMetadataSidecar":true}}' | Set-Content -LiteralPath (Join-Path $testRoot 'Config\appsettings.json')
        Initialize-HIRLogging -RootPath $testRoot
    }

    AfterEach {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'writes one tabular CSV and a JSON metadata sidecar' {
        $path = Export-HIRReportCsv -ReportName Test -Data @([pscustomobject]@{ Name = 'Alice'; Risk = 'High' }) -RootPath $testRoot
        @(Import-Csv -LiteralPath $path -Delimiter ';').Count | Should -Be 1
        $metadata = Get-Content -LiteralPath ([System.IO.Path]::ChangeExtension($path, '.metadata.json')) -Raw | ConvertFrom-Json
        $metadata.ResultCount | Should -Be 1
    }
}

Describe 'HIR run history' {
    BeforeEach {
        $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'persists runs and compares two snapshots' {
        Register-HIRRun -RootPath $testRoot -ReportId R1 -ReportName Report -Data @([pscustomobject]@{ Id = 1 }) -StartedAt (Get-Date) | Out-Null
        Start-Sleep -Milliseconds 5
        Register-HIRRun -RootPath $testRoot -ReportId R1 -ReportName Report -Data @([pscustomobject]@{ Id = 2 }) -StartedAt (Get-Date) | Out-Null
        @(Get-HIRRunHistory -RootPath $testRoot -ReportId R1).Count | Should -Be 2
        @(Compare-HIRReportExports -RootPath $testRoot -ReportId R1).Count | Should -Be 2
    }
}
