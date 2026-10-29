BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
    $script:Root = $script:TestCfg.Root
    $script:PrevCapture = $env:EDTWT_TEST_CAPTURE
    $env:EDTWT_TEST_CAPTURE = Join-Path $script:Root 'captured.json'
    Import-Module (Join-Path $PSScriptRoot '..\EdtWorktree.psd1') -Force -DisableNameChecking
    $script:m = Get-Module EdtWorktree

    # Корни с пробелом и кириллицей; клон стоит на эталонной ветке develop.
    $script:Repos = Join-Path $script:Root 'Репозитории проекта'
    $script:Wts = Join-Path $script:Root 'wt'
    $script:Wss = Join-Path $script:Root 'ws'
    $r = New-EdtWtTestRepo -Root $script:Repos -Name 'p' -Branch 'develop' -Projects @{
        'src/cf' = 'Configuration'; 'src/cfe_a' = 'Extension'; 'src/cfe_b' = 'Extension'
    }
    $script:Repo = $r.RepoPath
    $script:RepoSlash = $script:Repo.Replace('\', '/')
    $script:RefDir = Join-Path $script:Wss 'p\_reference'

    & $script:m {
        param($repos, $wts, $wss)
        $c = Get-EdtWtConfig
        $c.paths.repos_root = $repos
        $c.paths.worktrees_root = $wts
        $c.paths.workspaces_root = $wss
        $c.edt.cli_path = 'C:\Program Files\1C\1CE\components\1cedtcli.bat'
        Add-Member -InputObject $c.edt -MemberType NoteProperty -Name 'extra_vmargs' -Value '-DisableProjectChecks=true' -Force
        $def = [PSCustomObject]@{ ref_branch = 'develop'; cf_project = 'src/cf'; extensions = [string[]]@('src/cfe_a', 'src/cfe_gone') }
        Add-Member -InputObject $c.projects -MemberType NoteProperty -Name 'p' -Value $def
        Save-EdtWtConfig -Config $c | Out-Null
    } $script:Repos $script:Wts $script:Wss

    $script:Read = { (Get-Content -LiteralPath $env:EDTWT_TEST_CAPTURE -Raw -Encoding UTF8) | ConvertFrom-Json }
}

AfterAll {
    $env:EDTWT_TEST_CAPTURE = $script:PrevCapture
    Exit-EdtWtTestConfig -State $script:TestCfg
}

Describe 'Invoke-EdtWorktreeWarmup' {
    BeforeEach {
        if (Test-Path -LiteralPath $env:EDTWT_TEST_CAPTURE) { Remove-Item -LiteralPath $env:EDTWT_TEST_CAPTURE -Force }
        if (Test-Path -LiteralPath (Join-Path $script:Wss 'p')) { Remove-Item -LiteralPath (Join-Path $script:Wss 'p') -Recurse -Force }
        Mock -ModuleName EdtWorktree -CommandName Invoke-EdtWtCli -MockWith {
            [PSCustomObject]@{ Commands = @($Commands); JvmArgs = $Context.JvmArgs; WorkspaceDir = $WorkspaceDir } |
                ConvertTo-Json -Compress | Set-Content -LiteralPath $env:EDTWT_TEST_CAPTURE -Encoding UTF8
            New-Item -ItemType Directory -Force -Path $WorkspaceDir | Out-Null
        }
        Mock -ModuleName EdtWorktree -CommandName Get-EdtWtWorkspaceProcesses -MockWith { @() }
        Mock -ModuleName EdtWorktree -CommandName Stop-Process -MockWith { }
        Mock -ModuleName EdtWorktree -CommandName Stop-EdtWtProcesses -MockWith { 0 }
        Mock -ModuleName EdtWorktree -CommandName Start-EdtWtGui -MockWith { }
    }

    It 'батч: cf + рабочие расширения + validate, без -DisableProjectChecks' {
        $out = Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false 6>&1 | Out-String
        $cap = & $script:Read
        $cap.Commands | Should -Contain ('import --project "{0}/src/cf"' -f $script:RepoSlash)
        $cap.Commands | Should -Contain ('import --project "{0}/src/cfe_a"' -f $script:RepoSlash)
        @($cap.Commands -match 'cfe_b').Count | Should -Be 0
        @($cap.Commands -match 'cfe_gone').Count | Should -Be 0
        $cap.Commands[-1] | Should -Match '^validate --file ".+" --project-name-list \["cf" "cfe_a"\]$'
        $cap.JvmArgs | Should -Not -Match 'DisableProjectChecks'
        $cap.WorkspaceDir | Should -Be $script:RefDir
        $out | Should -Match '\[skip\].*cfe_gone'
        $out | Should -Match 'Не в рабочих: cfe_b\. Включить: edt project ext p'
    }

    It 'клон не на эталонной ветке: отказ с командой switch' {
        git -C $script:Repo switch -q -c other
        try {
            $msg = try { Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false; '' } catch { $_.Exception.Message }
        } finally {
            git -C $script:Repo switch -q develop
        }
        $msg | Should -BeExactly "Клон $script:Repo стоит на 'other', эталон собирается с 'develop'. Переключите: git -C $script:Repo switch develop"
        Should -Invoke Invoke-EdtWtCli -ModuleName EdtWorktree -Times 0
    }

    It 'занятый эталон: отказ, процессы не закрываются' {
        New-Item -ItemType Directory -Force -Path $script:RefDir | Out-Null
        Set-Content -LiteralPath (Join-Path $script:RefDir 'marker.txt') -Value 'old'
        Mock -ModuleName EdtWorktree -CommandName Get-EdtWtWorkspaceProcesses -MockWith {
            @([PSCustomObject]@{ Name = '1cedt.exe'; ProcessId = 42 }, [PSCustomObject]@{ Name = 'java.exe'; ProcessId = 7 })
        }
        $msg = try { Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false; '' } catch { $_.Exception.Message }
        $msg | Should -BeExactly 'Эталон занят: 1cedt.exe:42, java.exe:7. Закройте EDT и повторите.'
        Should -Invoke Stop-Process -ModuleName EdtWorktree -Times 0 -Exactly
        Should -Invoke Stop-EdtWtProcesses -ModuleName EdtWorktree -Times 0 -Exactly
        Should -Invoke Invoke-EdtWtCli -ModuleName EdtWorktree -Times 0 -Exactly
        Test-Path -LiteralPath (Join-Path $script:RefDir 'marker.txt') | Should -BeTrue
    }

    It 'старый _reference_preprod переименовывается в _reference' {
        $old = Join-Path $script:Wss 'p\_reference_preprod'
        New-Item -ItemType Directory -Force -Path $old | Out-Null
        Set-Content -LiteralPath (Join-Path $old 'marker.txt') -Value 'legacy'
        Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false 6>&1 | Out-Null
        Test-Path -LiteralPath $old | Should -BeFalse
        Test-Path -LiteralPath $script:RefDir | Should -BeTrue
    }

    It 'занятый _reference_preprod не переименовывается' {
        $old = Join-Path $script:Wss 'p\_reference_preprod'
        New-Item -ItemType Directory -Force -Path $old | Out-Null
        Mock -ModuleName EdtWorktree -CommandName Get-EdtWtWorkspaceProcesses -ParameterFilter { $WorkspaceDir -like '*_reference_preprod' } -MockWith {
            @([PSCustomObject]@{ Name = '1cedt.exe'; ProcessId = 5 })
        }
        Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false 6>&1 3>&1 | Out-Null
        Test-Path -LiteralPath $old | Should -BeTrue
        Should -Invoke Stop-Process -ModuleName EdtWorktree -Times 0 -Exactly
    }

    It 'ошибка сборки возвращает прежний эталон' {
        New-Item -ItemType Directory -Force -Path $script:RefDir | Out-Null
        Set-Content -LiteralPath (Join-Path $script:RefDir 'marker.txt') -Value 'old'
        Mock -ModuleName EdtWorktree -CommandName Invoke-EdtWtCli -MockWith { throw 'boom' }
        { Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false 6>&1 | Out-Null } | Should -Throw '*boom*'
        Test-Path -LiteralPath (Join-Path $script:RefDir 'marker.txt') | Should -BeTrue
        Test-Path -LiteralPath "$script:RefDir.previous" | Should -BeFalse
    }

    It 'ошибка сборки сохраняет журналы EDT и аварийный дамп JVM рядом с эталоном' {
        Mock -ModuleName EdtWorktree -CommandName Invoke-EdtWtCli -MockWith {
            New-Item -ItemType Directory -Force -Path (Join-Path $WorkspaceDir '.metadata') | Out-Null
            Set-Content -LiteralPath (Join-Path $WorkspaceDir '.metadata\.log') -Value 'EDT-ERROR-TRACE'
            Set-Content -LiteralPath (Join-Path $WorkspaceDir '.metadata\1cedtcli.log') -Value 'CLI-CONSOLE'
            Set-Content -LiteralPath (Join-Path $WorkspaceDir 'hs_err_pid42.log') -Value 'JVM-CRASH'
            throw 'boom'
        }
        $out = & { try { Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false 6>&1 } catch { $_.Exception.Message } } | Out-String
        $dir = Join-Path $script:Wss 'p\_reference.failed'
        Get-Content -LiteralPath (Join-Path $dir '.log') -Raw | Should -Match 'EDT-ERROR-TRACE'
        Get-Content -LiteralPath (Join-Path $dir '1cedtcli.log') -Raw | Should -Match 'CLI-CONSOLE'
        Get-Content -LiteralPath (Join-Path $dir 'hs_err_pid42.log') -Raw | Should -Match 'JVM-CRASH'
        $out | Should -Match ([regex]::Escape($dir))
    }

    It 'ошибка сборки без журналов: так и сказано' {
        Mock -ModuleName EdtWorktree -CommandName Invoke-EdtWtCli -MockWith { New-Item -ItemType Directory -Force -Path $WorkspaceDir | Out-Null; throw 'boom' }
        $out = & { try { Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false 6>&1 } catch { $_.Exception.Message } } | Out-String
        $out | Should -Match 'журналов не оставил'
    }

    It 'ошибка первой сборки не оставляет недособранный эталон' {
        Mock -ModuleName EdtWorktree -CommandName Invoke-EdtWtCli -MockWith { New-Item -ItemType Directory -Force -Path $WorkspaceDir | Out-Null; throw 'boom' }
        { Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false 6>&1 | Out-Null } | Should -Throw '*boom*'
        Test-Path -LiteralPath $script:RefDir | Should -BeFalse
    }

    It 'успешная сборка заменяет прежний эталон и убирает резерв' {
        New-Item -ItemType Directory -Force -Path $script:RefDir | Out-Null
        Set-Content -LiteralPath (Join-Path $script:RefDir 'marker.txt') -Value 'old'
        Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false 6>&1 | Out-Null
        Test-Path -LiteralPath (Join-Path $script:RefDir 'marker.txt') | Should -BeFalse
        Test-Path -LiteralPath $script:RefDir | Should -BeTrue
        Test-Path -LiteralPath "$script:RefDir.previous" | Should -BeFalse
    }

    It '-WhatIf ничего не запускает и не трогает эталон' {
        New-Item -ItemType Directory -Force -Path $script:RefDir | Out-Null
        Set-Content -LiteralPath (Join-Path $script:RefDir 'marker.txt') -Value 'old'
        Invoke-EdtWorktreeWarmup -ProjectName 'p' -WhatIf 6>&1 | Out-Null
        Should -Invoke Invoke-EdtWtCli -ModuleName EdtWorktree -Times 0 -Exactly
        Test-Path -LiteralPath (Join-Path $script:RefDir 'marker.txt') | Should -BeTrue
    }

    It 'ключей -Force, -Validate, -MaxHeap, -Extensions у warmup больше нет' {
        $p = (Get-Command Invoke-EdtWorktreeWarmup).Parameters.Keys
        foreach ($k in 'Force', 'Validate', 'MaxHeap', 'Extensions') { $p | Should -Not -Contain $k }
    }
}

Describe 'Get-EdtWtUnusedExtensions' {
    It 'возвращает найденные, но не рабочие расширения' {
        $r = & $script:m {
            param($repo)
            $ctx = Get-EdtWtContext -Path $repo
            Get-EdtWtUnusedExtensions -Context $ctx
        } $script:Repo
        @($r) | Should -Be @('src/cfe_b')
    }
}

Describe 'Get-EdtWtPrefsSource' {
    It 'без edt.prefs_source возвращает $null' {
        & $script:m { Get-EdtWtPrefsSource -Context ([PSCustomObject]@{ ProjectId = 'p' }) } | Should -BeNullOrEmpty
    }

    It 'берёт каталог настроек из edt.prefs_source' {
        $donor = Join-Path $script:Root 'donor'
        $settings = Join-Path $donor '.metadata\.plugins\org.eclipse.core.runtime\.settings'
        New-Item -ItemType Directory -Force -Path $settings | Out-Null
        & $script:m { param($d) $c = Get-EdtWtConfig; $c.edt.prefs_source = $d; Save-EdtWtConfig -Config $c | Out-Null } $donor
        try {
            & $script:m { Get-EdtWtPrefsSource -Context ([PSCustomObject]@{ ProjectId = 'p' }) } | Should -Be $settings
        } finally {
            & $script:m { $c = Get-EdtWtConfig; $c.edt.prefs_source = $null; Save-EdtWtConfig -Config $c | Out-Null }
        }
    }
}
