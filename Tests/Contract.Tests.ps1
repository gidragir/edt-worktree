BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
}

AfterAll {
    Exit-EdtWtTestConfig -State $script:TestCfg
}

BeforeAll {
    Import-Module (Get-EdtWtTestModulePath) -Force
    $script:Public = @(
        'Invoke-EdtCommand'
        'Invoke-EdtWorktreeOpen'
        'Invoke-EdtWorktreeWarmup'
        'Invoke-EdtWorktreeAdd'
        'Invoke-EdtWorktreeClean'
        'Get-EdtWorktreeList'
        'Get-EdtWtContext'
        'Update-EdtWtReference'
        'Get-EdtConfig'
        'Set-EdtConfig'
        'Invoke-EdtSetup'
        'Get-EdtProject'
        'Add-EdtProject'
        'Set-EdtProjectExtension'
        'Set-EdtProject'
        'Remove-EdtProject'
        'Update-EdtSelf'
        'Uninstall-EdtWorktree'
        'Test-EdtEnvironment'
    )
}

Describe 'Контракт модуля' {
    It 'экспортирует ровно заявленные функции' {
        $exported = (Get-Command -Module EdtWorktree -CommandType Function).Name
        ($exported | Sort-Object) | Should -Be ($script:Public | Sort-Object)
    }

    It 'короткое имя команды одно: edt' {
        # Прежде каждое действие имело два имени (wt-* и edt-wt-*), и это
        # сбивало с толку: разница была не в действии, а в способе задать
        # контекст.
        (Get-Command -Module EdtWorktree -CommandType Alias).Name | Should -Be @('edt')
    }

    It 'подкоманды edt покрывают все операции' {
        $set = (Get-Command Invoke-EdtCommand).Parameters['Command'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $set.ValidValues | Should -Be @('open', 'warmup', 'add', 'remove', 'status', 'update', 'vr', 'setup', 'project', 'config', 'doctor', 'self-update', 'uninstall', 'help')
    }

    It 'старых имён нет' {
        Get-Command 'wt-open', 'edt-wt-open', 'wt-list', 'edt-wt-clean', 'Invoke-EdtWtLegacyCommand' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'версия модуля 3.0.0' {
        (Get-Module EdtWorktree).Version.ToString() | Should -Be '3.0.0'
    }

    It 'у warmup нет ключей кроме ProjectName и общих' {
        (Get-Command Invoke-EdtWorktreeWarmup).Parameters.Keys | Should -Not -Contain 'Validate'
    }

    It 'не выносит приватные помощники наружу' {
        # Раньше вся логика лежала в профиле оболочки, и helper-функции
        # засоряли пространство имён и автодополнение.
        Get-Command -Module EdtWorktree -Name 'Get-EdtWtConfig' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Module EdtWorktree -Name 'Split-EdtWtArguments' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'у edt есть справка по подкомандам' {
        $help = (Get-Help Invoke-EdtCommand).Synopsis
        $help | Should -Not -BeNullOrEmpty
    }

    It 'у всех изменяющих состояние команд есть -WhatIf' {
        foreach ($name in 'Invoke-EdtWorktreeOpen', 'Invoke-EdtWorktreeWarmup', 'Invoke-EdtWorktreeAdd', 'Invoke-EdtWorktreeClean') {
            (Get-Command $name).Parameters.Keys | Should -Contain 'WhatIf'
        }
    }

    It 'у публичных команд есть описание в справке' {
        foreach ($name in $script:Public) {
            (Get-Help $name).Synopsis | Should -Not -BeNullOrEmpty
        }
    }

    It 'Get-EdtWorktreeList возвращает данные, а не результат форматирования' {
        # Регрессия: Format-Table внутри функции делал результат непригодным
        # для фильтрации и использования в скриптах.
        $root = & (Get-Module EdtWorktree) { (Get-EdtWtConfig).paths.workspaces_root }
        if (-not (Test-Path -LiteralPath $root)) {
            Set-ItResult -Skipped -Because "корень рабочих областей $root недоступен"
            return
        }

        $rows = @(Get-EdtWorktreeList)
        if ($rows.Count -eq 0) {
            Set-ItResult -Skipped -Because 'рабочих областей нет'
            return
        }

        $rows[0].GetType().FullName | Should -Not -BeLike 'Microsoft.PowerShell.Commands.Internal.Format.*'
        $rows[0].PSObject.Properties.Name | Should -Contain 'Workspace'
    }

    It 'ключей кучи у open, warmup и add больше нет (куча берётся из конфига)' {
        foreach ($name in 'Invoke-EdtWorktreeOpen', 'Invoke-EdtWorktreeWarmup', 'Invoke-EdtWorktreeAdd') {
            $keys = (Get-Command $name).Parameters.Keys
            $keys | Should -Not -Contain 'MaxHeap'
            $keys | Should -Not -Contain 'GuiMaxHeap'
        }
        (Get-Command Invoke-EdtWorktreeOpen).Parameters.Keys | Should -Not -Contain 'Extensions'
    }

    It 'edt project ext p +cfe_b -cfe_a доходит до Set-EdtProjectExtension' {
        # -cfe_a не ключ, а правка: разбор +/- идёт до общего парсера.
        Mock -ModuleName EdtWorktree Set-EdtProjectExtension {}
        Invoke-EdtCommand project ext p +cfe_b -cfe_a
        Should -Invoke Set-EdtProjectExtension -ModuleName EdtWorktree -Exactly 1 -ParameterFilter {
            $Name -eq 'p' -and ($Change -join ',') -eq '+cfe_b,-cfe_a'
        }
    }

    Context 'bin/edt.ps1 (дочерний процесс)' {
        BeforeAll {
            # Дочерний pwsh наследует окружение: конфиг обязан быть временным.
            $script:Bin = (Resolve-Path (Join-Path (Get-EdtWtTestModuleRoot) 'bin\edt.ps1')).Path
            $script:BinRoot = $script:TestCfg.Root
            $env:EDT_CONFIG_PATH | Should -BeLike "$($script:BinRoot)*"
            $env:EDT_LEGACY_CONFIG_PATH | Should -BeLike "$($script:BinRoot)*"
            $cfg = @{
                version = 3
                paths   = @{
                    repos_root      = Join-Path $script:BinRoot 'нет\repos'
                    worktrees_root  = Join-Path $script:BinRoot 'нет\wt'
                    workspaces_root = Join-Path $script:BinRoot 'нет\ws'
                }
            }
            [IO.File]::WriteAllText($env:EDT_CONFIG_PATH, ($cfg | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
        }

        It 'config path печатает временный файл (изоляция дочернего процесса)' {
            $out = (& pwsh -NoProfile -File $script:Bin config path 2>&1 | Out-String).Trim()
            $LASTEXITCODE | Should -Be 0
            $out | Should -Be $env:EDT_CONFIG_PATH
        }

        It 'doctor возвращает 1 при ошибке' {
            $before = [IO.File]::ReadAllBytes($env:EDT_CONFIG_PATH)
            $out = & pwsh -NoProfile -File $script:Bin doctor 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -BeLike '*paths.repos_root*'
            [IO.File]::ReadAllBytes($env:EDT_CONFIG_PATH) | Should -Be $before
        }

        It 'неизвестная подкоманда - код 2, help - код 0' {
            & pwsh -NoProfile -File $script:Bin nonsense *>$null
            $LASTEXITCODE | Should -Be 2
            & pwsh -NoProfile -File $script:Bin help *>$null
            $LASTEXITCODE | Should -Be 0
        }

        It 'список подкоманд bin совпадает с ValidateSet диспетчера' {
            $text = Get-Content -LiteralPath $script:Bin -Raw -Encoding utf8
            $block = [regex]::Match($text, '\$known = @\(([^)]*)\)')
            $block.Success | Should -BeTrue
            $known = @([regex]::Matches($block.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
            $set = (Get-Command Invoke-EdtCommand).Parameters['Command'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $known | Should -Be @($set.ValidValues)
        }

        It 'в справке и bin нет ключей прежних версий' {
            $text = (Get-Content -LiteralPath $script:Bin -Raw -Encoding utf8)
            $usage = & (Get-Module EdtWorktree) { Show-EdtWtUsage } 6>&1 | Out-String
            $text | Should -Not -Match 'GuiMaxHeap|-MaxHeap|-Validate|wt-open|edt-wt|edt init'
            $usage | Should -Not -Match 'GuiMaxHeap|-MaxHeap|-Validate|-Force|wt-open|edt-wt|edt init'
        }
    }
}
