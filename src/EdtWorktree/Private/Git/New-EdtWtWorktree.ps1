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
