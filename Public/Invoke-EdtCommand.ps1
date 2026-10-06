function Invoke-EdtCommand {
    <#
    .SYNOPSIS
        Единая команда управления рабочими областями 1C:EDT.

    .DESCRIPTION
        Одна точка входа с подкомандами, как у git. Контекст определяется сам:
        внутри каталога worktree проект и задача не нужны, снаружи они задаются
        аргументами.

            edt open                        открыть текущий worktree
            edt open <проект> <задача>      открыть чужой worktree
            edt warmup [проект]             собрать эталон
            edt add <расширения>            подключить расширения
            edt remove [задача]             удалить область и worktree
            edt status [проект]             что открыто и чем занято
            edt update [проекты]            подтянуть pre-prod и пересобрать эталоны
            edt vr <аргументы vrunner>      vrunner с рабочей областью этого worktree

    .PARAMETER Command
        open, warmup, add, remove, status, update, vr, help.

    .PARAMETER Arguments
        Позиционные значения и ключи подкоманды. Ключи пишутся в стиле
        PowerShell (-Refresh, -NoGui, -GuiMaxHeap 12g) либо в стиле nushell
        (--refresh, --no-gui); понимаются оба.

        Для vr всё, кроме -Full, принадлежит vrunner и передаётся ему без
        разбора. vr выполняется в каталоге worktree и читает настройки базы из
        autumn-properties.json в его корне; рабочая область EDT этого worktree
        передаётся через VRUNNER_EDT_WORKSPACE, VRUNNER_EDT_PATH,
        VRUNNER_EDT_VMARGS и VRUNNER_EDT_TIMEOUT (заданные вами не
        перезаписываются). К cf load и cfe load добавляется --increment;
        -Full отключает его. Код возврата vrunner остаётся в $LASTEXITCODE.

    .EXAMPLE
        edt open my-project TASK-123 -GuiMaxHeap 12g

    .EXAMPLE
        edt vr cf load src/cf

        Инкрементальная загрузка конфигурации в базу из autumn-properties.json.

    .EXAMPLE
        edt vr cf load src/cf -Full

        Полная загрузка: --increment не добавляется.

    .EXAMPLE
        edt vr validate edt

        Проверка EDT-проекта в рабочей области текущего worktree.

    .EXAMPLE
        edt open -Refresh -WhatIf

        Из каталога worktree: печатает план пересборки, ничего не меняя.

    .EXAMPLE
        edt status | Where-Object Locked -eq 'LOCK'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('open', 'warmup', 'add', 'remove', 'status', 'update', 'self-update', 'vr', 'init', 'config', 'help')]
        [string]$Command = 'help',

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    if ($Command -eq 'help') {
        Show-EdtWtUsage
        return
    }

    # Аргументы vr принадлежат vrunner и не разбираются как ключи edt.
    if ($Command -eq 'vr') {
        Invoke-EdtWtVrunner -Arguments $Arguments
        return
    }

    # @(...) обязательна: пустой массив из ветки switch иначе схлопывается
    # в $null, и обязательный параметр -Allowed не связывается.
    $allowed = @(switch ($Command) {
        'open' { @('-Refresh', '-NoGui', '-GuiMaxHeap <12g>', '-MaxHeap <12g>', '-WhatIf', '-Yes') }
        'warmup' { @('-Force', '-Validate', '-MaxHeap <16g>', '-WhatIf', '-Yes') }
        'add' { @('-Force', '-NoGui', '-MaxHeap <12g>', '-WhatIf', '-Yes') }
        'remove' { @('-WhatIf', '-Yes') }
        'status' { @() }
        'update' { @('-Validate', '-SkipGit', '-MaxHeap <16g>', '-WhatIf', '-Yes') }
        'self-update' { @() }
        'init' { @('-WhatIf', '-Yes') }
        'config' { @() }
    })

    $parsed = Resolve-EdtWtWrapperArgs -Items $Arguments -Allowed $allowed
    $positional = @($parsed.Extensions)

    # Общие ключи собираются один раз: дальше они уходят в любую подкоманду.
    $common = @{}
    if ($PSBoundParameters.ContainsKey('WhatIf') -or $parsed.Flags.WhatIf) { $common['WhatIf'] = $true }
    if ($PSBoundParameters.ContainsKey('Confirm')) { $common['Confirm'] = $PSBoundParameters['Confirm'] }
    elseif ($parsed.Flags.Yes) { $common['Confirm'] = $false }
    if ($parsed.Values.MaxHeap) { $common['MaxHeap'] = $parsed.Values.MaxHeap }

    switch ($Command) {
        'open' {
            $params = $common.Clone()
            $params['NoGui'] = $parsed.Flags.NoGui
            $params['Refresh'] = $parsed.Flags.Refresh
            if ($parsed.Values.GuiMaxHeap) { $params['GuiMaxHeap'] = $parsed.Values.GuiMaxHeap }

            # Форма записи: [проект задача] [расширения]
            $target = Resolve-EdtWtTarget -Positional $positional -Command 'open'
            if ($target.Extensions.Count -gt 0) { $params['Extensions'] = $target.Extensions }

            Invoke-EdtWtInLocation -Path $target.Path -Action {
                Invoke-EdtWorktreeOpen @params
            }
        }

        'warmup' {
            $params = $common.Clone()
            $params['Force'] = $parsed.Flags.Force
            $params['Validate'] = $parsed.Flags.Validate

            $target = Resolve-EdtWtTarget -Positional $positional -Command 'warmup'
            if ($target.ProjectId) { $params['ProjectName'] = $target.ProjectId }
            if ($target.Extensions.Count -gt 0) { $params['Extensions'] = $target.Extensions }

            Invoke-EdtWtInLocation -Path $target.Path -Action {
                Invoke-EdtWorktreeWarmup @params
            }
        }

        'add' {
            $params = $common.Clone()
            $params['Force'] = $parsed.Flags.Force
            $params['NoGui'] = $parsed.Flags.NoGui

            $target = Resolve-EdtWtTarget -Positional $positional -Command 'add'
            if ($target.Extensions.Count -eq 0) {
                throw "Не указано, какие расширения подключить. Пример: edt add cfe_esf"
            }
            $params['Extensions'] = $target.Extensions

            Invoke-EdtWtInLocation -Path $target.Path -Action {
                Invoke-EdtWorktreeAdd @params
            }
        }

        'remove' {
            $params = $common.Clone()
            $target = Resolve-EdtWtTarget -Positional $positional -Command 'remove'
            if ($target.WorktreeId) { $params['WorktreeId'] = $target.WorktreeId }

            Invoke-EdtWtInLocation -Path $target.Path -Action {
                Invoke-EdtWorktreeClean @params
            }
        }

        'status' {
            if ($positional.Count -gt 0) {
                Get-EdtWorktreeList -ProjectName $positional[0]
            } else {
                Get-EdtWorktreeList
            }
        }

        'update' {
            $params = $common.Clone()
            $params['Validate'] = $parsed.Flags.Validate
            $params['SkipGit'] = $parsed.Flags.SkipGit
            if ($positional.Count -gt 0) { $params['Project'] = $positional }

            Update-EdtWtReference @params
        }

        'self-update' {
            Update-EdtSelf
        }

        'init' {
            $params = @{}
            if ($common.ContainsKey('WhatIf')) { $params['WhatIf'] = $common['WhatIf'] }
            if ($positional.Count -gt 0) { $params['CfProject'] = $positional[0] }
            New-EdtProjectConfig @params
        }

        'config' {
            $sub = if ($positional.Count -gt 0) { $positional[0].ToLower() } else { 'get' }
            switch ($sub) {
                'init' {
                    Initialize-EdtConfig
                }
                'set' {
                    Write-Host "Для изменения настроек используйте: Set-EdtConfig [-ProjectsRoot ...] [-WorktreeRoot ...] [-WorkspacesRoot ...] [-EdtCliPath ...]" -ForegroundColor Yellow
                    Write-Host "Либо запустите мастер: edt config init" -ForegroundColor Cyan
                }
                default {
                    Get-EdtConfig
                }
            }
        }
    }
}
