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
    & robocopy $Context.ReferenceWsDir $Context.WorkspaceDir /E /XF .lock $script:EdtWtReferenceStampName /NFL /NDL /NJH /NJS /NC /NS /MT:8 | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ge 8) {
        throw "robocopy завершился с ошибкой (ExitCode $rc). Убедитесь, что эталон не занят работающим EDT."
    }
    Write-Host "    ✓ Клонирование завершено (robocopy rc=$rc)." -ForegroundColor Green
    Test-EdtWtReferenceFreshness -Context $Context | Out-Null
    return $true
}
