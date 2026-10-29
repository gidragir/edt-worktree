function Read-EdtWtJsonObject {
    <#
      Читает JSON-файл с объектом в корне. Нет файла - $null. Битый JSON или
      не-объект - исключение с путём файла.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }

    $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

    $problem = $null
    $obj = $null
    try {
        $obj = $raw | ConvertFrom-Json -NoEnumerate -ErrorAction Stop
        if ($null -eq $obj -or $obj.GetType().FullName -ne 'System.Management.Automation.PSCustomObject') {
            $problem = 'корнем должен быть JSON-объект'
        }
    } catch {
        $problem = $_.Exception.Message
    }
    if ($problem) { throw "Конфиг повреждён: ${Path}: $problem. Исправьте файл или удалите его." }
    return $obj
}
