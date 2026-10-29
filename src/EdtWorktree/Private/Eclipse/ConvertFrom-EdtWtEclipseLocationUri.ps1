function ConvertFrom-EdtWtEclipseLocationUri {
    <#
      Декодирует URI из .location Eclipse в локальный путь Windows.
      Снимает префикс 'URI//file:/' и разэкранирует percent-encoding (%20, %D0%... и т.д.).
    #>
    param([Parameter(Mandatory)][string]$UriValue)

    $prefix = 'URI//file:/'
    if (-not $UriValue.StartsWith($prefix)) {
        return $null
    }
    $raw = $UriValue.Substring($prefix.Length)
    return ([System.Uri]::UnescapeDataString($raw) -replace '/', '\')
}
