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

    It 'отделяет проект и задачу от ключей' {
        $r = & $script:Split @('test-proj', 'TASK-123', '-Refresh')
        $r.Positional | Should -Be @('test-proj', 'TASK-123')
        $r.Switches | Should -Be @('-Refresh')
    }

    It 'не теряет значение ключа: -GuiMaxHeap 12g остаётся при ключе' {
        # Регрессия: значение уходило в позиционные и принималось за расширения.
        $r = & $script:Split @('proj', 'task', '-GuiMaxHeap', '12g')
        $r.Positional | Should -Be @('proj', 'task')
        $r.Switches | Should -Be @('-GuiMaxHeap', '12g')
    }

    It 'сохраняет список расширений как позиционный аргумент' {
        $r = & $script:Split @('proj', 'task', 'changed', '--no-gui')
        $r.Positional | Should -Be @('proj', 'task', 'changed')
        $r.Switches | Should -Be @('--no-gui')
    }

    It 'разбирает несколько ключей со значениями и без' {
        $r = & $script:Split @('proj', 'task', '-MaxHeap', '8g', '-NoGui', '-Extensions', 'cfe,cfe_mp')
        $r.Positional | Should -Be @('proj', 'task')
        $r.Switches | Should -Be @('-MaxHeap', '8g', '-NoGui', '-Extensions', 'cfe,cfe_mp')
    }

    It 'не забирает следующий ключ как значение' {
        $r = & $script:Split @('proj', '-MaxHeap', '-NoGui')
        $r.Switches | Should -Be @('-MaxHeap', '-NoGui')
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
                param($i) Resolve-EdtWtWrapperArgs -Items $i -Allowed @('-Force', '-WhatIf')
            } $Items
        }
    }

    It 'распознаёт переключатели, пришедшие строками' {
        # Регрессия: wt.ps1 передаёт ключи splatting-ом массива, а он подставляет
        # элементы ПОЗИЦИОННО - '-Force' попадал в -Extensions и терялся.
        $r = & $script:Wrap @('-Force', '-Validate')
        $r.Flags.Force | Should -BeTrue
        $r.Flags.Validate | Should -BeTrue
        @($r.Extensions).Count | Should -Be 0
    }

    It 'забирает значение ключа, а не считает его расширением' {
        $r = & $script:Wrap @('-GuiMaxHeap', '12g')
        $r.Values.GuiMaxHeap | Should -Be '12g'
        @($r.Extensions).Count | Should -Be 0
    }

    It 'отделяет режим расширений от ключей' {
        $r = & $script:Wrap @('changed', '-Refresh', '-MaxHeap', '8g')
        $r.Extensions | Should -Be @('changed')
        $r.Flags.Refresh | Should -BeTrue
        $r.Values.MaxHeap | Should -Be '8g'
    }

    It 'понимает nushell-написание ключей' {
        $r = & $script:Wrap @('--no-gui', '--refresh', '--what-if')
        $r.Flags.NoGui | Should -BeTrue
        $r.Flags.Refresh | Should -BeTrue
        $r.Flags.WhatIf | Should -BeTrue
    }

    It 'сообщает о неизвестном ключе, а не молчит' {
        { & $script:Wrap @('-Unknown') } | Should -Throw -ExpectedMessage "*Неизвестный ключ*"
    }

    It 'требует значение для ключа, которое его ждёт' {
        { & $script:Wrap @('-MaxHeap') } | Should -Throw -ExpectedMessage "*требует значения*"
    }
}
