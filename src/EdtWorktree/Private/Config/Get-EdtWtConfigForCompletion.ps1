function Get-EdtWtConfigForCompletion {
    <#
      Конфиг для автодополнения: только чтение. Файла нет, он не JSON-объект или
      без version >= 3 - $null (миграция и запись конфига из TAB недопустимы).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $path = Get-EdtWtUserConfigPath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
        $raw = Get-Content -Raw -LiteralPath $path -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $userJson = $raw | ConvertFrom-Json -NoEnumerate -ErrorAction Stop
        if ($null -eq $userJson -or $userJson.GetType().FullName -ne 'System.Management.Automation.PSCustomObject') { return $null }
        $version = Get-EdtWtProperty $userJson 'version' 0
        if (-not ($version -is [ValueType] -and $version -ge 3)) { return $null }
        return (Merge-EdtWtConfigObject -Base (New-EdtWtDefaultConfig) -Override $userJson)
    } catch {
        return $null
    }
}
