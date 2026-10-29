function Invoke-EdtWtConfigMigration {
    <#
      Ищет конфиг 2.x (config.json без version >= 3 по пути Get-EdtWtUserConfigPath
      и legacy projects.json). Нечего переносить - $null. Иначе: копия config.json в
      config.json.v2.bak, запись v3, печать итога одним блоком, возврат конфига.
      Legacy-файл не изменяется.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $cfgPath = Get-EdtWtUserConfigPath
    $legacyPath = if ($env:EDT_LEGACY_CONFIG_PATH) { $env:EDT_LEGACY_CONFIG_PATH }
    else { Join-Path $HOME '.config\1c\projects.json' }

    $primary = Read-EdtWtJsonObject -Path $cfgPath
    # Битый legacy-файл не пропускаем: иначе проекты молча потеряются. Ничего не пишем.
    $legacy = Read-EdtWtJsonObject -Path $legacyPath

    if ($null -eq $primary -and $null -eq $legacy) { return $null }

    $reposRoot = Get-EdtWtProperty (Get-EdtWtProperty $primary 'paths') 'projects_root'
    if (-not $reposRoot) { $reposRoot = (New-EdtWtDefaultConfig).paths.repos_root }

    $result = ConvertFrom-EdtWtV2Config -Primary $primary -Legacy $legacy -ReposRootForCheck $reposRoot

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('Миграция конфига 2.x -> 3.0')
    if (Test-Path -LiteralPath $cfgPath -PathType Leaf) {
        # Существующий бэкап не перезаписываем: берём .v2.bak.1, .v2.bak.2, ...
        $bak = "$cfgPath.v2.bak"
        $i = 0
        while (Test-Path -LiteralPath $bak) { $i++; $bak = "$cfgPath.v2.bak.$i" }
        Copy-Item -LiteralPath $cfgPath -Destination $bak
        $lines.Add("  Копия прежнего config.json: $bak")
    }
    foreach ($n in $result.Notes) { $lines.Add("  $n") }

    $saved = Save-EdtWtConfig -Config $result.Config
    $lines.Add("  Сохранено: $saved")
    $lines.Add('  Legacy-файл ~/.config/1c/projects.json не изменён и больше не читается.')
    Write-Host ($lines -join [Environment]::NewLine) -ForegroundColor DarkGray

    return $result.Config
}
