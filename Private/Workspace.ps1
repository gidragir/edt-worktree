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

function Get-EdtWtExtensionNames {
    <# Имена (папки) рабочих расширений проекта из Context.Extensions (пути относительно клона). #>
    [OutputType([string[]])]
    param([Parameter(Mandatory)]$Context)

    return [string[]]@(@($Context.Extensions) | Where-Object { $_ } | ForEach-Object { Split-Path -Leaf $_ })
}

function Get-EdtWtUnusedExtensions {
    <#
      Расширения, найденные в клоне, но не включённые в рабочие (Context.Extensions).
      Возвращает относительные пути (RelPath). Нужна warmup и doctor.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)]$Context)

    $working = @(@($Context.Extensions) | Where-Object { $_ } | ForEach-Object { ($_ -replace '\\', '/').Trim('/') })
    $found = @(Find-EdtWtEdtProjects -RepoPath $Context.RepoPath | Where-Object { $_.Kind -eq 'Extension' })
    return [string[]]@($found | Where-Object { $working -inotcontains $_.RelPath } | ForEach-Object { $_.RelPath })
}

function Assert-EdtWtReferenceFree {
    <#
      Эталон не должен быть занят EDT. Процессы не закрываются: занятый эталон - отказ.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)

    $busy = @(Get-EdtWtWorkspaceProcesses -WorkspaceDir $Context.ReferenceWsDir)
    if ($busy.Count -gt 0) {
        throw "Эталон занят: $(($busy | ForEach-Object { "$($_.Name):$($_.ProcessId)" }) -join ', '). Закройте EDT и повторите."
    }
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
        # Имя расширения -> путь из конфига проекта; иначе имя трактуется как путь от корня worktree.
        $rel = @($Context.Extensions) | Where-Object { (Split-Path -Leaf $_) -ieq $ext } | Select-Object -First 1
        if (-not $rel) { $rel = $ext }
        $candidates += (Join-Path $Context.WorktreePath ($rel -replace '/', '\'))
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
      Каталог-донор настроек IDE: только edt.prefs_source из config.json
      (корень рабочей области или сам каталог .settings). Не задан - $null.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    param([Parameter(Mandatory)]$Context)

    $prefsSource = Get-EdtWtProperty (Get-EdtWtConfig).edt 'prefs_source'
    if (-not $prefsSource) { return $null }

    $c = ($prefsSource -replace '/', '\')
    $direct = if ($c -match '\.settings$') { $c } else { Join-Path $c ".metadata\.plugins\org.eclipse.core.runtime\.settings" }
    if (Test-Path -LiteralPath $direct) { return $direct }
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
        Write-Host "    [skip] Донор настроек IDE не найден (edt.prefs_source в config.json)." -ForegroundColor DarkGray
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
        [switch]$Refresh
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
        Invoke-EdtWorktreeWarmup -ProjectName $Context.ProjectId
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

  open   [проект задача]                Открыть рабочую область и запустить IDE.
         Без аргументов берётся текущий каталог worktree.
         Подключаются конфигурация и рабочие расширения проекта.
         Ключи: -Refresh, -NoGui, -WhatIf, -Yes

  warmup [проект]                       Собрать эталон из клона (на ref_branch) с валидацией.
         Занятый эталон не трогается. Ключи: -WhatIf, -Yes

  add    [проект задача] <расширения>   Подключить расширения к существующей области.
         Имена: cfe_x или относительный путь. Ключи: -Force, -NoGui, -WhatIf, -Yes

  remove [проект] [задача]              Удалить рабочую область и git worktree.
         Ключи: -WhatIf, -Yes

  status [проект]                       Что открыто и какими процессами занято.

  update [проекты]                      Подтянуть ref_branch клона и пересобрать эталоны.
         Для запуска по расписанию: занятые и конфликтные проекты пропускаются.
         Ключи: -SkipGit, -WhatIf, -Yes

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
  edt open my-project TASK-123
  edt open -NoGui                       без запуска IDE
  edt warmup my-project
  edt add cfe_esf
  edt remove TASK-123 -WhatIf
  edt status | Where-Object Locked -eq 'LOCK'

Подробно: Get-Help Invoke-EdtWorktreeOpen -Full
'@
}
