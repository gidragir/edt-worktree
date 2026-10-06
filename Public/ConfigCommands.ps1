# ==============================================================================
# ConfigCommands.ps1 - Публичные команды конфигурации окружения и проектов
# ==============================================================================

Set-StrictMode -Version Latest

function Get-EdtConfig {
    <#
    .SYNOPSIS
        Возвращает текущую конфигурацию модуля EdtWorktree.
    .DESCRIPTION
        Показывает настройки текущей машины (%APPDATA%\EdtWorktree\config.json)
        и активного git-репозитория (.edt-worktree.json).
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
    $projFile = Get-EdtWtProjectConfigFile

    $summary = [PSCustomObject]@{
        UserConfigFile     = $userPath
        ProjectConfigFile  = if ($projFile) { $projFile } else { 'none' }
        ProjectsRoot       = $cfg.paths.projects_root
        WorktreeRoot       = $cfg.paths.worktree_root
        WorkspacesRoot     = $cfg.paths.workspaces_root
        EdtCliPath         = if ($cfg.defaults.'1cedtcli') { $cfg.defaults.'1cedtcli' } else { 'not configured' }
        ReferenceBranch    = $cfg.defaults.reference_branch
        EdtPrefsSource     = if ($cfg.defaults.edt_prefs_source) { $cfg.defaults.edt_prefs_source } else { 'none' }
        MaxHeap            = (Get-EdtWtProperty (Get-EdtWtProperty $cfg.defaults 'jvm') 'max_heap' '12g')
        GuiMaxHeap         = (Get-EdtWtProperty (Get-EdtWtProperty $cfg.defaults 'jvm') 'gui_max_heap' '8g')
        ActiveProject      = if ($cfg.PSObject.Properties['ActiveProjectId']) { $cfg.ActiveProjectId } else { 'none' }
        KnownProjects      = if ($cfg.projects) { @($cfg.projects.PSObject.Properties | ForEach-Object { $_.Name }) } else { @() }
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
    .PARAMETER ReferenceBranch
        Имя эталонной ветки по умолчанию (например, pre-prod).
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
        [string]$ReferenceBranch,
        [string]$EdtPrefsSource
    )

    $cfg = Get-EdtWtConfig

    if ($PSBoundParameters.ContainsKey('ProjectsRoot')) {
        $cfg.paths.projects_root = $ProjectsRoot
    }
    if ($PSBoundParameters.ContainsKey('WorktreeRoot')) {
        $cfg.paths.worktree_root = $WorktreeRoot
    }
    if ($PSBoundParameters.ContainsKey('WorkspacesRoot')) {
        $cfg.paths.workspaces_root = $WorkspacesRoot
        $cfg.worktree.root_dir = $WorkspacesRoot
    }
    if ($PSBoundParameters.ContainsKey('EdtCliPath')) {
        if (-not (Test-Path -LiteralPath $EdtCliPath)) {
            Write-Warning "Указанный путь к 1cedtcli не существует: $EdtCliPath"
        }
        $cfg.defaults.'1cedtcli' = $EdtCliPath
    }
    if ($PSBoundParameters.ContainsKey('MaxHeap')) {
        if ($MaxHeap -notmatch '^\d+[gmGM]$') {
            throw "Недопустимый формат MaxHeap: '$MaxHeap'. Ожидается, например, '12g'."
        }
        $cfg.defaults.jvm.max_heap = $MaxHeap.ToLower()
    }
    if ($PSBoundParameters.ContainsKey('GuiMaxHeap')) {
        if ($GuiMaxHeap -notmatch '^\d+[gmGM]$') {
            throw "Недопустимый формат GuiMaxHeap: '$GuiMaxHeap'. Ожидается, например, '8g'."
        }
        $cfg.defaults.jvm.gui_max_heap = $GuiMaxHeap.ToLower()
    }
    if ($PSBoundParameters.ContainsKey('ReferenceBranch')) {
        $cfg.defaults.reference_branch = $ReferenceBranch
        $cfg.worktree.reference_branch = $ReferenceBranch
    }
    if ($PSBoundParameters.ContainsKey('EdtPrefsSource')) {
        $cfg.defaults.edt_prefs_source = $EdtPrefsSource
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

    $defaultProjects = $cfg.paths.projects_root
    $defaultWorktree = $cfg.paths.worktree_root
    $defaultWorkspaces = $cfg.paths.workspaces_root

    if ($NonInteractive) {
        $saved = Save-EdtWtConfig -Config $cfg
        Write-Host "✓ Конфигурация сохранена с параметрами по умолчанию в $saved" -ForegroundColor Green
        return (Get-EdtConfig)
    }

    # 1. Каталоги проектов
    Write-Host "`n1. Настройка каталогов:" -ForegroundColor Yellow
    $ans = Read-Host "Каталог исходных репозиториев [$defaultProjects]"
    if ($ans -and $ans.Trim()) { $cfg.paths.projects_root = $ans.Trim() }

    $ans = Read-Host "Каталог git-worktrees [$defaultWorktree]"
    if ($ans -and $ans.Trim()) { $cfg.paths.worktree_root = $ans.Trim() }

    $ans = Read-Host "Каталог рабочих областей EDT [$defaultWorkspaces]"
    if ($ans -and $ans.Trim()) {
        $cfg.paths.workspaces_root = $ans.Trim()
        $cfg.worktree.root_dir = $ans.Trim()
    }

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

        $defaultChoice = "1"
        $choiceStr = Read-Host "Выберите версию EDT [$defaultChoice]"
        if (-not $choiceStr -or -not $choiceStr.Trim()) { $choiceStr = $defaultChoice }

        [int]$choiceNum = 0
        if ([int]::TryParse($choiceStr, [ref]$choiceNum) -and $choiceNum -ge 1 -and $choiceNum -le $installed.Count) {
            $chosenCli = $installed[$choiceNum - 1].Path
        }
    }

    if (-not $chosenCli) {
        $cliPrompt = if ($cfg.defaults.'1cedtcli') { $cfg.defaults.'1cedtcli' } else { "не задан" }
        $ans = Read-Host "Путь к 1cedtcli.exe или 1cedtcli.bat [$cliPrompt]"
        if ($ans -and $ans.Trim()) {
            $chosenCli = $ans.Trim()
        } else {
            $chosenCli = $cfg.defaults.'1cedtcli'
        }
    }

    if ($chosenCli) {
        $cfg.defaults.'1cedtcli' = $chosenCli
        Write-Host "  Выбран: $chosenCli" -ForegroundColor Green
    }

    # 3. Дополнительные параметры
    Write-Host "`n3. Дополнительные параметры:" -ForegroundColor Yellow
    $currBranch = $cfg.defaults.reference_branch
    $ans = Read-Host "Эталонная ветка по умолчанию [$currBranch]"
    if ($ans -and $ans.Trim()) {
        $cfg.defaults.reference_branch = $ans.Trim()
        $cfg.worktree.reference_branch = $ans.Trim()
    }

    $currDonor = if ($cfg.defaults.edt_prefs_source) { $cfg.defaults.edt_prefs_source } else { "none" }
    $ans = Read-Host "Каталог-донор настроек IDE (шрифты, темы) [$currDonor]"
    if ($ans -and $ans.Trim() -and $ans.Trim() -ne 'none') {
        $cfg.defaults.edt_prefs_source = $ans.Trim()
    }

    # 4. Сохранение
    $savedPath = Save-EdtWtConfig -Config $cfg
    Write-Host "`n✓ Настройки успешно сохранены в: $savedPath" -ForegroundColor Green

    foreach ($p in @($cfg.paths.projects_root, $cfg.paths.worktree_root, $cfg.paths.workspaces_root)) {
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
        $topLevel = (git rev-parse --show-toplevel 2>$null)
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
