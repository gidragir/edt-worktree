BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
    $script:Root = $script:TestCfg.Root
    $script:PrevMark = $env:EDTWT_TEST_MARK
    $env:EDTWT_TEST_MARK = Join-Path $script:Root 'mark.txt'
    Import-Module (Get-EdtWtTestModulePath) -Force -DisableNameChecking
    $script:m = Get-Module EdtWorktree

    $script:Repos = Join-Path $script:Root 'repos'
    $script:Wts = Join-Path $script:Root 'wt'
    $script:Wss = Join-Path $script:Root 'ws'
    $r = New-EdtWtTestRepo -Root $script:Repos -Name 'ka' -Branch 'main' -WithRemote -Projects @{
        'src/cf' = 'Configuration'; 'src/cfe_a' = 'Extension'; 'src/cfe_b' = 'Extension'
    }
    $script:Repo = $r.RepoPath
    # Второй клон не зарегистрирован.
    $script:Loose = (New-EdtWtTestRepo -Root $script:Repos -Name 'loose' -Branch 'main' -Projects @{ 'src/cf' = 'Configuration' }).RepoPath

    $script:Seed = {
        & $script:m {
            param($repos, $wts, $wss)
            $c = Get-EdtWtConfig
            $c.paths.repos_root = $repos
            $c.paths.worktrees_root = $wts
            $c.paths.workspaces_root = $wss
            foreach ($n in @($c.projects.PSObject.Properties).ForEach('Name')) { $c.projects.PSObject.Properties.Remove($n) }
            $def = [PSCustomObject]@{ ref_branch = 'main'; cf_project = 'src/cf'; extensions = [string[]]@('src/cfe_a') }
            Add-Member -InputObject $c.projects -MemberType NoteProperty -Name 'ka' -Value $def
            Save-EdtWtConfig -Config $c | Out-Null
        } $script:Repos $script:Wts $script:Wss
    }
    & $script:Seed
}

AfterAll {
    $env:EDTWT_TEST_MARK = $script:PrevMark
    Exit-EdtWtTestConfig -State $script:TestCfg
}

Describe 'Диспетчер edt: проекты и конфиг' {
    BeforeEach {
        Mock -ModuleName EdtWorktree Get-EdtProject { @() }
        Mock -ModuleName EdtWorktree Add-EdtProject {}
        Mock -ModuleName EdtWorktree Set-EdtProjectExtension {}
        Mock -ModuleName EdtWorktree Set-EdtProject {}
        Mock -ModuleName EdtWorktree Remove-EdtProject {}
        Mock -ModuleName EdtWorktree Get-EdtConfig {}
        Mock -ModuleName EdtWorktree Set-EdtConfig {}
        Mock -ModuleName EdtWorktree Invoke-EdtSetup {}
        Mock -ModuleName EdtWorktree Test-EdtEnvironment { @() }
        Mock -ModuleName EdtWorktree Update-EdtSelf {}
        Mock -ModuleName EdtWorktree Uninstall-EdtWorktree {}
    }

    It 'project list [имя] -> Get-EdtProject' {
        Invoke-EdtCommand project list | Out-Null
        Should -Invoke Get-EdtProject -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { -not $Name }
        Invoke-EdtCommand project list ka | Out-Null
        Should -Invoke Get-EdtProject -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { $Name -eq 'ka' }
    }

    It 'project без подкоманды показывает список' {
        Invoke-EdtCommand project | Out-Null
        Should -Invoke Get-EdtProject -ModuleName EdtWorktree -Exactly 1
    }

    It 'project add передаёт расширения, ветку, конфигурацию и -Yes' {
        Invoke-EdtCommand project add ka -Extensions cfe_a,cfe_b -RefBranch develop -CfProject src/cf -Yes
        Should -Invoke Add-EdtProject -ModuleName EdtWorktree -Exactly 1 -ParameterFilter {
            $Name -eq 'ka' -and ($Extensions -join ',') -eq 'cfe_a,cfe_b' -and $RefBranch -eq 'develop' -and
            $CfProject -eq 'src/cf' -and $Confirm -eq $false
        }
    }

    It 'project add без имени регистрирует все клоны; --dry-run даёт -WhatIf' {
        Invoke-EdtCommand project add --dry-run
        Should -Invoke Add-EdtProject -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { -not $Name -and $WhatIf -eq $true }
    }

    It 'project ext без правок запускает диалог (Change не задан)' {
        Invoke-EdtCommand project ext ka
        Should -Invoke Set-EdtProjectExtension -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { $Name -eq 'ka' -and -not $Change }
    }

    It 'project ext: -Yes и --dry-run остаются ключами, а -cfe_a правкой' {
        Invoke-EdtCommand project ext ka -Yes +cfe_b -cfe_a --dry-run
        Should -Invoke Set-EdtProjectExtension -ModuleName EdtWorktree -Exactly 1 -ParameterFilter {
            $Name -eq 'ka' -and ($Change -join ',') -eq '+cfe_b,-cfe_a' -and $Confirm -eq $false -and $WhatIf -eq $true
        }
    }

    It 'project ext без проекта - ошибка' {
        { Invoke-EdtCommand project ext } | Should -Throw '*Использование*'
    }

    It 'project set / remove' {
        Invoke-EdtCommand project set ka -RefBranch pre-prod
        Should -Invoke Set-EdtProject -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { $Name -eq 'ka' -and $RefBranch -eq 'pre-prod' -and -not $CfProject }
        Invoke-EdtCommand project set ka --cf-project src/cf
        Should -Invoke Set-EdtProject -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { $CfProject -eq 'src/cf' }
        Invoke-EdtCommand project remove ka -Yes
        Should -Invoke Remove-EdtProject -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { $Name -eq 'ka' -and $Confirm -eq $false }
    }

    It 'неизвестная подкоманда project - ошибка со списком' {
        { Invoke-EdtCommand project bogus } | Should -Throw '*list*add*ext*set*remove*'
    }

    It 'ключ не той подкоманды отвергается' {
        { Invoke-EdtCommand project list -RefBranch x } | Should -Throw '*Неизвестный ключ*'
        { Invoke-EdtCommand status -NoGui } | Should -Throw '*Неизвестный ключ*'
        { Invoke-EdtCommand warmup ka -Refresh } | Should -Throw '*Неизвестный ключ*'
    }

    It 'config show/path/set; значение, начинающееся с дефиса, не ключ' {
        Invoke-EdtCommand config | Out-Null
        Invoke-EdtCommand config show | Out-Null
        Should -Invoke Get-EdtConfig -ModuleName EdtWorktree -Exactly 2 -ParameterFilter { -not $Path }
        Invoke-EdtCommand config path | Out-Null
        Should -Invoke Get-EdtConfig -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { $Path }
        Invoke-EdtCommand config set edt.extra_vmargs -Dfoo=bar -Yes
        Should -Invoke Set-EdtConfig -ModuleName EdtWorktree -Exactly 1 -ParameterFilter {
            $Key -eq 'edt.extra_vmargs' -and $Value -eq '-Dfoo=bar' -and $Confirm -eq $false
        }
    }

    It 'config set без значения и config init - ошибки' {
        { Invoke-EdtCommand config set edt.max_heap } | Should -Throw '*Использование*'
        { Invoke-EdtCommand config init } | Should -Throw '*show*path*set*'
    }

    It 'setup передаёт только заданные пути и -NoProjects' {
        Invoke-EdtCommand setup -ReposRoot X:\r --no-projects --yes
        Should -Invoke Invoke-EdtSetup -ModuleName EdtWorktree -Exactly 1 -ParameterFilter {
            $ReposRoot -eq 'X:\r' -and -not $WorktreesRoot -and -not $WorkspacesRoot -and $NoProjects -and $Confirm -eq $false
        }
    }

    It 'doctor, self-update, uninstall' {
        Invoke-EdtCommand doctor | Out-Null
        Should -Invoke Test-EdtEnvironment -ModuleName EdtWorktree -Exactly 1
        Invoke-EdtCommand self-update
        Should -Invoke Update-EdtSelf -ModuleName EdtWorktree -Exactly 1
        Invoke-EdtCommand uninstall -Purge -Yes
        Should -Invoke Uninstall-EdtWorktree -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { $Purge -and $Confirm -eq $false }
    }

    It 'прежние команды init и ключи кучи отвергаются' {
        { Invoke-EdtCommand init } | Should -Throw
        { Invoke-EdtCommand open -GuiMaxHeap 12g } | Should -Throw '*Неизвестный ключ*'
    }

    It 'help печатает справку 3.0' {
        $text = (Invoke-EdtCommand help 6>&1 | Out-String)
        $text | Should -BeLike '*project*'
        $text | Should -BeLike '*setup*'
        $text | Should -BeLike '*doctor*'
        $text | Should -Not -Match 'GuiMaxHeap|-MaxHeap|-Validate|-Force|wt-|edt init'
    }
}

Describe 'Диспетчер edt: рабочие области' {
    BeforeEach {
        & $script:Seed
        Remove-Item -LiteralPath $env:EDTWT_TEST_MARK -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:Wts -Recurse -Force -ErrorAction SilentlyContinue
        Mock -ModuleName EdtWorktree Invoke-EdtWorktreeOpen { (Get-Location).Path | Set-Content -LiteralPath $env:EDTWT_TEST_MARK }
        Mock -ModuleName EdtWorktree Invoke-EdtWorktreeWarmup { (Get-Location).Path | Set-Content -LiteralPath $env:EDTWT_TEST_MARK }
        Mock -ModuleName EdtWorktree Invoke-EdtWorktreeAdd {}
        Mock -ModuleName EdtWorktree Invoke-EdtWorktreeClean {}
        Mock -ModuleName EdtWorktree Get-EdtWorktreeList {}
        Mock -ModuleName EdtWorktree Update-EdtWtReference {}
        Mock -ModuleName EdtWorktree Test-EdtWtInteractive { $false }
    }

    AfterAll {
        # Фикстурные worktree лежат во временном корне; ссылки на них из клона убирает prune.
        & git -C $script:Repo worktree prune 2>$null
    }

    It 'open: короткая ветка получает префикс, worktree создаётся, запуск в нём' {
        Invoke-EdtCommand open ka T-1 --no-gui 6>$null
        $wt = Join-Path (Join-Path $script:Wts 'ka') 'feature-T-1'
        Test-Path -LiteralPath $wt | Should -BeTrue
        (& git -C $wt rev-parse --abbrev-ref HEAD) | Should -Be 'feature/T-1'
        (Get-Content -LiteralPath $env:EDTWT_TEST_MARK -Raw).Trim() | Should -Be $wt
        Should -Invoke Invoke-EdtWorktreeOpen -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { $NoGui -and -not $Refresh }
    }

    It 'open с полным именем ветки и повтор: worktree переиспользуется' {
        Invoke-EdtCommand open ka bugfix/x 6>$null
        $wt = Join-Path (Join-Path $script:Wts 'ka') 'bugfix-x'
        (& git -C $wt rev-parse --abbrev-ref HEAD) | Should -Be 'bugfix/x'
        Mock -ModuleName EdtWorktree New-EdtWtWorktree { throw 'не должен вызываться' }
        Invoke-EdtCommand open ka bugfix/x -Refresh 6>$null
        (Get-Content -LiteralPath $env:EDTWT_TEST_MARK -Raw).Trim() | Should -Be $wt
        Should -Invoke Invoke-EdtWorktreeOpen -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { $Refresh }
    }

    It 'open --dry-run не создаёт worktree и не запускает IDE' {
        $null = Invoke-EdtCommand open ka T-2 --dry-run *>&1
        Test-Path -LiteralPath (Join-Path (Join-Path $script:Wts 'ka') 'feature-T-2') | Should -BeFalse
        Should -Invoke Invoke-EdtWorktreeOpen -ModuleName EdtWorktree -Exactly 0
    }

    It 'open: проект без ветки - ошибка; не проект - не зарегистрирован' {
        { Invoke-EdtCommand open ka } | Should -Throw '*Не указана ветка*'
        { Invoke-EdtCommand open nonexistent T-1 } | Should -Throw '*не зарегистрирован*'
    }

    It 'open без аргументов работает в текущем каталоге' {
        Push-Location -LiteralPath $script:Repo
        try { Invoke-EdtCommand open --no-gui --refresh 6>$null } finally { Pop-Location }
        (Get-Content -LiteralPath $env:EDTWT_TEST_MARK -Raw).Trim() | Should -Be $script:Repo
        Should -Invoke Invoke-EdtWorktreeOpen -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { $NoGui -and $Refresh }
    }

    It 'незарегистрированный клон: без диалога ошибка с командой регистрации' {
        Mock -ModuleName EdtWorktree Add-EdtProject {}
        { Invoke-EdtCommand open loose T-1 } | Should -Throw '*edt project add loose*'
        { Invoke-EdtCommand warmup loose } | Should -Throw '*edt project add loose*'
        # Без аргументов ошибку даёт Get-EdtWtContext (внутри Invoke-EdtWorktreeOpen).
        { Get-EdtWtContext -Path $script:Loose } | Should -Throw '*edt project add loose*'
        Push-Location -LiteralPath $script:Loose
        try { Invoke-EdtCommand open --no-gui 6>$null } finally { Pop-Location }
        Should -Invoke Add-EdtProject -ModuleName EdtWorktree -Exactly 0
    }

    It 'незарегистрированный клон: интерактивно вызывается Add-EdtProject -Name' {
        Mock -ModuleName EdtWorktree Test-EdtWtInteractive { $true }
        Mock -ModuleName EdtWorktree Add-EdtProject {
            & (Get-Module EdtWorktree) {
                param($n)
                $c = Get-EdtWtConfig
                Add-Member -InputObject $c.projects -MemberType NoteProperty -Name $n -Value ([PSCustomObject]@{ ref_branch = 'main'; cf_project = 'src/cf'; extensions = [string[]]@() })
                Save-EdtWtConfig -Config $c | Out-Null
            } $Name
        }
        Invoke-EdtCommand warmup loose 6>$null
        Should -Invoke Add-EdtProject -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { $Name -eq 'loose' }
        Should -Invoke Invoke-EdtWorktreeWarmup -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { $ProjectName -eq 'loose' }
        (Get-Content -LiteralPath $env:EDTWT_TEST_MARK -Raw).Trim() | Should -Be $script:Loose
    }

    It 'незарегистрированный клон: интерактивно open без аргументов тоже предлагает регистрацию' {
        Mock -ModuleName EdtWorktree Test-EdtWtInteractive { $true }
        Mock -ModuleName EdtWorktree Add-EdtProject {}
        Push-Location -LiteralPath $script:Loose
        try { Invoke-EdtCommand open --no-gui 6>$null } finally { Pop-Location }
        Should -Invoke Add-EdtProject -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { $Name -eq 'loose' }
    }

    It 'warmup с проектом запускается в клоне; лишний аргумент - ошибка' {
        Invoke-EdtCommand warmup ka 6>$null
        Should -Invoke Invoke-EdtWorktreeWarmup -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { $ProjectName -eq 'ka' }
        (Get-Content -LiteralPath $env:EDTWT_TEST_MARK -Raw).Trim() | Should -Be $script:Repo
        { Invoke-EdtCommand warmup ka cfe_a } | Should -Throw '*Лишние аргументы*'
    }

    It 'warmup --skip-git передаётся в Invoke-EdtWorktreeWarmup' {
        Invoke-EdtCommand warmup ka --skip-git 6>$null
        Should -Invoke Invoke-EdtWorktreeWarmup -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { $ProjectName -eq 'ka' -and $SkipGit }
    }

    It 'warmup без аргументов берёт проект текущего каталога (ProjectName не задан)' {
        Invoke-EdtCommand warmup 6>$null
        Should -Invoke Invoke-EdtWorktreeWarmup -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { -not $ProjectName }
    }

    It 'add с расширениями и --no-gui; без расширений - ошибка' {
        Invoke-EdtCommand add cfe_a cfe_b --no-gui
        Should -Invoke Invoke-EdtWorktreeAdd -ModuleName EdtWorktree -Exactly 1 -ParameterFilter {
            ($Extensions -join ',') -eq 'cfe_a,cfe_b' -and $NoGui
        }
        { Invoke-EdtCommand add } | Should -Throw '*расширения*'
    }

    It 'remove с проектом и веткой: полная ветка уходит в Clean (не имя папки)' {
        $wt = (Join-Path (Join-Path $script:Wts 'ka') 'feature-T-1')
        Invoke-EdtCommand open ka T-1 --no-gui 6>$null
        Invoke-EdtCommand remove ka T-1 -Yes 6>$null
        Should -Invoke Invoke-EdtWorktreeClean -ModuleName EdtWorktree -Exactly 1 -ParameterFilter {
            $WorktreeId -eq 'feature/T-1' -and $Confirm -eq $false
        }
        (Get-Content -LiteralPath $env:EDTWT_TEST_MARK -Raw).Trim() | Should -Be $wt
    }

    It 'remove только с веткой: нормализация префиксом, текущий каталог' {
        Invoke-EdtCommand remove T-9 --dry-run
        Should -Invoke Invoke-EdtWorktreeClean -ModuleName EdtWorktree -Exactly 1 -ParameterFilter {
            $WorktreeId -eq 'feature/T-9' -and $WhatIf -eq $true
        }
        Invoke-EdtCommand remove bugfix/y
        Should -Invoke Invoke-EdtWorktreeClean -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { $WorktreeId -eq 'bugfix/y' }
    }

    It 'remove без аргументов - текущий worktree; проект без ветки - ошибка' {
        Invoke-EdtCommand remove
        Should -Invoke Invoke-EdtWorktreeClean -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { -not $WorktreeId }
        { Invoke-EdtCommand remove ka } | Should -Throw '*Не указана ветка*'
    }

    It 'remove несуществующего worktree - ошибка' {
        { Invoke-EdtCommand remove ka T-404 } | Should -Throw '*Worktree не найден*'
    }

    It 'status и update' {
        Invoke-EdtCommand status ka
        Should -Invoke Get-EdtWorktreeList -ModuleName EdtWorktree -Exactly 1 -ParameterFilter { $ProjectName -eq 'ka' }
        Invoke-EdtCommand update ka kb --skip-git
        Should -Invoke Update-EdtWtReference -ModuleName EdtWorktree -Exactly 1 -ParameterFilter {
            ($Project -join ',') -eq 'ka,kb' -and $SkipGit
        }
    }
}

Describe 'Автодополнение edt' {
    BeforeAll {
        & $script:Seed
        $script:Complete = {
            param([string]$Line)
            @([System.Management.Automation.CommandCompletion]::CompleteInput($Line, $Line.Length, $null).CompletionMatches | ForEach-Object CompletionText)
        }
    }

    It 'подкоманды' {
        # PowerShell сортирует подсказки ValidateSet по алфавиту.
        $r = & $script:Complete 'edt '
        $r | Sort-Object | Should -Be @('open', 'warmup', 'add', 'remove', 'status', 'update', 'vr', 'setup', 'project', 'config', 'doctor', 'self-update', 'uninstall', 'help' | Sort-Object)
    }

    It 'project -> list add ext set remove' {
        (& $script:Complete 'edt project ') | Should -Be @('list', 'add', 'ext', 'set', 'remove')
    }

    It 'config -> show path set и ключи для set' {
        (& $script:Complete 'edt config ') | Should -Be @('show', 'path', 'set')
        (& $script:Complete 'edt config set ') | Should -Contain 'paths.repos_root'
        (& $script:Complete 'edt config set edt.m') | Should -Be @('edt.max_heap')
    }

    It 'имена проектов после open, warmup, update, remove и project (подкоманды с проектом)' {
        foreach ($line in 'edt open ', 'edt warmup ', 'edt update ', 'edt remove ', 'edt project ext ', 'edt project set ', 'edt project remove ', 'edt project list ') {
            (& $script:Complete $line) | Should -Be @('ka') -Because $line
        }
    }

    It 'project add предлагает незарегистрированные клоны' {
        (& $script:Complete 'edt project add ') | Should -Be @('loose')
    }

    It 'после project ext и имени проекта: +имя для нерабочих и -имя для рабочих' {
        $r = & $script:Complete 'edt project ext ka +'
        $r | Should -Be @('+cfe_b')
        $all = & $script:Complete 'edt project ext ka '
        $all | Should -Contain '+cfe_b'
        $all | Should -Contain '-cfe_a'
        $all | Should -Not -Contain '+cfe_a'
    }

    It 'значение ключа не считается позиционным аргументом' {
        (& $script:Complete 'edt project add -RefBranch main ') | Should -Be @('loose')
    }
}

Describe 'Автодополнение edt: безопасность и ветки' {
    BeforeAll {
        $script:Complete = {
            param([string]$Line)
            @([System.Management.Automation.CommandCompletion]::CompleteInput($Line, $Line.Length, $null).CompletionMatches | ForEach-Object CompletionText)
        }
        $script:CfgFile = $env:EDT_CONFIG_PATH
    }

    AfterAll { & $script:Seed }

    It 'повреждённый конфиг: пусто, без исключения, файл не тронут' {
        [IO.File]::WriteAllText($script:CfgFile, '{ broken')
        $before = [IO.File]::ReadAllBytes($script:CfgFile)
        { & $script:Complete 'edt project ' } | Should -Not -Throw
        # PowerShell сам подставляет имена файлов, когда подсказок нет: наших кандидатов быть не должно.
        (& $script:Complete 'edt project ') | Should -Not -Contain 'list'
        (& $script:Complete 'edt open ') | Should -Not -Contain 'ka'
        [IO.File]::ReadAllBytes($script:CfgFile) | Should -Be $before
    }

    It 'конфиг старше v3: пусто, файл не тронут, .v2.bak нет' {
        [IO.File]::WriteAllText($script:CfgFile, '{"paths":{"projects_root":"X:\r"},"projects":{"ka":{}}}')
        $before = [IO.File]::ReadAllBytes($script:CfgFile)
        (& $script:Complete 'edt open ') | Should -Not -Contain 'ka'
        [IO.File]::ReadAllBytes($script:CfgFile) | Should -Be $before
        @(Get-ChildItem -LiteralPath (Split-Path $script:CfgFile) -Filter '*.v2.bak').Count | Should -Be 0
    }

    It 'конфиг отсутствует: пусто, файл не создаётся' {
        Remove-Item -LiteralPath $script:CfgFile -Force -ErrorAction SilentlyContinue
        (& $script:Complete 'edt open ') | Should -Not -Contain 'ka'
        Test-Path -LiteralPath $script:CfgFile | Should -BeFalse
    }

    It 'конфиг v3 работает как раньше' {
        & $script:Seed
        (& $script:Complete 'edt open ') | Should -Be @('ka')
    }

    It 'ветки: только имена, переживающие Resolve-EdtWtBranchName' {
        & $script:Seed
        foreach ($b in 'feature/T-5', 'develop', 'bugfix/y', 'feature/a/b') {
            & git -C $script:Repo branch $b 2>$null
        }
        $r = & $script:Complete 'edt open ka '
        $r | Should -Contain 'T-5'
        $r | Should -Contain 'bugfix/y'
        $r | Should -Contain 'feature/a/b'
        $r | Should -Not -Contain 'develop'
        $r | Should -Not -Contain 'main'
        $r | Should -Not -Contain 'feature/T-5'
        foreach ($name in $r) {
            $full = & $script:m { param($n) Resolve-EdtWtBranchName -Name $n -Prefix 'feature/' } $name
            (& git -C $script:Repo branch --list $full) | Should -Not -BeNullOrEmpty -Because $name
        }
    }
}

