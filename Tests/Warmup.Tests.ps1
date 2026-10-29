BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
    $script:Root = $script:TestCfg.Root
    $script:PrevCapture = $env:EDTWT_TEST_CAPTURE
    $env:EDTWT_TEST_CAPTURE = Join-Path $script:Root 'captured.json'
    Import-Module (Get-EdtWtTestModulePath) -Force -DisableNameChecking
    $script:m = Get-Module EdtWorktree

    # Корни с пробелом и кириллицей; клон стоит на эталонной ветке develop.
    $script:Repos = Join-Path $script:Root 'Репозитории проекта'
    $script:Wts = Join-Path $script:Root 'wt'
    $script:Wss = Join-Path $script:Root 'ws'
    $r = New-EdtWtTestRepo -Root $script:Repos -Name 'p' -Branch 'develop' -WithRemote -Projects @{
        'src/cf' = 'Configuration'; 'src/cfe_a' = 'Extension'; 'src/cfe_b' = 'Extension'
    }
    $script:Repo = $r.RepoPath
    $script:Remote = $r.RemotePath
    $script:RepoSlash = $script:Repo.Replace('\', '/')
    $script:RefDir = Join-Path $script:Wss 'p\_reference'
    $script:BuildDir = "$script:RefDir.building"

    # Результаты build/validate, по которым warmup судит, что проект собран.
    $script:FakeBuilt = {
        param([string]$Ws, [string[]]$Names)
        foreach ($n in $Names) {
            $v = Join-Path $Ws ".metadata\.plugins\com._1c.g5.v8.dt.validation\project\$n"
            New-Item -ItemType Directory -Force -Path (Join-Path $v 'index'), (Join-Path $v 'cache') | Out-Null
            Set-Content -LiteralPath (Join-Path $v 'index\segments_1') -Value 'x'
            Set-Content -LiteralPath (Join-Path $v 'cache\object_checkid_cache') -Value 'x'
        }
    }
    # Коммит в remote от имени другого разработчика: клон эталона от него отстаёт.
    $script:PushRemoteCommit = {
        param([string]$FileName)
        $other = Join-Path $script:Root ('other_' + [guid]::NewGuid().ToString('N'))
        git clone -q $script:Remote $other 2>&1 | Out-Null
        Set-Content -LiteralPath (Join-Path $other $FileName) -Value 'x'
        git -C $other add -A
        git -C $other -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m $FileName
        git -C $other push -q origin develop 2>&1 | Out-Null
    }

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
            [PSCustomObject]@{
                Commands = @($Commands); JvmArgs = $Context.JvmArgs; WorkspaceDir = $WorkspaceDir
                RefMarkerDuringBuild = (Test-Path -LiteralPath (Join-Path $Context.ReferenceWsDir 'marker.txt'))
            } | ConvertTo-Json -Compress | Set-Content -LiteralPath $env:EDTWT_TEST_CAPTURE -Encoding UTF8
            New-Item -ItemType Directory -Force -Path $WorkspaceDir | Out-Null
            & $script:FakeBuilt $WorkspaceDir @('cf', 'cfe_a', 'retail')
        }
        Mock -ModuleName EdtWorktree -CommandName Get-EdtWtWorkspaceProcesses -MockWith { @() }
        Mock -ModuleName EdtWorktree -CommandName Stop-Process -MockWith { }
        Mock -ModuleName EdtWorktree -CommandName Stop-EdtWtProcesses -MockWith { 0 }
        Mock -ModuleName EdtWorktree -CommandName Start-EdtWtGui -MockWith { }
    }

    It 'батч: cf + рабочие расширения + build + validate, без -DisableProjectChecks' {
        $out = Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false 6>&1 | Out-String
        $cap = & $script:Read
        $cap.Commands | Should -Contain ('import --project "{0}/src/cf"' -f $script:RepoSlash)
        $cap.Commands | Should -Contain ('import --project "{0}/src/cfe_a"' -f $script:RepoSlash)
        @($cap.Commands -match 'cfe_b').Count | Should -Be 0
        @($cap.Commands -match 'cfe_gone').Count | Should -Be 0
        $cap.Commands[-2] | Should -BeExactly 'build --yes true'
        $cap.Commands[-1] | Should -Match '^validate --file ".+\.building/warmup_validation\.tsv" --project-name-list \["cf" "cfe_a"\]$'
        $cap.JvmArgs | Should -Not -Match 'DisableProjectChecks'
        $cap.WorkspaceDir | Should -Be $script:BuildDir
        $out | Should -Match '\[skip\].*cfe_gone'
        $out | Should -Match 'Не в рабочих: cfe_b\. Включить: edt project ext p'
    }

    It 'сначала подтягивает эталонную ветку клона, потом собирает' {
        & $script:PushRemoteCommit 'fresh.txt'
        $out = Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false 6>&1 | Out-String
        Test-Path -LiteralPath (Join-Path $script:Repo 'fresh.txt') | Should -BeTrue
        $out | Should -Match 'подтянуто коммитов: 1'
        $stamp = Get-Content -LiteralPath (Join-Path $script:RefDir '.edtwt-reference.json') -Raw | ConvertFrom-Json
        $stamp.commit | Should -Be (git -C $script:Repo rev-parse HEAD)
        $stamp.branch | Should -Be 'develop'
        @($stamp.projects) | Should -Be @('cf', 'cfe_a')
    }

    It 'грязный клон: отказ до сборки, эталон не тронут' {
        New-Item -ItemType Directory -Force -Path $script:RefDir | Out-Null
        Set-Content -LiteralPath (Join-Path $script:RefDir 'marker.txt') -Value 'old'
        $dirty = Join-Path $script:Repo 'dirty.txt'
        Set-Content -LiteralPath $dirty -Value 'x'
        try {
            $msg = try { Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false 6>$null; '' } catch { $_.Exception.Message }
        } finally {
            Remove-Item -LiteralPath $dirty -Force
        }
        $msg | Should -BeLike 'Клон не обновлён, эталон не пересобирается:*незакоммиченные*'
        Should -Invoke Invoke-EdtWtCli -ModuleName EdtWorktree -Times 0 -Exactly
        Test-Path -LiteralPath (Join-Path $script:RefDir 'marker.txt') | Should -BeTrue
    }

    It '-SkipGit собирает из текущего состояния клона без fetch' {
        & $script:PushRemoteCommit 'skipped.txt'
        Invoke-EdtWorktreeWarmup -ProjectName 'p' -SkipGit -Confirm:$false 6>&1 | Out-Null
        Test-Path -LiteralPath (Join-Path $script:Repo 'skipped.txt') | Should -BeFalse
        Should -Invoke Invoke-EdtWtCli -ModuleName EdtWorktree -Times 1 -Exactly
        git -C $script:Repo pull -q --ff-only 2>&1 | Out-Null
    }

    It 'прежний эталон доступен на время сборки' {
        New-Item -ItemType Directory -Force -Path $script:RefDir | Out-Null
        Set-Content -LiteralPath (Join-Path $script:RefDir 'marker.txt') -Value 'old'
        Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false 6>&1 | Out-Null
        (& $script:Read).RefMarkerDuringBuild | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:RefDir 'marker.txt') | Should -BeFalse
        Test-Path -LiteralPath $script:BuildDir | Should -BeFalse
    }

    It 'проект без результатов проверки: сборка неполная, прежний эталон остаётся' {
        New-Item -ItemType Directory -Force -Path $script:RefDir | Out-Null
        Set-Content -LiteralPath (Join-Path $script:RefDir 'marker.txt') -Value 'old'
        Mock -ModuleName EdtWorktree -CommandName Invoke-EdtWtCli -MockWith {
            New-Item -ItemType Directory -Force -Path $WorkspaceDir | Out-Null
            & $script:FakeBuilt $WorkspaceDir @('cf')
        }
        { Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false 6>&1 | Out-Null } | Should -Throw '*не полностью*cfe_a*'
        Test-Path -LiteralPath (Join-Path $script:RefDir 'marker.txt') | Should -BeTrue
        Test-Path -LiteralPath $script:BuildDir | Should -BeFalse
    }

    It 'служебный проект EGit перепривязывается из каталога сборки на эталон' {
        Mock -ModuleName EdtWorktree -CommandName Invoke-EdtWtCli -MockWith {
            & $script:FakeBuilt $WorkspaceDir @('cf', 'cfe_a')
            $cmp = Join-Path $WorkspaceDir '.metadata\.plugins\org.eclipse.core.resources\.projects\.org.eclipse.egit.core.cmp'
            New-Item -ItemType Directory -Force -Path $cmp | Out-Null
            $uri = "URI//file:/$((Join-Path $WorkspaceDir '.metadata\.plugins\org.eclipse.egit.core\.cmp') -replace '\\', '/')"
            $body = [System.Text.Encoding]::UTF8.GetBytes($uri)
            $bytes = [byte[]]((1..16) + @([byte](($body.Length -shr 8) -band 0xFF), [byte]($body.Length -band 0xFF)) + $body + @(40, 41))
            [System.IO.File]::WriteAllBytes((Join-Path $cmp '.location'), $bytes)
        }
        Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false 6>&1 | Out-Null
        $loc = Join-Path $script:RefDir '.metadata\.plugins\org.eclipse.core.resources\.projects\.org.eclipse.egit.core.cmp\.location'
        $parsed = & $script:m { param($f) Get-EdtWtLocationUri -LocationFile $f } $loc
        $parsed.Value | Should -Not -Match '\.building'
        $parsed.Value | Should -Match '/_reference/\.metadata/'
    }

    It 'проект с именем не по каталогу импортируется, но в validate не попадает' {
        $dotProject = Join-Path $script:Repo 'src\cf\.project'
        $orig = [System.IO.File]::ReadAllText($dotProject)
        [System.IO.File]::WriteAllText($dotProject, $orig.Replace('<name>cf</name>', '<name>retail</name>'), [System.Text.UTF8Encoding]::new($false))
        try {
            # Правка .project делает клон грязным: git здесь не проверяется.
            $out = Invoke-EdtWorktreeWarmup -ProjectName 'p' -SkipGit -Confirm:$false 6>&1 | Out-String
        } finally {
            [System.IO.File]::WriteAllText($dotProject, $orig, [System.Text.UTF8Encoding]::new($false))
        }
        $cap = & $script:Read
        $cap.Commands | Should -Contain ('import --project "{0}/src/cf"' -f $script:RepoSlash)
        $cap.Commands | Should -Contain 'build --yes true'
        $cap.Commands[-1] | Should -Match '^validate --file ".+" --project-name-list \["cfe_a"\]$'
        $out | Should -Match '\[skip\] validate:.*retail \(каталог cf\)'
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
        Test-Path -LiteralPath $script:BuildDir | Should -BeFalse
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

    It 'принимает файл экспорта .epf' {
        $epf = Join-Path $script:Root 'my.epf'
        Set-Content -LiteralPath $epf -Value 'file_export_version=3.0'
        & $script:m { param($d) $c = Get-EdtWtConfig; $c.edt.prefs_source = $d; Save-EdtWtConfig -Config $c | Out-Null } $epf
        try {
            & $script:m { Get-EdtWtPrefsSource -Context ([PSCustomObject]@{ ProjectId = 'p' }) } | Should -Be $epf
        } finally {
            & $script:m { $c = Get-EdtWtConfig; $c.edt.prefs_source = $null; Save-EdtWtConfig -Config $c | Out-Null }
        }
    }
}

Describe 'Настройки IDE из экспорта .epf' {
    BeforeEach {
        $script:Ws = Join-Path $script:Root ('epfws_' + [guid]::NewGuid().ToString('N'))
        $script:Settings = Join-Path $script:Ws '.metadata\.plugins\org.eclipse.core.runtime\.settings'
        New-Item -ItemType Directory -Force -Path $script:Settings | Out-Null
        $script:Epf = Join-Path $script:Root ('prefs_' + [guid]::NewGuid().ToString('N') + '.epf')
        # Кириллица в .epf - экранами \uXXXX (ISO-8859-1), как пишет Eclipse.
        $script:Escaped = (@(0x0413, 0x0440, 0x0443) | ForEach-Object { '\' + 'u' + $_.ToString('X4') }) -join ''
        $lines = @(
            '#Thu Oct 29 12:00:00 QYZT 2026'
            '\!/='
            'file_export_version=3.0'
            '@org.eclipse.ui.editors=3.17.0'
            '/instance/org.eclipse.ui.editors/currentLineColor=65,69,89'
            '/instance/org.eclipse.ui.editors/lineNumberColor=115,121,148'
            "/instance/com._1c.g5.v8.dt.navigator.ui.navigator/searchHistory/patterns=$script:Escaped"
            '/instance/org.eclipse.debug.ui/org.eclipse.debug.ui.PREF_LAUNCH_PERSPECTIVES=<?xml version\="1.0"?>\r\n\'
            '    <launchPerspectives/>\r\n'
            '/configuration/org.eclipse.ui.ide/MAX_RECENT_WORKSPACES=10'
        )
        [System.IO.File]::WriteAllText($script:Epf, (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::Latin1)
    }

    It 'пишет ключи /instance/ в .prefs узлов, сохраняя прочие ключи файла' {
        [System.IO.File]::WriteAllText((Join-Path $script:Settings 'org.eclipse.ui.editors.prefs'),
            "currentLineColor=1,1,1`r`neclipse.preferences.version=1`r`nkeep=me`r`n", [System.Text.Encoding]::Latin1)
        $r = & $script:m { param($e, $w) Import-EdtWtEpf -EpfPath $e -WorkspaceDir $w } $script:Epf $script:Ws
        $r.Applied | Should -Be 4
        $r.Skipped | Should -Be 1
        $editors = [System.IO.File]::ReadAllText((Join-Path $script:Settings 'org.eclipse.ui.editors.prefs'), [System.Text.Encoding]::Latin1)
        $editors | Should -BeExactly "currentLineColor=65,69,89`r`neclipse.preferences.version=1`r`nkeep=me`r`nlineNumberColor=115,121,148`r`n"
        $nav = Get-Content -LiteralPath (Join-Path $script:Settings 'com._1c.g5.v8.dt.navigator.ui.navigator.prefs') -Raw
        $nav | Should -Match ([regex]::Escape("searchHistory/patterns=$script:Escaped"))
        $nav | Should -Match 'eclipse\.preferences\.version=1'
        $debug = Get-Content -LiteralPath (Join-Path $script:Settings 'org.eclipse.debug.ui.prefs') -Raw
        $debug | Should -Match ([regex]::Escape('PREF_LAUNCH_PERSPECTIVES=<?xml version\="1.0"?>\r\n<launchPerspectives/>\r\n'))
        Test-Path -LiteralPath (Join-Path $script:Settings 'org.eclipse.ui.ide.prefs') | Should -BeFalse
    }

    It 'применяется один раз на версию файла и повторно после его изменения' {
        Mock -ModuleName EdtWorktree -CommandName Get-EdtWtWorkspaceProcesses -MockWith { @() }
        & $script:m { param($e) $c = Get-EdtWtConfig; $c.edt.prefs_source = $e; Save-EdtWtConfig -Config $c | Out-Null } $script:Epf
        try {
            $first = & $script:m { param($w) Copy-EdtWtPreferences -Context ([PSCustomObject]@{ ProjectId = 'p' }) -WorkspaceDir $w } $script:Ws 6>$null
            @($first) | Should -Contain 'org.eclipse.ui.editors'
            $prefs = Join-Path $script:Settings 'org.eclipse.ui.editors.prefs'
            [System.IO.File]::WriteAllText($prefs, "currentLineColor=9,9,9`r`n", [System.Text.Encoding]::Latin1)

            $second = & $script:m { param($w) Copy-EdtWtPreferences -Context ([PSCustomObject]@{ ProjectId = 'p' }) -WorkspaceDir $w } $script:Ws 6>$null
            @($second).Count | Should -Be 0
            Get-Content -LiteralPath $prefs -Raw | Should -Match '9,9,9'

            Add-Content -LiteralPath $script:Epf -Value '/instance/org.eclipse.ui.editors/printMarginColor=81,87,109'
            & $script:m { param($w) Copy-EdtWtPreferences -Context ([PSCustomObject]@{ ProjectId = 'p' }) -WorkspaceDir $w } $script:Ws 6>$null | Out-Null
            Get-Content -LiteralPath $prefs -Raw | Should -Match 'currentLineColor=65,69,89'
            Get-Content -LiteralPath $prefs -Raw | Should -Match 'printMarginColor=81,87,109'
        } finally {
            & $script:m { $c = Get-EdtWtConfig; $c.edt.prefs_source = $null; Save-EdtWtConfig -Config $c | Out-Null }
        }
    }

    It 'не применяется к рабочей области, открытой в EDT' {
        Mock -ModuleName EdtWorktree -CommandName Get-EdtWtWorkspaceProcesses -MockWith { @([PSCustomObject]@{ Name = '1cedt.exe'; ProcessId = 3 }) }
        $out = & $script:m { param($e, $w) Copy-EdtWtPreferences -Context ([PSCustomObject]@{ ProjectId = 'p' }) -WorkspaceDir $w -SourceDir $e } $script:Epf $script:Ws 6>&1 | Out-String
        $out | Should -Match 'открыта в EDT'
        Test-Path -LiteralPath (Join-Path $script:Settings 'org.eclipse.ui.editors.prefs') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Ws '.metadata\.edtwt-prefs') | Should -BeFalse
    }
}

Describe 'Test-EdtWtReferenceFreshness' {
    It 'считает отставание эталона от remote-ветки клона и предупреждает' {
        $ctx = & $script:m { param($repo) Get-EdtWtContext -Path $repo -ProjectName 'p' } $script:Repo
        New-Item -ItemType Directory -Force -Path $ctx.ReferenceWsDir | Out-Null
        $head = git -C $script:Repo rev-parse HEAD
        [ordered]@{ branch = 'develop'; commit = $head; built_at = (Get-Date).ToString('o') } | ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $ctx.ReferenceWsDir '.edtwt-reference.json') -Encoding UTF8
        & $script:m { param($c) Test-EdtWtReferenceFreshness -Context $c -Quiet } $ctx | Should -Be 0

        & $script:PushRemoteCommit 'later.txt'
        git -C $script:Repo fetch -q origin 2>&1 | Out-Null
        $out = & $script:m { param($c) Test-EdtWtReferenceFreshness -Context $c } $ctx 6>&1
        @($out | Where-Object { $_ -is [int] }) | Should -Be @(1)
        ($out | Out-String) | Should -Match 'отстал от origin/develop на 1'
        git -C $script:Repo merge -q --ff-only origin/develop 2>&1 | Out-Null
    }

    It 'эталон без отметки сборки: предупреждение и $null' {
        $ctx = & $script:m { param($repo) Get-EdtWtContext -Path $repo -ProjectName 'p' } $script:Repo
        Remove-Item -LiteralPath (Join-Path $ctx.ReferenceWsDir '.edtwt-reference.json') -Force -ErrorAction SilentlyContinue
        $out = & $script:m { param($c) Test-EdtWtReferenceFreshness -Context $c } $ctx 6>&1
        ($out | Out-String) | Should -Match 'нет отметки сборки'
        @($out | Where-Object { $_ -is [int] }).Count | Should -Be 0
    }
}
