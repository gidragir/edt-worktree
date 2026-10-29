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
