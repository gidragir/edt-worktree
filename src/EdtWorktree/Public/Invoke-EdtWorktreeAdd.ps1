function Invoke-EdtWorktreeAdd {
    <#
    .SYNOPSIS
        Доимпортирует расширения в уже существующую рабочую область.

    .DESCRIPTION
        Рабочая область блокируется запущенным EDT (.metadata/.lock), поэтому
        IDE на время headless-импорта закрывается и по завершении поднимается
        обратно. Эталон и конфигурация проекта не меняются.

    .PARAMETER Extensions
        Расширения текущего worktree: имя папки (cfe_x) или относительный путь.

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

        [switch]$NoGui,

        [switch]$Force
    )

    $ctx = Get-EdtWtContext
    if ($null -eq $ctx) { return }

    if (-not (Test-Path -LiteralPath $ctx.WorkspaceDir)) {
        throw "Рабочая область не найдена: $($ctx.WorkspaceDir). Сначала выполните edt open."
    }

    $found = @(Find-EdtWtEdtProjects -RepoPath $ctx.WorktreePath | Where-Object { $_.Kind -eq 'Extension' })
    $extList = [string[]]@($Extensions | ForEach-Object { Resolve-EdtWtExtensionRef -Found $found -Ref $_ } | Select-Object -Unique)

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
    Invoke-EdtWtCli -Context $ctx -WorkspaceDir $ctx.WorkspaceDir -Commands $batch.ToArray() -BatchName "add_batch.txt"
    Write-Host "    ✓ Импортировано: $(($plan.Targets | ForEach-Object { Split-Path -Leaf $_ }) -join ', ')" -ForegroundColor Green

    if ($NoGui) {
        Write-Host "✓ Готово (GUI не запускается: -NoGui)." -ForegroundColor Green
        return
    }
    if (-not $wasRunning) {
        Write-Host "✓ Готово. EDT не был запущен — стартуйте его через edt open." -ForegroundColor Green
        return
    }

    Write-Host "==> Возврат 1C:EDT..." -ForegroundColor Cyan
    Start-EdtWtGui -Context $ctx
}
