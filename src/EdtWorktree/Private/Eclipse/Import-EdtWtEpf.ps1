function Import-EdtWtEpf {
    <#
      Применяет экспорт настроек Eclipse (.epf) к рабочей области так же, как
      File > Import > Preferences: ключи области /instance/<узел>/<ключ> пишутся
      в .metadata\.plugins\org.eclipse.core.runtime\.settings\<узел>.prefs,
      существующие значения заменяются, прочие ключи файла сохраняются.
      Дочерние узлы Eclipse хранит в файле родителя ключом "дочерний/ключ".
      Область /configuration/ относится к установке EDT, а не к рабочей области,
      и не применяется. Возвращает число применённых ключей и затронутые узлы.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$EpfPath,
        [Parameter(Mandatory)][string]$WorkspaceDir
    )

    $byNode = [ordered]@{}
    $skipped = 0
    $entries = Read-EdtWtPropertiesFile -Path $EpfPath
    foreach ($key in $entries.Keys) {
        $m = [regex]::Match($key, '^/instance/([^/]+)/(.+)$')
        if (-not $m.Success) {
            if ($key -like '/*') { $skipped++ }
            continue
        }
        $node = $m.Groups[1].Value
        $name = $m.Groups[2].Value
        # \!/ - служебная отметка существования узла в экспорте, не настройка.
        if ($name.StartsWith('\!')) { continue }
        if (-not $byNode.Contains($node)) { $byNode[$node] = [ordered]@{} }
        $byNode[$node][$name] = $entries[$key]
    }

    $dir = Join-Path $WorkspaceDir '.metadata\.plugins\org.eclipse.core.runtime\.settings'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    $applied = 0
    foreach ($node in $byNode.Keys) {
        $file = Join-Path $dir "$node.prefs"
        $values = Read-EdtWtPropertiesFile -Path $file
        foreach ($name in $byNode[$node].Keys) {
            $values[$name] = $byNode[$node][$name]
            $applied++
        }
        if (-not $values.Contains('eclipse.preferences.version')) { $values['eclipse.preferences.version'] = '1' }
        # Eclipse пишет ключи по порядку строк (TreeMap), CRLF на Windows.
        [string[]]$names = @($values.Keys)
        [Array]::Sort($names, [StringComparer]::Ordinal)
        $text = (@($names | ForEach-Object { "$_=$($values[$_])" }) -join "`r`n") + "`r`n"
        [System.IO.File]::WriteAllText($file, $text, [System.Text.Encoding]::Latin1)
    }

    return [PSCustomObject]@{
        Applied = $applied
        Nodes   = [string[]]@($byNode.Keys)
        Skipped = $skipped
    }
}
