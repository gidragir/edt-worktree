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
