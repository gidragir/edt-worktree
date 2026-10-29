BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
}

AfterAll {
    Exit-EdtWtTestConfig -State $script:TestCfg
}

BeforeAll {
    Import-Module (Get-EdtWtTestModulePath) -Force -DisableNameChecking
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
            param($p) Update-EdtWtBranch -WorktreePath $p -Branch 'pre-prod' -Remote 'origin'
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
            param($p) Update-EdtWtBranch -WorktreePath $p -Branch 'pre-prod' -Remote 'origin'
        } $script:Wt

        $r.Success | Should -BeFalse
        $r.Message | Should -BeLike '*ожидалась*'
    }
}


Describe 'Update-EdtWtBranch: удалённый репозиторий и перемотка' {
    BeforeAll {
        $script:Root = $script:TestCfg.Root
        $r = New-EdtWtTestRepo -Root $script:Root -Name 'ff' -Branch 'develop' -WithRemote
        $script:FfRepo = $r.RepoPath
        $script:FfRemote = $r.RemotePath
        # Второй клон пушит новый коммит в общий bare-репозиторий.
        $script:Other = Join-Path $script:Root 'ff-other'
        git clone -q $script:FfRemote $script:Other
        $script:Push = {
            Set-Content -LiteralPath (Join-Path $script:Other "f$([guid]::NewGuid().ToString('N')).txt") -Value 'x'
            git -C $script:Other add -A
            git -C $script:Other -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m 'next'
            git -C $script:Other push -q origin develop
        }
    }

    It 'подтягивает коммиты с remote по умолчанию' {
        & $script:Push
        $r = & (Get-Module EdtWorktree) { param($p) Update-EdtWtBranch -WorktreePath $p -Branch 'develop' -Remote 'origin' } $script:FfRepo
        $r.Success | Should -BeTrue
        $r.Message | Should -Be 'подтянуто коммитов: 1'
    }

    It 'использует переданный -Remote, а не зашитый origin' {
        git -C $script:FfRepo remote rename origin upstream | Out-Null
        & $script:Push
        $r = & (Get-Module EdtWorktree) { param($p) Update-EdtWtBranch -WorktreePath $p -Branch 'develop' -Remote 'upstream' } $script:FfRepo
        $r.Success | Should -BeTrue
        $r.Message | Should -Be 'подтянуто коммитов: 1'
    }
}

Describe 'Update-EdtWtReference' {
    BeforeAll {
        $script:Root = $script:TestCfg.Root
        $script:Repos = Join-Path $script:Root 'repos'
        $script:Wss = Join-Path $script:Root 'ws'
        $r = New-EdtWtTestRepo -Root $script:Repos -Name 'p' -Branch 'develop' -WithRemote -Projects @{ 'src/cf' = 'Configuration' }
        $script:Repo = $r.RepoPath
        $script:Other = Join-Path $script:Root 'p-other'
        git clone -q $r.RemotePath $script:Other
        Import-Module (Get-EdtWtTestModulePath) -Force -DisableNameChecking
        & (Get-Module EdtWorktree) {
            param($repos, $wss)
            $c = Get-EdtWtConfig
            $c.paths.repos_root = $repos
            $c.paths.worktrees_root = $repos
            $c.paths.workspaces_root = $wss
            $c.edt.cli_path = 'C:\Program Files\1C\1CE\components\1cedtcli.bat'
            $def = [PSCustomObject]@{ ref_branch = 'develop'; cf_project = 'src/cf'; extensions = [string[]]@() }
            Add-Member -InputObject $c.projects -MemberType NoteProperty -Name 'p' -Value $def
            Save-EdtWtConfig -Config $c | Out-Null
        } $script:Repos $script:Wss
    }

    BeforeEach {
        Mock -ModuleName EdtWorktree -CommandName Invoke-EdtWorktreeWarmup -MockWith { }
        Mock -ModuleName EdtWorktree -CommandName Get-EdtWtWorkspaceProcesses -MockWith { @() }
        Mock -ModuleName EdtWorktree -CommandName Stop-Process -MockWith { }
    }

    It 'пропускает грязный клон с причиной' {
        $dirty = Join-Path $script:Repo 'dirty.txt'
        Set-Content -LiteralPath $dirty -Value 'x'
        try {
            $report = @(Update-EdtWtReference -Project 'p' -Confirm:$false 6>&1 | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] })
        } finally {
            Remove-Item -LiteralPath $dirty -Force
        }
        $report.Count | Should -Be 1
        $report[0].Status | Should -Be 'skipped'
        $report[0].Detail | Should -BeLike '*незакоммиченные*'
        Should -Invoke Invoke-EdtWorktreeWarmup -ModuleName EdtWorktree -Times 0 -Exactly
    }

    It 'подтягивает ветку клона и собирает эталон' {
        Set-Content -LiteralPath (Join-Path $script:Other 'n.txt') -Value 'x'
        git -C $script:Other add -A
        git -C $script:Other -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m 'next'
        git -C $script:Other push -q origin develop
        $report = @(Update-EdtWtReference -Project 'p' -Confirm:$false 6>&1 | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] })
        $report[0].Status | Should -Be 'updated'
        Test-Path -LiteralPath (Join-Path $script:Repo 'n.txt') | Should -BeTrue
        Should -Invoke Invoke-EdtWorktreeWarmup -ModuleName EdtWorktree -Times 1 -Exactly -ParameterFilter { $ProjectName -eq 'p' }
    }

    It 'занятый эталон пропускается без закрытия процессов' {
        Mock -ModuleName EdtWorktree -CommandName Get-EdtWtWorkspaceProcesses -MockWith {
            @([PSCustomObject]@{ Name = '1cedt.exe'; ProcessId = 9 })
        }
        $report = @(Update-EdtWtReference -Project 'p' -Confirm:$false 6>&1 | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] })
        $report[0].Status | Should -Be 'skipped'
        $report[0].Detail | Should -BeLike '*Эталон занят*1cedt.exe:9*'
        Should -Invoke Stop-Process -ModuleName EdtWorktree -Times 0 -Exactly
        Should -Invoke Invoke-EdtWorktreeWarmup -ModuleName EdtWorktree -Times 0 -Exactly
    }

    It 'сообщает о проекте, которого нет в реестре' {
        $report = @(Update-EdtWtReference -Project 'no-such-project' -WhatIf 6>&1 | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] })
        $report[0].Status | Should -Be 'skipped'
        $report[0].Detail | Should -BeLike '*не зарегистрирован*'
    }

    It 'возвращает отчёт с длительностью по каждому проекту' {
        $report = @(Update-EdtWtReference -Project 'p' -SkipGit -Confirm:$false 6>&1 | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] })
        $report[0].PSObject.Properties.Name | Should -Contain 'Seconds'
    }

    It 'ключей -Validate и -MaxHeap у update больше нет' {
        $p = (Get-Command Update-EdtWtReference).Parameters.Keys
        foreach ($k in 'Validate', 'MaxHeap') { $p | Should -Not -Contain $k }
    }
}
