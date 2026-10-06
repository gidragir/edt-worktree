#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Установщик модуля EdtWorktree для разработчика.
.DESCRIPTION
    1. Создает символическую ссылку (или копирует) модуль в пользовательский PSModulePath:
       Documents\PowerShell\Modules\EdtWorktree
    2. Добавляет каталог bin в переменную окружения PATH пользователя (для edt.cmd и edt.ps1).
    3. Запускает интерактивный мастер первичной настройки Initialize-EdtConfig.
.PARAMETER NonInteractive
    Не запускать интерактивный диалог настройки.
.PARAMETER CopyOnly
    Копировать файлы вместо создания символической ссылки.
#>
[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [switch]$CopyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "==> Установка модуля EdtWorktree" -ForegroundColor Cyan

# 1. Определение путей
$scriptsDir = $PSScriptRoot
$repoRoot = Split-Path -Parent $scriptsDir

$moduleSource = $repoRoot
if (-not (Test-Path -LiteralPath (Join-Path $moduleSource "EdtWorktree.psd1"))) {
    if (Test-Path -LiteralPath (Join-Path $repoRoot "src\EdtWorktree\EdtWorktree.psd1")) {
        $moduleSource = Join-Path $repoRoot "src\EdtWorktree"
    } elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot "..\EdtWorktree.psd1")) {
        $moduleSource = Split-Path -Parent $PSScriptRoot
    }
}

$userDocs = [Environment]::GetFolderPath('MyDocuments')
$targetModuleBase = Join-Path $userDocs "PowerShell\Modules"
$targetModuleDir = Join-Path $targetModuleBase "EdtWorktree"

if (-not (Test-Path -LiteralPath $targetModuleBase)) {
    New-Item -ItemType Directory -Path $targetModuleBase -Force | Out-Null
}

# 2. Создание ссылки или копирование
if (Test-Path -LiteralPath $targetModuleDir) {
    Write-Host "    Обнаружена существующая установка в $targetModuleDir. Обновление..." -ForegroundColor Yellow
    Remove-Item -LiteralPath $targetModuleDir -Recurse -Force
}

$installedAsSymlink = $false
if (-not $CopyOnly) {
    # 1. Попытка создания Junction (работает без прав администратора и Developer Mode на Windows)
    try {
        New-Item -ItemType Junction -Path $targetModuleDir -Target $moduleSource -Force -ErrorAction Stop | Out-Null
        $installedAsSymlink = $true
        Write-Host "    ✓ Создана связь (Junction): $targetModuleDir -> $moduleSource" -ForegroundColor Green
    } catch {
        # 2. Попытка создания SymbolicLink
        try {
            New-Item -ItemType SymbolicLink -Path $targetModuleDir -Target $moduleSource -Force -ErrorAction Stop | Out-Null
            $installedAsSymlink = $true
            Write-Host "    ✓ Создана символическая ссылка: $targetModuleDir -> $moduleSource" -ForegroundColor Green
        } catch {
            Write-Host "    Не удалось создать ссылку (Junction/Symlink). Выполняется копирование..." -ForegroundColor Yellow
        }
    }
}

if (-not $installedAsSymlink) {
    Copy-Item -LiteralPath $moduleSource -Destination $targetModuleDir -Recurse -Force
    Write-Host "    ✓ Модуль скопирован в $targetModuleDir" -ForegroundColor Green
}

# 3. Добавление bin в User PATH
$binDir = Join-Path $repoRoot "bin"
if (-not (Test-Path -LiteralPath $binDir)) {
    $binDir = Join-Path $moduleSource "bin"
}

if (Test-Path -LiteralPath $binDir) {
    $userPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
    $pathParts = @($userPath -split ';' | Where-Object { $_ -and $_.Trim() })
    if ($pathParts -notcontains $binDir) {
        $newPath = ($pathParts + $binDir) -join ';'
        [Environment]::SetEnvironmentVariable("Path", $newPath, [EnvironmentVariableTarget]::User)
        $env:Path = "$env:Path;$binDir"
        Write-Host "    ✓ Каталог $binDir добавлен в переменную PATH пользователя" -ForegroundColor Green
    } else {
        Write-Host "    Каталог $binDir уже присутствует в PATH" -ForegroundColor Gray
    }
}

# 4. Проверка доступности модуля
Write-Host "`n==> Проверка импорта модуля..." -ForegroundColor Cyan
try {
    Import-Module EdtWorktree -Force -ErrorAction Stop
    Write-Host "    ✓ Модуль EdtWorktree успешно загружен" -ForegroundColor Green
} catch {
    Write-Host "    ✗ Ошибка импорта: $($_.Exception.Message)" -ForegroundColor Red
}

# 5. Первичная настройка
if (-not $NonInteractive) {
    Initialize-EdtConfig
} else {
    Write-Host "`nДля первоначальной настройки запустите: edt config init" -ForegroundColor Yellow
}

Write-Host "`n✓ Установка EdtWorktree завершена!" -ForegroundColor Green
