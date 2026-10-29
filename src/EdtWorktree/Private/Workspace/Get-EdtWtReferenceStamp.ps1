function Get-EdtWtReferenceStamp {
    <#
      Отметка сборки эталона (.edtwt-reference.json в корне рабочей области):
      ветка, коммит клона и время сборки. Нет файла или он битый - $null.
    #>
    [OutputType([PSCustomObject])]
    param([Parameter(Mandatory)][string]$WorkspaceDir)

    $file = Join-Path $WorkspaceDir $script:EdtWtReferenceStampName
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try {
        return (Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}
