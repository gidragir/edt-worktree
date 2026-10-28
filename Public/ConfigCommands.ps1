# ==============================================================================
# ConfigCommands.ps1 - Публичные команды конфигурации: setup, config show|path|set
# ==============================================================================

Set-StrictMode -Version Latest

function Get-EdtConfig {
    <#
    .SYNOPSIS
        Возвращает сводку текущей конфигурации EdtWorktree.
    .DESCRIPTION
        Показывает пути, EDT и зарегистрированные проекты. С -Path возвращает только
        путь к файлу конфигурации.
    .PARAMETER Path
        Вернуть только путь к config.json.
    .PARAMETER AsJson
        Вернуть сводку в виде JSON.
    .EXAMPLE
        Get-EdtConfig
    .EXAMPLE
        Get-EdtConfig -Path
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject], [string])]
    param(
        [switch]$Path,
        [switch]$AsJson
    )

    $file = Get-EdtWtUserConfigPath
    if ($Path) { return $file }

    $cfg = Get-EdtWtConfig
    $edtCli = $cfg.edt.cli_path
    if (-not $edtCli) {
        $found = @(Find-EdtWtCli)
        $edtCli = if ($found.Count -gt 0) { "авто: $($found[0].Path)" } else { 'авто: не найден' }
    }

    $summary = [PSCustomObject]@{
        ConfigFile     = $file
        ReposRoot      = $cfg.paths.repos_root
        WorktreesRoot  = $cfg.paths.worktrees_root
        WorkspacesRoot = $cfg.paths.workspaces_root
        EdtCli         = $edtCli
        Projects       = @($cfg.projects.PSObject.Properties | ForEach-Object { $_.Name })
    }

    if ($AsJson) {
        return (ConvertTo-Json -InputObject $summary -Depth 5)
    }
    return $summary
}

function Set-EdtConfig {
    <#
    .SYNOPSIS
        Меняет один параметр конфигурации по ключу.
    .DESCRIPTION
        Допустимые ключи: paths.repos_root, paths.worktrees_root, paths.workspaces_root,
        edt.cli_path, edt.vm_path, edt.prefs_source, edt.max_heap, edt.gui_max_heap,
        edt.extra_vmargs, edt.timeout_sec, git.remote, git.branch_prefix.
        Значение 'null' или пустое сбрасывает параметр (авто или значение по умолчанию).
    .PARAMETER Key
        Ключ вида раздел.имя.
    .PARAMETER Value
        Новое значение.
    .EXAMPLE
        Set-EdtConfig -Key edt.max_heap -Value 16g
    .EXAMPLE
        Set-EdtConfig -Key edt.cli_path -Value null
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Key,
        [Parameter(Mandatory, Position = 1)][AllowNull()][AllowEmptyString()][string]$Value
    )

    $kinds = [ordered]@{
        'paths.repos_root'      = 'string'
        'paths.worktrees_root'  = 'string'
        'paths.workspaces_root' = 'string'
        'edt.cli_path'          = 'path'
        'edt.vm_path'           = 'path'
        'edt.prefs_source'      = 'path'
        'edt.max_heap'          = 'heap'
        'edt.gui_max_heap'      = 'heap'
        'edt.extra_vmargs'      = 'string'
        'edt.timeout_sec'       = 'positiveInt'
        'git.remote'            = 'string'
        'git.branch_prefix'     = 'string'
    }
    if (-not $kinds.Contains($Key)) {
        throw "Неизвестный ключ '$Key'. Допустимые ключи: $($kinds.Keys -join ', ')."
    }

    $newValue = $null
    if (-not [string]::IsNullOrWhiteSpace($Value) -and $Value.Trim() -ne 'null') {
        $newValue = $Value
        switch ($kinds[$Key]) {
            'heap' {
                if ($Value -notmatch '^\d+[gGmM]$') {
                    throw "Недопустимое значение '$Value' для $Key. Ожидается число с суффиксом g или m, например 16g."
                }
            }
            'positiveInt' {
                [int]$n = 0
                if ($Value -notmatch '^\d+$' -or -not [int]::TryParse($Value, [ref]$n) -or $n -le 0) {
                    throw "Недопустимое значение '$Value' для $Key. Ожидается целое число больше нуля."
                }
                $newValue = $n
            }
            'path' {
                if (-not (Test-Path -LiteralPath $Value)) {
                    Write-Warning "Путь для $Key не существует: $Value"
                }
            }
        }
    }

    $cfg = Get-EdtWtConfig
    $section, $name = $Key -split '\.', 2
    $cfg.$section.$name = $newValue

    if ($PSCmdlet.ShouldProcess((Get-EdtWtUserConfigPath), "Установить $Key")) {
        Save-EdtWtConfig -Config $cfg | Out-Null
        $shown = if ($null -eq $newValue) { 'null (по умолчанию)' } else { $newValue }
        Write-Host "✓ $Key = $shown" -ForegroundColor Green
    }
}

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

    return (Get-EdtConfig)
}
