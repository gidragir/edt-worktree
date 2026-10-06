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
        Определяет проект по git-репозиторию и реестру projects.json, вычисляет
        каталоги рабочей области и эталона, путь к 1cedtcli и GUI, аргументы JVM
        и список активных расширений. Используется всеми операциями модуля.

    .PARAMETER Path
        Каталог внутри worktree. По умолчанию - текущий.

    .PARAMETER ProjectName
        Явное имя проекта, если автоопределение по репозиторию не срабатывает.

    .EXAMPLE
        Get-EdtWtContext | Select-Object ProjectId, WorkspaceDir, ActiveExtensions
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$Path,
        [string]$ProjectName
    )

    $settings = Get-EdtWtSettings
    $cfg = $settings.Config

    $startPath = if ($Path) { $Path } else { (Get-Location).Path }
    Push-Location -LiteralPath $startPath
    try {
        $topLevel = (git rev-parse --show-toplevel 2>$null)
        if (-not $topLevel) { throw "Каталог '$startPath' не находится внутри git-репозитория." }
        $topLevel = ($topLevel -replace '/', '\')

        $gitCommonDir = (git rev-parse --git-common-dir 2>$null)
        if (-not $gitCommonDir) { throw "Не удалось определить git-common-dir для '$startPath'." }
        if (-not [System.IO.Path]::IsPathRooted($gitCommonDir)) {
            $gitCommonDir = Join-Path $topLevel $gitCommonDir
        }
        $gitCommonDir = ($gitCommonDir -replace '/', '\')

        $branch = (git rev-parse --abbrev-ref HEAD 2>$null)

        $projectId = $null
        if ($ProjectName) {
            $projectId = $ProjectName
        } elseif (($null -ne $cfg.PSObject.Properties['ActiveProjectId']) -and $cfg.ActiveProjectId) {
            $projectId = $cfg.ActiveProjectId
        } else {
            $projectId = Get-EdtWtProjectIdFromRepo -GitCommonDir $gitCommonDir -Projects $cfg.projects
        }
    } finally {
        Pop-Location
    }

    if (-not $projectId) {
        throw "Проект не найден в конфигурации (.edt-worktree.json или реестре проектов). Репозиторий: $topLevel. Укажите -ProjectName явно."
    }
    if ($null -eq $cfg.projects.PSObject.Properties[$projectId]) {
        throw "Проект '$projectId' отсутствует в конфигурации (.edt-worktree.json или реестре проектов)."
    }

    $projDef = $cfg.projects.$projectId
    $defaults = $cfg.defaults

    $worktreeId = if ($branch -and $branch -ne 'HEAD') { ConvertTo-EdtWtSafeName $branch } else { ConvertTo-EdtWtSafeName (Split-Path -Leaf $topLevel) }

    $edtCli = Get-EdtWtProperty $projDef '1cedtcli' (Get-EdtWtProperty $defaults '1cedtcli')
    if (-not $edtCli) {
        $found = Find-EdtWtCli
        if ($found -and $found.Count -gt 0) { $edtCli = $found[0].Path }
    }
    if (-not $edtCli) {
        throw "Путь к 1cedtcli не настроен. Запустите 'Initialize-EdtConfig' или укажите 1cedtcli в конфигурации."
    }
    $edtCli = ($edtCli -replace '/', '\')
    $edtGui = Join-Path (Split-Path -Parent $edtCli) "1cedt.exe"

    $jvm = Get-EdtWtProperty $defaults 'jvm'
    $jvmArgs = "-Xmx$(Get-EdtWtProperty $jvm 'max_heap' '8g') -Xms$(Get-EdtWtProperty $jvm 'min_heap' '2g') $(Get-EdtWtProperty $jvm 'extra_args' '')"

    $projectRootWs = Join-Path $settings.RootDir $projectId

    return [PSCustomObject]@{
        ProjectId       = $projectId
        WorktreeId      = $worktreeId
        Branch          = $branch
        WorktreePath    = $topLevel
        GitCommonDir    = $gitCommonDir
        ProjectWsRoot   = $projectRootWs
        WorkspaceDir    = Join-Path $projectRootWs $worktreeId
        ReferenceWsDir  = Join-Path $projectRootWs "_reference_preprod"
        ReferenceBranch = $settings.ReferenceBranch
        CfProject       = Get-EdtWtProperty $projDef 'cf_project' 'src/cf'
        ActiveExtensions= @(Get-EdtWtProperty $projDef 'active_extensions' @())
        EdtCliPath      = $edtCli
        EdtGuiPath      = $edtGui
        JvmArgs         = $jvmArgs
        TimeoutSec      = Get-EdtWtProperty (Get-EdtWtProperty $defaults 'timeouts') 'export_batch_sec' 7200
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

    $settings = Get-EdtWtSettings
    $cfg = $settings.Config
    $root = $settings.RootDir

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
        try { $lines = git worktree list --porcelain 2>$null } finally { Pop-Location }
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
        _reference_preprod, поэтому индексы не строятся заново. Затем проекты
        перепривязываются на текущий worktree, недостающие импортируются
        headless-вызовом 1cedtcli, переносятся пользовательские настройки IDE
        и запускается сам EDT.

    .PARAMETER Extensions
        Какие расширения подключить: 'all' (по умолчанию - все active_extensions
        проекта), 'none' - только конфигурация, 'changed' - затронутые веткой
        относительно эталонной ветки, либо явный список имён.

    .PARAMETER MaxHeap
        Куча headless-процесса 1cedtcli, например 12g.

    .PARAMETER GuiMaxHeap
        Куча самой IDE, например 12g.

    .PARAMETER NoGui
        Выполнить синхронизацию, но не запускать IDE.

    .PARAMETER Refresh
        Пересобрать рабочую область из текущего эталона.

    .EXAMPLE
        Invoke-EdtWorktreeOpen -GuiMaxHeap 12g

    .EXAMPLE
        Invoke-EdtWorktreeOpen -Refresh -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Position = 0)]
        [string[]]$Extensions,

        [ValidatePattern('^\d+[gGmM]$')]
        [string]$MaxHeap,

        [ValidatePattern('^\d+[gGmM]$')]
        [string]$GuiMaxHeap,

        [switch]$NoGui,

        [switch]$Refresh
    )

    $ctx = Get-EdtWtContext
    if ($null -eq $ctx) { return }

    Write-Host "==> Открытие рабочей области EDT" -ForegroundColor Green
    Write-Host "    Проект:   $($ctx.ProjectId)" -ForegroundColor Cyan
    Write-Host "    Worktree: $($ctx.WorktreeId) ($($ctx.WorktreePath))" -ForegroundColor Cyan
    Write-Host "    WS:       $($ctx.WorkspaceDir)" -ForegroundColor Cyan

    $initParams = @{
        Context = $ctx
        Refresh = $Refresh
    }
    if ($MaxHeap) { $initParams['MaxHeap'] = $MaxHeap }
    if (-not (Initialize-EdtWtWorkspace @initParams)) {
        return
    }

    if ($PSCmdlet.ShouldProcess($ctx.WorkspaceDir, 'Перепривязать проекты на текущий worktree')) {
        Write-Host "==> Перепривязка проектов на текущий worktree..." -ForegroundColor Cyan
        Repair-EdtWtWorkspaceLocations -WorkspaceDir $ctx.WorkspaceDir -WorktreePath $ctx.WorktreePath -ReferenceWsDir $ctx.ReferenceWsDir | Out-Null
    }

    Test-EdtWtWorkspaceFreshness -Context $ctx | Out-Null

    $extList = @(Resolve-EdtWtExtensionList -Context $ctx -Extensions $Extensions)
    Write-Host "    Расширения: $(if ($extList.Count) { $extList -join ', ' } else { '<нет>' })" -ForegroundColor Cyan

    $plan = Get-EdtWtImportTargets -Context $ctx -Extensions $extList -IncludeConfiguration
    $batch = New-EdtWtBatch
    foreach ($t in $plan.Targets) { $batch.AddImport($t) | Out-Null }

    if ($batch.IsEmpty()) {
        Write-Host "==> Импорт не требуется — все проекты уже в рабочей области." -ForegroundColor Cyan
    } elseif ($PSCmdlet.ShouldProcess($ctx.WorkspaceDir, "Импортировать проектов: $($batch.Commands.Count)")) {
        Write-Host "==> Headless-синхронизация рабочей области..." -ForegroundColor Cyan
        Invoke-EdtWtCli -Context $ctx -WorkspaceDir $ctx.WorkspaceDir -Commands $batch.ToArray() -BatchName "sync_batch.txt" -MaxHeap $MaxHeap
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

    $guiParams = @{
        Context = $ctx
    }
    if ($GuiMaxHeap) { $guiParams['GuiMaxHeap'] = $GuiMaxHeap }
    Start-EdtWtGui @guiParams
}

function Invoke-EdtWorktreeWarmup {
    <#
    .SYNOPSIS
        Прогревает эталонную рабочую область _reference_preprod.

    .DESCRIPTION
        Импортирует конфигурацию и расширения из worktree эталонной ветки в
        отдельную рабочую область. Из неё затем клонируются области задач, что
        избавляет от повторного построения индексов.

    .PARAMETER ProjectName
        Проект из projects.json. По умолчанию определяется по текущему репозиторию.

    .PARAMETER Extensions
        Что импортировать: 'all' (по умолчанию), 'none' или явный список.

    .PARAMETER MaxHeap
        Куча headless-процесса 1cedtcli, например 16g.

    .PARAMETER Force
        Пересобрать существующий эталон: остановить процессы и удалить его.

    .PARAMETER Validate
        Дополнительно прогнать проверки и построить derived-данные.

    .EXAMPLE
        Invoke-EdtWorktreeWarmup -Force -Validate
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Position = 0)]
        [string]$ProjectName,

        [string[]]$Extensions,

        [ValidatePattern('^\d+[gGmM]$')]
        [string]$MaxHeap,

        [switch]$Force,

        [switch]$Validate
    )

    $ctx = Get-EdtWtContext -ProjectName $ProjectName
    if ($null -eq $ctx) { return }

    Write-Host "==> Прогрев эталона: $($ctx.ProjectId)" -ForegroundColor Green
    Write-Host "    Reference WS: $($ctx.ReferenceWsDir)" -ForegroundColor Cyan

    if ((Test-Path -LiteralPath $ctx.ReferenceWsDir) -and -not $Force) {
        Write-Host "    Эталон уже существует. Пропуск (используйте -Force для пересборки)." -ForegroundColor Yellow
        return
    }

    $refPath = Get-EdtWtWorktreePathForBranch -RepoPath $ctx.WorktreePath -Branch $ctx.ReferenceBranch
    if (-not $refPath) {
        throw "Не найден рабочий каталог (worktree) для ветки '$($ctx.ReferenceBranch)'. Создайте его: git worktree add <path> $($ctx.ReferenceBranch)"
    }
    if (-not (Test-Path -LiteralPath $refPath)) {
        throw "Worktree ветки '$($ctx.ReferenceBranch)' зарегистрирован, но каталог отсутствует: $refPath"
    }
    Write-Host "    Источник:     $refPath [$($ctx.ReferenceBranch)]" -ForegroundColor Cyan

    if ($Force -and (Test-Path -LiteralPath $ctx.ReferenceWsDir)) {
        if (-not $PSCmdlet.ShouldProcess($ctx.ReferenceWsDir, 'Удалить прогретый эталон и собрать заново')) {
            return
        }
        Write-Host "    Удаление существующего эталона..." -ForegroundColor Yellow
        Stop-EdtWtProcesses -WorkspaceDir $ctx.ReferenceWsDir
        Remove-Item -LiteralPath $ctx.ReferenceWsDir -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $ctx.ReferenceWsDir | Out-Null

    $extList = Resolve-EdtWtExtensionList -Context $ctx -Extensions $Extensions

    $batch = New-EdtWtBatch
    $batch.AddImport((Join-Path $refPath $ctx.CfProject)) | Out-Null
    $imported = @()
    foreach ($ext in $extList) {
        $extAbs = Join-Path $refPath "src\$ext"
        if (Test-Path -LiteralPath (Join-Path $extAbs ".project")) {
            $batch.AddImport($extAbs) | Out-Null
            $imported += $ext
        } else {
            Write-Host "    [skip] Не EDT-проект или каталог отсутствует: src\$ext" -ForegroundColor Yellow
        }
    }
    Write-Host "    Расширения:   $(if ($imported.Count) { $imported -join ', ' } else { '<нет>' })" -ForegroundColor Cyan

    if ($Validate) {
        $projectNames = @((Get-EdtWtEclipseProjectName -ProjectDir (Join-Path $refPath $ctx.CfProject)))
        foreach ($ext in $imported) {
            $projectNames += Get-EdtWtEclipseProjectName -ProjectDir (Join-Path $refPath "src\$ext")
        }
        $tsv = Join-Path $ctx.ReferenceWsDir "warmup_validation.tsv"
        if (Test-Path -LiteralPath $tsv) { Remove-Item -LiteralPath $tsv -Force }
        $batch.AddValidate($projectNames, $tsv) | Out-Null
        Write-Host "    Прогрев проверок: включён (-Validate), отчёт: $tsv" -ForegroundColor Cyan
        $ctx.JvmArgs = ($ctx.JvmArgs -replace '\s*-DisableProjectChecks=true', '')
    }

    if (-not $PSCmdlet.ShouldProcess($ctx.ReferenceWsDir, "Импортировать проектов: $($batch.Commands.Count)")) {
        return
    }

    Invoke-EdtWtCli -Context $ctx -WorkspaceDir $ctx.ReferenceWsDir -Commands $batch.ToArray() -BatchName "warmup_batch.txt" -MaxHeap $MaxHeap
    Copy-EdtWtPreferences -Context $ctx -WorkspaceDir $ctx.ReferenceWsDir | Out-Null

    Write-Host "✓ Эталон прогрет: $($ctx.ReferenceWsDir)" -ForegroundColor Green
}

function Invoke-EdtWorktreeAdd {
    <#
    .SYNOPSIS
        Доимпортирует расширения в уже существующую рабочую область.

    .DESCRIPTION
        Рабочая область блокируется запущенным EDT (.metadata/.lock), поэтому
        IDE на время headless-импорта закрывается и по завершении поднимается
        обратно.

    .PARAMETER Extensions
        Что импортировать: 'all', 'changed', 'none' либо явный список имён.

    .PARAMETER MaxHeap
        Куча headless-процесса 1cedtcli, например 12g.

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

        [ValidatePattern('^\d+[gGmM]$')]
        [string]$MaxHeap,

        [switch]$NoGui,

        [switch]$Force
    )

    $ctx = Get-EdtWtContext
    if ($null -eq $ctx) { return }

    if (-not (Test-Path -LiteralPath $ctx.WorkspaceDir)) {
        throw "Рабочая область не найдена: $($ctx.WorkspaceDir). Сначала выполните edt-wt-open."
    }

    $extList = Resolve-EdtWtExtensionList -Context $ctx -Extensions $Extensions

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
    Invoke-EdtWtCli -Context $ctx -WorkspaceDir $ctx.WorkspaceDir -Commands $batch.ToArray() -BatchName "add_batch.txt" -MaxHeap $MaxHeap
    Write-Host "    ✓ Импортировано: $(($plan.Targets | ForEach-Object { Split-Path -Leaf $_ }) -join ', ')" -ForegroundColor Green

    if ($NoGui) {
        Write-Host "✓ Готово (GUI не запускается: -NoGui)." -ForegroundColor Green
        return
    }
    if (-not $wasRunning) {
        Write-Host "✓ Готово. EDT не был запущен — стартуйте его через edt-wt-open." -ForegroundColor Green
        return
    }

    Write-Host "==> Возврат 1C:EDT..." -ForegroundColor Cyan
    Start-Process -FilePath $ctx.EdtGuiPath -ArgumentList "-data `"$($ctx.WorkspaceDir)`""
    Write-Host "✓ 1C:EDT перезапущен на рабочей области $($ctx.WorkspaceDir)" -ForegroundColor Green
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

    if ($targetId -eq '_reference_preprod') {
        throw "Эталонная рабочая область '_reference_preprod' не удаляется этой командой. Используйте 'edt-wt-warmup -Force' для пересборки."
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
            git worktree remove $wtPath --force
            git worktree prune
        } finally {
            Pop-Location
        }
        Write-Host "    ✓ git worktree удалён." -ForegroundColor Green
    } else {
        Write-Host "    Каталог git worktree не найден — выполняется только prune." -ForegroundColor Gray
        Push-Location -LiteralPath $ctx.GitCommonDir
        try { git worktree prune } finally { Pop-Location }
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
