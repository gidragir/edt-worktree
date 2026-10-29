#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Установщик модуля EdtWorktree (одна строка в PowerShell 7).
.DESCRIPTION
    irm https://github.com/gidragir/edt-worktree/releases/latest/download/install.ps1 | iex

    Скачивает EdtWorktree.zip последнего выпуска и ставит модуль в
    Documents\PowerShell\Modules\EdtWorktree\<версия> (другие версии остаются), снимает
    старую установку 3.0 (ссылку на клон), ставит shim edt в %LOCALAPPDATA%\EdtWorktree\bin
    и показывает проверки окружения. Повторный запуск обновляет установку.

    Источники (взаимоисключающие): по умолчанию - выпуск (EDT_RELEASE_URL переопределяет
    адрес); -ZipPath - локальный zip; -Branch - архив ветки GitHub; -Dev - ссылка на
    src\EdtWorktree клона, из которого запущен файл.

    Под iex нет $PSScriptRoot и param(): параметры задаются переменными окружения
    EDT_INSTALL_ZIP, EDT_INSTALL_BRANCH, EDT_INSTALL_DEV, EDT_INSTALL_NOSETUP либо ключами
    Install-EdtWorktree в вызове & ([scriptblock]::Create((irm <url>))) -NoSetup.
    Файл самодостаточен: модуль в этот процесс не импортируется, git для установки не нужен.
#>

function Add-EdtWtInstallPathEntry {
    <# Добавляет Entry в конец PATH, если его нет (без учёта регистра и хвостового слеша). #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$PathValue,
        [Parameter(Mandatory)][string]$Entry
    )

    $norm = { param([string]$p) $p.Trim().TrimEnd('\', '/').ToLowerInvariant() }
    $target = & $norm $Entry
    $parts = @($PathValue -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($part in $parts) {
        if ((& $norm $part) -eq $target) { return $PathValue }
    }
    return (($parts + $Entry) -join ';')
}

function Remove-EdtWtInstallPathEntry {
    <# Убирает из PATH все записи, равные Entry (без учёта регистра и хвостового слеша); пустые элементы выбрасываются. #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$PathValue,
        [Parameter(Mandatory)][string]$Entry
    )

    $norm = { param([string]$p) $p.Trim().TrimEnd('\', '/').ToLowerInvariant() }
    $target = & $norm $Entry
    $kept = @($PathValue -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (& $norm $_) -ne $target })
    return ($kept -join ';')
}

function Get-EdtWtInstallDownload {
    <# Скачивает Url в OutFile. Адрес file:/// копируется с диска (Invoke-WebRequest его не принимает). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutFile
    )

    $uri = [Uri]$Url
    if ($uri.IsFile) {
        Copy-Item -LiteralPath $uri.LocalPath -Destination $OutFile -ErrorAction Stop
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
    }
}

function Get-EdtWtInstallChecks {
    <# Проверки окружения для итоговой таблицы: pwsh, git, 1C:EDT, JDK 17+ с JavaFX. #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param()

    $rows = New-Object System.Collections.Generic.List[object]
    $add = {
        param($name, $ok, $detail, $hint)
        $rows.Add([pscustomobject]@{
            Проверка = $name
            Статус   = $(if ($ok) { 'OK' } else { 'нет' })
            Детали   = $(if ($ok) { $detail } else { $hint })
        })
    }

    & $add 'PowerShell 7' ($PSVersionTable.PSVersion.Major -ge 7) $PSVersionTable.PSVersion.ToString() 'winget install Microsoft.PowerShell'

    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    & $add 'git' ([bool]$git) $(if ($git) { $git.Source } else { '' }) 'нужен для работы edt (не для установки): winget install Git.Git'

    $edtRoots = @("$env:ProgramFiles\1C", "$env:LOCALAPPDATA\Programs\1C", "${env:ProgramFiles(x86)}\1C")
    $edt = $null
    foreach ($root in $edtRoots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        $edt = Get-ChildItem -LiteralPath $root -Filter '1cedtcli.*' -Recurse -Depth 5 -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.exe', '.bat') } | Select-Object -First 1
        if ($edt) { break }
    }
    & $add '1C:EDT' ([bool]$edt) $(if ($edt) { $edt.FullName } else { '' }) 'не найден; укажет edt setup, либо установите 1C:EDT'

    $jdkHome = $null
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:JAVA_HOME) { $candidates.Add($env:JAVA_HOME) }
    foreach ($pattern in @("$env:ProgramFiles\Zulu\*", "$env:ProgramFiles\BellSoft\*", "$env:ProgramFiles\Axiom*\*", "$env:ProgramFiles\Java\*")) {
        foreach ($d in @(Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue)) { $candidates.Add($d.FullName) }
    }
    foreach ($c in $candidates) {
        $fx = (Test-Path -LiteralPath (Join-Path $c 'jmods\javafx.base.jmod')) -or (Test-Path -LiteralPath (Join-Path $c 'lib\javafx-swt.jar'))
        $rel = Join-Path $c 'release'
        if (-not $fx -or -not (Test-Path -LiteralPath $rel)) { continue }
        $line = Get-Content -LiteralPath $rel -ErrorAction SilentlyContinue | Where-Object { $_ -match '^JAVA_VERSION=' } | Select-Object -First 1
        if ($line -match 'JAVA_VERSION="?(\d+)' -and [int]$Matches[1] -ge 17) { $jdkHome = $c; break }
    }
    & $add 'JDK 17 с JavaFX' ([bool]$jdkHome) $jdkHome 'не найдена; нужна полная сборка (Azul Zulu FX, Liberica Full), иначе EDT не запустится с GUI'

    return $rows.ToArray()
}

function Install-EdtWorktree {
    <#
    .SYNOPSIS
        Ставит или обновляет модуль EdtWorktree.
    .PARAMETER ZipPath
        Локальный zip выпуска (EdtWorktree\<версия>\...) вместо скачивания.
    .PARAMETER Branch
        Ветка GitHub: ставится src\EdtWorktree из архива ветки.
    .PARAMETER Dev
        Ссылка (Junction) модуля на src\EdtWorktree клона, из которого запущен файл.
    .PARAMETER ReleaseUrl
        Адрес активов выпуска (по умолчанию $env:EDT_RELEASE_URL или releases/latest/download).
    .PARAMETER ModulesDir
        Каталог пользовательских модулей (по умолчанию $env:EDT_MODULES_DIR, иначе Documents\PowerShell\Modules).
    .PARAMETER NoSetup
        Не запускать edt setup, только напечатать следующий шаг.
    .PARAMETER NoPath
        Не ставить shim и не добавлять его в PATH. Запись bin старой установки 3.0 убирается из PATH всегда.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [string]$ZipPath,
        [string]$Branch,
        [switch]$Dev,
        [string]$ReleaseUrl = $(if ($env:EDT_RELEASE_URL) { $env:EDT_RELEASE_URL } else { 'https://github.com/gidragir/edt-worktree/releases/latest/download' }),
        [string]$ModulesDir = $(if ($env:EDT_MODULES_DIR) { $env:EDT_MODULES_DIR } else { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules' }),
        [switch]$NoSetup,
        [switch]$NoPath
    )

    $ErrorActionPreference = 'Stop'
    $sources = @(@($ZipPath, $Branch) | Where-Object { $_ }).Count + [int][bool]$Dev
    if ($sources -gt 1) { throw 'Ключи -ZipPath, -Branch и -Dev взаимоисключающие: укажите один источник.' }

    Write-Host '==> Установка EdtWorktree' -ForegroundColor Cyan
    $ModulesDir = [IO.Path]::GetFullPath($ModulesDir)
    $link = Join-Path $ModulesDir 'EdtWorktree'
    $pwsh = (Get-Process -Id $PID).Path

    # Источник для -Dev проверяем до любых изменений на диске.
    $devSource = $null
    if ($Dev) {
        $candidate = if ($PSScriptRoot) { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src\EdtWorktree')) } else { $null }
        if (-not $candidate -or -not (Test-Path -LiteralPath (Join-Path $candidate 'EdtWorktree.psd1'))) {
            throw '-Dev работает только при запуске scripts\install.ps1 из клона репозитория (рядом нет src\EdtWorktree).'
        }
        # Запуск через ссылку: берём реальную цель, иначе снятие ссылки отрежет собственный источник.
        $target = (Get-Item -LiteralPath $candidate -Force).ResolveLinkTarget($true)
        $devSource = if ($target) { $target.FullName } else { $candidate }
        $existingDir = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
        if ($existingDir -and -not ($existingDir.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "В $link уже установлены версии модуля. Удалите их (edt uninstall) и повторите установку с -Dev."
        }
    }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('edtwt-install-' + [guid]::NewGuid().ToString('N'))
    try {
        # 1. Распаковка zip (выпуск, локальный или архив ветки) во временный каталог.
        $moduleSource = $null
        $version = $null
        if (-not $Dev) {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $zip = Join-Path $tmp 'EdtWorktree.zip'
            if ($ZipPath) {
                Write-Host "    Источник: $ZipPath"
                Copy-Item -LiteralPath $ZipPath -Destination $zip
            } else {
                $url = if ($Branch) {
                    "https://github.com/gidragir/edt-worktree/archive/refs/heads/$Branch.zip"
                } else {
                    $ReleaseUrl.TrimEnd('/') + '/EdtWorktree.zip'
                }
                Write-Host "    Загрузка: $url"
                Get-EdtWtInstallDownload -Url $url -OutFile $zip
            }
            $expanded = Join-Path $tmp 'x'
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [IO.Compression.ZipFile]::ExtractToDirectory($zip, $expanded)
            Get-ChildItem -LiteralPath $expanded -Recurse -File | Unblock-File

            $pattern = if ($Branch) { '*\src\EdtWorktree\EdtWorktree.psd1' } else { '*\EdtWorktree\*\EdtWorktree.psd1' }
            $manifests = @(Get-ChildItem -LiteralPath $expanded -Recurse -File -Filter 'EdtWorktree.psd1' |
                Where-Object { $_.FullName -like $pattern })
            if ($manifests.Count -ne 1) { throw "В архиве не найден единственный манифест модуля ($pattern): найдено $($manifests.Count)." }
            $moduleSource = $manifests[0].DirectoryName
            $version = [string](Import-PowerShellDataFile -LiteralPath $manifests[0].FullName).ModuleVersion
            if (-not $version) { throw "В манифесте $($manifests[0].FullName) нет ModuleVersion." }
        }

        # 2. Старая ссылка модуля (3.0 или Dev) снимается без рекурсии: цель и клон не трогаются.
        if (-not (Test-Path -LiteralPath $ModulesDir)) { New-Item -ItemType Directory -Path $ModulesDir -Force | Out-Null }
        $existing = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
        if ($existing -and ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $oldTarget = if ($existing.Target) { ([string]@($existing.Target)[0]).TrimEnd('\', '/') } else { $null }
            [IO.Directory]::Delete($link)
            Write-Host "    Ссылка модуля снята: $link"
            if ($oldTarget -and (Test-Path -LiteralPath (Join-Path $oldTarget '.git')) -and
                (Test-Path -LiteralPath (Join-Path $oldTarget 'EdtWorktree.psd1'))) {
                # Корень клона 3.0: его bin был в PATH пользователя.
                $oldBin = Join-Path $oldTarget 'bin'
                if ($env:EDT_PATH_SCOPE -ne 'Process') {
                    $userPath = [string][Environment]::GetEnvironmentVariable('Path', 'User')
                    $newUser = Remove-EdtWtInstallPathEntry -PathValue $userPath -Entry $oldBin
                    if ($newUser -ne $userPath) { [Environment]::SetEnvironmentVariable('Path', $newUser, 'User') }
                }
                $env:Path = Remove-EdtWtInstallPathEntry -PathValue $env:Path -Entry $oldBin
                Write-Host "    Старая установка 3.0 снята. Клон $oldTarget больше не нужен модулю, его можно удалить" -ForegroundColor Yellow
            }
        }

        # 3. Установка.
        if ($Dev) {
            New-Item -ItemType Junction -Path $link -Target $devSource | Out-Null
            $moduleDir = $link
            Write-Host "    Junction: $link -> $devSource" -ForegroundColor Green
        } else {
            if ((Test-Path -LiteralPath (Join-Path $link 'EdtWorktree.psd1'))) {
                Write-Host "    ! В $link лежит копия модуля без каталога версии; удалите её вручную." -ForegroundColor Yellow
            }
            $moduleDir = Join-Path $link $version
            # Копия рядом, затем замена: только каталог этой версии, другие версии остаются.
            $staging = Join-Path $link ('.installing-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $link -Force | Out-Null
            Copy-Item -LiteralPath $moduleSource -Destination $staging -Recurse
            $old = Get-Item -LiteralPath $moduleDir -Force -ErrorAction SilentlyContinue
            if ($old) {
                if ($old.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    [IO.Directory]::Delete($moduleDir)
                } else {
                    Remove-Item -LiteralPath $moduleDir -Recurse -Force
                }
            }
            Move-Item -LiteralPath $staging -Destination $moduleDir
            Write-Host "    Модуль EdtWorktree $version`: $moduleDir" -ForegroundColor Green
        }

        # 4. Shim edt: только что установленным модулем, в дочернем pwsh (в этот процесс модуль не грузится).
        if (-not $NoPath) {
            $manifest = Join-Path $moduleDir 'EdtWorktree.psd1'
            $shimOut = & $pwsh -NoProfile -NonInteractive -Command {
                param($Manifest)
                $ErrorActionPreference = 'Stop'
                Import-Module $Manifest -Force -DisableNameChecking
                & (Get-Module EdtWorktree) { Install-EdtWtShim }
            } -args $manifest 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Не удалось поставить shim edt: $($shimOut | Out-String)" }
            $shimDir = [string]($shimOut | Where-Object { $_ -is [string] } | Select-Object -Last 1)
            if (-not $shimDir) { throw "Не удалось поставить shim edt: $($shimOut | Out-String)" }
            $env:Path = Add-EdtWtInstallPathEntry -PathValue $env:Path -Entry $shimDir
            Write-Host "    Shim edt: $shimDir" -ForegroundColor Green
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # 5. Проверки окружения (предупреждения, не ошибки).
    Write-Host "`n==> Проверки окружения" -ForegroundColor Cyan
    Write-Host ((Get-EdtWtInstallChecks | Format-Table -AutoSize -Wrap | Out-String -Width 200).TrimEnd())

    # 6. Первичная настройка или подсказка.
    $configPath = if ($env:EDT_CONFIG_PATH) { $env:EDT_CONFIG_PATH } else { Join-Path $env:APPDATA 'EdtWorktree\config.json' }
    $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    if (-not $NoSetup -and $interactive -and -not (Test-Path -LiteralPath $configPath)) {
        Write-Host "`n==> edt setup" -ForegroundColor Cyan
        & $pwsh -NoProfile -File (Join-Path $moduleDir 'bin\edt.ps1') setup
    } else {
        Write-Host "`nСледующий шаг: edt setup" -ForegroundColor Yellow
    }
    Write-Host "`nУстановка EdtWorktree завершена." -ForegroundColor Green
}

# --- Точка входа (файл должен парситься в Windows PowerShell 5.1) ---------------
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host 'PowerShell 7 не найден. Установите: winget install Microsoft.PowerShell, затем выполните команду установки в pwsh.' -ForegroundColor Red
    return
}
if ($env:EDT_INSTALL_NO_AUTORUN) { return }

$edtInstallArgs = @{}
if ($env:EDT_INSTALL_ZIP) { $edtInstallArgs['ZipPath'] = $env:EDT_INSTALL_ZIP }
if ($env:EDT_INSTALL_BRANCH) { $edtInstallArgs['Branch'] = $env:EDT_INSTALL_BRANCH }
if ($env:EDT_INSTALL_DEV) { $edtInstallArgs['Dev'] = $true }
if ($env:EDT_INSTALL_NOSETUP) { $edtInstallArgs['NoSetup'] = $true }
# & ([scriptblock]::Create((irm <url>))) -NoSetup: ключи вызова приходят в $args и заменяют переменные окружения.
if ($args.Count -gt 0) { Install-EdtWorktree @args } else { Install-EdtWorktree @edtInstallArgs }
