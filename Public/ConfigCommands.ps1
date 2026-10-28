# ==============================================================================
# ConfigCommands.ps1 - Публичные команды конфигурации окружения и проектов
# ==============================================================================

Set-StrictMode -Version Latest

function Get-EdtConfig {
    <#
    .SYNOPSIS
        Возвращает текущую конфигурацию модуля EdtWorktree.
    .DESCRIPTION
        Показывает настройки текущей машины (%APPDATA%\EdtWorktree\config.json).
    .PARAMETER AsJson
        Вывести конфигурацию в виде форматированного JSON.
    .EXAMPLE
        Get-EdtConfig
    .EXAMPLE
        Get-EdtConfig -AsJson
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject], [string])]
    param(
        [switch]$AsJson
    )

    $cfg = Get-EdtWtConfig
    $userPath = Get-EdtWtUserConfigPath

    $summary = [PSCustomObject]@{
        UserConfigFile     = $userPath
        ProjectsRoot       = $cfg.paths.repos_root
        WorktreeRoot       = $cfg.paths.worktrees_root
        WorkspacesRoot     = $cfg.paths.workspaces_root
        EdtCliPath         = if ($cfg.edt.cli_path) { $cfg.edt.cli_path } else { 'auto' }
        EdtPrefsSource     = if ($cfg.edt.prefs_source) { $cfg.edt.prefs_source } else { 'none' }
        MaxHeap            = if ($cfg.edt.max_heap) { $cfg.edt.max_heap } else { 'auto' }
        GuiMaxHeap         = if ($cfg.edt.gui_max_heap) { $cfg.edt.gui_max_heap } else { 'auto' }
        KnownProjects      = @($cfg.projects.PSObject.Properties | ForEach-Object { $_.Name })
    }

    if ($AsJson) {
        return (ConvertTo-Json -InputObject $summary -Depth 5)
    }

    return $summary
}

function Set-EdtConfig {
    <#
    .SYNOPSIS
        Устанавливает параметры конфигурации пользователя.
    .DESCRIPTION
        Сохраняет указанные параметры в %APPDATA%\EdtWorktree\config.json.
    .PARAMETER ProjectsRoot
        Каталог основных репозиториев (например, D:\projects\default).
    .PARAMETER WorktreeRoot
        Каталог git-worktrees (например, D:\projects\worktree).
    .PARAMETER WorkspacesRoot
        Каталог рабочих областей EDT (например, D:\workspaces\worktree).
    .PARAMETER EdtCliPath
        Полный путь к исполняемому файлу 1cedtcli.exe / 1cedtcli.bat.
    .PARAMETER MaxHeap
        Размер кучи JVM для headless операций (например, 12g).
    .PARAMETER GuiMaxHeap
        Размер кучи JVM для GUI IDE (например, 8g).
    .PARAMETER EdtPrefsSource
        Каталог-донор настроек IDE (шрифты, цвета, горячие клавиши).
    .EXAMPLE
        Set-EdtConfig -WorkspacesRoot "D:\workspaces\worktree" -MaxHeap "16g"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$ProjectsRoot,
        [string]$WorktreeRoot,
        [string]$WorkspacesRoot,
        [string]$EdtCliPath,
        [string]$MaxHeap,
        [string]$GuiMaxHeap,
        [string]$EdtPrefsSource
    )

    $cfg = Get-EdtWtConfig

    if ($PSBoundParameters.ContainsKey('ProjectsRoot')) {
        $cfg.paths.repos_root = $ProjectsRoot
    }
    if ($PSBoundParameters.ContainsKey('WorktreeRoot')) {
        $cfg.paths.worktrees_root = $WorktreeRoot
    }
    if ($PSBoundParameters.ContainsKey('WorkspacesRoot')) {
        $cfg.paths.workspaces_root = $WorkspacesRoot
    }
    if ($PSBoundParameters.ContainsKey('EdtCliPath')) {
        if (-not (Test-Path -LiteralPath $EdtCliPath)) {
            Write-Warning "Указанный путь к 1cedtcli не существует: $EdtCliPath"
        }
        $cfg.edt.cli_path = $EdtCliPath
    }
    if ($PSBoundParameters.ContainsKey('MaxHeap')) {
        if ($MaxHeap -notmatch '^\d+[gmGM]$') {
            throw "Недопустимый формат MaxHeap: '$MaxHeap'. Ожидается, например, '12g'."
        }
        $cfg.edt.max_heap = $MaxHeap.ToLower()
    }
    if ($PSBoundParameters.ContainsKey('GuiMaxHeap')) {
        if ($GuiMaxHeap -notmatch '^\d+[gmGM]$') {
            throw "Недопустимый формат GuiMaxHeap: '$GuiMaxHeap'. Ожидается, например, '8g'."
        }
        $cfg.edt.gui_max_heap = $GuiMaxHeap.ToLower()
    }
    if ($PSBoundParameters.ContainsKey('EdtPrefsSource')) {
        $cfg.edt.prefs_source = $EdtPrefsSource
    }

    if ($PSCmdlet.ShouldProcess("config.json", "Сохранить параметры конфигурации EdtWorktree")) {
        $savedPath = Save-EdtWtConfig -Config $cfg
        Write-Host "✓ Конфигурация успешно сохранена в $savedPath" -ForegroundColor Green
    }
    return (Get-EdtConfig)
}

function Initialize-EdtConfig {
    <#
    .SYNOPSIS
        Интерактивный мастер первичной настройки окружения EdtWorktree.
    .DESCRIPTION
        Опрашивает пользователя о расположении рабочих папок, сканирует установленные
        версии 1C:EDT и сохраняет файл конфигурации в %APPDATA%\EdtWorktree\config.json.
    .PARAMETER NonInteractive
        Использовать значения по умолчанию без интерактивного диалога.
    .EXAMPLE
        Initialize-EdtConfig
    #>
    [CmdletBinding()]
    param(
        [switch]$NonInteractive
    )

    Write-Host "`n=== [EdtWorktree] Первичная настройка окружения ===" -ForegroundColor Cyan

    $cfg = Get-EdtWtConfig

    if ($NonInteractive) {
        $saved = Save-EdtWtConfig -Config $cfg
        Write-Host "✓ Конфигурация сохранена с параметрами по умолчанию в $saved" -ForegroundColor Green
        return (Get-EdtConfig)
    }

    # 1. Каталоги проектов
    Write-Host "`n1. Настройка каталогов:" -ForegroundColor Yellow
    $cfg.paths.repos_root = Read-EdtWtAnswer -Prompt 'Каталог исходных репозиториев' -Default $cfg.paths.repos_root
    $cfg.paths.worktrees_root = Read-EdtWtAnswer -Prompt 'Каталог git-worktrees' -Default $cfg.paths.worktrees_root
    $cfg.paths.workspaces_root = Read-EdtWtAnswer -Prompt 'Каталог рабочих областей EDT' -Default $cfg.paths.workspaces_root

    # 2. Выбор версии EDT
    Write-Host "`n2. Поиск установленных версий 1C:EDT..." -ForegroundColor Yellow
    $installed = @(Find-EdtWtCli)

    $chosenCli = $null
    if ($installed.Count -gt 0) {
        Write-Host "Найдено версий: $($installed.Count)" -ForegroundColor Gray
        for ($i = 0; $i -lt $installed.Count; $i++) {
            Write-Host ("  [{0}] 1C:EDT {1} ({2})" -f ($i + 1), $installed[$i].Version, $installed[$i].Path)
        }
        Write-Host ("  [{0}] Указать свой путь" -f ($installed.Count + 1))

        $choiceStr = Read-EdtWtAnswer -Prompt 'Выберите версию EDT' -Default '1'

        [int]$choiceNum = 0
        if ([int]::TryParse($choiceStr, [ref]$choiceNum) -and $choiceNum -ge 1 -and $choiceNum -le $installed.Count) {
            $chosenCli = $installed[$choiceNum - 1].Path
        }
    }

    if (-not $chosenCli) {
        $cliPrompt = if ($cfg.edt.cli_path) { $cfg.edt.cli_path } else { $null }
        $chosenCli = Read-EdtWtAnswer -Prompt 'Путь к 1cedtcli.exe или 1cedtcli.bat' -Default $cliPrompt
    }

    if ($chosenCli) {
        $cfg.edt.cli_path = $chosenCli
        Write-Host "  Выбран: $chosenCli" -ForegroundColor Green
    }

    # 3. Дополнительные параметры
    Write-Host "`n3. Дополнительные параметры:" -ForegroundColor Yellow
    $currDonor = if ($cfg.edt.prefs_source) { $cfg.edt.prefs_source } else { 'none' }
    $ans = Read-EdtWtAnswer -Prompt 'Каталог-донор настроек IDE (шрифты, темы)' -Default $currDonor
    if ($ans -and $ans -ne 'none') {
        $cfg.edt.prefs_source = $ans
    }

    # 4. Сохранение
    $savedPath = Save-EdtWtConfig -Config $cfg
    Write-Host "`n✓ Настройки успешно сохранены в: $savedPath" -ForegroundColor Green

    foreach ($p in @($cfg.paths.repos_root, $cfg.paths.worktrees_root, $cfg.paths.workspaces_root)) {
        if ($p -and -not (Test-Path -LiteralPath $p)) {
            $create = Read-Host "Каталог '$p' не существует. Создать? [Y/n]"
            if (-not $create -or $create -match '^[yYдД]') {
                New-Item -ItemType Directory -Path $p -Force | Out-Null
                Write-Host "  Создан: $p" -ForegroundColor Gray
            }
        }
    }

    return (Get-EdtConfig)
}
function New-EdtProjectConfig {
    <#
    .SYNOPSIS
        Инициализирует файл конфигурации .edt-worktree.json для проекта 1C.
    .DESCRIPTION
        Создает .edt-worktree.json в корне текущего Git-репозитория с автоопределением
        имени проекта и расширений.
    .PARAMETER Path
        Каталог репозитория. По умолчанию текущий.
    .PARAMETER CfProject
        Имя или относительный путь проекта основной конфигурации.
    .PARAMETER ReferenceBranch
        Имя эталонной ветки (по умолчанию pre-prod).
    .PARAMETER Force
        Перезаписать существующий .edt-worktree.json.
    .EXAMPLE
        New-EdtProjectConfig
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Path,
        [string]$CfProject,
        [string]$ReferenceBranch = 'pre-prod',
        [switch]$Force
    )

    $targetDir = if ($Path) { $Path } else { (Get-Location).Path }
    Push-Location -LiteralPath $targetDir
    try {
        $topLevel = (Invoke-EdtWtGit rev-parse --show-toplevel 2>$null)
        if (-not $topLevel) {
            throw "Каталог '$targetDir' не находится внутри git-репозитория."
        }
        $topLevel = ($topLevel -replace '/', '\')
        $cfgFile = Join-Path $topLevel ".edt-worktree.json"

        if ((Test-Path -LiteralPath $cfgFile) -and -not $Force) {
            throw "Файл уже существует: $cfgFile. Используйте -Force для перезаписи."
        }

        if (-not $CfProject) {
            if (Test-Path -LiteralPath (Join-Path $topLevel "src\cf")) {
                $CfProject = "src/cf"
            } elseif (Test-Path -LiteralPath (Join-Path $topLevel ".project")) {
                $xml = [xml](Get-Content -LiteralPath (Join-Path $topLevel ".project") -Raw)
                $CfProject = $xml.projectDescription.name
            }
            if (-not $CfProject) {
                $CfProject = Split-Path -Leaf $topLevel
            }
        }

        $extensions = @()
        $extDirs = Get-ChildItem -LiteralPath $topLevel -Directory -Depth 2 -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'cfe*' -or $_.Name -like 'ext*' }
        foreach ($ed in $extDirs) {
            if (Test-Path -LiteralPath (Join-Path $ed.FullName ".project")) {
                $extensions += $ed.Name
            }
        }

        $template = [ordered]@{
            cf_project        = $CfProject
            reference_branch  = $ReferenceBranch
            v8version         = "8.3.24"
            active_extensions = $extensions
            ignored_patterns  = @()
            ibconnection      = ""
        }

        if ($PSCmdlet.ShouldProcess($cfgFile, "Создать файл конфигурации проекта")) {
            $json = ConvertTo-Json -InputObject $template -Depth 5
            Set-Content -LiteralPath $cfgFile -Value $json -Encoding UTF8
            Write-Host "✓ Создан файл конфигурации проекта: $cfgFile" -ForegroundColor Green
            return $template
        }
    } finally {
        Pop-Location
    }
}
