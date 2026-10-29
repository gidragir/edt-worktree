#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Прогоняет тесты Pester и статический анализ модуля EdtWorktree.

.DESCRIPTION
    Запускается без профиля оболочки, поэтому годится и для локальной проверки,
    и для CI:

        pwsh -NoProfile -File scripts/Invoke-EdtWtChecks.ps1

    Код возврата 0 - всё чисто, 1 - есть провалившиеся тесты или замечания
    анализатора.

.PARAMETER SkipAnalyzer
    Пропустить PSScriptAnalyzer (например, если он не установлен).

.PARAMETER ModulePath
    Манифест модуля, над которым гонять тесты (например, собранный out\EdtWorktree\...\EdtWorktree.psd1).
    На время прогона выставляется в EDT_TEST_MODULE; по умолчанию - src\EdtWorktree\EdtWorktree.psd1.
    Анализатор в любом случае идёт по src, scripts и Tests.
#>
[CmdletBinding()]
param(
    [switch]$SkipAnalyzer,
    [string]$ModulePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
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
if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.0.0' })) {
    Write-Host 'Нужен Pester 5: Install-Module Pester -MinimumVersion 5 -Scope CurrentUser -Force -SkipPublisherCheck' -ForegroundColor Red
    exit 1
}
Import-Module Pester -MinimumVersion 5.0.0
$cfg = New-PesterConfiguration
$cfg.Run.Path = Join-Path $repoRoot 'Tests'
$cfg.Run.PassThru = $true
$cfg.Output.Verbosity = 'Normal'
$prevTestModule = $env:EDT_TEST_MODULE
if ($ModulePath) { $env:EDT_TEST_MODULE = (Resolve-Path -LiteralPath $ModulePath).Path }
try {
    $result = Invoke-Pester -Configuration $cfg
} finally {
    $env:EDT_TEST_MODULE = $prevTestModule
}

Write-Host "    пройдено: $($result.PassedCount), провалено: $($result.FailedCount), пропущено: $($result.SkippedCount)"
if ($result.FailedCount -gt 0) { $failed = 1 }

if (-not $SkipAnalyzer) {
    Write-Host '==> PSScriptAnalyzer' -ForegroundColor Cyan
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        Write-Host '    не установлен, пропуск' -ForegroundColor Yellow
    } else {
        Import-Module PSScriptAnalyzer
        $settings = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
        $issues = @(foreach ($dir in 'src', 'scripts', 'Tests') {
            Invoke-ScriptAnalyzer -Path (Join-Path $repoRoot $dir) -Recurse -Severity Error, Warning -Settings $settings
        })

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
