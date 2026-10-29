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
        # Журналы EDT и дамп JVM - единственные улики причины сбоя: сохраняются до удаления
        # недособранного эталона. hs_err_pid*.log JVM пишет в рабочий каталог процесса.
        $evidence = @(
            @(Get-ChildItem -LiteralPath (Join-Path $ref '.metadata') -Filter '*.log' -File -Force -ErrorAction SilentlyContinue)
            @(Get-ChildItem -LiteralPath $ref -Filter 'hs_err_pid*.log' -File -ErrorAction SilentlyContinue)
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
        if (Test-Path -LiteralPath $ref) { Remove-Item -LiteralPath $ref -Recurse -Force }
        if ($moved) {
            Rename-Item -LiteralPath $backup -NewName (Split-Path -Leaf $ref) -Force
            Write-Host "    Прежний эталон возвращён на место." -ForegroundColor Yellow
        }
        throw
    }
}
