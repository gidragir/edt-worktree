function Invoke-EdtSetup {
    <#
    .SYNOPSIS
        Первичная настройка: три каталога, поиск EDT, регистрация проектов.
    .DESCRIPTION
        Для каждого не переданного пути интерактивно спрашивает значение (по умолчанию
        текущее), неинтерактивно оставляет текущее. Отсутствующие каталоги создаются
        (интерактивно после вопроса). Затем показывается найденный EDT и сохраняется
        конфиг; повторный запуск не трогает зарегистрированные проекты и прочие ключи.
        Интерактивно и без -NoProjects в конце предлагается зарегистрировать клоны.
    .PARAMETER ReposRoot
        Каталог клонов репозиториев.
    .PARAMETER WorktreesRoot
        Каталог git-worktree.
    .PARAMETER WorkspacesRoot
        Каталог рабочих областей EDT.
    .PARAMETER NoProjects
        Не предлагать регистрацию проектов.
    .EXAMPLE
        Invoke-EdtSetup
    .EXAMPLE
        Invoke-EdtSetup -ReposRoot D:\git -WorktreesRoot D:\wt -WorkspacesRoot D:\ws
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [string]$ReposRoot,
        [string]$WorktreesRoot,
        [string]$WorkspacesRoot,
        [switch]$NoProjects
    )

    # Сначала чтение: повреждённый конфиг должен остановить setup до любых действий.
    $cfg = Get-EdtWtConfig
    $interactive = Test-EdtWtInteractive
    Write-Host "`n=== [EdtWorktree] Настройка окружения ===" -ForegroundColor Cyan

    $items = @(
        @{ Key = 'repos_root'; Value = $ReposRoot; Prompt = 'Каталог клонов репозиториев' }
        @{ Key = 'worktrees_root'; Value = $WorktreesRoot; Prompt = 'Каталог git-worktree' }
        @{ Key = 'workspaces_root'; Value = $WorkspacesRoot; Prompt = 'Каталог рабочих областей EDT' }
    )
    foreach ($item in $items) {
        if ($item.Value) {
            $cfg.paths.($item.Key) = $item.Value
        } elseif ($interactive) {
            $answer = Read-EdtWtAnswer -Prompt $item.Prompt -Default $cfg.paths.($item.Key)
            if ($answer) { $cfg.paths.($item.Key) = $answer }
        }
    }

    foreach ($item in $items) {
        $dir = $cfg.paths.($item.Key)
        if (-not $dir -or (Test-Path -LiteralPath $dir)) { continue }
        $create = $true
        if ($interactive) {
            $reply = Read-EdtWtAnswer -Prompt "Каталог '$dir' не существует. Создать? (Y/n)" -Default 'Y'
            $create = (-not $reply) -or ($reply -match '^[yYдД]')
        }
        if ($create -and $PSCmdlet.ShouldProcess($dir, 'Создать каталог')) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host "  Создан: $dir" -ForegroundColor Gray
        }
    }

    $found = @(Find-EdtWtCli)
    if ($cfg.edt.cli_path) {
        Write-Host "EDT: $($cfg.edt.cli_path) (задан в конфиге)" -ForegroundColor Gray
    } elseif ($found.Count -gt 0) {
        Write-Host "EDT найден: $($found[0].Version) ($($found[0].Path))" -ForegroundColor Gray
    } else {
        Write-Host 'EDT не найден - укажите: edt config set edt.cli_path <путь>' -ForegroundColor Yellow
    }

    if ($PSCmdlet.ShouldProcess((Get-EdtWtUserConfigPath), 'Сохранить конфигурацию')) {
        $saved = Save-EdtWtConfig -Config $cfg
        Write-Host "✓ Настройки сохранены: $saved" -ForegroundColor Green
        if ($interactive -and -not $NoProjects) {
            Add-EdtProject
        }
    }

    if ($PSCmdlet.ShouldProcess((Get-EdtWtShimDir), 'Установить shim edt')) {
        $shimDir = Install-EdtWtShim
        Write-Host "✓ Shim edt (nushell, cmd, планировщик): $shimDir" -ForegroundColor Green
    }

    return (Get-EdtConfig)
}
