function Get-EdtWtPrefsSource {
    <#
      Донор настроек IDE: только edt.prefs_source из config.json - файл экспорта
      настроек Eclipse (.epf), корень рабочей области или сам каталог .settings.
      Не задан или не найден - $null.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    param([Parameter(Mandatory)]$Context)

    $prefsSource = Get-EdtWtProperty (Get-EdtWtConfig).edt 'prefs_source'
    if (-not $prefsSource) { return $null }

    $c = ($prefsSource -replace '/', '\')
    if ($c -match '\.epf$') {
        if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
        return $null
    }
    $direct = if ($c -match '\.settings$') { $c } else { Join-Path $c ".metadata\.plugins\org.eclipse.core.runtime\.settings" }
    if (Test-Path -LiteralPath $direct) { return $direct }
    return $null
}
