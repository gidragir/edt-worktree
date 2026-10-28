# ==============================================================================
# WorktreeCommands.ps1 - Публичные команды управления воркспейсами и воркдеревьями
# ==============================================================================

Set-StrictMode -Version Latest

# ------------------------------------------------------------------------------
# 1. Получение контекста и сводки рабочих областей
# ------------------------------------------------------------------------------

function Get-EdtWtContext {
    <#
    .SYNOPSIS
        Собирает контекст текущего worktree: проект, пути, параметры EDT.

    .DESCRIPTION
        Определяет проект по клону (git rev-parse --git-common-dir): клон и все его
        worktree относятся к проекту с именем папки клона в repos_root. Вычисляет
        каталоги рабочей области и эталона (_reference), путь к 1cedtcli и GUI,
        аргументы JVM, эталонную ветку проекта (RefBranch) и расширения
        (Extensions - пути относительно клона). Незарегистрированный клон - ошибка.

    .PARAMETER Path
        Каталог внутри клона или его worktree. По умолчанию - текущий.

    .PARAMETER ProjectName
        Явное имя проекта: клон берётся из repos_root, если Path не указан
        и текущий каталог не внутри клона.

    .EXAMPLE
        Get-EdtWtContext | Select-Object ProjectId, WorkspaceDir, Extensions
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$Path,
        [string]$ProjectName
    )

    $cfg = Get-EdtWtConfig
    $reposRoot = $cfg.paths.repos_root

    $startPath = if ($Path) { $Path } else { (Get-Location).Path }
    $resolved = Resolve-EdtWtProjectFromPath -Path $startPath -Config $cfg
    if (-not $resolved -and $ProjectName -and -not $Path) {
        # Явный проект вне клона: работаем от самого клона.
        $startPath = Join-Path $reposRoot $ProjectName
        $resolved = Resolve-EdtWtProjectFromPath -Path $startPath -Config $cfg
    }
    if (-not $resolved) {
        throw "Каталог '$startPath' не относится к клону из repos_root ($reposRoot). Перейдите в клон проекта или его worktree либо укажите -ProjectName."
    }

    $projectId = if ($ProjectName) { $ProjectName } else { $resolved.Name }
    $projDef = Get-EdtWtProjectDef -Config $cfg -Name $projectId

    Push-Location -LiteralPath $startPath
    try {
        $topLevel = (Invoke-EdtWtGit rev-parse --show-toplevel 2>$null)
        if (-not $topLevel) { throw "Каталог '$startPath' не находится внутри git-репозитория." }
        $topLevel = ($topLevel -replace '/', '\')
        $branch = (Invoke-EdtWtGit rev-parse --abbrev-ref HEAD 2>$null)
    } finally {
        Pop-Location
    }

    $repoPath = if ($projectId -ne $resolved.Name) { Join-Path $reposRoot $projectId } else { $resolved.RepoPath }
    $edtCfg = $cfg.edt

    $worktreeId = if ($branch -and $branch -ne 'HEAD') { ConvertTo-EdtWtSafeName $branch } else { ConvertTo-EdtWtSafeName (Split-Path -Leaf $topLevel) }

    $edtCli = Get-EdtWtProperty $edtCfg 'cli_path'
    if (-not $edtCli) {
        $found = @(Find-EdtWtCli)
        if ($found.Count -gt 0) { $edtCli = $found[0].Path }
    }
    if (-not $edtCli) {
        throw "Путь к 1cedtcli не настроен. Установите 1C:EDT или укажите edt.cli_path в конфигурации (edt config set edt.cli_path <путь>)."
    }
    $edtCli = ($edtCli -replace '/', '\')
    $edtGui = Join-Path (Split-Path -Parent $edtCli) "1cedt.exe"

    # Неявный max_heap = авто: без -Xmx кучу подберёт Resolve-EdtWtJvmArgs.
    $maxHeap = Get-EdtWtProperty $edtCfg 'max_heap'
    $xmx = if ($maxHeap) { "-Xmx$maxHeap " } else { '' }
    $jvmArgs = "$xmx-Xms2g $(Get-EdtWtProperty $edtCfg 'extra_vmargs' '')".Trim()

    $workspacesRoot = ($cfg.paths.workspaces_root -replace '/', '\')
    $projectRootWs = Join-Path $workspacesRoot $projectId

    return [PSCustomObject]@{
        ProjectId      = $projectId
        WorktreeId     = $worktreeId
        Branch         = $branch
        WorktreePath   = $topLevel
        RepoPath       = $repoPath
        GitCommonDir   = Join-Path $repoPath '.git'
        ProjectWsRoot  = $projectRootWs
        WorkspaceDir   = Join-Path $projectRootWs $worktreeId
        ReferenceWsDir = Join-Path $projectRootWs '_reference'
        RefBranch      = Get-EdtWtProperty $projDef 'ref_branch' 'pre-prod'
        CfProject      = Get-EdtWtProperty $projDef 'cf_project' 'src/cf'
        Extensions     = [string[]]@(Get-EdtWtProperty $projDef 'extensions' @())
        EdtCliPath     = $edtCli
        EdtGuiPath     = $edtGui
        JvmArgs        = $jvmArgs
        VmPath         = Get-EdtWtProperty $edtCfg 'vm_path'
        GuiMaxHeap     = Get-EdtWtProperty $edtCfg 'gui_max_heap'
        TimeoutSec     = Get-EdtWtProperty $edtCfg 'timeout_sec' 7200
    }
}

function Get-EdtWorktreeList {
    <#
    .SYNOPSIS
        Возвращает сводку по рабочим областям 1C:EDT.

    .DESCRIPTION
        Для каждой области показывает проект, worktree, путь к исходникам,
        каталог области, признак блокировки (.metadata/.lock) и процессы,
        которые её занимают.

    .PARAMETER ProjectName
        Ограничить выборку одним проектом из projects.json.

    .EXAMPLE
        Get-EdtWorktreeList | Format-Table

    .EXAMPLE
        Get-EdtWorktreeList | Where-Object Locked -eq 'LOCK'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([string]$ProjectName)

    $cfg = Get-EdtWtConfig
    $root = ($cfg.paths.workspaces_root -replace '/', '\')

    if (-not (Test-Path -LiteralPath $root)) {
        Write-Host "Корень рабочих областей не найден: $root" -ForegroundColor Yellow
        return
    }

    $wtMap = @{}
    foreach ($prop in $cfg.projects.PSObject.Properties) {
        $pid_ = $prop.Name
        if ($ProjectName -and $pid_ -ne $ProjectName) { continue }
        $wtMap[$pid_] = @{}
    }

    $procs = @(Get-CimInstance -ClassName Win32_Process `
        -Filter "Name = '1cedt.exe' OR Name = '1cedtc.exe' OR Name = '1cedtcli.exe' OR Name = 'javaw.exe' OR Name = 'java.exe'" `
        -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine })

    $rows = @()

    foreach ($projDir in (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $pid_ = $projDir.Name
        if ($ProjectName -and $pid_ -ne $ProjectName) { continue }

        foreach ($wsDir in (Get-ChildItem -LiteralPath $projDir.FullName -Directory -ErrorAction SilentlyContinue)) {
            $wsPath = $wsDir.FullName
            $locked = Test-Path -LiteralPath (Join-Path $wsPath ".metadata\.lock")

            $matching = @($procs | Where-Object { $_.CommandLine -like "*$wsPath*" })
            $pidList = if ($matching.Count -gt 0) { ($matching | ForEach-Object { "$($_.Name):$($_.ProcessId)" }) -join ', ' } else { '' }

            $rows += [PSCustomObject]@{
                Project   = $pid_
                Worktree  = $wsDir.Name
                Workspace = $wsPath
                Locked    = if ($locked) { 'LOCK' } else { '' }
                Processes = $pidList
            }
        }
    }

    try {
        $ctx = Get-EdtWtContext -ErrorAction SilentlyContinue
    } catch { $ctx = $null }

    if ($ctx) {
        Push-Location -LiteralPath $ctx.WorktreePath
        try { $lines = Invoke-EdtWtGit worktree list --porcelain 2>$null } finally { Pop-Location }
        $cur = $null
        $map = @{}
        foreach ($line in $lines) {
            if ($line -match '^worktree\s+(.+)$') { $cur = ($matches[1] -replace '/', '\') }
            elseif ($line -match '^branch\s+refs/heads/(.+)$') { $map[(ConvertTo-EdtWtSafeName $matches[1])] = $cur }
        }
        foreach ($r in $rows) {
            if ($r.Project -eq $ctx.ProjectId -and $map.ContainsKey($r.Worktree)) {
                $r | Add-Member -NotePropertyName CodePath -NotePropertyValue $map[$r.Worktree] -Force
            }
        }
    }

    foreach ($r in $rows) {
        if ($null -eq $r.PSObject.Properties['CodePath']) {
            $r | Add-Member -NotePropertyName CodePath -NotePropertyValue '' -Force
        }
    }

    if ($rows.Count -eq 0) {
        Write-Host "Рабочие области не найдены в $root" -ForegroundColor Yellow
        return
    }

    return $rows | Select-Object Project, Worktree, CodePath, Workspace, Locked, Processes
}

# ------------------------------------------------------------------------------
# 2. Жизненный цикл рабочих областей: Open, Warmup, Add, Clean
# ------------------------------------------------------------------------------

function Invoke-EdtWorktreeOpen {
    <#
    .SYNOPSIS
        Открывает рабочую область 1C:EDT для текущего git worktree.

    .DESCRIPTION
        Рабочая область при первом открытии клонируется из прогретого эталона
        _reference, поэтому индексы не строятся заново. Затем проекты
        перепривязываются на текущий worktree, недостающие (конфигурация и
        рабочие расширения проекта) импортируются headless-вызовом 1cedtcli,
        переносятся пользовательские настройки IDE и запускается сам EDT.
        Куча JVM берётся из конфигурации (edt.max_heap).

    .PARAMETER NoGui
        Выполнить синхронизацию, но не запускать IDE.

    .PARAMETER Refresh
        Пересобрать рабочую область из текущего эталона.

    .EXAMPLE
        Invoke-EdtWorktreeOpen

    .EXAMPLE
        Invoke-EdtWorktreeOpen -Refresh -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [switch]$NoGui,

        [switch]$Refresh
    )

    $ctx = Get-EdtWtContext
    if ($null -eq $ctx) { return }

    Write-Host "==> Открытие рабочей области EDT" -ForegroundColor Green
    Write-Host "    Проект:   $($ctx.ProjectId)" -ForegroundColor Cyan
    Write-Host "    Worktree: $($ctx.WorktreeId) ($($ctx.WorktreePath))" -ForegroundColor Cyan
    Write-Host "    WS:       $($ctx.WorkspaceDir)" -ForegroundColor Cyan

    if (-not (Initialize-EdtWtWorkspace -Context $ctx -Refresh:$Refresh)) {
        return
    }

    if ($PSCmdlet.ShouldProcess($ctx.WorkspaceDir, 'Перепривязать проекты на текущий worktree')) {
        Write-Host "==> Перепривязка проектов на текущий worktree..." -ForegroundColor Cyan
        Repair-EdtWtWorkspaceLocations -WorkspaceDir $ctx.WorkspaceDir -WorktreePath $ctx.WorktreePath -ReferenceWsDir $ctx.ReferenceWsDir | Out-Null
    }

    Test-EdtWtWorkspaceFreshness -Context $ctx | Out-Null

    $extNames = @(Get-EdtWtExtensionNames -Context $ctx)
    Write-Host "    Расширения: $(if ($extNames.Count) { $extNames -join ', ' } else { '<нет>' })" -ForegroundColor Cyan

    $plan = Get-EdtWtImportTargets -Context $ctx -Extensions @($ctx.Extensions) -IncludeConfiguration
    $batch = New-EdtWtBatch
    foreach ($t in $plan.Targets) { $batch.AddImport($t) | Out-Null }

    if ($batch.IsEmpty()) {
        Write-Host "==> Импорт не требуется — все проекты уже в рабочей области." -ForegroundColor Cyan
    } elseif ($PSCmdlet.ShouldProcess($ctx.WorkspaceDir, "Импортировать проектов: $($batch.Commands.Count)")) {
        Write-Host "==> Headless-синхронизация рабочей области..." -ForegroundColor Cyan
        Invoke-EdtWtCli -Context $ctx -WorkspaceDir $ctx.WorkspaceDir -Commands $batch.ToArray() -BatchName "sync_batch.txt"
        Write-Host "    ✓ Синхронизация завершена." -ForegroundColor Green
    } else {
        $batch.Print()
    }

    if ($PSCmdlet.ShouldProcess($ctx.WorkspaceDir, 'Перенести настройки IDE')) {
        Copy-EdtWtPreferences -Context $ctx -WorkspaceDir $ctx.WorkspaceDir | Out-Null
    }

    if ($NoGui) {
        Write-Host "✓ Готово (GUI не запускается: -NoGui)." -ForegroundColor Green
        return
    }

    Start-EdtWtGui -Context $ctx
}

function Invoke-EdtWorktreeWarmup {
    <#
    .SYNOPSIS
        Собирает эталонную рабочую область _reference из клона проекта.

    .DESCRIPTION
        Импортирует конфигурацию и рабочие расширения проекта прямо из клона
        (он должен стоять на эталонной ветке), затем проверяет все
        импортированные проекты (validate), чтобы индексы и derived-данные были
        готовы. Из эталона клонируются рабочие области веток. Прежний эталон
        сохраняется в <эталон>.previous и возвращается, если сборка не удалась.
        Занятый EDT эталон не пересобирается: процессы не закрываются.

    .PARAMETER ProjectName
        Проект из конфигурации. По умолчанию определяется по текущему каталогу.

    .EXAMPLE
        Invoke-EdtWorktreeWarmup -ProjectName my-project
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Position = 0)]
        [string]$ProjectName
    )

    $ctx = Get-EdtWtContext -ProjectName $ProjectName
    if ($null -eq $ctx) { return }

    Write-Host "==> Сборка эталона: $($ctx.ProjectId)" -ForegroundColor Green
    Write-Host "    Reference WS: $($ctx.ReferenceWsDir)" -ForegroundColor Cyan

    # 1. Эталон старого именования переименовывается, если он свободен.
    $legacyDir = Join-Path $ctx.ProjectWsRoot '_reference_preprod'
    if (-not (Test-Path -LiteralPath $ctx.ReferenceWsDir) -and (Test-Path -LiteralPath $legacyDir)) {
        $legacyBusy = @(Get-EdtWtWorkspaceProcesses -WorkspaceDir $legacyDir)
        if ($legacyBusy.Count -gt 0) {
            Write-Warning "Старый эталон '$legacyDir' занят ($(($legacyBusy | ForEach-Object { "$($_.Name):$($_.ProcessId)" }) -join ', ')), не переименован."
        } elseif ($PSCmdlet.ShouldProcess($legacyDir, 'Переименовать в _reference')) {
            Rename-Item -LiteralPath $legacyDir -NewName '_reference'
            Write-Host "    Старый эталон _reference_preprod переименован в _reference." -ForegroundColor Yellow
        }
    }

    # 2. Источник - сам клон на эталонной ветке.
    $cloneBranch = Get-EdtWtCloneBranch -RepoPath $ctx.RepoPath
    if ($cloneBranch -ne $ctx.RefBranch) {
        $shown = if ($cloneBranch) { $cloneBranch } else { '(detached HEAD)' }
        throw "Клон $($ctx.RepoPath) стоит на '$shown', эталон собирается с '$($ctx.RefBranch)'. Переключите: git -C $($ctx.RepoPath) switch $($ctx.RefBranch)"
    }
    Write-Host "    Источник:     $($ctx.RepoPath) [$($ctx.RefBranch)]" -ForegroundColor Cyan

    # 3. Занятый эталон не трогаем, процессы не закрываем.
    Assert-EdtWtReferenceFree -Context $ctx

    # 4. Батч: конфигурация, рабочие расширения, затем проверка всего импортированного.
    $cfDir = Join-Path $ctx.RepoPath ($ctx.CfProject -replace '/', '\')
    $batch = New-EdtWtBatch
    $batch.AddImport($cfDir) | Out-Null
    $projectDirs = @($cfDir)
    $imported = @()
    foreach ($rel in @($ctx.Extensions)) {
        $extDir = Join-Path $ctx.RepoPath ($rel -replace '/', '\')
        if (Test-Path -LiteralPath (Join-Path $extDir '.project')) {
            $batch.AddImport($extDir) | Out-Null
            $projectDirs += $extDir
            $imported += (Split-Path -Leaf $rel)
        } else {
            Write-Host "    [skip] Не EDT-проект или каталог отсутствует: $rel" -ForegroundColor Yellow
        }
    }
    Write-Host "    Расширения:   $(if ($imported.Count) { $imported -join ', ' } else { '<нет>' })" -ForegroundColor Cyan

    $projectNames = @($projectDirs | ForEach-Object { Get-EdtWtEclipseProjectName -ProjectDir $_ })
    $tsv = Join-Path $ctx.ReferenceWsDir "warmup_validation.tsv"
    $batch.AddValidate($projectNames, $tsv) | Out-Null
    Write-Host "    Проверки:     validate по всем импортированным, отчёт: $tsv" -ForegroundColor Cyan
    # Проверки должны отработать по-настоящему, иначе индексы не прогреются.
    $ctx.JvmArgs = ($ctx.JvmArgs -replace '\s*-DisableProjectChecks=true', '')

    # 7. Найденные, но не рабочие расширения.
    $unused = @(Get-EdtWtUnusedExtensions -Context $ctx | ForEach-Object { Split-Path -Leaf $_ })
    if ($unused.Count -gt 0) {
        Write-Host "    Не в рабочих: $($unused -join ', '). Включить: edt project ext $($ctx.ProjectId)" -ForegroundColor Yellow
    }

    if (-not $PSCmdlet.ShouldProcess($ctx.ReferenceWsDir, "Собрать эталон заново, импортировать проектов: $($batch.Commands.Count)")) {
        $batch.Print()
        return
    }

    # 5-6. Сборка с резервом прежнего эталона, затем настройки IDE.
    Invoke-EdtWtSafeWarmup -Context $ctx -Build {
        Invoke-EdtWtCli -Context $ctx -WorkspaceDir $ctx.ReferenceWsDir -Commands $batch.ToArray() -BatchName "warmup_batch.txt"
        Copy-EdtWtPreferences -Context $ctx -WorkspaceDir $ctx.ReferenceWsDir | Out-Null
    }

    Write-Host "✓ Эталон собран: $($ctx.ReferenceWsDir)" -ForegroundColor Green
}

function Invoke-EdtWorktreeAdd {
    <#
    .SYNOPSIS
        Доимпортирует расширения в уже существующую рабочую область.

    .DESCRIPTION
        Рабочая область блокируется запущенным EDT (.metadata/.lock), поэтому
        IDE на время headless-импорта закрывается и по завершении поднимается
        обратно. Эталон и конфигурация проекта не меняются.

    .PARAMETER Extensions
        Расширения текущего worktree: имя папки (cfe_x) или относительный путь.

    .PARAMETER NoGui
        Не поднимать IDE обратно после импорта.

    .PARAMETER Force
        Закрыть работающий EDT без вопроса.

    .EXAMPLE
        Invoke-EdtWorktreeAdd cfe_mp,cfe_pos
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Position = 0, Mandatory)]
        [string[]]$Extensions,

        [switch]$NoGui,

        [switch]$Force
    )

    $ctx = Get-EdtWtContext
    if ($null -eq $ctx) { return }

    if (-not (Test-Path -LiteralPath $ctx.WorkspaceDir)) {
        throw "Рабочая область не найдена: $($ctx.WorkspaceDir). Сначала выполните edt open."
    }

    $found = @(Find-EdtWtEdtProjects -RepoPath $ctx.WorktreePath | Where-Object { $_.Kind -eq 'Extension' })
    $extList = [string[]]@($Extensions | ForEach-Object { Resolve-EdtWtExtensionRef -Found $found -Ref $_ } | Select-Object -Unique)

    Write-Host "==> Доимпорт расширений: $($ctx.ProjectId)/$($ctx.WorktreeId)" -ForegroundColor Green
    Write-Host "    WS: $($ctx.WorkspaceDir)" -ForegroundColor Cyan

    $plan = Get-EdtWtImportTargets -Context $ctx -Extensions $extList

    if ($plan.Targets.Count -eq 0) {
        Write-Host "Нечего импортировать — все указанные расширения уже в рабочей области." -ForegroundColor Yellow
        return
    }

    $running = @(Get-EdtWtWorkspaceProcesses -WorkspaceDir $ctx.WorkspaceDir)
    $wasRunning = $running.Count -gt 0
    if ($wasRunning) {
        Write-Host "    На этой рабочей области запущен EDT (PID: $(($running | ForEach-Object { $_.ProcessId }) -join ', '))." -ForegroundColor Yellow
        $closeAction = 'Закрыть EDT для импорта (несохранённые изменения будут потеряны)'
        if (-not $Force -and -not $PSCmdlet.ShouldProcess($ctx.WorkspaceDir, $closeAction)) {
            Write-Host "Отменено. Сохраните работу и повторите, либо импортируйте через File > Import в самом EDT." -ForegroundColor Yellow
            return
        }
        Stop-EdtWtProcesses -WorkspaceDir $ctx.WorkspaceDir | Out-Null
    }

    $batch = New-EdtWtBatch
    foreach ($t in $plan.Targets) { $batch.AddImport($t) | Out-Null }

    if (-not $PSCmdlet.ShouldProcess($ctx.WorkspaceDir, "Импортировать проектов: $($batch.Commands.Count)")) {
        $batch.Print()
        return
    }

    Repair-EdtWtWorkspaceLocations -WorkspaceDir $ctx.WorkspaceDir -WorktreePath $ctx.WorktreePath -ReferenceWsDir $ctx.ReferenceWsDir | Out-Null
    Invoke-EdtWtCli -Context $ctx -WorkspaceDir $ctx.WorkspaceDir -Commands $batch.ToArray() -BatchName "add_batch.txt"
    Write-Host "    ✓ Импортировано: $(($plan.Targets | ForEach-Object { Split-Path -Leaf $_ }) -join ', ')" -ForegroundColor Green

    if ($NoGui) {
        Write-Host "✓ Готово (GUI не запускается: -NoGui)." -ForegroundColor Green
        return
    }
    if (-not $wasRunning) {
        Write-Host "✓ Готово. EDT не был запущен — стартуйте его через edt open." -ForegroundColor Green
        return
    }

    Write-Host "==> Возврат 1C:EDT..." -ForegroundColor Cyan
    Start-EdtWtGui -Context $ctx
}

function Invoke-EdtWorktreeClean {
    <#
    .SYNOPSIS
        Удаляет рабочую область 1C:EDT и связанный git worktree.

    .DESCRIPTION
        Останавливает процессы EDT, работающие на этой области, удаляет каталог
        области целиком и снимает git worktree.

    .PARAMETER WorktreeId
        Какую область удалить. По умолчанию - область текущего worktree.

    .PARAMETER Force
        Устаревший ключ, оставлен для совместимости: равнозначен -Confirm:$false.

    .EXAMPLE
        Invoke-EdtWorktreeClean -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Position = 0)]
        [string]$WorktreeId,

        [switch]$Force
    )

    if ($Force -and -not $PSBoundParameters.ContainsKey('Confirm')) {
        $ConfirmPreference = 'None'
    }

    $ctx = Get-EdtWtContext
    if ($null -eq $ctx) { return }

    $targetId = if ($WorktreeId) { ConvertTo-EdtWtSafeName $WorktreeId } else { $ctx.WorktreeId }
    $wsDir = Join-Path $ctx.ProjectWsRoot $targetId

    if ($targetId -eq '_reference') {
        throw "Эталонная рабочая область '_reference' не удаляется этой командой. Пересоберите её командой 'edt warmup'."
    }

    $branchGuess = if ($WorktreeId) { $WorktreeId } else { $ctx.Branch }
    $wtPath = Get-EdtWtWorktreePathForBranch -RepoPath $ctx.WorktreePath -Branch $branchGuess
    if (-not $wtPath -and -not $WorktreeId) { $wtPath = $ctx.WorktreePath }

    Write-Host "==> Очистка worktree: $($ctx.ProjectId)/$targetId" -ForegroundColor Green
    Write-Host "    WS:       $wsDir" -ForegroundColor Cyan
    Write-Host "    Worktree: $(if ($wtPath) { $wtPath } else { '<не найден>' })" -ForegroundColor Cyan

    $target = "$($ctx.ProjectId)/$targetId"
    if (-not $PSCmdlet.ShouldProcess($target, 'Удалить рабочую область и git worktree')) {
        return
    }

    if ($wtPath -and ($wtPath.TrimEnd('\') -ieq $ctx.WorktreePath.TrimEnd('\'))) {
        Write-Host "    Текущий каталог находится внутри удаляемого worktree — переход в $($ctx.ProjectWsRoot)." -ForegroundColor Yellow
        if (-not (Test-Path -LiteralPath $ctx.ProjectWsRoot)) {
            New-Item -ItemType Directory -Force -Path $ctx.ProjectWsRoot | Out-Null
        }
        Set-Location -LiteralPath $ctx.ProjectWsRoot
    }

    if (Test-Path -LiteralPath $wsDir) {
        Stop-EdtWtProcesses -WorkspaceDir $wsDir | Out-Null
        Write-Host "    Удаление рабочей области..." -ForegroundColor Cyan
        Remove-Item -LiteralPath $wsDir -Recurse -Force
        Write-Host "    ✓ Рабочая область удалена." -ForegroundColor Green
    } else {
        Write-Host "    Рабочая область отсутствует — пропуск." -ForegroundColor Gray
    }

    if ($wtPath -and (Test-Path -LiteralPath $wtPath)) {
        Write-Host "    Удаление git worktree..." -ForegroundColor Cyan
        Push-Location -LiteralPath $ctx.GitCommonDir
        try {
            Invoke-EdtWtGit worktree remove $wtPath --force
            Invoke-EdtWtGit worktree prune
        } finally {
            Pop-Location
        }
        Write-Host "    ✓ git worktree удалён." -ForegroundColor Green
    } else {
        Write-Host "    Каталог git worktree не найден — выполняется только prune." -ForegroundColor Gray
        Push-Location -LiteralPath $ctx.GitCommonDir
        try { Invoke-EdtWtGit worktree prune } finally { Pop-Location }
    }

    Write-Host "✓ Очистка завершена: $($ctx.ProjectId)/$targetId" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 3. Совместимость с legacy-именами
# ------------------------------------------------------------------------------

function Invoke-EdtWtLegacyCommand {
    <#
    .SYNOPSIS
        Совместимость со старыми именами команд (wt-* и edt-wt-*).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$LegacyName,
        [Parameter(Mandatory)][string]$Subcommand,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
    )

    if (-not $script:EdtWtLegacyWarned.Contains($LegacyName)) {
        Write-Warning "Команда '$LegacyName' устарела, используйте 'edt $Subcommand'. Список подкоманд: edt help"
        [void]$script:EdtWtLegacyWarned.Add($LegacyName)
    }

    $params = @{ Command = $Subcommand }
    if ($Arguments) { $params['Arguments'] = $Arguments }
    if ($PSBoundParameters.ContainsKey('WhatIf')) { $params['WhatIf'] = $PSBoundParameters['WhatIf'] }
    if ($PSBoundParameters.ContainsKey('Confirm')) { $params['Confirm'] = $PSBoundParameters['Confirm'] }

    Invoke-EdtCommand @params
}
