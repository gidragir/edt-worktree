function Get-EdtWtUnbuiltProjects {
    <#
      Проекты рабочей области без результатов сборки и проверки: нет индекса
      проверок (com._1c.g5.v8.dt.validation\project\<имя>\index) или кэша
      проверенных объектов (cache\object_checkid_cache). Без них GUI при первом
      открытии заново проверяет весь проект.
    #>
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$WorkspaceDir,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ProjectNames
    )

    $root = Join-Path $WorkspaceDir '.metadata\.plugins\com._1c.g5.v8.dt.validation\project'
    $missing = @()
    foreach ($name in $ProjectNames) {
        $index = Join-Path $root "$name\index"
        $cache = Join-Path $root "$name\cache\object_checkid_cache"
        $hasIndex = (Test-Path -LiteralPath $index) -and @(Get-ChildItem -LiteralPath $index -File -ErrorAction SilentlyContinue).Count -gt 0
        if (-not $hasIndex -or -not (Test-Path -LiteralPath $cache)) { $missing += $name }
    }
    return , [string[]]$missing
}
