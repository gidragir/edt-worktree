function Set-EdtWtWorkspaceName {
    <#
      Записывает имя рабочей области (WORKSPACE_NAME) в настройки Eclipse
      (.metadata\.plugins\org.eclipse.core.runtime\.settings\org.eclipse.ui.ide.prefs).
      Отображается в заголовке окна 1C:EDT.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$WorkspaceDir,
        [string]$Title
    )

    $name = if ($Title) { $Title } else { Get-EdtWtWorkspaceTitle -Context $Context -WorkspaceDir $WorkspaceDir }
    if (-not $name) { return }

    $settingsDir = Join-Path $WorkspaceDir '.metadata\.plugins\org.eclipse.core.runtime\.settings'
    if (-not (Test-Path -LiteralPath $settingsDir)) {
        New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null
    }

    $file = Join-Path $settingsDir 'org.eclipse.ui.ide.prefs'
    $values = Read-EdtWtPropertiesFile -Path $file

    $escaped = [System.Text.StringBuilder]::new()
    foreach ($ch in $name.ToCharArray()) {
        $code = [int]$ch
        if ($code -gt 127) {
            $null = $escaped.AppendFormat('\u{0:x4}', $code)
        } else {
            $null = $escaped.Append($ch)
        }
    }
    $values['WORKSPACE_NAME'] = $escaped.ToString()

    if (-not $values.Contains('eclipse.preferences.version')) {
        $values['eclipse.preferences.version'] = '1'
    }

    [string[]]$keys = @($values.Keys)
    [Array]::Sort($keys, [StringComparer]::Ordinal)
    $text = (@($keys | ForEach-Object { "$_=$($values[$_])" }) -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($file, $text, [System.Text.Encoding]::Latin1)
}
