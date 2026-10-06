#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Удаляет модуль EdtWorktree из системы пользователя.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "==> Удаление модуля EdtWorktree" -ForegroundColor Cyan

$userDocs = [Environment]::GetFolderPath('MyDocuments')
$targetModuleDir = Join-Path $userDocs "PowerShell\Modules\EdtWorktree"

if (Test-Path -LiteralPath $targetModuleDir) {
    Remove-Item -LiteralPath $targetModuleDir -Recurse -Force
    Write-Host "    ✓ Каталог модуля удален: $targetModuleDir" -ForegroundColor Green
} else {
    Write-Host "    Каталог модуля не найден: $targetModuleDir" -ForegroundColor Gray
}

$moduleSource = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $moduleSource
$binDir = Join-Path $repoRoot "bin"

$userPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
if ($userPath) {
    $pathParts = @($userPath -split ';' | Where-Object { $_ -and $_.Trim() -and $_ -ne $binDir })
    $newPath = $pathParts -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newPath, [EnvironmentVariableTarget]::User)
    Write-Host "    ✓ Каталог $binDir удален из переменной PATH пользователя" -ForegroundColor Green
}

Write-Host "✓ Удаление завершено." -ForegroundColor Green
