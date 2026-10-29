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
