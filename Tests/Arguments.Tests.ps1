BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
}

AfterAll {
    Exit-EdtWtTestConfig -State $script:TestCfg
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\EdtWorktree.psd1') -Force
}

Describe 'Split-EdtWtArguments' {
    BeforeAll {
        $script:Split = {
            param($a)
            & (Get-Module EdtWorktree) { param($x) Split-EdtWtArguments $x } $a
        }
    }

    It 'отделяет проект и ветку от ключей' {
        $r = & $script:Split @('test-proj', 'TASK-123', '-Refresh')
        $r.Positional | Should -Be @('test-proj', 'TASK-123')
        $r.Switches | Should -Be @('-Refresh')
    }

    It 'не теряет значение ключа: -RefBranch develop остаётся при ключе' {
        # Регрессия: значение уходило в позиционные и принималось за расширения.
        $r = & $script:Split @('proj', 'task', '-RefBranch', 'develop')
        $r.Positional | Should -Be @('proj', 'task')
        $r.Switches | Should -Be @('-RefBranch', 'develop')
    }

    It 'сохраняет список расширений как позиционный аргумент' {
        $r = & $script:Split @('proj', 'task', 'changed', '--no-gui')
        $r.Positional | Should -Be @('proj', 'task', 'changed')
        $r.Switches | Should -Be @('--no-gui')
    }

    It 'разбирает несколько ключей со значениями и без' {
        $r = & $script:Split @('proj', '-RefBranch', 'develop', '-NoGui', '-Extensions', 'cfe,cfe_mp')
        $r.Positional | Should -Be @('proj')
        $r.Switches | Should -Be @('-RefBranch', 'develop', '-NoGui', '-Extensions', 'cfe,cfe_mp')
    }

    It 'не забирает следующий ключ как значение' {
        $r = & $script:Split @('proj', '-RefBranch', '-NoGui')
        $r.Switches | Should -Be @('-RefBranch', '-NoGui')
    }

    It 'ключей кучи больше нет: -MaxHeap и его значение не склеиваются' {
        $r = & $script:Split @('proj', '-MaxHeap', '8g')
        $r.Positional | Should -Be @('proj', '8g')
    }

    It 'выдерживает пустой ввод' {
        $r = & $script:Split @()
        @($r.Positional).Count | Should -Be 0
        @($r.Switches).Count | Should -Be 0
    }
}

Describe 'Resolve-EdtWtWrapperArgs' {
    BeforeAll {
        $script:Wrap = {
            param($Items)
            & (Get-Module EdtWorktree) {
                param($i) Resolve-EdtWtWrapperArgs -Items $i -Allowed @('-NoGui', '-WhatIf')
            } $Items
        }
    }

    It 'распознаёт переключатели, пришедшие строками' {
        # Регрессия: ключи приходят строками и не должны попадать в позиционные.
        $r = & $script:Wrap @('-NoGui', '-Yes', '-SkipGit', '-Purge', '-NoProjects', '-Refresh')
        $r.Flags.NoGui | Should -BeTrue
        $r.Flags.Yes | Should -BeTrue
        $r.Flags.SkipGit | Should -BeTrue
        $r.Flags.Purge | Should -BeTrue
        $r.Flags.NoProjects | Should -BeTrue
        $r.Flags.Refresh | Should -BeTrue
        @($r.Extensions).Count | Should -Be 0
    }

    It 'забирает значение ключа, а не считает его позиционным: -RefBranch develop' {
        $r = & $script:Wrap @('-RefBranch', 'develop')
        $r.Values.RefBranch | Should -Be 'develop'
        @($r.Extensions).Count | Should -Be 0
    }

    It '-CfProject и корни принимают значение' {
        $r = & $script:Wrap @('-CfProject', 'src/cf', '-ReposRoot', 'D:\git', '-WorktreesRoot', 'D:\wt', '-WorkspacesRoot', 'D:\ws')
        $r.Values.CfProject | Should -Be 'src/cf'
        $r.Values.ReposRoot | Should -Be 'D:\git'
        $r.Values.WorktreesRoot | Should -Be 'D:\wt'
        $r.Values.WorkspacesRoot | Should -Be 'D:\ws'
    }

    It '-Extensions разбирается по запятым' {
        $r = & $script:Wrap @('ka', '-Extensions', 'cfe,cfe_mp')
        $r.Values.Extensions | Should -Be @('cfe', 'cfe_mp')
        $r.Extensions | Should -Be @('ka')
    }

    It 'отделяет позиционные значения от ключей' {
        $r = & $script:Wrap @('changed', '-Refresh', '-RefBranch', 'x')
        $r.Extensions | Should -Be @('changed')
        $r.Flags.Refresh | Should -BeTrue
        $r.Values.RefBranch | Should -Be 'x'
    }

    It 'понимает nushell-написание ключей' {
        $r = & $script:Wrap @('--no-gui', '--refresh', '--what-if', '--yes', '--skip-git', '--no-projects', '--purge',
            '--ref-branch', 'develop', '--cf-project', 'src/cf', '--repos-root', 'a', '--worktrees-root', 'b', '--workspaces-root', 'c')
        $r.Flags.NoGui | Should -BeTrue
        $r.Flags.Refresh | Should -BeTrue
        $r.Flags.WhatIf | Should -BeTrue
        $r.Flags.Yes | Should -BeTrue
        $r.Flags.SkipGit | Should -BeTrue
        $r.Flags.NoProjects | Should -BeTrue
        $r.Flags.Purge | Should -BeTrue
        $r.Values.RefBranch | Should -Be 'develop'
        $r.Values.CfProject | Should -Be 'src/cf'
        $r.Values.ReposRoot | Should -Be 'a'
        $r.Values.WorktreesRoot | Should -Be 'b'
        $r.Values.WorkspacesRoot | Should -Be 'c'
    }

    It '--dry-run равнозначен -WhatIf' {
        (& $script:Wrap @('--dry-run')).Flags.WhatIf | Should -BeTrue
    }

    It 'запоминает, какие ключи были заданы' {
        $r = & $script:Wrap @('--no-gui', '-RefBranch', 'x')
        $r.Used | Should -Be @('NoGui', 'RefBranch')
    }

    It 'ключи прежних версий отвергаются как неизвестные' {
        foreach ($old in '-Force', '-Validate', '-MaxHeap', '-GuiMaxHeap') {
            { & $script:Wrap @($old, '12g') } | Should -Throw -ExpectedMessage "*Неизвестный ключ*"
        }
    }

    It 'сообщает о неизвестном ключе, а не молчит' {
        { & $script:Wrap @('-Unknown') } | Should -Throw -ExpectedMessage "*Неизвестный ключ*"
    }

    It 'требует значение для ключа, которое его ждёт' {
        { & $script:Wrap @('-RefBranch') } | Should -Throw -ExpectedMessage "*требует значения*"
        { & $script:Wrap @('-RefBranch', '-NoGui') } | Should -Throw -ExpectedMessage "*требует значения*"
    }
}
