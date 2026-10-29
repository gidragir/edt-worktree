function Get-EdtWtConfig {
    <#
      Конфиг v3. Файл с version >= 3 - его JSON поверх дефолтов. Файла нет или в нём
      нет version >= 3 - миграция с 2.x (Invoke-EdtWtConfigMigration), если есть что
      переносить, иначе дефолты без записи на диск.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $path = Get-EdtWtUserConfigPath
    $config = New-EdtWtDefaultConfig

    if (-not (Test-Path -LiteralPath $path)) {
        $migrated = Invoke-EdtWtConfigMigration
        if ($null -eq $migrated) { return $config }
        return (Merge-EdtWtConfigObject -Base $config -Override $migrated)
    }

    $userJson = $null
    $problem = $null
    try {
        $raw = Get-Content -Raw -LiteralPath $path -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $userJson = $raw | ConvertFrom-Json -NoEnumerate -ErrorAction Stop
            if ($null -eq $userJson -or $userJson.GetType().FullName -ne 'System.Management.Automation.PSCustomObject') { $problem = 'корнем конфига должен быть JSON-объект' }
        }
    } catch {
        $problem = $_.Exception.Message
    }
    if ($problem) {
        throw "Конфиг повреждён: ${path}: $problem. Исправьте файл или удалите его и выполните edt setup."
    }

    if ($null -eq $userJson) { return $config }

    $version = Get-EdtWtProperty $userJson 'version' 0
    if (-not ($version -is [ValueType] -and $version -ge 3)) {
        $migrated = Invoke-EdtWtConfigMigration
        if ($null -ne $migrated) { return (Merge-EdtWtConfigObject -Base $config -Override $migrated) }
    }
    return (Merge-EdtWtConfigObject -Base $config -Override $userJson)
}
