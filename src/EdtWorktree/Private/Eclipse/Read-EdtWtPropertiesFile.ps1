function Read-EdtWtPropertiesFile {
    <#
      Читает файл формата java.util.Properties (.prefs Eclipse, экспорт настроек .epf)
      как упорядоченный словарь "ключ -> значение" в экранированном виде: текст
      ключей и значений не декодируется, чтобы записать его обратно байт в байт.
      Eclipse пишет такие файлы в ISO-8859-1 с \uXXXX, поэтому чтение - Latin1.
      Строки, оканчивающиеся нечётным числом '\', продолжаются на следующей.
    #>
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)][string]$Path)

    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $result }

    $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::Latin1)
    $logical = ''
    foreach ($raw in $lines) {
        $line = if ($logical) { $raw.TrimStart() } else { $raw }
        $trailing = ([regex]::Match($line, '\\*$')).Length
        if ($trailing % 2 -eq 1) {
            $logical += $line.Substring(0, $line.Length - 1)
            continue
        }
        $logical += $line
        $entry = $logical.TrimStart()
        $logical = ''

        if (-not $entry -or $entry[0] -in '#', '!') { continue }
        $m = [regex]::Match($entry, '^((?:\\.|[^=:\\])*)[=:](.*)$')
        if (-not $m.Success) { continue }
        $result[$m.Groups[1].Value.TrimEnd()] = $m.Groups[2].Value.TrimStart()
    }
    return $result
}
