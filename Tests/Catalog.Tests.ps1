BeforeAll {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    Get-ChildItem -LiteralPath (Join-Path $projectRoot 'Modules') -Filter '*.psm1' -Recurse |
        ForEach-Object { Import-Module $_.FullName -Force }
    $reports = Get-Content -LiteralPath (Join-Path $projectRoot 'Config\reports.json') -Raw | ConvertFrom-Json
}

Describe 'HIR report catalog' {
    It 'has unique IDs, display names and implemented function mappings' {
        @($reports | Group-Object Id | Where-Object Count -gt 1).Count | Should -Be 0
        @($reports | Group-Object DisplayName | Where-Object Count -gt 1).Count | Should -Be 0
        $missing = @($reports | Where-Object Implemented | Where-Object { -not (Get-Command $_.Function -ErrorAction SilentlyContinue) })
        $missing.Count | Should -Be 0
    }

    It 'resolves permission details for every report' {
        foreach ($report in $reports) {
            $permission = Get-HIRReportPermission -RootPath $projectRoot -Report $report
            $permission.Source | Should -Not -BeNullOrEmpty
            $permission.Permissions | Should -Not -BeNullOrEmpty
            $permission.Prerequisites | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Users Review menu' {
    It 'groups the AD user lifecycle reports' {
        $ids = @($reports | Where-Object Category -eq 'Users Review' | ForEach-Object Id)
        foreach ($id in 'AD.DisabledUsers', 'AD.LockedUsers', 'AD.InactiveUsers90Days', 'AD.UsersWithoutEmail', 'AD.UsersWithoutManager', 'AD.ExpiredOrNeverLoggedOnUsers', 'AD.OldPasswordLastSet') {
            $ids | Should -Contain $id
        }
    }

    It 'requests DisplayName from Get-ADUser in the user reports' {
        $source = Get-Content -LiteralPath (Join-Path $projectRoot 'Modules\AD\ADUsers.psm1') -Raw
        ([regex]::Matches($source, "Properties\s*=\s*@\('(?!DisplayName)")).Count | Should -Be 0
    }
}
