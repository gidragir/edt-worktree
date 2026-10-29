function Copy-EdtWtPreferences {
    <#
      Переносит пользовательские настройки IDE в рабочую область.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$WorkspaceDir,
        [string]$SourceDir,
        [switch]$Force
    )

    $src = if ($SourceDir) {
        if ($SourceDir -match '\.settings$') { $SourceDir } else { Join-Path $SourceDir ".metadata\.plugins\org.eclipse.core.runtime\.settings" }
    } else {
        Get-EdtWtPrefsSource -Context $Context
    }

    if (-not $src -or -not (Test-Path -LiteralPath $src)) {
        Write-Host "    [skip] Донор настроек IDE не найден (edt.prefs_source в config.json)." -ForegroundColor DarkGray
        return @()
    }

    $dst = Join-Path $WorkspaceDir ".metadata\.plugins\org.eclipse.core.runtime\.settings"
    New-Item -ItemType Directory -Force -Path $dst | Out-Null

    $copied = @()
    foreach ($name in $script:EdtWtPortablePrefs) {
        $from = Join-Path $src $name
        if (-not (Test-Path -LiteralPath $from)) { continue }
        $to = Join-Path $dst $name
        if ((Test-Path -LiteralPath $to) -and -not $Force) { continue }
        Copy-Item -LiteralPath $from -Destination $to -Force
        $copied += $name
    }

    if ($copied.Count -gt 0) {
        Write-Host "    Настройки IDE перенесены из $src ($($copied.Count) файлов)." -ForegroundColor DarkGray
    } else {
        Write-Host "    Настройки IDE уже на месте (перенос не требуется)." -ForegroundColor DarkGray
    }
    return $copied
}
