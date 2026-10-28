BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
    $script:Root = $script:TestCfg.Root
    $script:cfg = $script:TestCfg.Path
    $script:ReposRoot = Join-Path $script:Root 'repos'
    New-Item -ItemType Directory -Path $script:ReposRoot -Force | Out-Null
    Import-Module (Join-Path $PSScriptRoot '..\EdtWorktree.psd1') -Force -DisableNameChecking
    $script:m = Get-Module EdtWorktree

    $r = New-EdtWtTestRepo -Root $script:ReposRoot -Name 'p' -Projects @{ 'src/cf' = 'Configuration'; 'src/cfe_a' = 'Extension'; 'src/cfe_b' = 'Extension' }
    $script:repo = $r.RepoPath
    New-EdtWtTestRepo -Root $script:ReposRoot -Name 'two' -Branch 'dev' -Projects @{ 'src/cf1' = 'Configuration'; 'src/cf2' = 'Configuration'; 'src/cfe_x' = 'Extension' } | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:ReposRoot 'not-a-repo') -Force | Out-Null

    function script:Read-TestConfig { Get-Content -LiteralPath $script:cfg -Raw | ConvertFrom-Json }
    function script:Get-TestProjectNames { @((Read-TestConfig).projects.PSObject.Properties | ForEach-Object { $_.Name }) }
}

AfterAll {
    Exit-EdtWtTestConfig -State $script:TestCfg
}

Describe 'Команды edt project' {
    BeforeEach {
        Remove-Item -LiteralPath $script:cfg -Force -ErrorAction SilentlyContinue
        & $script:m {
            param($root, $repos)
            $c = Get-EdtWtConfig
            $c.paths.repos_root = $repos
            $c.paths.worktrees_root = Join-Path $root 'wt'
            $c.paths.workspaces_root = Join-Path $root 'ws'
            Save-EdtWtConfig -Config $c | Out-Null
        } $script:Root $script:ReposRoot
        # Ни один тест не должен зависнуть на вводе: по умолчанию сеанс неинтерактивный, а вопрос - ошибка.
        Mock -ModuleName EdtWorktree Test-EdtWtInteractive { $false }
        Mock -ModuleName EdtWorktree Write-Host { }
        Mock -ModuleName EdtWorktree Read-EdtWtAnswer { throw "Неожиданный вопрос: $Prompt" }
    }

    Context 'Add-EdtProject' {
        It 'неинтерактивно регистрирует проект с выбранными расширениями' {
            Add-EdtProject -Name 'p' -Extensions 'cfe_a' -Confirm:$false
            $p = (Read-TestConfig).projects.p
            $p.cf_project | Should -Be 'src/cf'
            $p.extensions | Should -Be @('src/cfe_a')
            $p.ref_branch | Should -Be 'main'
        }
        It 'неинтерактивно без -Extensions не зависает, а падает с подсказкой' {
            { Add-EdtProject -Name 'p' -Confirm:$false } | Should -Throw '*-Extensions*'
            Should -Invoke -ModuleName EdtWorktree Read-EdtWtAnswer -Times 0
            (Get-TestProjectNames) | Should -Not -Contain 'p'
        }
        It 'интерактивно принимает номера' {
            Mock -ModuleName EdtWorktree Test-EdtWtInteractive { $true }
            Mock -ModuleName EdtWorktree Read-EdtWtAnswer { param($Prompt, $Default) if ($Prompt -match 'ветка') { $Default } else { '1 2' } }
            Add-EdtProject -Name 'p' -Confirm:$false
            (Read-TestConfig).projects.p.extensions | Should -Be @('src/cfe_a', 'src/cfe_b')
        }
        It 'интерактивно берёт эталонную ветку из ответа' {
            Mock -ModuleName EdtWorktree Test-EdtWtInteractive { $true }
            Mock -ModuleName EdtWorktree Read-EdtWtAnswer { param($Prompt) if ($Prompt -match 'ветка') { 'pre-prod' } else { 'нет' } }
            Add-EdtProject -Name 'p' -Confirm:$false
            $p = (Read-TestConfig).projects.p
            $p.ref_branch | Should -Be 'pre-prod'
            @($p.extensions).Count | Should -Be 0
        }
        It '-Extensions all и none работают без диалога' {
            Add-EdtProject -Name 'p' -Extensions 'all' -Confirm:$false
            (Read-TestConfig).projects.p.extensions | Should -Be @('src/cfe_a', 'src/cfe_b')
            Remove-EdtProject -Name 'p' -Confirm:$false
            Add-EdtProject -Name 'p' -Extensions 'none' -Confirm:$false
            @((Read-TestConfig).projects.p.extensions).Count | Should -Be 0
        }
        It '-RefBranch перекрывает текущую ветку и не задаёт вопросов' {
            Add-EdtProject -Name 'p' -Extensions 'none' -RefBranch 'pre-prod' -Confirm:$false
            (Read-TestConfig).projects.p.ref_branch | Should -Be 'pre-prod'
        }
        It 'неизвестное расширение в -Extensions - ошибка со списком найденных' {
            { Add-EdtProject -Name 'p' -Extensions 'nope' -Confirm:$false } | Should -Throw '*cfe_a*'
        }
        It 'несколько конфигураций неинтерактивно требуют -CfProject' {
            { Add-EdtProject -Name 'two' -Extensions 'none' -Confirm:$false } | Should -Throw '*-CfProject*'
            Add-EdtProject -Name 'two' -Extensions 'cfe_x' -CfProject 'src/cf2' -Confirm:$false
            $p = (Read-TestConfig).projects.two
            $p.cf_project | Should -Be 'src/cf2'
            $p.ref_branch | Should -Be 'dev'
        }
        It 'несколько конфигураций интерактивно выбираются номером' {
            Mock -ModuleName EdtWorktree Test-EdtWtInteractive { $true }
            Mock -ModuleName EdtWorktree Read-EdtWtAnswer {
                param($Prompt, $Default)
                if ($Prompt -match 'ветка') { $Default } elseif ($Prompt -match 'Конфигурация') { '2' } else { 'нет' }
            }
            Add-EdtProject -Name 'two' -Confirm:$false
            (Read-TestConfig).projects.two.cf_project | Should -Be 'src/cf2'
        }
        It 'уже зарегистрированный проект пропускается с предупреждением' {
            Add-EdtProject -Name 'p' -Extensions 'cfe_a' -Confirm:$false
            Add-EdtProject -Name 'p' -Extensions 'cfe_b' -Confirm:$false -WarningVariable w -WarningAction SilentlyContinue
            "$w" | Should -BeLike '*уже зарегистрирован*'
            (Read-TestConfig).projects.p.extensions | Should -Be @('src/cfe_a')
        }
        It 'без имени регистрирует все незарегистрированные клоны, не трогая каталоги без .git' {
            Add-EdtProject -Name 'two' -Extensions 'none' -CfProject 'src/cf2' -Confirm:$false
            Add-EdtProject -Extensions 'none' -Confirm:$false
            $names = (Get-TestProjectNames)
            $names | Should -Contain 'p'
            $names | Should -Not -Contain 'not-a-repo'
            @($names).Count | Should -Be 2
        }
        It 'несуществующий клон - ошибка' {
            { Add-EdtProject -Name 'nope' -Extensions 'none' -Confirm:$false } | Should -Throw '*nope*'
        }
        It 'имя с разделителем пути отклоняется' {
            { Add-EdtProject -Name '..\p' -Extensions 'none' -Confirm:$false } | Should -Throw
        }
        It '-WhatIf ничего не пишет' {
            Add-EdtProject -Name 'p' -Extensions 'all' -WhatIf
            (Get-TestProjectNames) | Should -Not -Contain 'p'
        }
    }

    Context 'Set-EdtProjectExtension' {
        BeforeEach { Add-EdtProject -Name 'p' -Extensions 'cfe_a' -Confirm:$false }

        It '+/- меняет набор без диалога' {
            Set-EdtProjectExtension -Name 'p' -Change '+cfe_b', '-cfe_a'
            (Read-TestConfig).projects.p.extensions | Should -Be @('src/cfe_b')
        }
        It 'принимает относительный путь' {
            Set-EdtProjectExtension -Name 'p' -Change '+src/cfe_b'
            (Read-TestConfig).projects.p.extensions | Should -Be @('src/cfe_a', 'src/cfe_b')
        }
        It 'неизвестное расширение - ошибка со списком' {
            { Set-EdtProjectExtension -Name 'p' -Change '+nope' } | Should -Throw '*cfe_a*'
        }
        It 'имя без + или - - ошибка' {
            { Set-EdtProjectExtension -Name 'p' -Change 'cfe_b' } | Should -Throw '*+*'
        }
        It 'неинтерактивно без -Change падает, а не спрашивает' {
            { Set-EdtProjectExtension -Name 'p' } | Should -Throw '*-Change*'
            Should -Invoke -ModuleName EdtWorktree Read-EdtWtAnswer -Times 0
        }
        It 'интерактивно номера заменяют набор' {
            Mock -ModuleName EdtWorktree Test-EdtWtInteractive { $true }
            Mock -ModuleName EdtWorktree Read-EdtWtAnswer { '2' }
            Set-EdtProjectExtension -Name 'p'
            (Read-TestConfig).projects.p.extensions | Should -Be @('src/cfe_b')
        }
        It 'интерактивно пустой ответ оставляет набор' {
            Mock -ModuleName EdtWorktree Test-EdtWtInteractive { $true }
            Mock -ModuleName EdtWorktree Read-EdtWtAnswer { $null }
            Set-EdtProjectExtension -Name 'p'
            (Read-TestConfig).projects.p.extensions | Should -Be @('src/cfe_a')
        }
        It '-WhatIf не меняет конфиг' {
            Set-EdtProjectExtension -Name 'p' -Change '+cfe_b' -WhatIf
            (Read-TestConfig).projects.p.extensions | Should -Be @('src/cfe_a')
        }
        It 'неизвестный проект - ошибка' {
            { Set-EdtProjectExtension -Name 'zzz' -Change '+cfe_b' } | Should -Throw '*zzz*'
        }
    }

    Context 'Определения проектов без необязательных ключей' {
        BeforeEach {
            # Рукописный или перенесённый конфиг: у проекта нет extensions / cf_project, а лишний ключ должен уцелеть.
            $json = '{"version":3,"paths":{"repos_root":' + (ConvertTo-Json $script:ReposRoot) + '},"projects":{"two":{"custom":"keep"},"p":{"ref_branch":"main"}}}'
            [IO.File]::WriteAllText($script:cfg, $json, [Text.UTF8Encoding]::new($false))
        }
        It 'Set-EdtProject дописывает ref_branch и cf_project и сохраняет чужие ключи' {
            Set-EdtProject -Name 'two' -RefBranch 'pre-prod' -CfProject 'src/cf2'
            $p = (Read-TestConfig).projects.two
            $p.ref_branch | Should -Be 'pre-prod'
            $p.cf_project | Should -Be 'src/cf2'
            $p.custom | Should -Be 'keep'
        }
        It 'Set-EdtProjectExtension дописывает extensions' {
            Set-EdtProjectExtension -Name 'p' -Change '+cfe_a'
            $p = (Read-TestConfig).projects.p
            $p.extensions | Should -Be @('src/cfe_a')
            $p.ref_branch | Should -Be 'main'
        }
        It 'Get-EdtProject не падает на пустом определении' {
            (Get-EdtProject -Name 'two').Extensions | Should -Be '0/1'
        }
    }

    Context 'Set-EdtProject' {
        BeforeEach { Add-EdtProject -Name 'two' -Extensions 'none' -CfProject 'src/cf1' -Confirm:$false }

        It 'меняет ветку и конфигурацию' {
            Set-EdtProject -Name 'two' -RefBranch 'pre-prod' -CfProject 'src/cf2'
            $p = (Read-TestConfig).projects.two
            $p.ref_branch | Should -Be 'pre-prod'
            $p.cf_project | Should -Be 'src/cf2'
        }
        It 'без параметров - ошибка' {
            { Set-EdtProject -Name 'two' } | Should -Throw '*-RefBranch*'
        }
        It 'неизвестная конфигурация - ошибка со списком' {
            { Set-EdtProject -Name 'two' -CfProject 'nope' } | Should -Throw '*cf1*'
        }
        It '-WhatIf не меняет конфиг' {
            Set-EdtProject -Name 'two' -RefBranch 'x' -WhatIf
            (Read-TestConfig).projects.two.ref_branch | Should -Be 'dev'
        }
    }

    Context 'Remove-EdtProject' {
        It 'не трогает клон' {
            Add-EdtProject -Name 'p' -Extensions 'none' -Confirm:$false
            Remove-EdtProject -Name 'p' -Confirm:$false
            Test-Path $script:repo | Should -BeTrue
            (Get-TestProjectNames) | Should -Not -Contain 'p'
        }
        It 'неизвестный проект - ошибка' {
            { Remove-EdtProject -Name 'zzz' -Confirm:$false } | Should -Throw '*zzz*'
        }
        It '-WhatIf оставляет проект' {
            Add-EdtProject -Name 'p' -Extensions 'none' -Confirm:$false
            Remove-EdtProject -Name 'p' -WhatIf
            (Get-TestProjectNames) | Should -Contain 'p'
        }
    }

    Context 'Get-EdtProject' {
        It 'возвращает сведения о проекте' {
            Add-EdtProject -Name 'p' -Extensions 'cfe_a' -Confirm:$false
            $p = @(Get-EdtProject)
            $p.Count | Should -Be 1
            $p[0].Name | Should -Be 'p'
            $p[0].RefBranch | Should -Be 'main'
            $p[0].CloneBranch | Should -Be 'main'
            $p[0].Extensions | Should -Be '1/2'
            $p[0].Reference | Should -Be 'нет'
            $p[0].RepoPath | Should -Be (Join-Path $script:ReposRoot 'p')
        }
        It 'видит эталон в workspaces_root' {
            Add-EdtProject -Name 'p' -Extensions 'none' -Confirm:$false
            New-Item -ItemType Directory -Path (Join-Path $script:Root 'ws\p\_reference') -Force | Out-Null
            (Get-EdtProject -Name 'p').Reference | Should -Be 'есть'
        }
        It 'без клона не падает' {
            Add-EdtProject -Name 'p' -Extensions 'none' -Confirm:$false
            & $script:m { param($r) $c = Get-EdtWtConfig; $c.paths.repos_root = $r; Save-EdtWtConfig -Config $c | Out-Null } (Join-Path $script:Root 'elsewhere')
            $p = Get-EdtProject -Name 'p'
            $p.CloneBranch | Should -Be '-'
            $p.Extensions | Should -Be '?'
        }
        It 'неизвестное имя - ошибка' {
            { Get-EdtProject -Name 'zzz' } | Should -Throw '*zzz*'
        }
    }
}
