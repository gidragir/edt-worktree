function Install-EdtWtShim {
    <#
      Копирует edt.cmd и edt.ps1 (запускатель) из bin\shim модуля в постоянный каталог
      Get-EdtWtShimDir и добавляет его в PATH пользователя (EDT_PATH_SCOPE=Process -
      только процесса) без дублей. Каталог всегда попадает в $env:Path текущего процесса.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([string])]
    param([switch]$NoPath)

    $dir = Get-EdtWtShimDir
    # Shim не кладётся внутрь клона EdtWorktree (например, 3.0 в %LOCALAPPDATA%\EdtWorktree):
    # иначе он перезапишет отслеживаемые файлы и исчезнет вместе с клоном. Посторонние
    # репозитории выше по пути (dotfiles в профиле) не мешают.
    $probe = [IO.Path]::GetFullPath($dir)
    while ($probe) {
        if (Test-EdtWtLegacyClone -Path $probe) {
            throw "Каталог shim $dir лежит внутри клона EdtWorktree $probe. Укажите другой каталог в EDT_SHIM_DIR."
        }
        $probe = Split-Path -Parent $probe
    }

    $template = Join-Path $script:EdtWtModuleRoot 'bin\shim'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    foreach ($name in 'edt.cmd', 'edt.ps1') {
        Copy-Item -LiteralPath (Join-Path $template $name) -Destination (Join-Path $dir $name) -Force
    }

    if (-not $NoPath) {
        if ($env:EDT_PATH_SCOPE -ne 'Process') {
            $userPath = [string][Environment]::GetEnvironmentVariable('Path', 'User')
            $has = $false
            foreach ($part in $userPath -split ';') {
                if ([string]::IsNullOrWhiteSpace($part)) { continue }
                try { if (Test-EdtWtSamePath -A $part -B $dir) { $has = $true; break } } catch { Write-Verbose $_.Exception.Message }
            }
            if (-not $has) {
                $newUser = if ($userPath) { $userPath.TrimEnd(';') + ';' + $dir } else { $dir }
                [Environment]::SetEnvironmentVariable('Path', $newUser, 'User')
            }
        }
    }

    $inProcess = $false
    foreach ($part in $env:Path -split ';') {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        try { if (Test-EdtWtSamePath -A $part -B $dir) { $inProcess = $true; break } } catch { Write-Verbose $_.Exception.Message }
    }
    if (-not $inProcess) { $env:Path = $env:Path.TrimEnd(';') + ';' + $dir }
    return $dir
}
