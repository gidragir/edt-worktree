BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\EdtWorktree.psd1') -Force

    function New-TestVrunnerContext {
        # Тестовая фикстура во временном каталоге.
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
        param([string]$Root, [switch]$NoSettings, [switch]$NoWorkspace)
        $wt = Join-Path $Root 'wt'
        $ws = Join-Path $Root 'ws'
        New-Item -ItemType Directory -Force -Path $wt | Out-Null
        if (-not $NoWorkspace) { New-Item -ItemType Directory -Force -Path $ws | Out-Null }
        if (-not $NoSettings) { Set-Content -LiteralPath (Join-Path $wt 'autumn-properties.json') -Value '{}' }
        return [PSCustomObject]@{
            WorktreePath = $wt
            WorkspaceDir = $ws
            EdtCliPath   = 'C:\edt\1cedtcli.exe'
            JvmArgs      = '-Xmx16g -Xms4g'
            TimeoutSec   = 7200
        }
    }

    function Get-TestPlan {
        param($Context, [string[]]$Arguments = @(), [string[]]$PresetEnv = @())
        & (Get-Module EdtWorktree) {
            param($c, $a, $p) Resolve-EdtWtVrunnerPlan -Context $c -Arguments $a -PresetEnv $p
        } $Context $Arguments $PresetEnv
    }
}

Describe 'Resolve-EdtWtVrunnerPlan' {
    BeforeEach {
        $script:Root = Join-Path ([System.IO.Path]::GetTempPath()) ("edtvr_" + [guid]::NewGuid().ToString('N'))
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:Root) { Remove-Item -LiteralPath $script:Root -Recurse -Force }
    }

    It 'задаёт окружение vrunner из контекста worktree' {
        $ctx = New-TestVrunnerContext -Root $script:Root
        $plan = Get-TestPlan -Context $ctx -Arguments @('validate', 'edt')

        $plan.Env['VRUNNER_EDT_WORKSPACE'] | Should -Be $ctx.WorkspaceDir
        $plan.Env['VRUNNER_EDT_PATH'] | Should -Be $ctx.EdtCliPath
        $plan.Env['VRUNNER_EDT_TIMEOUT'] | Should -Be '7200'
        $plan.Env['VRUNNER_EDT_VMARGS'] | Should -Match '^-Xmx\d+g$'
        $plan.WorkingDirectory | Should -Be $ctx.WorktreePath
        $plan.Arguments | Should -Be @('validate', 'edt')
    }

    It 'не перезаписывает переменные, заданные пользователем' {
        $ctx = New-TestVrunnerContext -Root $script:Root
        $plan = Get-TestPlan -Context $ctx -Arguments @('validate', 'edt') -PresetEnv @('VRUNNER_EDT_WORKSPACE')

        $plan.Env.Contains('VRUNNER_EDT_WORKSPACE') | Should -BeFalse
        $plan.Env.Contains('VRUNNER_EDT_PATH') | Should -BeTrue
    }

    It 'без autumn-properties.json завершается ошибкой, понятной по тексту' {
        $ctx = New-TestVrunnerContext -Root $script:Root -NoSettings
        { Get-TestPlan -Context $ctx -Arguments @('validate', 'edt') } | Should -Throw '*autumn-properties.json не найден*'
    }

    It 'с явным --settings не требует autumn-properties.json' {
        $ctx = New-TestVrunnerContext -Root $script:Root -NoSettings
        $plan = Get-TestPlan -Context $ctx -Arguments @('validate', 'edt', '--settings', 'env.json')

        $plan.Arguments | Should -Be @('validate', 'edt', '--settings', 'env.json')
        $plan.Env['VRUNNER_EDT_WORKSPACE'] | Should -Be $ctx.WorkspaceDir
    }

    It 'принимает --settings=путь без autumn-properties.json' {
        $ctx = New-TestVrunnerContext -Root $script:Root -NoSettings
        { Get-TestPlan -Context $ctx -Arguments @('validate', 'edt', '--settings=env.json') } | Should -Not -Throw
    }

    It 'без рабочей области подсказывает edt open' {
        $ctx = New-TestVrunnerContext -Root $script:Root -NoWorkspace
        { Get-TestPlan -Context $ctx -Arguments @('validate', 'edt') } | Should -Throw '*edt open*'
    }

    Context 'инкрементальная загрузка' {
        It 'добавляет --increment к cf load' {
            $ctx = New-TestVrunnerContext -Root $script:Root
            $plan = Get-TestPlan -Context $ctx -Arguments @('cf', 'load', 'src/cf')

            # Опция обязана стоять до позиционного SRC, иначе vrunner не читает параметры.
            $plan.Arguments | Should -Be @('cf', 'load', '--increment', 'src/cf')
            $plan.Notes | Should -Not -BeNullOrEmpty
        }

        It 'добавляет --increment к cfe load' {
            $ctx = New-TestVrunnerContext -Root $script:Root
            $plan = Get-TestPlan -Context $ctx -Arguments @('cfe', 'load', 'src/cfe')

            $plan.Arguments | Should -Contain '--increment'
        }

        It 'находит cfe load, если перед командой стоят опции' {
            $ctx = New-TestVrunnerContext -Root $script:Root
            $plan = Get-TestPlan -Context $ctx -Arguments @('--settings', 'x.json', 'cfe', 'load', 'src/cfe_YAXUNIT', '--extension-name', 'YAXUNIT', '--src-format', 'edt')

            $plan.Arguments | Should -Be @('--settings', 'x.json', 'cfe', 'load', '--increment', 'src/cfe_YAXUNIT', '--extension-name', 'YAXUNIT', '--src-format', 'edt')
        }

        It 'не трогает остальные команды' {
            $ctx = New-TestVrunnerContext -Root $script:Root
            $plan = Get-TestPlan -Context $ctx -Arguments @('test', 'yaxunit', '--modules', 'X')

            $plan.Arguments | Should -Not -Contain '--increment'
            $plan.Notes | Should -BeNullOrEmpty
        }

        It '-Full отключает подстановку и не попадает в vrunner' {
            $ctx = New-TestVrunnerContext -Root $script:Root
            $plan = Get-TestPlan -Context $ctx -Arguments @('cf', 'load', '-Full')

            $plan.Arguments | Should -Be @('cf', 'load')
        }

        It 'переносит --increment, стоящий до команды, на место после load' {
            $ctx = New-TestVrunnerContext -Root $script:Root
            $plan = Get-TestPlan -Context $ctx -Arguments @('--settings', 'x.json', '--increment', 'cf', 'load', 'src/cf')

            $plan.Arguments | Should -Be @('--settings', 'x.json', 'cf', 'load', '--increment', 'src/cf')
        }

        It 'переносит --increment, стоящий после SRC, на место после load' {
            $ctx = New-TestVrunnerContext -Root $script:Root
            $plan = Get-TestPlan -Context $ctx -Arguments @('cfe', 'load', 'src/cfe', '--increment')

            $plan.Arguments | Should -Be @('cfe', 'load', '--increment', 'src/cfe')
        }

        It '-Full убирает и явный --increment' {
            $ctx = New-TestVrunnerContext -Root $script:Root
            $plan = Get-TestPlan -Context $ctx -Arguments @('cf', 'load', '--increment', '-Full', 'src/cf')

            $plan.Arguments | Should -Be @('cf', 'load', 'src/cf')
        }

        It 'не дублирует --increment, переданный явно' {
            $ctx = New-TestVrunnerContext -Root $script:Root
            $plan = Get-TestPlan -Context $ctx -Arguments @('cf', 'load', '--increment')

            @($plan.Arguments | Where-Object { $_ -eq '--increment' }).Count | Should -Be 1
        }
    }
}
