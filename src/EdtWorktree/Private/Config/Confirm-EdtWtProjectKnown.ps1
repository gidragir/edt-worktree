function Confirm-EdtWtProjectKnown {
    <#
      open и warmup для клона из repos_root, который ещё не зарегистрирован:
      интерактивно запускается регистрация (Add-EdtProject -Name), без диалога
      ничего не делается, и вызывающий получит ошибку Get-EdtWtProjectDef с
      командой регистрации. Имя не задано - проект берётся по текущему каталогу.
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [hashtable]$Params = @{}
    )

    $cfg = Get-EdtWtConfig
    if ($Name) {
        if ($null -ne $cfg.projects.PSObject.Properties[$Name]) { return }
        if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $cfg.paths.repos_root $Name) '.git'))) { return }
    } else {
        $resolved = Resolve-EdtWtProjectFromPath -Path (Get-Location).Path -Config $cfg
        if (-not $resolved -or $resolved.Registered) { return }
        $Name = $resolved.Name
    }

    if (-not (Test-EdtWtInteractive)) { return }
    Write-Host "Проект '$Name' ещё не зарегистрирован." -ForegroundColor Yellow
    Add-EdtProject -Name $Name @Params
}
