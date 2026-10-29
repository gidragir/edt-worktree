function Resolve-EdtWtVrunnerPlan {
    <#
      Готовит запуск vrunner: аргументы, окружение и рабочий каталог.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]$Context,
        [AllowEmptyCollection()][string[]]$Arguments = @(),
        [AllowEmptyCollection()][string[]]$PresetEnv = @()
    )

    $hasSettings = [bool]($Arguments | Where-Object { $_ -match '^--settings(=.*)?$' })
    $settingsFile = Join-Path $Context.WorktreePath 'autumn-properties.json'
    if (-not $hasSettings -and -not (Test-Path -LiteralPath $settingsFile)) {
        throw "Файл autumn-properties.json не найден в $($Context.WorktreePath): vrunner не получит настройки базы."
    }
    if (-not (Test-Path -LiteralPath $Context.WorkspaceDir)) {
        throw "Рабочая область EDT не найдена: $($Context.WorkspaceDir). Создайте её: edt open -NoGui"
    }

    $notes = @()
    $full = $false
    $vrArgs = @()
    foreach ($item in @($Arguments | Where-Object { $_ })) {
        if ($item -match '^--?full$') { $full = $true } else { $vrArgs += $item }
    }

    $findLoad = {
        param($list)
        for ($i = 0; $i -lt ($list.Count - 1); $i++) {
            if ($list[$i] -in @('cf', 'cfe') -and $list[$i + 1] -eq 'load') { return $i + 1 }
        }
        return -1
    }
    if ((& $findLoad $vrArgs) -ge 0) {
        $explicit = [bool]($vrArgs | Where-Object { $_ -eq '--increment' })
        $vrArgs = @($vrArgs | Where-Object { $_ -ne '--increment' })
        if (-not $full) {
            $loadAt = & $findLoad $vrArgs
            $vrArgs = @($vrArgs[0..$loadAt]) + '--increment' + @($vrArgs | Select-Object -Skip ($loadAt + 1))
            if (-not $explicit) { $notes += 'инкрементальная загрузка (отключить: -Full)' }
        }
    }

    $jvm = Resolve-EdtWtJvmArgs -JvmArgs $Context.JvmArgs
    $wanted = [ordered]@{
        VRUNNER_EDT_WORKSPACE = $Context.WorkspaceDir
        VRUNNER_EDT_PATH      = $Context.EdtCliPath
        VRUNNER_EDT_VMARGS    = "-Xmx$($jvm.MaxHeapGb)g"
        VRUNNER_EDT_TIMEOUT   = [string]$Context.TimeoutSec
    }
    $envVars = [ordered]@{}
    foreach ($name in $wanted.Keys) {
        if ($PresetEnv -notcontains $name) { $envVars[$name] = $wanted[$name] }
    }

    return [PSCustomObject]@{
        WorkingDirectory = $Context.WorktreePath
        Arguments        = $vrArgs
        Env              = $envVars
        Notes            = $notes
    }
}
