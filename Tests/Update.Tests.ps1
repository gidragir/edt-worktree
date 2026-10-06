BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\EdtWorktree.psd1') -Force -DisableNameChecking
}

Describe 'Update-EdtWtBranch' {
    BeforeEach {
        $script:Wt = Join-Path ([System.IO.Path]::GetTempPath()) ("branch_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:Wt | Out-Null
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:Wt) { Remove-Item -LiteralPath $script:Wt -Recurse -Force }
    }

    It 'отказывается трогать каталог с незакоммиченными изменениями' {
        # Задание по расписанию не должно затирать чью-то работу.
        Mock -ModuleName EdtWorktree -CommandName git -MockWith { return @(' M src/cf/x.bsl') }

        $r = & (Get-Module EdtWorktree) {
            param($p) Update-EdtWtBranch -WorktreePath $p -Branch 'pre-prod'
        } $script:Wt

        $r.Success | Should -BeFalse
        $r.Message | Should -BeLike '*незакоммиченные*'
    }

    It 'отказывается работать при другой ветке в каталоге' {
        Mock -ModuleName EdtWorktree -CommandName git -MockWith {
            if ($args -contains 'status') { return @() }
            if ($args -contains '--abbrev-ref') { return 'feature-X' }
            return @()
        }

        $r = & (Get-Module EdtWorktree) {
            param($p) Update-EdtWtBranch -WorktreePath $p -Branch 'pre-prod'
        } $script:Wt

        $r.Success | Should -BeFalse
        $r.Message | Should -BeLike '*ожидалась*'
    }
}

Describe 'Update-EdtWtReference' {
    BeforeAll {
        $script:OrigConfigPath = $env:EDT_CONFIG_PATH
        $script:TempCfgDir = Join-Path ([System.IO.Path]::GetTempPath()) ("update_cfg_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TempCfgDir -Force | Out-Null
        $script:TempCfgFile = Join-Path $script:TempCfgDir 'config.json'

        $cfgData = @{
            paths    = @{
                projects_root   = $script:TempCfgDir
                worktree_root   = $script:TempCfgDir
                workspaces_root = $script:TempCfgDir
            }
            projects = @{
                'test-proj' = @{
                    cf_project       = 'src/cf'
                    reference_branch = 'pre-prod'
                }
            }
        }
        $cfgData | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:TempCfgFile -Encoding UTF8
        $env:EDT_CONFIG_PATH = $script:TempCfgFile
    }

    AfterAll {
        $env:EDT_CONFIG_PATH = $script:OrigConfigPath
        if (Test-Path -LiteralPath $script:TempCfgDir) {
            Remove-Item -LiteralPath $script:TempCfgDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'пропускает проект без рабочего каталога эталонной ветки' {
        $report = @(Update-EdtWtReference -Project 'test-proj' -WhatIf)
        $report.Count | Should -Be 1
        $report[0].Status | Should -Be 'skipped'
    }

    It 'сообщает о проекте, которого нет в реестре' {
        $report = @(Update-EdtWtReference -Project 'no-such-project' -WhatIf)
        $report[0].Status | Should -Be 'skipped'
        $report[0].Detail | Should -BeLike '*projects.json*'
    }

    It 'возвращает отчёт с длительностью по каждому проекту' {
        $report = @(Update-EdtWtReference -Project 'test-proj' -WhatIf)
        $report[0].PSObject.Properties.Name | Should -Contain 'Seconds'
    }
}
