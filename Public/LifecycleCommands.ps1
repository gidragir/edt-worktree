# ==============================================================================
# LifecycleCommands.ps1 - Обновление эталонов по расписанию и самообновление модуля
# ==============================================================================

Set-StrictMode -Version Latest

function Update-EdtWtReference {
    <#
    .SYNOPSIS
        Подтягивает эталонную ветку клонов и пересобирает эталоны проектов.

    .DESCRIPTION
        Предназначена для запуска по расписанию. Для каждого проекта реестра:

          1. проверяет, что эталон не занят EDT (процессы не закрываются);
          2. в клоне <repos_root>\<проект> делает fetch и перемотку вперёд
             (merge --ff-only) ветки ref_branch с remote из git.remote;
          3. собирает эталон (Invoke-EdtWorktreeWarmup).

        Грязный клон, клон на другой ветке, занятый эталон и ошибки сборки не
        останавливают обход: проект получает статус skipped с причиной.

    .PARAMETER Project
        Какие проекты обновлять. По умолчанию - все из конфигурации.

    .PARAMETER SkipGit
        Не трогать git, только пересобрать эталоны из текущего состояния клонов.

    .EXAMPLE
        Update-EdtWtReference -WhatIf

    .EXAMPLE
        Update-EdtWtReference -Project my-project -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [string[]]$Project,

        [switch]$SkipGit
    )

    $cfg = Get-EdtWtConfig

    $knownProjects = if ($cfg.projects) { @($cfg.projects.PSObject.Properties | ForEach-Object { $_.Name }) } else { @() }
    $names = if ($Project) { $Project } else { $knownProjects }
    $remote = Get-EdtWtProperty $cfg.git 'remote' 'origin'
    $started = Get-Date
    $report = @()

    Write-Host "==> Обновление эталонов" -ForegroundColor Green

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
                throw "проект не зарегистрирован (edt project add $name)"
            }

            $refBranch = Get-EdtWtProperty $cfg.projects.$name 'ref_branch' 'pre-prod'
            $repo = Join-Path $cfg.paths.repos_root $name
            if (-not (Test-Path -LiteralPath $repo)) {
                throw "каталог проекта не найден: $repo"
            }

            $ctx = Get-EdtWtContext -Path $repo -ProjectName $name
            Assert-EdtWtReferenceFree -Context $ctx

            if (-not $SkipGit) {
                Write-Host "    [$name] обновление ветки $refBranch в клоне..." -ForegroundColor Cyan
                if ($PSCmdlet.ShouldProcess($repo, "git fetch и перемотка ветки $refBranch ($remote)")) {
                    $git = Update-EdtWtBranch -WorktreePath $repo -Branch $refBranch -Remote $remote
                    if (-not $git.Success) { throw $git.Message }
                    Write-Host "    [$name] $($git.Message)" -ForegroundColor Gray
                    $row.Detail = $git.Message
                }
            }

            $warmupParams = @{ ProjectName = $name }
            if ($PSBoundParameters.ContainsKey('WhatIf')) { $warmupParams['WhatIf'] = $PSBoundParameters['WhatIf'] }
            if ($PSBoundParameters.ContainsKey('Confirm')) { $warmupParams['Confirm'] = $PSBoundParameters['Confirm'] }

            Invoke-EdtWorktreeWarmup @warmupParams
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

function Remove-EdtWtPathEntry {
    <#
      Убирает из значения PATH все записи, равные Entry (Test-EdtWtSamePath: без учёта
      регистра и хвостового слеша). Пустые элементы выбрасываются.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$PathValue,
        [Parameter(Mandatory)][string]$Entry
    )

    $kept = foreach ($part in $PathValue -split ';') {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $same = $false
        try { $same = Test-EdtWtSamePath -A $part -B $Entry } catch { $same = $false }
        if (-not $same) { $part }
    }
    return (@($kept) -join ';')
}

function Get-EdtWtInstallInfo {
    <#
      Раскладка установки: ссылка модуля в Documents\PowerShell\Modules (корень
      переопределяется EDT_MODULES_DIR), каталог установки (цель junction/symlink или
      сам каталог модуля, если это копия), bin и каталог конфигурации.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $modulesDir = if ($env:EDT_MODULES_DIR) {
        $env:EDT_MODULES_DIR
    } else {
        Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules'
    }
    $link = Join-Path $modulesDir 'EdtWorktree'

    $installDir = $null
    $viaLink = $false
    $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    if ($item) {
        $viaLink = $true
        if ($item.LinkType -and $item.Target) { $installDir = @($item.Target)[0] } else { $installDir = $link }
    } else {
        $installDir = $script:EdtWtModuleRoot
    }

    return [PSCustomObject]@{
        ModuleLink = $link
        InstallDir = $installDir
        ViaLink    = $viaLink
        BinDir     = Join-Path $installDir 'bin'
        ConfigDir  = Split-Path -Parent (Get-EdtWtUserConfigPath)
    }
}

function Remove-EdtWtModuleLink {
    <#
      Удаляет ссылку модуля. Для junction/symlink удаляется только сама ссылка
      (нерекурсивное Directory.Delete), цель не затрагивается. Remove-Item -Recurse
      по ссылке не используется: в части версий PowerShell он заходит в цель.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return }
    $isLink = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    if ($isLink) {
        [System.IO.Directory]::Delete($Path)
    } else {
        # Копия модуля: обычный каталог.
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Test-EdtWtDirtyWorkTree {
    <#
      Состояние рабочего дерева git (только чтение): 'clean' (или это не git-каталог),
      'dirty' (есть незафиксированные изменения) или 'unverified' (.git есть, но git
      недоступен или status завершился ошибкой). Проверка закрывается в сторону отказа:
      при неопределённости каталог считается занятым.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath (Join-Path $Path '.git'))) { return 'clean' }
    if (-not (Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue)) { return 'unverified' }
    try {
        $global:LASTEXITCODE = 0
        $out = Invoke-EdtWtGit -C $Path status --porcelain 2>$null
        if ($LASTEXITCODE -ne 0) { return 'unverified' }
    } catch {
        return 'unverified'
    }
    if ($out) { return 'dirty' }
    return 'clean'
}

function Uninstall-EdtWorktree {
    <#
    .SYNOPSIS
        Удаляет установку модуля: ссылку в Modules и запись bin из PATH пользователя.

    .DESCRIPTION
        Сначала печатает список удаляемого, затем (после подтверждения) удаляет ссылку
        модуля и каталог bin из PATH. Конфиг, клоны, worktree и рабочие области не
        трогает. -Purge дополнительно удаляет каталог установки и каталог конфигурации.
        EDT_PATH_SCOPE=Process (для тестов) ограничивает правку PATH процессом.

    .PARAMETER Purge
        Удалить также каталог установки и каталог конфигурации.

    .EXAMPLE
        Uninstall-EdtWorktree -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([switch]$Purge)

    $info = Get-EdtWtInstallInfo
    $processOnly = ($env:EDT_PATH_SCOPE -eq 'Process')

    Write-Host '==> Будет удалено:' -ForegroundColor Cyan
    Write-Host "    ссылка модуля:  $($info.ModuleLink)"
    Write-Host "    запись в PATH:  $($info.BinDir)$(if ($processOnly) { ' (только процесс)' } else { ' (пользователь)' })"
    if ($Purge) {
        Write-Host "    каталог установки: $($info.InstallDir)"
        Write-Host "    каталог конфигурации: $($info.ConfigDir)"
    }
    Write-Host '    Клоны, worktree и рабочие области не затрагиваются.' -ForegroundColor Gray

    if (-not $PSCmdlet.ShouldProcess($info.ModuleLink, 'Удалить установку EdtWorktree')) { return }

    # Решение о каталоге установки принимается до удаления ссылки (для копии каталог и есть ссылка).
    $purgeInstall = $false
    if ($Purge) {
        if (-not $info.ViaLink) {
            Write-Warning "Каталог установки не удалён: ссылки модуля нет, а текущий каталог модуля ($($info.InstallDir)) может быть рабочим клоном. Удалите его вручную."
        } else {
            switch (Test-EdtWtDirtyWorkTree -Path $info.InstallDir) {
                'dirty' { Write-Warning "Каталог установки не удалён: в нём есть незафиксированные изменения git ($($info.InstallDir)). Закоммитьте или уберите их (stash) либо удалите каталог вручную." }
                'unverified' { Write-Warning "Каталог установки не удалён: не удалось проверить состояние git ($($info.InstallDir)). Проверьте каталог и удалите его вручную." }
                default { $purgeInstall = $true }
            }
        }
    }

    if (Get-Item -LiteralPath $info.ModuleLink -Force -ErrorAction SilentlyContinue) {
        Remove-EdtWtModuleLink -Path $info.ModuleLink
    }

    if (-not $processOnly) {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($userPath) {
            $newUser = Remove-EdtWtPathEntry -PathValue $userPath -Entry $info.BinDir
            if ($newUser -ne $userPath) { [Environment]::SetEnvironmentVariable('Path', $newUser, 'User') }
        }
    }
    $env:Path = Remove-EdtWtPathEntry -PathValue $env:Path -Entry $info.BinDir

    if ($Purge) {
        if ($purgeInstall -and (Get-Item -LiteralPath $info.InstallDir -Force -ErrorAction SilentlyContinue)) {
            Remove-EdtWtModuleLink -Path $info.InstallDir
        }
        # Только файлы конфигурации; каталог удаляется, лишь если после этого пуст.
        $cfgFile = Get-EdtWtUserConfigPath
        $cfgDir = $info.ConfigDir
        if ($cfgDir -and (Test-Path -LiteralPath $cfgDir -PathType Container)) {
            $leaf = Split-Path -Leaf $cfgFile
            $owned = Get-ChildItem -LiteralPath $cfgDir -Force -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq $leaf -or $_.Name -like "$leaf.v2.bak*" -or $_.Name -eq "$leaf.tmp" }
            foreach ($f in $owned) { Remove-Item -LiteralPath $f.FullName -Force }
            if (-not (Get-ChildItem -LiteralPath $cfgDir -Force -ErrorAction SilentlyContinue) -and (Split-Path -Parent $cfgDir)) {
                Remove-Item -LiteralPath $cfgDir -Force
            }
        }
    }

    Write-Host '==> EdtWorktree удалён. Откройте новую сессию PowerShell.' -ForegroundColor Green
}

function Update-EdtSelf {
    <#
    .SYNOPSIS
        Обновляет модуль EdtWorktree из исходного Git-репозитория.

    .DESCRIPTION
        Находит клон модуля (с переходом по junction/symlink), выполняет
        git pull --ff-only и перезагружает модуль. Требует git в PATH.

    .EXAMPLE
        Update-EdtSelf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (-not (Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'git не найден в PATH. Установите: winget install Git.Git'
    }

    $mod = Get-Module -Name EdtWorktree
    $modBase = if ($mod) { $mod.ModuleBase } else { $script:EdtWtModuleRoot }

    $targetPath = $modBase
    $item = Get-Item -LiteralPath $modBase -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -and $item.Target) {
        $targetPath = @($item.Target)[0]
    }

    $curr = $targetPath
    $repoDir = $null
    while ($curr) {
        if (Test-Path -LiteralPath (Join-Path $curr '.git')) {
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

    if (-not $PSCmdlet.ShouldProcess($repoDir, 'Обновить модуль из Git-репозитория')) {
        return
    }

    Write-Host "==> Обновление модуля EdtWorktree из: $repoDir" -ForegroundColor Cyan

    $remotes = Invoke-EdtWtGit -C $repoDir remote
    if (-not $remotes) {
        Write-Host '    ! В репозитории не настроен remote (удалённый сервер).' -ForegroundColor Yellow
        Write-Host '    Для включения автообновлений добавьте remote: git remote add origin <url>' -ForegroundColor Yellow
        return
    }

    $out = Invoke-EdtWtGit -C $repoDir pull --ff-only 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    Ошибка git pull: $out" -ForegroundColor Red
        throw "Не удалось обновить репозиторий: $out"
    }
    Write-Host "    $out" -ForegroundColor Gray

    Write-Host '==> Перезагрузка модуля в сессии...' -ForegroundColor Cyan
    $manifest = Join-Path $repoDir 'EdtWorktree.psd1'
    if (Test-Path -LiteralPath $manifest) {
        Import-Module $manifest -Force -DisableNameChecking
    } else {
        Import-Module EdtWorktree -Force -DisableNameChecking
    }

    Write-Host 'Модуль EdtWorktree обновлён.' -ForegroundColor Green
}
