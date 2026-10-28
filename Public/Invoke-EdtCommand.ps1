function Split-EdtWtCommonFlagTokens {
    <#
      Отделяет общие ключи (-Yes, -WhatIf, --dry-run) от остальных слов. Нужна
      подкомандам со свободным вводом (project ext: +имя/-имя; config set: значение
      может начинаться с дефиса), где общий разбор ключей принял бы такое слово за ключ.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([Parameter(Position = 0)][AllowEmptyCollection()][string[]]$Items)

    $flags = @()
    $rest = @()
    foreach ($item in @($Items | Where-Object { $_ })) {
        if ($item -match '^--?(what-?if|dry-?run|yes)$') { $flags += $item } else { $rest += $item }
    }
    return [PSCustomObject]@{ Flags = $flags; Rest = $rest }
}

function Confirm-EdtWtProjectKnown {
    <#
      open и warmup для клона из repos_root, который ещё не зарегистрирован:
      интерактивно запускается регистрация (Add-EdtProject -Name), без диалога
      ничего не делается, и вызывающий получит ошибку Get-EdtWtProjectDef с
      командой регистрации. Имя не задано - проект берётся по текущему каталогу.
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [hashtable]$Params = @{}
    )

    $cfg = Get-EdtWtConfig
    if ($Name) {
        if ($null -ne $cfg.projects.PSObject.Properties[$Name]) { return }
        if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $cfg.paths.repos_root $Name) '.git'))) { return }
    } else {
        $resolved = Resolve-EdtWtProjectFromPath -Path (Get-Location).Path -Config $cfg
        if (-not $resolved -or $resolved.Registered) { return }
        $Name = $resolved.Name
    }

    if (-not (Test-EdtWtInteractive)) { return }
    Write-Host "Проект '$Name' ещё не зарегистрирован." -ForegroundColor Yellow
    Add-EdtProject -Name $Name @Params
}

function Invoke-EdtCommand {
    <#
    .SYNOPSIS
        Единая команда управления рабочими областями 1C:EDT.

    .DESCRIPTION
        Одна точка входа с подкомандами, как у git. Контекст определяется сам:
        внутри каталога worktree проект и ветка не нужны, снаружи они задаются
        аргументами.

            edt setup                       первичная настройка каталогов
            edt project list|add|ext|set|remove   проекты
            edt open [проект ветка]         открыть рабочую область
            edt warmup [проект]             собрать эталон
            edt add <расширения>            подключить расширения
            edt remove [проект] [ветка]     удалить область и worktree
            edt status [проект]             что открыто и чем занято
            edt update [проекты]            подтянуть ref_branch и пересобрать эталоны
            edt vr <аргументы vrunner>      vrunner с рабочей областью этого worktree
            edt config show|path|set        конфигурация
            edt doctor                      проверка окружения
            edt self-update, edt uninstall  обновление и удаление модуля

    .PARAMETER Command
        open, warmup, add, remove, status, update, vr, setup, project, config,
        doctor, self-update, uninstall, help.

    .PARAMETER Arguments
        Позиционные значения и ключи подкоманды. Ключи пишутся в стиле
        PowerShell (-Refresh, -NoGui) либо в стиле nushell (--refresh, --no-gui);
        понимаются оба. Изменяющие команды принимают -WhatIf (--dry-run) и -Yes.

        Короткое имя ветки дополняется префиксом git.branch_prefix (по умолчанию
        feature/), имя со слешем берётся как есть.

        Для vr всё, кроме -Full, принадлежит vrunner и передаётся ему без
        разбора. vr выполняется в каталоге worktree и читает настройки базы из
        autumn-properties.json в его корне; рабочая область EDT этого worktree
        передаётся через VRUNNER_EDT_WORKSPACE, VRUNNER_EDT_PATH,
        VRUNNER_EDT_VMARGS и VRUNNER_EDT_TIMEOUT (заданные вами не
        перезаписываются). К cf load и cfe load добавляется --increment;
        -Full отключает его. Код возврата vrunner остаётся в $LASTEXITCODE.

    .EXAMPLE
        edt open my-project TASK-123

    .EXAMPLE
        edt project ext my-project +cfe_new -cfe_old

        Точечная правка рабочих расширений без диалога.

    .EXAMPLE
        edt vr cf load src/cf

        Инкрементальная загрузка конфигурации в базу из autumn-properties.json.

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
        [ValidateSet('open', 'warmup', 'add', 'remove', 'status', 'update', 'vr', 'setup', 'project', 'config', 'doctor', 'self-update', 'uninstall', 'help')]
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

    $tokens = @($Arguments | Where-Object { $_ })

    # Подкоманда project и config - первое слово, если оно не ключ.
    $sub = $null
    if ($Command -in @('project', 'config')) {
        $sub = if ($Command -eq 'project') { 'list' } else { 'show' }
        if ($tokens.Count -gt 0 -and -not $tokens[0].StartsWith('-')) {
            $sub = $tokens[0].ToLower()
            $tokens = @($tokens | Select-Object -Skip 1)
        }
        $validSubs = if ($Command -eq 'project') { @('list', 'add', 'ext', 'set', 'remove') } else { @('show', 'path', 'set') }
        if ($validSubs -notcontains $sub) {
            throw "Неизвестная подкоманда '$sub'. Доступны: edt $Command $($validSubs -join '|')."
        }
    }

    # Слова со свободным вводом разбираются ДО общего парсера: -cfe_a - правка, а не ключ.
    $changes = @()
    $configKeyValue = @()
    if ($Command -eq 'project' -and $sub -eq 'ext') {
        $split = Split-EdtWtCommonFlagTokens -Items $tokens
        if ($split.Rest.Count -eq 0 -or $split.Rest[0] -match '^[+-]') {
            throw 'Использование: edt project ext <проект> [+имя ...] [-имя ...]'
        }
        $tokens = @($split.Flags) + @($split.Rest[0])
        # PowerShell склеивает +a,+b в одно слово 'a b': список делится и по запятым, и по пробелам.
        $changes = @($split.Rest | Select-Object -Skip 1 | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ })
        foreach ($c in $changes) {
            if ($c -notmatch '^[+-].+') { throw "Правка '$c' неверна: ожидается '+имя' или '-имя'." }
        }
    } elseif ($Command -eq 'config' -and $sub -eq 'set') {
        $split = Split-EdtWtCommonFlagTokens -Items $tokens
        if ($split.Rest.Count -ne 2) { throw 'Использование: edt config set <ключ> <значение>' }
        $tokens = @($split.Flags)
        $configKeyValue = @($split.Rest)
    }

    $allowed = @(switch ($Command) {
        'open' { @('-Refresh', '-NoGui', '-WhatIf', '-Yes') }
        'warmup' { @('-WhatIf', '-Yes') }
        'add' { @('-NoGui', '-WhatIf', '-Yes') }
        'remove' { @('-WhatIf', '-Yes') }
        'update' { @('-SkipGit', '-WhatIf', '-Yes') }
        'setup' { @('-ReposRoot', '-WorktreesRoot', '-WorkspacesRoot', '-NoProjects', '-WhatIf', '-Yes') }
        'self-update' { @('-WhatIf', '-Yes') }
        'uninstall' { @('-Purge', '-WhatIf', '-Yes') }
        'project' {
            switch ($sub) {
                'add' { @('-Extensions', '-RefBranch', '-CfProject', '-WhatIf', '-Yes') }
                'ext' { @('-WhatIf', '-Yes') }
                'set' { @('-RefBranch', '-CfProject', '-WhatIf', '-Yes') }
                'remove' { @('-WhatIf', '-Yes') }
                default { @() }
            }
        }
        'config' { if ($sub -eq 'set') { @('-WhatIf', '-Yes') } else { @() } }
        default { @() }
    })

    $parsed = Resolve-EdtWtWrapperArgs -Items $tokens -Allowed $allowed
    foreach ($key in $parsed.Used) {
        if ($allowed -notcontains "-$key") {
            $where = if ($sub) { "$Command $sub" } else { $Command }
            $hint = if ($allowed.Count -gt 0) { "Доступны: $($allowed -join ', ')." } else { 'Эта подкоманда ключей не принимает.' }
            throw "Неизвестный ключ '-$key' для 'edt $where'. $hint"
        }
    }
    $positional = @($parsed.Extensions)
    # Списки (add cfe_a,cfe_b; update ka,kb) PowerShell отдаёт словом с пробелом.
    if ($Command -in @('add', 'update')) {
        $positional = @($positional | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ })
    }

    # Общие ключи собираются один раз: дальше они уходят в любую подкоманду.
    $common = @{}
    if ($PSBoundParameters.ContainsKey('WhatIf') -or $parsed.Flags.WhatIf) {
        $common['WhatIf'] = $true
        # Наследуется вызываемыми функциями, в том числе при создании worktree.
        $WhatIfPreference = $true
    }
    if ($PSBoundParameters.ContainsKey('Confirm')) { $common['Confirm'] = $PSBoundParameters['Confirm'] }
    elseif ($parsed.Flags.Yes) { $common['Confirm'] = $false }

    switch ($Command) {
        'open' {
            $params = $common.Clone()
            $params['NoGui'] = $parsed.Flags.NoGui
            $params['Refresh'] = $parsed.Flags.Refresh

            Confirm-EdtWtProjectKnown -Name ($positional | Select-Object -First 1) -Params $common
            $target = Resolve-EdtWtTarget -Positional $positional -Command 'open'

            Invoke-EdtWtInLocation -Path $target.Path -Action {
                Invoke-EdtWorktreeOpen @params
            }
        }

        'warmup' {
            $params = $common.Clone()

            Confirm-EdtWtProjectKnown -Name ($positional | Select-Object -First 1) -Params $common
            $target = Resolve-EdtWtTarget -Positional $positional -Command 'warmup'
            if ($target.ProjectId) { $params['ProjectName'] = $target.ProjectId }

            Invoke-EdtWtInLocation -Path $target.Path -Action {
                Invoke-EdtWorktreeWarmup @params
            }
        }

        'add' {
            $params = $common.Clone()
            $params['NoGui'] = $parsed.Flags.NoGui

            $target = Resolve-EdtWtTarget -Positional $positional -Command 'add'
            if ($target.Extensions.Count -eq 0) {
                throw 'Не указано, какие расширения подключить. Пример: edt add cfe_esf'
            }
            $params['Extensions'] = $target.Extensions

            Invoke-EdtWorktreeAdd @params
        }

        'remove' {
            $params = $common.Clone()
            $target = Resolve-EdtWtTarget -Positional $positional -Command 'remove'
            # Clean принимает полное имя ветки: по нему же ищется git worktree.
            if ($target.Branch) { $params['WorktreeId'] = $target.Branch }

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
            $params['SkipGit'] = $parsed.Flags.SkipGit
            if ($positional.Count -gt 0) { $params['Project'] = $positional }

            Update-EdtWtReference @params
        }

        'setup' {
            $params = $common.Clone()
            foreach ($key in 'ReposRoot', 'WorktreesRoot', 'WorkspacesRoot') {
                if ($parsed.Values[$key]) { $params[$key] = $parsed.Values[$key] }
            }
            if ($parsed.Flags.NoProjects) { $params['NoProjects'] = $true }

            Invoke-EdtSetup @params
        }

        'project' {
            switch ($sub) {
                'list' {
                    if ($positional.Count -gt 0) { Get-EdtProject -Name $positional[0] } else { Get-EdtProject }
                }
                'add' {
                    $params = $common.Clone()
                    if ($positional.Count -gt 0) { $params['Name'] = $positional[0] }
                    if ($parsed.Values.Extensions) { $params['Extensions'] = [string[]]$parsed.Values.Extensions }
                    if ($parsed.Values.RefBranch) { $params['RefBranch'] = $parsed.Values.RefBranch }
                    if ($parsed.Values.CfProject) { $params['CfProject'] = $parsed.Values.CfProject }
                    Add-EdtProject @params
                }
                'ext' {
                    $params = $common.Clone()
                    $params['Name'] = $positional[0]
                    if ($changes.Count -gt 0) { $params['Change'] = [string[]]$changes }
                    Set-EdtProjectExtension @params
                }
                'set' {
                    if ($positional.Count -eq 0) { throw 'Использование: edt project set <проект> -RefBranch <ветка> | -CfProject <путь>' }
                    $params = $common.Clone()
                    $params['Name'] = $positional[0]
                    if ($parsed.Values.RefBranch) { $params['RefBranch'] = $parsed.Values.RefBranch }
                    if ($parsed.Values.CfProject) { $params['CfProject'] = $parsed.Values.CfProject }
                    Set-EdtProject @params
                }
                'remove' {
                    if ($positional.Count -eq 0) { throw 'Использование: edt project remove <проект>' }
                    Remove-EdtProject -Name $positional[0] @common
                }
            }
        }

        'config' {
            switch ($sub) {
                'show' { Get-EdtConfig }
                'path' { Get-EdtConfig -Path }
                'set' { Set-EdtConfig -Key $configKeyValue[0] -Value $configKeyValue[1] @common }
            }
        }

        'doctor' {
            Test-EdtEnvironment
        }

        'self-update' {
            Update-EdtSelf @common
        }

        'uninstall' {
            Uninstall-EdtWorktree -Purge:$parsed.Flags.Purge @common
        }
    }
}
