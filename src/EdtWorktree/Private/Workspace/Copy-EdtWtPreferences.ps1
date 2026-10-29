function Copy-EdtWtPreferences {
    <#
      Переносит пользовательские настройки IDE в рабочую область: из экспорта
      .epf - все ключи рабочей области, из каталога-донора - только переносимые
      файлы ($script:EdtWtPortablePrefs).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$WorkspaceDir,
        [string]$SourceDir,
        [switch]$Force
    )

    $src = if ($SourceDir) {
        if ($SourceDir -match '\.(settings|epf)$') { $SourceDir } else { Join-Path $SourceDir ".metadata\.plugins\org.eclipse.core.runtime\.settings" }
    } else {
        Get-EdtWtPrefsSource -Context $Context
    }

    if (-not $src -or -not (Test-Path -LiteralPath $src)) {
        Write-Host "    [skip] Донор настроек IDE не найден (edt.prefs_source в config.json)." -ForegroundColor DarkGray
        return @()
    }

    if (Test-Path -LiteralPath $src -PathType Leaf) {
        # Экспорт .epf применяется один раз на версию файла: отметка с его хешем
        # лежит в .metadata. Изменённый экспорт применится при следующем открытии,
        # а правки настроек в самой IDE до тех пор не затираются.
        $marker = Join-Path $WorkspaceDir '.metadata\.edtwt-prefs'
        $hash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
        if (-not $Force -and (Test-Path -LiteralPath $marker) -and (Get-Content -LiteralPath $marker -Raw).Trim() -eq $hash) {
            Write-Host "    Настройки IDE из $src уже применены." -ForegroundColor DarkGray
            return @()
        }
        $busy = @(Get-EdtWtWorkspaceProcesses -WorkspaceDir $WorkspaceDir)
        if ($busy.Count -gt 0) {
            Write-Host "    [skip] Настройки IDE не применены: рабочая область открыта в EDT, он перезапишет их при выходе." -ForegroundColor Yellow
            return @()
        }
        $r = Import-EdtWtEpf -EpfPath $src -WorkspaceDir $WorkspaceDir
        Set-Content -LiteralPath $marker -Value $hash -Encoding ascii
        $note = if ($r.Skipped -gt 0) { ", вне рабочей области пропущено: $($r.Skipped)" } else { '' }
        Write-Host "    Настройки IDE применены из $src (ключей: $($r.Applied), узлов: $($r.Nodes.Count)$note)." -ForegroundColor DarkGray
        return $r.Nodes
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
