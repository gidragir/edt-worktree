# ==============================================================================
# GitWorktree.ps1 - Управление git worktree, ветками и разрешением целевых путей
# ==============================================================================

Set-StrictMode -Version Latest

# ------------------------------------------------------------------------------
# 1. Санитайзинг и форматирование имен
# ------------------------------------------------------------------------------

function ConvertTo-EdtWtSafeName {
    param([Parameter(Mandatory)][string]$Name)
    $sanitized = $Name
    foreach ($ch in @('/', '\', ':', '*', '?', '"', '<', '>', '|')) {
        $sanitized = $sanitized.Replace($ch, '-')
    }
    return $sanitized.Trim('-')
}

function ConvertTo-EdtWtTaskFolder {
    <#
      Короткое имя задачи (TASK-123) приводится к имени каталога и рабочей
      области (feature-TASK-123). Полное имя остаётся как есть.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Task)

    if ($Task.StartsWith('feature-')) { return $Task }
    return "feature-$Task"
}

# ------------------------------------------------------------------------------
# 2. Определение путей и переходов по каталогам
# ------------------------------------------------------------------------------

function Get-EdtWtWorktreePathForBranch {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$Branch
    )
    Push-Location -LiteralPath $RepoPath
    try {
        $lines = git worktree list --porcelain 2>$null
    } finally {
        Pop-Location
    }
    if (-not $lines) { return $null }

    $current = $null
    foreach ($line in $lines) {
        if ($line -match '^worktree\s+(.+)$') {
            $current = ($matches[1] -replace '/', '\')
        } elseif ($line -match '^branch\s+refs/heads/(.+)$') {
            if ($matches[1] -eq $Branch) { return $current }
        }
    }
    return $null
}

function Get-EdtWtWorktreeDir {
    <#
      Каталог worktree задачи. Префикс feature- подставляется, если его нет.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$Task,
        [switch]$CreateIfMissing
    )

    $folder = ConvertTo-EdtWtTaskFolder -Task $Task
    $path = Join-Path (Join-Path $script:EdtWtWorktreeRoot $Project) $folder
    if (Test-Path -LiteralPath $path) { return $path }

    if ($CreateIfMissing) {
        return (New-EdtWtWorktree -Project $Project -Task $Task)
    }

    throw "Worktree не найден: $path"
}

function Invoke-EdtWtInLocation {
    <#
      Выполняет действие в указанном каталоге, возвращая прежний. Если каталог
      не задан, действие выполняется там, где пользователь находится сейчас.
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    if (-not $Path) {
        & $Action
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "    Каталог задачи не создан (сухой прогон): $Path" -ForegroundColor Gray
        return
    }

    Push-Location -LiteralPath $Path
    try { & $Action } finally { Pop-Location }
}

# ------------------------------------------------------------------------------
# 3. Создание worktree и обновление веток
# ------------------------------------------------------------------------------

function New-EdtWtWorktree {
    <#
      Создаёт git worktree задачи: fetch, prune, затем подключение существующей
      ветки feature/<задача> либо создание новой от эталонной ветки.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$Task,
        [string]$Base
    )

    $repo = Join-Path $script:EdtWtProjectsRoot $Project
    if (-not (Test-Path -LiteralPath $repo)) {
        throw "Каталог проекта не найден: $repo"
    }

    $folder = ConvertTo-EdtWtTaskFolder -Task $Task
    $wtPath = Join-Path (Join-Path $script:EdtWtWorktreeRoot $Project) $folder
    $branch = "feature/" + ($Task -replace '^feature[-/]', '')

    if (-not $Base) {
        $Base = "origin/" + (Get-EdtWtSettings).ReferenceBranch
    }

    if (-not $PSCmdlet.ShouldProcess($wtPath, "Создать git worktree ветки $branch")) {
        return $wtPath
    }

    Write-Host "==> Создание worktree: $branch" -ForegroundColor Cyan
    git -C $repo fetch origin 2>&1 | Out-Null
    git -C $repo worktree prune 2>&1 | Out-Null

    git -C $repo show-ref --verify --quiet "refs/heads/$branch"
    $branchExists = ($LASTEXITCODE -eq 0)

    if ($branchExists) {
        Write-Host "    Ветка $branch уже есть — подключается." -ForegroundColor Gray
        $out = git -C $repo worktree add $wtPath $branch 2>&1
    } else {
        Write-Host "    Ветка создаётся от $Base." -ForegroundColor Gray
        $out = git -C $repo worktree add -b $branch $wtPath $Base 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
        throw "git worktree add не удался: $out"
    }

    Write-Host "    ✓ Worktree создан: $wtPath" -ForegroundColor Green
    return $wtPath
}

function Update-EdtWtBranch {
    <#
      Подтягивает ветку в рабочем каталоге: fetch и перемотка вперёд.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$WorktreePath,
        [Parameter(Mandatory)][string]$Branch
    )

    Push-Location -LiteralPath $WorktreePath
    try {
        $dirty = @(git status --porcelain 2>$null)
        if ($dirty.Count -gt 0) {
            return [PSCustomObject]@{ Success = $false; Message = "в каталоге ветки есть незакоммиченные изменения ($($dirty.Count) файлов)" }
        }

        $current = (git rev-parse --abbrev-ref HEAD 2>$null)
        if ($current -ne $Branch) {
            return [PSCustomObject]@{ Success = $false; Message = "в каталоге ветки checkout на '$current', ожидалась '$Branch'" }
        }

        $fetch = (git fetch --prune 2>&1)
        if ($LASTEXITCODE -ne 0) {
            return [PSCustomObject]@{ Success = $false; Message = "git fetch не удался: $fetch" }
        }

        $behind = (git rev-list --count "HEAD..origin/$Branch" 2>$null)
        if (-not $behind) { $behind = '0' }
        if ($behind -eq '0') {
            return [PSCustomObject]@{ Success = $true; Message = 'ветка уже актуальна' }
        }

        $merge = (git merge --ff-only "origin/$Branch" 2>&1)
        if ($LASTEXITCODE -ne 0) {
            return [PSCustomObject]@{ Success = $false; Message = "перемотка невозможна (нужен ручной merge): $merge" }
        }

        return [PSCustomObject]@{ Success = $true; Message = "подтянуто коммитов: $behind" }
    } finally {
        Pop-Location
    }
}

function Invoke-EdtWtSafeWarmup {
    <#
      Пересборка эталона без окна, когда его нет: старый каталог отставляется
      в сторону и удаляется лишь после успеха, а при ошибке возвращается.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][hashtable]$WarmupParams
    )

    $ref = $Context.ReferenceWsDir
    $backup = "$ref.previous"
    $dryRun = $WarmupParams.ContainsKey('WhatIf') -and $WarmupParams['WhatIf']

    if ((Test-Path -LiteralPath $backup) -and -not $dryRun) {
        Remove-Item -LiteralPath $backup -Recurse -Force
    }

    $moved = $false
    if ((Test-Path -LiteralPath $ref) -and -not $dryRun) {
        Rename-Item -LiteralPath $ref -NewName (Split-Path -Leaf $backup) -Force
        $moved = $true
    }

    try {
        Invoke-EdtWorktreeWarmup @WarmupParams

        if ($moved -and (Test-Path -LiteralPath $ref)) {
            Remove-Item -LiteralPath $backup -Recurse -Force
        }
    } catch {
        if ($moved) {
            if (Test-Path -LiteralPath $ref) { Remove-Item -LiteralPath $ref -Recurse -Force }
            Rename-Item -LiteralPath $backup -NewName (Split-Path -Leaf $ref) -Force
            Write-Host "    Прежний эталон возвращён на место." -ForegroundColor Yellow
        }
        throw
    }
}

# ------------------------------------------------------------------------------
# 4. Резолвинг целевых аргументов командной строки
# ------------------------------------------------------------------------------

function Resolve-EdtWtTarget {
    <#
      Определяет, над чем работать, по позиционным аргументам и текущему каталогу.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()][AllowEmptyCollection()][string[]]$Positional,

        [Parameter(Mandatory)][ValidateSet('open', 'warmup', 'add', 'remove')]
        [string]$Command
    )

    $items = @($Positional | Where-Object { $_ })
    $projects = @((Get-EdtWtProjectsConfig).projects.PSObject.Properties.Name)

    $result = [PSCustomObject]@{
        Path       = $null
        ProjectId  = $null
        WorktreeId = $null
        Extensions = @()
    }

    $projectGiven = ($items.Count -gt 0 -and $projects -contains $items[0])

    switch ($Command) {
        'warmup' {
            if ($projectGiven) {
                $result.ProjectId = $items[0]
                $result.Extensions = @($items | Select-Object -Skip 1)
                $result.Path = Join-Path $script:EdtWtProjectsRoot $items[0]
                if (-not (Test-Path -LiteralPath $result.Path)) {
                    throw "Каталог проекта не найден: $($result.Path)"
                }
            } else {
                $result.Extensions = $items
            }
        }

        'remove' {
            if ($projectGiven) {
                if ($items.Count -lt 2) { throw "Не указана задача. Пример: edt remove $($items[0]) TASK-123" }
                $result.ProjectId = $items[0]
                $result.Path = Get-EdtWtWorktreeDir -Project $items[0] -Task $items[1]
            } elseif ($items.Count -gt 0) {
                $result.WorktreeId = ConvertTo-EdtWtTaskFolder -Task $items[0]
            }
        }

        default {
            # open и add
            if ($projectGiven) {
                if ($items.Count -lt 2) { throw "Не указана задача. Пример: edt $Command $($items[0]) TASK-123" }
                $result.ProjectId = $items[0]
                $result.WorktreeId = $items[1]
                $result.Path = Get-EdtWtWorktreeDir -Project $items[0] -Task $items[1] -CreateIfMissing:($Command -eq 'open')
                $result.Extensions = @($items | Select-Object -Skip 2)
            } else {
                $result.Extensions = $items
            }
        }
    }

    return $result
}
