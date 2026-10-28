BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
    $script:Root = $script:TestCfg.Root
    Import-Module (Join-Path $PSScriptRoot '..\EdtWorktree.psd1') -Force -DisableNameChecking
    $script:m = Get-Module EdtWorktree

    # Корни с пробелом и кириллицей: путь к клонам и к worktree.
    $script:Repos = Join-Path $script:Root 'Интеграция с Каспи'
    $script:Wts = Join-Path $script:Root 'Рабочие деревья\wt'
    $script:Wss = Join-Path $script:Root 'ws'
    $r = New-EdtWtTestRepo -Root $script:Repos -Name 'proj' -WithRemote -Projects @{ 'src/cf' = 'Configuration'; 'src/cfe_a' = 'Extension' }
    $script:Repo = $r.RepoPath
    New-EdtWtTestRepo -Root $script:Repos -Name 'other' | Out-Null
    git -C $script:Repo push -q origin main:develop

    & $script:m {
        param($repos, $wts, $wss)
        $c = Get-EdtWtConfig
        $c.paths.repos_root = $repos
        $c.paths.worktrees_root = $wts
        $c.paths.workspaces_root = $wss
        $c.edt.cli_path = 'C:\Program Files\1C\1CE\components\1cedtcli.bat'
        $def = [PSCustomObject]@{ ref_branch = 'develop'; cf_project = 'src/cf'; extensions = [string[]]@('src/cfe_a') }
        Add-Member -InputObject $c.projects -MemberType NoteProperty -Name 'proj' -Value $def
        Save-EdtWtConfig -Config $c | Out-Null
    } $script:Repos $script:Wts $script:Wss

    $script:Cfg = & $script:m { Get-EdtWtConfig }
    $script:Same = { param($a, $b) & $script:m { param($a, $b) Test-EdtWtSamePath -A $a -B $b } $a $b }
}

AfterAll {
    Exit-EdtWtTestConfig -State $script:TestCfg
}

Describe 'Test-EdtWtSamePath' {
    It 'сравнение путей без учёта регистра и хвостового слеша' {
        & $script:m { Test-EdtWtSamePath -A 'd:\ws\p\x\' -B 'D:\WS\p\x' } | Should -BeTrue
        & $script:m { Test-EdtWtSamePath -A 'D:\ws\p\x1' -B 'D:\ws\p\x10' } | Should -BeFalse
    }
}

Describe 'Resolve-EdtWtProjectFromPath' {
    BeforeAll {
        $script:WtPath = Join-Path $script:Wts 'proj\feature-T-1'
        git -C $script:Repo worktree add -q -b feature/T-1 $script:WtPath
        $script:Resolve = { param($p, $c) & $script:m { param($p, $c) Resolve-EdtWtProjectFromPath -Path $p -Config $c } $p $c }
    }

    It 'проект определяется и в клоне, и в его worktree (путь с пробелом и кириллицей)' {
        (& $script:Resolve $script:WtPath $script:Cfg).Name | Should -Be 'proj'
        $inClone = & $script:Resolve $script:Repo $script:Cfg
        $inClone.Name | Should -Be 'proj'
        $inClone.Registered | Should -BeTrue
        & $script:Same $inClone.RepoPath $script:Repo | Should -BeTrue
    }
    It 'RepoPath из worktree указывает на клон' {
        $r = & $script:Resolve $script:WtPath $script:Cfg
        & $script:Same $r.RepoPath $script:Repo | Should -BeTrue
    }
    It 'подкаталог клона тоже определяется' {
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'src\cfe_a') -Force | Out-Null
        (& $script:Resolve (Join-Path $script:Repo 'src\cfe_a') $script:Cfg).Name | Should -Be 'proj'
    }
    It 'незарегистрированный клон: Registered = $false' {
        $r = & $script:Resolve (Join-Path $script:Repos 'other') $script:Cfg
        $r.Name | Should -Be 'other'
        $r.Registered | Should -BeFalse
    }
    It 'repos_root сравнивается без учёта регистра и слеша' {
        $cfg2 = & $script:m { Get-EdtWtConfig }
        $cfg2.paths.repos_root = $script:Repos.ToUpperInvariant() + '\'
        (& $script:Resolve $script:Repo $cfg2).Name | Should -Be 'proj'
    }
    It 'клон вне repos_root и не-git каталог дают $null' {
        $outside = New-EdtWtTestRepo -Root (Join-Path $script:Root 'elsewhere') -Name 'x'
        & $script:Resolve $outside.RepoPath $script:Cfg | Should -BeNullOrEmpty
        $plain = Join-Path $script:Root 'plain'
        New-Item -ItemType Directory -Path $plain -Force | Out-Null
        & $script:Resolve $plain $script:Cfg | Should -BeNullOrEmpty
        & $script:Resolve (Join-Path $script:Root 'нет такого') $script:Cfg | Should -BeNullOrEmpty
    }
}

Describe 'Get-EdtWtContext' {
    BeforeAll {
        $script:WtPath2 = Join-Path $script:Wts 'proj\feature-T-2'
        git -C $script:Repo worktree add -q -b feature/T-2 $script:WtPath2
    }

    It 'эталонная ветка берётся из проекта' {
        (Get-EdtWtContext -Path $script:Repo).RefBranch | Should -Be 'develop'
    }
    It 'в worktree: проект, пути, расширения и эталон' {
        $c = Get-EdtWtContext -Path $script:WtPath2
        $c.ProjectId | Should -Be 'proj'
        $c.Branch | Should -Be 'feature/T-2'
        $c.WorktreeId | Should -Be 'feature-T-2'
        $c.Extensions | Should -Be @('src/cfe_a')
        $c.CfProject | Should -Be 'src/cf'
        $c.ReferenceWsDir | Should -Be (Join-Path $script:Wss 'proj\_reference')
        $c.WorkspaceDir | Should -Be (Join-Path $script:Wss 'proj\feature-T-2')
        & $script:Same $c.RepoPath $script:Repo | Should -BeTrue
        $c.EdtCliPath | Should -Be 'C:\Program Files\1C\1CE\components\1cedtcli.bat'
        $c.PSObject.Properties.Name | Should -Not -Contain 'ReferenceBranch'
        $c.PSObject.Properties.Name | Should -Not -Contain 'ActiveExtensions'
    }
    It 'незарегистрированный клон - ошибка с командой регистрации' {
        { Get-EdtWtContext -Path (Join-Path $script:Repos 'other') } | Should -Throw '*edt project add other*'
    }
    It '-ProjectName без пути берёт клон из repos_root' {
        Push-Location -LiteralPath $script:Root
        try { (Get-EdtWtContext -ProjectName 'proj').ProjectId | Should -Be 'proj' } finally { Pop-Location }
    }
    It 'каталог вне repos_root - понятная ошибка' {
        $plain = Join-Path $script:Root 'plain2'
        New-Item -ItemType Directory -Path $plain -Force | Out-Null
        { Get-EdtWtContext -Path $plain } | Should -Throw '*repos_root*'
    }
}

Describe 'Resolve-EdtWtBranchName' {
    It 'короткое имя дополняется префиксом' {
        & $script:m { Resolve-EdtWtBranchName -Name 'T-1' -Prefix 'feature/' } | Should -Be 'feature/T-1'
    }
    It 'имя со слешем остаётся как есть' {
        & $script:m { Resolve-EdtWtBranchName -Name 'bugfix/x' -Prefix 'feature/' } | Should -Be 'bugfix/x'
    }
}

Describe 'New-EdtWtWorktree' {
    BeforeAll {
        Mock -ModuleName EdtWorktree Write-Host { }
        # Ветка bugfix/x есть только на remote.
        git -C $script:Repo branch bugfix/x
        git -C $script:Repo push -q origin bugfix/x
        git -C $script:Repo branch -q -D bugfix/x
        # Локальная ветка без worktree.
        git -C $script:Repo branch local/only
        $script:New = { param($b) & $script:m { param($b) New-EdtWtWorktree -Project 'proj' -Branch $b } $b }
    }

    It 'ветка с remote подключается с отслеживанием' {
        $wt = & $script:New 'bugfix/x'
        $wt | Should -Be (Join-Path $script:Wts 'proj\bugfix-x')
        git -C $wt rev-parse --abbrev-ref '@{u}' | Should -Be 'origin/bugfix/x'
    }
    It 'новая ветка создаётся от remote/ref_branch проекта' {
        $wt = & $script:New 'feature/new'
        $wt | Should -Be (Join-Path $script:Wts 'proj\feature-new')
        git -C $wt merge-base --is-ancestor origin/develop HEAD
        $LASTEXITCODE | Should -Be 0
        git -C $wt rev-parse --abbrev-ref HEAD | Should -Be 'feature/new'
    }
    It 'локальная ветка подключается без пересоздания' {
        $wt = & $script:New 'local/only'
        git -C $wt rev-parse --abbrev-ref HEAD | Should -Be 'local/only'
    }
    It 'существующий worktree ветки (в другом месте) используется повторно' {
        $other = Join-Path $script:Root 'вне корня\custom wt'
        git -C $script:Repo worktree add -q -b feature/elsewhere $other
        $wt = & $script:New 'feature/elsewhere'
        & $script:Same $wt $other | Should -BeTrue
    }
    It 'повторный вызов возвращает тот же путь' {
        (& $script:New 'feature/new') | Should -Be (Join-Path $script:Wts 'proj\feature-new')
    }
    It 'незарегистрированный проект - ошибка' {
        { & $script:m { New-EdtWtWorktree -Project 'other' -Branch 'feature/q' } } | Should -Throw '*edt project add other*'
    }
}

Describe 'Get-EdtWtContext: авто-куча' {
    It 'без edt.max_heap в JvmArgs нет жёсткого -Xmx (кучу подберёт Resolve-EdtWtJvmArgs)' {
        (Get-EdtWtContext -Path $script:Repo).JvmArgs | Should -Not -Match '-Xmx'
    }
    It 'без edt.gui_max_heap GuiMaxHeap пуст' {
        (Get-EdtWtContext -Path $script:Repo).GuiMaxHeap | Should -BeNullOrEmpty
    }
}
