# ==============================================================================
# LifecycleCommands.ps1 - Обновление эталонов по расписанию и самообновление модуля
# ==============================================================================

Set-StrictMode -Version Latest

function Update-EdtWtReference {
    <#
    .SYNOPSIS
        Подтягивает эталонную ветку и пересобирает эталоны проектов.

    .DESCRIPTION
        Предназначена для запуска по расписанию. Для каждого проекта реестра:

          1. находит worktree эталонной ветки (pre-prod);
          2. делает fetch и перемотку вперёд (merge --ff-only);
          3. пересобирает эталонную рабочую область.

    .PARAMETER Project
        Какие проекты обновлять. По умолчанию - все из projects.json.

    .PARAMETER Validate
        Прогревать ещё и проверки: дольше, зато первый запуск IDE быстрее.

    .PARAMETER SkipGit
        Не трогать git, только пересобрать эталоны из текущего состояния веток.

    .EXAMPLE
        Update-EdtWtReference -WhatIf

    .EXAMPLE
        Update-EdtWtReference -Validate -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [string[]]$Project,

        [switch]$Validate,

        [switch]$SkipGit,

        [ValidatePattern('^\d+[gGmM]$')]
        [string]$MaxHeap
    )

    $settings = Get-EdtWtSettings
    $cfg = $settings.Config
    $refBranch = $settings.ReferenceBranch

    $knownProjects = if ($cfg.projects) { @($cfg.projects.PSObject.Properties | ForEach-Object { $_.Name }) } else { @() }
    $names = if ($Project) { $Project } else { $knownProjects }
    $started = Get-Date
    $report = @()

    Write-Host "==> Обновление эталонов (ветка $refBranch)" -ForegroundColor Green

    foreach ($name in $names) {
        $row = [PSCustomObject]@{
            Project = $name
            Status  = 'skipped'
            Detail  = ''
            Seconds = 0
        }
        $stepStarted = Get-Date

        try {
            if ($name -notin $knownProjects) {
                throw "проекта нет в projects.json"
            }

            $repo = Join-Path $script:EdtWtProjectsRoot $name
            if (-not (Test-Path -LiteralPath $repo)) {
                throw "каталог проекта не найден: $repo"
            }

            $ctx = Get-EdtWtContext -Path $repo -ProjectName $name
            $refPath = Get-EdtWtWorktreePathForBranch -RepoPath $repo -Branch $refBranch
            if (-not $refPath -or -not (Test-Path -LiteralPath $refPath)) {
                throw "нет рабочего каталога ветки '$refBranch'"
            }

            $busy = @(Get-EdtWtWorkspaceProcesses -WorkspaceDir $ctx.ReferenceWsDir)
            if ($busy.Count -gt 0) {
                throw "эталон занят процессами: $(($busy | ForEach-Object { $_.Name }) -join ', ')"
            }

            if (-not $SkipGit) {
                Write-Host "    [$name] обновление ветки $refBranch..." -ForegroundColor Cyan
                if ($PSCmdlet.ShouldProcess($refPath, "git fetch и перемотка ветки $refBranch")) {
                    $git = Update-EdtWtBranch -WorktreePath $refPath -Branch $refBranch
                    if (-not $git.Success) { throw $git.Message }
                    Write-Host "    [$name] $($git.Message)" -ForegroundColor Gray
                    $row.Detail = $git.Message
                }
            }

            $warmupParams = @{
                ProjectName = $name
                Force       = $true
                Validate    = $Validate
            }
            if ($MaxHeap) { $warmupParams['MaxHeap'] = $MaxHeap }
            if ($PSBoundParameters.ContainsKey('WhatIf')) { $warmupParams['WhatIf'] = $PSBoundParameters['WhatIf'] }
            if ($PSBoundParameters.ContainsKey('Confirm')) { $warmupParams['Confirm'] = $PSBoundParameters['Confirm'] }

            Invoke-EdtWtInLocation -Path $repo -Action {
                Invoke-EdtWtSafeWarmup -Context $ctx -WarmupParams $warmupParams
            }
            $row.Status = 'updated'
        } catch {
            $row.Status = 'skipped'
            $row.Detail = $_.Exception.Message
            Write-Host "    [$name] пропуск: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        $row.Seconds = [int]((Get-Date) - $stepStarted).TotalSeconds
        $report += $row
    }

    $total = [int]((Get-Date) - $started).TotalMinutes
    $ok = @($report | Where-Object Status -eq 'updated').Count
    Write-Host "==> Готово за $total мин: обновлено $ok из $($report.Count)" -ForegroundColor Green

    return $report
}

function Update-EdtSelf {
    <#
    .SYNOPSIS
        Обновляет модуль EdtWorktree из исходного Git-репозитория.

    .DESCRIPTION
        Находит корневой Git-репозиторий модуля (включая переход по символической ссылке),
        выполняет git pull --ff-only и перезагружает модуль в текущей сессии.

    .EXAMPLE
        Update-EdtSelf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    # 1. Поиск репозитория модуля
    $mod = Get-Module -Name EdtWorktree
    $modBase = if ($mod) { $mod.ModuleBase } else { $PSScriptRoot }

    $targetPath = $modBase
    $item = Get-Item -LiteralPath $modBase -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType) {
        $targetPath = $item.Target
    }

    $curr = $targetPath
    $repoDir = $null
    while ($curr) {
        if (Test-Path -LiteralPath (Join-Path $curr ".git")) {
            $repoDir = $curr
            break
        }
        $parent = Split-Path -Parent $curr
        if (-not $parent -or $parent -eq $curr) { break }
        $curr = $parent
    }

    if (-not $repoDir) {
        throw "Не удалось найти Git-репозиторий для модуля в '$targetPath'. Убедитесь, что модуль установлен из git-репозитория."
    }

    if (-not $PSCmdlet.ShouldProcess($repoDir, "Обновить модуль из Git-репозитория")) {
        return
    }

    Write-Host "==> Обновление модуля EdtWorktree из: $repoDir" -ForegroundColor Cyan

    $gitCmd = Get-Command "git" -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        $commonGitPaths = @(
            (Join-Path $env:ProgramFiles "Git\cmd\git.exe"),
            (Join-Path $env:LocalAppData "Programs\Git\cmd\git.exe")
        )
        foreach ($gp in $commonGitPaths) {
            if (Test-Path -LiteralPath $gp) {
                $gitCmd = [PSCustomObject]@{ Source = $gp }
                break
            }
        }
    }
    if (-not $gitCmd) {
        throw "Команда 'git' не найдена в PATH."
    }

    $remotes = & $gitCmd.Source -C $repoDir remote
    if (-not $remotes) {
        Write-Host "    ! В репозитории не настроен remote (удаленный сервер)." -ForegroundColor Yellow
        Write-Host "    Для включения автообновлений добавьте remote: git remote add origin <url>" -ForegroundColor Yellow
        return
    }

    $out = & $gitCmd.Source -C $repoDir pull --ff-only 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    ✗ Ошибка git pull:" -ForegroundColor Red
        Write-Host "    $out" -ForegroundColor Red
        throw "Не удалось обновить репозиторий: $out"
    }

    Write-Host "    $out" -ForegroundColor Gray

    Write-Host "==> Перезагрузка модуля в сессии..." -ForegroundColor Cyan
    $manifest = Join-Path $repoDir "EdtWorktree.psd1"
    if (Test-Path -LiteralPath $manifest) {
        Import-Module $manifest -Force -DisableNameChecking
    } else {
        Import-Module EdtWorktree -Force -DisableNameChecking
    }

    Write-Host "✓ Модуль EdtWorktree успешно обновлен!" -ForegroundColor Green
}
