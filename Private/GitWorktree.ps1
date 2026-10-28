# ==============================================================================
# GitWorktree.ps1 - Управление git worktree, ветками и разрешением целевых путей
# ==============================================================================

Set-StrictMode -Version Latest

# ------------------------------------------------------------------------------
# 0. Безопасный вызов Git с сохранением UTF-8
# ------------------------------------------------------------------------------

function Invoke-EdtWtGit {
    <#
      Выполняет git с принудительной установкой кодировки вывода UTF-8 и флагом core.quotepath=false.
      Предотвращает искажение путей и веток с кириллицей (cp866/кракозябры ╨Ш╨╜╤В...).
    #>
    $prevEnc = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        & git -c core.quotepath=false @args
    } finally {
        [Console]::OutputEncoding = $prevEnc
    }
}

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

function Resolve-EdtWtBranchName {
    <#
      Полное имя ветки: имя со слешем (feature/TASK-1, bugfix/x) остаётся как
      есть, короткое (TASK-1) дополняется префиксом git.branch_prefix.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prefix
    )

    if ($Name.Contains('/')) { return $Name }
    return $Prefix + $Name
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
        $lines = Invoke-EdtWtGit worktree list --porcelain 2>$null
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
      Каталог worktree ветки. Короткое имя дополняется git.branch_prefix, полное
      (со слешем) берётся как есть. Сначала спрашивается git (worktree может лежать
      где угодно), затем проверяется ожидаемый путь; при -CreateIfMissing
      недостающий worktree создаётся.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$Branch,
        [switch]$CreateIfMissing
    )

    $cfg = Get-EdtWtConfig
    $full = Resolve-EdtWtBranchName -Name $Branch -Prefix (Get-EdtWtProperty $cfg.git 'branch_prefix' '')
    $repo = Join-Path $cfg.paths.repos_root $Project
    if (-not (Test-Path -LiteralPath $repo)) { throw "Каталог проекта не найден: $repo" }

    $existing = Get-EdtWtWorktreePathForBranch -RepoPath $repo -Branch $full
    if ($existing -and (Test-Path -LiteralPath $existing)) { return $existing }

    $path = Join-Path (Join-Path $cfg.paths.worktrees_root $Project) (ConvertTo-EdtWtSafeName $full)
    if (Test-Path -LiteralPath $path) { return $path }

    if ($CreateIfMissing) {
        return (New-EdtWtWorktree -Project $Project -Branch $full)
    }

    throw "Worktree не найден: ветка '$full' проекта '$Project' (ожидался $path)"
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
      Создаёт (или находит) git worktree ветки. fetch и prune, затем по порядку:
      существующий worktree ветки, локальная ветка, ветка на remote (с
      отслеживанием), новая ветка от <remote>/<ref_branch> проекта.
      Каталог: <worktrees_root>\<проект>\<имя ветки с / -> ->.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$Branch,
        [string]$Base
    )

    $cfg = Get-EdtWtConfig
    $projDef = Get-EdtWtProjectDef -Config $cfg -Name $Project
    $repo = Join-Path $cfg.paths.repos_root $Project
    if (-not (Test-Path -LiteralPath $repo)) {
        throw "Каталог проекта не найден: $repo"
    }

    $remote = Get-EdtWtProperty $cfg.git 'remote' 'origin'
    $wtPath = Join-Path (Join-Path $cfg.paths.worktrees_root $Project) (ConvertTo-EdtWtSafeName $Branch)

    if (-not $PSCmdlet.ShouldProcess($wtPath, "Создать git worktree ветки $Branch")) {
        return $wtPath
    }

    Write-Host "==> Worktree ветки: $Branch" -ForegroundColor Cyan
    Invoke-EdtWtGit -C $repo fetch $remote 2>&1 | Out-Null
    Invoke-EdtWtGit -C $repo worktree prune 2>&1 | Out-Null

    $existing = Get-EdtWtWorktreePathForBranch -RepoPath $repo -Branch $Branch
    if ($existing) {
        Write-Host "    Worktree ветки уже есть: $existing" -ForegroundColor Gray
        return $existing
    }

    Invoke-EdtWtGit -C $repo show-ref --verify --quiet "refs/heads/$Branch"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    Локальная ветка $Branch подключается." -ForegroundColor Gray
        $out = Invoke-EdtWtGit -C $repo worktree add $wtPath $Branch 2>&1
    } else {
        Invoke-EdtWtGit -C $repo show-ref --verify --quiet "refs/remotes/$remote/$Branch"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    Ветка $remote/$Branch подключается с отслеживанием." -ForegroundColor Gray
            $out = Invoke-EdtWtGit -C $repo worktree add --track -b $Branch $wtPath "$remote/$Branch" 2>&1
        } else {
            if (-not $Base) { $Base = "$remote/" + (Get-EdtWtProperty $projDef 'ref_branch' 'pre-prod') }
            Write-Host "    Ветка создаётся от $Base." -ForegroundColor Gray
            $out = Invoke-EdtWtGit -C $repo worktree add -b $Branch $wtPath $Base 2>&1
        }
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
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$Remote
    )

    Push-Location -LiteralPath $WorktreePath
    try {
        $dirty = @(Invoke-EdtWtGit status --porcelain 2>$null)
        if ($dirty.Count -gt 0) {
            return [PSCustomObject]@{ Success = $false; Message = "в каталоге ветки есть незакоммиченные изменения ($($dirty.Count) файлов)" }
        }

        $current = (Invoke-EdtWtGit rev-parse --abbrev-ref HEAD 2>$null)
        if ($current -ne $Branch) {
            return [PSCustomObject]@{ Success = $false; Message = "в каталоге ветки checkout на '$current', ожидалась '$Branch'" }
        }

        $fetch = (Invoke-EdtWtGit fetch --prune $Remote 2>&1)
        if ($LASTEXITCODE -ne 0) {
            return [PSCustomObject]@{ Success = $false; Message = "git fetch не удался: $fetch" }
        }

        $behind = (Invoke-EdtWtGit rev-list --count "HEAD..$Remote/$Branch" 2>$null)
        if (-not $behind) { $behind = '0' }
        if ($behind -eq '0') {
            return [PSCustomObject]@{ Success = $true; Message = 'ветка уже актуальна' }
        }

        $merge = (Invoke-EdtWtGit merge --ff-only "$Remote/$Branch" 2>&1)
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
      в сторону (<эталон>.previous) и удаляется лишь после успеха, а при ошибке
      недособранный эталон убирается, и прежний возвращается на место.
      Сама сборка передаётся блоком -Build.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][scriptblock]$Build
    )

    $ref = $Context.ReferenceWsDir
    $backup = "$ref.previous"

    if (Test-Path -LiteralPath $backup) {
        Remove-Item -LiteralPath $backup -Recurse -Force
    }

    $moved = $false
    if (Test-Path -LiteralPath $ref) {
        Rename-Item -LiteralPath $ref -NewName (Split-Path -Leaf $backup) -Force
        $moved = $true
    }

    try {
        & $Build

        if ($moved -and (Test-Path -LiteralPath $ref)) {
            Remove-Item -LiteralPath $backup -Recurse -Force
        }
    } catch {
        if (Test-Path -LiteralPath $ref) { Remove-Item -LiteralPath $ref -Recurse -Force }
        if ($moved) {
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
      Возвращает Path (где выполнять; $null - текущий каталог), ProjectId,
      Branch (полное имя ветки, для remove) и Extensions (для add).
      open <проект> <ветка> создаёт недостающий worktree (под -WhatIf - нет).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()][AllowEmptyCollection()][string[]]$Positional,

        [Parameter(Mandatory)][ValidateSet('open', 'warmup', 'add', 'remove')]
        [string]$Command
    )

    $items = @($Positional | Where-Object { $_ })
    $cfg = Get-EdtWtConfig
    $prefix = Get-EdtWtProperty $cfg.git 'branch_prefix' ''

    $result = [PSCustomObject]@{
        Path       = $null
        ProjectId  = $null
        Branch     = $null
        Extensions = @()
    }

    switch ($Command) {
        'warmup' {
            if ($items.Count -gt 1) {
                throw "Лишние аргументы: $(($items | Select-Object -Skip 1) -join ', '). Использование: edt warmup [проект]"
            }
            if ($items.Count -eq 1) {
                Get-EdtWtProjectDef -Config $cfg -Name $items[0] | Out-Null
                $result.ProjectId = $items[0]
                $result.Path = Join-Path $cfg.paths.repos_root $items[0]
                if (-not (Test-Path -LiteralPath $result.Path)) {
                    throw "Каталог проекта не найден: $($result.Path)"
                }
            }
        }

        'add' {
            $result.Extensions = $items
        }

        'remove' {
            if ($items.Count -gt 2) {
                throw "Лишние аргументы: $(($items | Select-Object -Skip 2) -join ', '). Использование: edt remove [проект] [ветка]"
            }
            $projectGiven = ($items.Count -gt 0 -and $null -ne $cfg.projects.PSObject.Properties[$items[0]])
            if ($projectGiven) {
                if ($items.Count -lt 2) { throw "Не указана ветка. Пример: edt remove $($items[0]) TASK-123" }
                $result.ProjectId = $items[0]
                $result.Branch = Resolve-EdtWtBranchName -Name $items[1] -Prefix $prefix
                $result.Path = Get-EdtWtWorktreeDir -Project $items[0] -Branch $result.Branch
            } elseif ($items.Count -eq 2) {
                Get-EdtWtProjectDef -Config $cfg -Name $items[0] | Out-Null
            } elseif ($items.Count -eq 1) {
                $result.Branch = Resolve-EdtWtBranchName -Name $items[0] -Prefix $prefix
            }
        }

        'open' {
            if ($items.Count -gt 2) {
                throw "Лишние аргументы: $(($items | Select-Object -Skip 2) -join ', '). Использование: edt open [проект ветка]"
            }
            if ($items.Count -gt 0) {
                Get-EdtWtProjectDef -Config $cfg -Name $items[0] | Out-Null
                if ($items.Count -lt 2) { throw "Не указана ветка. Пример: edt open $($items[0]) TASK-123" }
                $result.ProjectId = $items[0]
                $result.Branch = Resolve-EdtWtBranchName -Name $items[1] -Prefix $prefix
                $result.Path = Get-EdtWtWorktreeDir -Project $items[0] -Branch $result.Branch -CreateIfMissing
            }
        }
    }

    return $result
}
