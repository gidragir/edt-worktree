#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Прогоняет тесты Pester и статический анализ модуля EdtWorktree.

.DESCRIPTION
    Запускается без профиля оболочки, поэтому годится и для локальной проверки,
    и для CI:

        pwsh -NoProfile -File Invoke-EdtWtChecks.ps1

    Код возврата 0 - всё чисто, 1 - есть провалившиеся тесты или замечания
    анализатора.

.PARAMETER SkipAnalyzer
    Пропустить PSScriptAnalyzer (например, если он не установлен).
#>
[CmdletBinding()]
param(
    [switch]$SkipAnalyzer
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = $PSScriptRoot
$failed = 0

# Если git не в PATH (при запуске под pwsh -NoProfile), ищем в стандартных путях
if (-not (Get-Command 'git' -ErrorAction SilentlyContinue)) {
    foreach ($gitDir in @("${env:ProgramFiles}\Git\cmd", "${env:ProgramFiles(x86)}\Git\cmd")) {
        if (Test-Path (Join-Path $gitDir "git.exe")) {
            $env:Path = "$gitDir;$env:Path"
            break
        }
    }
}

Write-Host '==> Pester' -ForegroundColor Cyan
Import-Module Pester -MinimumVersion 5.0.0
$cfg = New-PesterConfiguration
$cfg.Run.Path = Join-Path $moduleRoot 'Tests'
$cfg.Run.PassThru = $true
$cfg.Output.Verbosity = 'Normal'
$result = Invoke-Pester -Configuration $cfg

Write-Host "    пройдено: $($result.PassedCount), провалено: $($result.FailedCount), пропущено: $($result.SkippedCount)"
if ($result.FailedCount -gt 0) { $failed = 1 }

if (-not $SkipAnalyzer) {
    Write-Host '==> PSScriptAnalyzer' -ForegroundColor Cyan
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        Write-Host '    не установлен, пропуск' -ForegroundColor Yellow
    } else {
        Import-Module PSScriptAnalyzer
        $settings = Join-Path $moduleRoot 'PSScriptAnalyzerSettings.psd1'
        $issues = @(Invoke-ScriptAnalyzer -Path $moduleRoot -Recurse -Severity Error, Warning -Settings $settings)

        # Профиль оболочки (если есть) проверяется теми же правилами.
        $dotfilesProfile = Join-Path $HOME '.config\powershell\conf.d\08-edt-worktree.ps1'
        if (Test-Path -LiteralPath $dotfilesProfile) {
            $issues += @(Invoke-ScriptAnalyzer -Path $dotfilesProfile -Severity Error, Warning -Settings $settings)
        }

        if ($issues.Count -eq 0) {
            Write-Host '    замечаний нет' -ForegroundColor Green
        } else {
            $failed = 1
            $issues | ForEach-Object {
                Write-Host ("    {0} | {1}:{2} | {3}" -f $_.RuleName, (Split-Path -Leaf $_.ScriptPath), $_.Line, $_.Message) -ForegroundColor Yellow
            }
        }
    }
}

if ($failed -eq 0) {
    Write-Host '✓ Проверки пройдены' -ForegroundColor Green
} else {
    Write-Host '✗ Проверки не пройдены' -ForegroundColor Red
}
exit $failed
