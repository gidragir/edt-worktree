function Invoke-EdtWtSafeWarmup {
    <#
      Пересборка эталона без окна, когда его нет: новый эталон собирается рядом
      (<эталон>.building), а действующий остаётся на месте и доступен для
      клонирования, пока сборка не закончится. Блок -Build получает каталог
      сборки параметром. Только после успеха прежний эталон отставляется в
      <эталон>.previous, новый встаёт на его место, а резерв удаляется. При
      ошибке недособранный каталог убирается (журналы - в <эталон>.failed).
      Служебные проекты, указывающие внутрь каталога сборки (EGit cmp),
      перепривязываются на итоговый каталог эталона.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][scriptblock]$Build
    )

    $ref = $Context.ReferenceWsDir
    $building = "$ref.building"
    $backup = "$ref.previous"

    foreach ($stale in $building, $backup) {
        if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Recurse -Force }
    }

    try {
        & $Build $building
    } catch {
        # Журналы EDT и дамп JVM - единственные улики причины сбоя: сохраняются до удаления
        # недособранного эталона. hs_err_pid*.log JVM пишет в рабочий каталог процесса.
        $evidence = @(
            @(Get-ChildItem -LiteralPath (Join-Path $building '.metadata') -Filter '*.log' -File -Force -ErrorAction SilentlyContinue)
            @(Get-ChildItem -LiteralPath $building -Filter 'hs_err_pid*.log' -File -ErrorAction SilentlyContinue)
        )
        if ($evidence.Count -gt 0) {
            $failedDir = "$ref.failed"
            if (Test-Path -LiteralPath $failedDir) { Remove-Item -LiteralPath $failedDir -Recurse -Force }
            New-Item -ItemType Directory -Path $failedDir | Out-Null
            $evidence | Copy-Item -Destination $failedDir -Force
            Write-Host "    Журналы EDT сохранены: $failedDir" -ForegroundColor Yellow
        } else {
            Write-Host '    EDT журналов не оставил: процесс завершился до открытия рабочей области.' -ForegroundColor Yellow
        }
        if (Test-Path -LiteralPath $building) { Remove-Item -LiteralPath $building -Recurse -Force }
        if (Test-Path -LiteralPath $ref) { Write-Host "    Прежний эталон не тронут." -ForegroundColor Yellow }
        throw
    }

    # Эталон могли открыть, пока шла сборка: тогда новый остаётся в .building.
    Assert-EdtWtReferenceFree -Context $Context
    $moved = $false
    if (Test-Path -LiteralPath $ref) {
        Rename-Item -LiteralPath $ref -NewName (Split-Path -Leaf $backup) -Force
        $moved = $true
    }
    try {
        Rename-Item -LiteralPath $building -NewName (Split-Path -Leaf $ref) -Force
    } catch {
        if ($moved) { Rename-Item -LiteralPath $backup -NewName (Split-Path -Leaf $ref) -Force }
        throw "Не удалось поставить новый эталон на место ($($_.Exception.Message)). Сборка оставлена в $building."
    }
    Repair-EdtWtWorkspaceLocations -WorkspaceDir $ref -WorktreePath $Context.RepoPath -ReferenceWsDir $building | Out-Null
    if ($moved) { Remove-Item -LiteralPath $backup -Recurse -Force }
}
