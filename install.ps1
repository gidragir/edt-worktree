#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Установщик модуля EdtWorktree (одна строка в PowerShell 7).
.DESCRIPTION
    irm https://raw.githubusercontent.com/gidragir/edt-worktree/main/install.ps1 | iex

    Клонирует репозиторий в %LOCALAPPDATA%\EdtWorktree (или использует клон, из которого
    запущен файл), делает ссылку модуля в Documents\PowerShell\Modules, добавляет bin в PATH
    пользователя и показывает проверки окружения. Повторный запуск обновляет установку.

    Под iex нет $PSScriptRoot и param(): параметры задаются переменными окружения
    EDT_INSTALL_DIR, EDT_INSTALL_BRANCH, EDT_INSTALL_NOSETUP либо ключами
    Install-EdtWorktree в вызове & ([scriptblock]::Create((irm <url>))) -NoSetup.
    Файл самодостаточен: модуль не импортируется, git вызывается напрямую.
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

    $git = Get-Command git -ErrorAction SilentlyContinue
    & $add 'git' ([bool]$git) $(if ($git) { $git.Source } else { '' }) 'winget install Git.Git'

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
    .PARAMETER InstallDir
        Каталог клона (по умолчанию %LOCALAPPDATA%\EdtWorktree).
    .PARAMETER Branch
        Ветка для git clone (по умолчанию main).
    .PARAMETER RepoUrl
        Адрес репозитория.
    .PARAMETER ModulesDir
        Каталог пользовательских модулей (по умолчанию $env:EDT_MODULES_DIR, иначе Documents\PowerShell\Modules).
    .PARAMETER NoSetup
        Не запускать edt setup, только напечатать следующий шаг.
    .PARAMETER NoPath
        Не менять PATH (пользователя и сессии).
    #>
    [CmdletBinding()]
    param(
        [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'EdtWorktree'),
        [string]$Branch = 'main',
        [string]$RepoUrl = 'https://github.com/gidragir/edt-worktree.git',
        [string]$ModulesDir = $(if ($env:EDT_MODULES_DIR) { $env:EDT_MODULES_DIR } else { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules' }),
        [switch]$NoSetup,
        [switch]$NoPath
    )

    $ErrorActionPreference = 'Stop'
    Write-Host '==> Установка EdtWorktree' -ForegroundColor Cyan

    # 1-2. PowerShell 7 проверяет точка входа; здесь - git.
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host 'git не найден. Установите: winget install Git.Git, затем повторите установку.' -ForegroundColor Red
        return
    }

    # 3. Источник: клон, из которого запущен файл, иначе InstallDir (clone / pull --ff-only).
    $source = $null
    if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'EdtWorktree.psd1'))) {
        $source = $PSScriptRoot
        # Запуск через саму ссылку модуля: берём реальную цель, иначе замена ссылки удалит свой источник.
        $srcItem = Get-Item -LiteralPath $source -Force
        $srcTarget = $srcItem.ResolveLinkTarget($true)
        if ($srcTarget) { $source = $srcTarget.FullName }
        Write-Host "    Используется клон: $source"
    } else {
        $source = $InstallDir
        if (Test-Path -LiteralPath (Join-Path $InstallDir '.git')) {
            Write-Host "    Обновление клона: $InstallDir"
            $out = & git -C $InstallDir pull --ff-only -q 2>&1
            if ($LASTEXITCODE -ne 0) { throw "git pull завершился с кодом ${LASTEXITCODE}: $out" }
        } else {
            if ((Test-Path -LiteralPath $InstallDir) -and @(Get-ChildItem -LiteralPath $InstallDir -Force).Count -gt 0) {
                throw "Каталог установки не пуст и не является клоном: $InstallDir"
            }
            Write-Host "    Клонирование $RepoUrl ($Branch) в $InstallDir"
            $out = & git clone -q --branch $Branch $RepoUrl $InstallDir 2>&1
            if ($LASTEXITCODE -ne 0) { throw "git clone завершился с кодом ${LASTEXITCODE}: $out" }
        }
    }

    # 4. Ссылка модуля: Junction, затем SymbolicLink, затем копия.
    if (-not (Test-Path -LiteralPath $ModulesDir)) { New-Item -ItemType Directory -Path $ModulesDir -Force | Out-Null }
    $link = Join-Path $ModulesDir 'EdtWorktree'
    $existing = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "    Замена существующей установки: $link" -ForegroundColor Yellow
        if ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            # Ссылка удаляется без рекурсии: содержимое цели не трогаем.
            ([IO.DirectoryInfo]$link).Delete()
        } else {
            Remove-Item -LiteralPath $link -Recurse -Force
        }
    }
    $linked = $false
    try {
        New-Item -ItemType Junction -Path $link -Target $source -ErrorAction Stop | Out-Null
        $linked = $true
        Write-Host "    Junction: $link -> $source" -ForegroundColor Green
    } catch {
        try {
            New-Item -ItemType SymbolicLink -Path $link -Target $source -ErrorAction Stop | Out-Null
            $linked = $true
            Write-Host "    SymbolicLink: $link -> $source" -ForegroundColor Green
        } catch {
            Write-Host '    Не удалось создать ссылку, выполняется копирование. edt self-update в копии не работает.' -ForegroundColor Yellow
        }
    }
    if (-not $linked) {
        New-Item -ItemType Directory -Path $link -Force | Out-Null
        foreach ($item in @(Get-ChildItem -LiteralPath $source -Force | Where-Object { $_.Name -ne '.git' })) {
            Copy-Item -LiteralPath $item.FullName -Destination $link -Recurse -Force
        }
        Write-Host "    Модуль скопирован: $link" -ForegroundColor Green
    }

    # 5. bin в PATH пользователя (без дублей) и текущей сессии.
    $binDir = Join-Path $source 'bin'
    if (-not $NoPath) {
        # EDT_PATH_SCOPE=Process (шов для тестов): реестр пользователя не читается и не пишется.
        $processOnly = ($env:EDT_PATH_SCOPE -eq 'Process')
        if (-not $processOnly) {
            $userPath = [string][Environment]::GetEnvironmentVariable('Path', 'User')
            $newPath = Add-EdtWtInstallPathEntry -PathValue $userPath -Entry $binDir
            if ($newPath -ne $userPath) {
                [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
                Write-Host "    $binDir добавлен в PATH пользователя" -ForegroundColor Green
            } else {
                Write-Host "    $binDir уже в PATH пользователя"
            }
        }
        $env:Path = Add-EdtWtInstallPathEntry -PathValue $env:Path -Entry $binDir
    }

    # 6. Проверки окружения (предупреждения, не ошибки).
    Write-Host "`n==> Проверки окружения" -ForegroundColor Cyan
    Write-Host ((Get-EdtWtInstallChecks | Format-Table -AutoSize -Wrap | Out-String -Width 200).TrimEnd())

    # 7. Первичная настройка или подсказка.
    $configPath = if ($env:EDT_CONFIG_PATH) { $env:EDT_CONFIG_PATH } else { Join-Path $env:APPDATA 'EdtWorktree\config.json' }
    $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    if (-not $NoSetup -and $interactive -and -not (Test-Path -LiteralPath $configPath)) {
        Write-Host "`n==> edt setup" -ForegroundColor Cyan
        & pwsh -NoProfile -File (Join-Path $binDir 'edt.ps1') setup
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
if ($env:EDT_INSTALL_DIR) { $edtInstallArgs['InstallDir'] = $env:EDT_INSTALL_DIR }
if ($env:EDT_INSTALL_BRANCH) { $edtInstallArgs['Branch'] = $env:EDT_INSTALL_BRANCH }
if ($env:EDT_INSTALL_NOSETUP) { $edtInstallArgs['NoSetup'] = $true }
# & ([scriptblock]::Create((irm <url>))) -NoSetup: ключи вызова приходят в $args и заменяют переменные окружения.
if ($args.Count -gt 0) { Install-EdtWorktree @args } else { Install-EdtWorktree @edtInstallArgs }
