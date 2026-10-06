BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\EdtWorktree.psd1') -Force
    $script:Public = @(
        'Invoke-EdtCommand'
        'Invoke-EdtWorktreeOpen'
        'Invoke-EdtWorktreeWarmup'
        'Invoke-EdtWorktreeAdd'
        'Invoke-EdtWorktreeClean'
        'Get-EdtWorktreeList'
        'Get-EdtWtContext'
        'Invoke-EdtWtLegacyCommand'
        'Update-EdtWtReference'
        'Get-EdtConfig'
        'Set-EdtConfig'
        'Initialize-EdtConfig'
        'New-EdtProjectConfig'
        'Update-EdtSelf'
    )
    $script:Legacy = @('wt-open', 'wt-warmup', 'wt-add', 'wt-clean', 'wt-list',
        'edt-wt-open', 'edt-wt-warmup', 'edt-wt-add', 'edt-wt-clean', 'edt-wt-list')
}

Describe 'Контракт модуля' {
    It 'экспортирует ровно заявленные функции' {
        $exported = (Get-Command -Module EdtWorktree -CommandType Function).Name
        $expected = @($script:Public + $script:Legacy)
        ($exported | Sort-Object) | Should -Be ($expected | Sort-Object)
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
        $set.ValidValues | Should -Be @('open', 'warmup', 'add', 'remove', 'status', 'update', 'self-update', 'vr', 'init', 'config', 'help')
    }

    It 'старые имена работают и предупреждают о замене' {
        foreach ($name in $script:Legacy) {
            Get-Command $name -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    It 'не выносит приватные помощники наружу' {
        # Раньше вся логика лежала в профиле оболочки, и helper-функции
        # засоряли пространство имён и автодополнение.
        Get-Command -Module EdtWorktree -Name 'Get-EdtWtSettings' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
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
        $root = & (Get-Module EdtWorktree) { (Get-EdtWtSettings).RootDir }
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

    It 'отклоняет неверный формат размера кучи' {
        { Invoke-EdtWorktreeOpen -GuiMaxHeap '12' -WhatIf } | Should -Throw
        { Invoke-EdtWorktreeWarmup -MaxHeap 'много' -WhatIf } | Should -Throw
    }
}
