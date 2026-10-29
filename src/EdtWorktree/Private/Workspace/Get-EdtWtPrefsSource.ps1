function Get-EdtWtPrefsSource {
    <#
      Каталог-донор настроек IDE: только edt.prefs_source из config.json
      (корень рабочей области или сам каталог .settings). Не задан - $null.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    param([Parameter(Mandatory)]$Context)

    $prefsSource = Get-EdtWtProperty (Get-EdtWtConfig).edt 'prefs_source'
    if (-not $prefsSource) { return $null }

    $c = ($prefsSource -replace '/', '\')
    $direct = if ($c -match '\.settings$') { $c } else { Join-Path $c ".metadata\.plugins\org.eclipse.core.runtime\.settings" }
    if (Test-Path -LiteralPath $direct) { return $direct }
    return $null
}
