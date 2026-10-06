# ==============================================================================
# Workspace.ps1 - Инициализация, батчи, расширения и настройки рабочих областей
# ==============================================================================

Set-StrictMode -Version Latest

# ------------------------------------------------------------------------------
# 1. Builder батча 1cedtcli
# ------------------------------------------------------------------------------

function New-EdtWtBatch {
    <#
      Builder батча для 1cedtcli. Команды собираются как значение, поэтому их
      можно напечатать под -WhatIf и сравнить в тесте, не запуская EDT.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $batch = [PSCustomObject]@{
        Commands = [System.Collections.Generic.List[string]]::new()
    }

    $batch | Add-Member -MemberType ScriptMethod -Name AddImport -Value {
        param([Parameter(Mandatory)][string]$ProjectDir)
        $this.Commands.Add("import --project `"$($ProjectDir.Replace('\', '/'))`"")
        return $this
    }

    $batch | Add-Member -MemberType ScriptMethod -Name AddExport -Value {
        param(
            [Parameter(Mandatory)][string]$ProjectDir,
            [Parameter(Mandatory)][string]$ConfigurationFiles
        )
        $this.Commands.Add("export --project `"$($ProjectDir.Replace('\', '/'))`" --configuration-files `"$($ConfigurationFiles.Replace('\', '/'))`"")
        return $this
    }

    $batch | Add-Member -MemberType ScriptMethod -Name AddValidate -Value {
        param(
            [Parameter(Mandatory)][string[]]$ProjectNames,
            [Parameter(Mandatory)][string]$ResultFile
        )
        $this.Commands.Add("validate --project-name-list $($ProjectNames -join ',') --file `"$($ResultFile.Replace('\', '/'))`"")
        return $this
    }

    $batch | Add-Member -MemberType ScriptMethod -Name IsEmpty -Value {
        return $this.Commands.Count -eq 0
    }

    $batch | Add-Member -MemberType ScriptMethod -Name ToArray -Value {
        return , $this.Commands.ToArray()
    }

    $batch | Add-Member -MemberType ScriptMethod -Name Print -Value {
        foreach ($c in $this.Commands) {
            Write-Host "       $c" -ForegroundColor DarkGray
        }
    }

    return $batch
}

# ------------------------------------------------------------------------------
# 2. Выбор расширений и определение целей импорта
# ------------------------------------------------------------------------------

function Get-EdtWtChangedExtensions {
    <#
      Расширения, затронутые текущей веткой: незакоммиченные изменения плюс
      diff относительно эталонной ветки.
    #>
    param($Context)

    Push-Location -LiteralPath $Context.WorktreePath
    try {
        $changed = @()
        $st = git status --porcelain 2>$null
        if ($st) { $changed += ($st | ForEach-Object { $_.Substring(3).Trim() }) }
        $df = git diff --name-only "$($Context.ReferenceBranch)...HEAD" 2>$null
        if ($df) { $changed += $df }
    } finally {
        Pop-Location
    }

    $result = @()
    foreach ($f in ($changed | Select-Object -Unique)) {
        if (($f -replace '\\', '/') -match '^src/([^/]+)/') {
            $folder = $matches[1]
            if ($Context.ActiveExtensions -contains $folder -and $result -notcontains $folder) {
                $result += $folder
            }
        }
    }
    return $result
}

function Resolve-EdtWtExtensionList {
    <#
      Единственное место выбора расширений (Strategy). Режимы:
        (не задан) / 'all' -> все active_extensions проекта
        'none'             -> пустой список, открывается одна конфигурация
        'changed'          -> только расширения, затронутые веткой относительно
                               эталонной ветки (git status + git diff)
        иначе              -> список как передан
    #>
    param(
        $Context,
        [string[]]$Extensions
    )

    if (-not $Extensions -or $Extensions.Count -eq 0) { return @($Context.ActiveExtensions) }

    if ($Extensions.Count -eq 1) {
        switch ($Extensions[0].ToLower()) {
            'all' { return @($Context.ActiveExtensions) }
            'none' { return @() }
            'changed' { return @(Get-EdtWtChangedExtensions -Context $Context) }
        }
    }

    if ($Extensions.Count -eq 1 -and $Context.ActiveExtensions -notcontains $Extensions[0]) {
        Write-Warning "Расширение '$($Extensions[0])' не указано в active_extensions проекта. Режимы: all, none, changed."
    }

    return @($Extensions)
}

function Get-EdtWtImportTargets {
    <#
      Каталоги проектов, которые нужно импортировать в рабочую область.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Extensions,
        [switch]$IncludeConfiguration,
        [string]$WorkspaceDir
    )

    $ws = if ($WorkspaceDir) { $WorkspaceDir } else { $Context.WorkspaceDir }
    $existing = @(Get-EdtWtWorkspaceProjectNames -WorkspaceDir $ws)

    $candidates = @()
    if ($IncludeConfiguration) {
        $candidates += (Join-Path $Context.WorktreePath $Context.CfProject)
    }
    foreach ($ext in $Extensions) {
        $candidates += (Join-Path $Context.WorktreePath "src\$ext")
    }

    $targets = @()
    $skipped = @()

    foreach ($dir in $candidates) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir '.project'))) {
            Write-Host "    [skip] Не EDT-проект или каталог отсутствует: $dir" -ForegroundColor Yellow
            $skipped += $dir
            continue
        }

        $name = Get-EdtWtEclipseProjectName -ProjectDir $dir
        if ($existing -contains $name) {
            Write-Host "    [skip] Проект '$name' уже в рабочей области." -ForegroundColor DarkGray
            $skipped += $dir
            continue
        }

        $targets += $dir
    }

    return [PSCustomObject]@{
        Targets  = $targets
        Skipped  = $skipped
        Existing = $existing
    }
}

# ------------------------------------------------------------------------------
# 3. Настройки IDE и актуальность рабочей области
# ------------------------------------------------------------------------------

function Get-EdtWtPrefsSource {
    <#
      Каталог-донор настроек. Приоритет:
        1. defaults.edt_prefs_source из projects.json
        2. D:\workspaces\full\<проект> — обычная (не worktree) рабочая область проекта
    #>
    param([Parameter(Mandatory)]$Context)

    $settingsLeaf = ".metadata\.plugins\org.eclipse.core.runtime\.settings"
    $candidates = @()

    $cfg = (Get-EdtWtSettings).Config
    $prefsSource = Get-EdtWtProperty (Get-EdtWtProperty $cfg 'defaults') 'edt_prefs_source'
    if ($prefsSource) {
        $candidates += ($prefsSource -replace '/', '\')
    }
    $candidates += (Join-Path "D:\workspaces\full" $Context.ProjectId)

    foreach ($c in $candidates) {
        if (-not $c) { continue }
        $direct = if ($c -match '\.settings$') { $c } else { Join-Path $c $settingsLeaf }
        if (Test-Path -LiteralPath $direct) { return $direct }
    }
    return $null
}

function Copy-EdtWtPreferences {
    <#
      Переносит пользовательские настройки IDE в рабочую область.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$WorkspaceDir,
        [string]$SourceDir,
        [switch]$Force
    )

    $src = if ($SourceDir) {
        if ($SourceDir -match '\.settings$') { $SourceDir } else { Join-Path $SourceDir ".metadata\.plugins\org.eclipse.core.runtime\.settings" }
    } else {
        Get-EdtWtPrefsSource -Context $Context
    }

    if (-not $src -or -not (Test-Path -LiteralPath $src)) {
        Write-Host "    [skip] Донор настроек IDE не найден (defaults.edt_prefs_source в projects.json)." -ForegroundColor DarkGray
        return @()
    }

    $dst = Join-Path $WorkspaceDir ".metadata\.plugins\org.eclipse.core.runtime\.settings"
    New-Item -ItemType Directory -Force -Path $dst | Out-Null

    $copied = @()
    foreach ($name in $script:EdtWtPortablePrefs) {
        $from = Join-Path $src $name
        if (-not (Test-Path -LiteralPath $from)) { continue }
        $to = Join-Path $dst $name
        if ((Test-Path -LiteralPath $to) -and -not $Force) { continue }
        Copy-Item -LiteralPath $from -Destination $to -Force
        $copied += $name
    }

    if ($copied.Count -gt 0) {
        Write-Host "    Настройки IDE перенесены из $src ($($copied.Count) файлов)." -ForegroundColor DarkGray
    } else {
        Write-Host "    Настройки IDE уже на месте (перенос не требуется)." -ForegroundColor DarkGray
    }
    return $copied
}

function Test-EdtWtWorkspaceFreshness {
    <#
      Сравнивает состав рабочей области с эталоном.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]$Context,
        [switch]$Quiet
    )

    $refProjects = @(Get-EdtWtWorkspaceProjectNames -WorkspaceDir $Context.ReferenceWsDir)
    $wsProjects = @(Get-EdtWtWorkspaceProjectNames -WorkspaceDir $Context.WorkspaceDir)
    $missing = @($refProjects | Where-Object { $wsProjects -notcontains $_ })

    if ($missing.Count -gt 0 -and -not $Quiet) {
        Write-Host "    [warn] Рабочая область отстала от эталона: нет проектов $($missing -join ', ')" -ForegroundColor Yellow
        Write-Host "           Быстрее пересобрать её из эталона: wt-open <проект> <задача> -Refresh" -ForegroundColor Yellow
    }

    return , $missing
}

# ------------------------------------------------------------------------------
# 4. Инициализация и справка
# ------------------------------------------------------------------------------

function Initialize-EdtWtWorkspace {
    <#
      Готовит рабочую область к синхронизации: при необходимости пересоздаёт её
      и клонирует из эталона.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]$Context,
        [switch]$Refresh,
        [string]$MaxHeap
    )

    if ($Refresh -and (Test-Path -LiteralPath $Context.WorkspaceDir)) {
        if ($PSCmdlet.ShouldProcess($Context.WorkspaceDir, 'Удалить рабочую область и склонировать заново из эталона')) {
            Write-Host "    Пересоздание рабочей области из эталона (-Refresh)..." -ForegroundColor Yellow
            Stop-EdtWtProcesses -WorkspaceDir $Context.WorkspaceDir
            Remove-Item -LiteralPath $Context.WorkspaceDir -Recurse -Force
        }
    }

    if (Test-Path -LiteralPath $Context.WorkspaceDir) {
        Write-Host "    Рабочая область уже существует — только синхронизация." -ForegroundColor Gray
        return $true
    }

    if (-not (Test-Path -LiteralPath $Context.ReferenceWsDir)) {
        Write-Host "    Эталон отсутствует — запуск прогрева..." -ForegroundColor Yellow
        Invoke-EdtWorktreeWarmup -ProjectName $Context.ProjectId -MaxHeap $MaxHeap
    }

    if (-not $PSCmdlet.ShouldProcess($Context.WorkspaceDir, "Склонировать эталон $($Context.ReferenceWsDir)")) {
        return $false
    }

    Write-Host "==> Клонирование эталона (robocopy)..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $Context.ProjectWsRoot | Out-Null
    & robocopy $Context.ReferenceWsDir $Context.WorkspaceDir /E /XF .lock /NFL /NDL /NJH /NJS /NC /NS /MT:8 | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ge 8) {
        throw "robocopy завершился с ошибкой (ExitCode $rc). Убедитесь, что эталон не занят работающим EDT."
    }
    Write-Host "    ✓ Клонирование завершено (robocopy rc=$rc)." -ForegroundColor Green
    return $true
}

function Show-EdtWtUsage {
    <#
      Краткая справка команды edt.
    #>
    [CmdletBinding()]
    param()

    Write-Host @'
edt <подкоманда> [аргументы] [ключи]

  open   [проект задача] [расширения]   Открыть рабочую область и запустить IDE.
         Без аргументов берётся текущий каталог worktree.
         Расширения: all (по умолчанию), none, changed либо список через запятую.
         Ключи: -Refresh, -NoGui, -GuiMaxHeap 12g, -MaxHeap 12g, -WhatIf, -Yes

  warmup [проект] [расширения]          Собрать эталон, из которого клонируются области.
         Ключи: -Force, -Validate, -MaxHeap 16g, -WhatIf, -Yes

  add    [проект задача] <расширения>   Подключить расширения к существующей области.
         Ключи: -Force, -NoGui, -MaxHeap 12g, -WhatIf, -Yes

  remove [проект] [задача]              Удалить рабочую область и git worktree.
         Ключи: -WhatIf, -Yes

  status [проект]                       Что открыто и какими процессами занято.

  update [проекты]                      Подтянуть pre-prod и пересобрать эталоны.
         Для запуска по расписанию: занятые и конфликтные проекты пропускаются.
         Ключи: -Validate, -SkipGit, -MaxHeap 16g, -WhatIf, -Yes

  init   [cf_project]                   Создать .edt-worktree.json в корне текущего репозитория.

  config [get | set | init]             Просмотр, изменение или мастер настройки окружения.

  self-update                           Обновить модуль EdtWorktree из исходного Git-репозитория.

  vr     <аргументы vrunner>            Запустить vrunner в текущем worktree.
         Вызывать из каталога worktree. Аргументы уходят в vrunner как есть,
         код возврата vrunner сохраняется.
         Настройки базы: autumn-properties.json в корне worktree (не меняется).
         Рабочая область EDT этого worktree передаётся через VRUNNER_EDT_WORKSPACE,
         VRUNNER_EDT_PATH, VRUNNER_EDT_VMARGS, VRUNNER_EDT_TIMEOUT; уже заданные
         вами VRUNNER_EDT_* не перезаписываются.
         cf load и cfe load идут с --increment (инкрементальная загрузка).
         Ключ: -Full - полная загрузка (первая загрузка в пустую базу, сомнения
         в рассинхроне); в vrunner не передаётся.
         Нужна область: если её нет, выполните edt open -NoGui.

Примеры:
  edt vr validate edt
  edt vr test yaxunit --modules МойМодуль
  edt vr cf load src/cf                 инкрементально
  edt vr cf load src/cf -Full           полностью
  edt open                            открыть текущий worktree
  edt open my-project TASK-123 -GuiMaxHeap 12g
  edt open changed -NoGui               только затронутые веткой расширения, без IDE
  edt warmup my-project -Force -Validate
  edt add cfe_esf
  edt remove TASK-123 -WhatIf
  edt status | Where-Object Locked -eq 'LOCK'

Подробно: Get-Help Invoke-EdtWorktreeOpen -Full
'@
}
