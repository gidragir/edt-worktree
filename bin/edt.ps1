#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Точка входа edt для любых оболочек.

.DESCRIPTION
    Тонкий запуск модуля EdtWorktree без профиля оболочки:

        pwsh -NoProfile -File edt.ps1 <подкоманда> [аргументы]

    Годится для nushell, cmd, планировщика задач и CI. Разбор аргументов и вся
    логика живут в модуле; здесь только загрузка и коды возврата.

.EXAMPLE
    edt.ps1 open my-project TASK-123 -GuiMaxHeap 12g

.EXAMPLE
    edt.ps1 status
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = 'help',

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Коды возврата: 0 успех, 1 ошибка выполнения, 2 ошибка вызова.
$EXIT_OK = 0
$EXIT_FAILURE = 1
$EXIT_USAGE = 2

try {
    $foundModule = Get-Module -ListAvailable -Name EdtWorktree | Select-Object -First 1
    if ($foundModule) {
        Import-Module $foundModule -Force -DisableNameChecking
    } else {
        $candidatePaths = @(
            (Join-Path $PSScriptRoot "..\EdtWorktree.psd1"),
            (Join-Path $PSScriptRoot "..\powershell\modules\EdtWorktree\EdtWorktree.psd1"),
            (Join-Path $PSScriptRoot "..\src\EdtWorktree\EdtWorktree.psd1")
        )
        $modulePath = $null
        foreach ($cp in $candidatePaths) {
            if (Test-Path -LiteralPath $cp) { $modulePath = $cp; break }
        }
        if (-not $modulePath) {
            Write-Host "Модуль EdtWorktree не найден в PSModulePath или рядом с bin/." -ForegroundColor Red
            exit $EXIT_USAGE
        }
        Import-Module $modulePath -Force -DisableNameChecking
    }
} catch {
    Write-Host "Не удалось загрузить модуль EdtWorktree: $($_.Exception.Message)" -ForegroundColor Red
    exit $EXIT_USAGE
}

$known = @('open', 'warmup', 'add', 'remove', 'status', 'update', 'self-update', 'vr', 'init', 'config', 'help')
if ($known -notcontains $Command.ToLower()) {
    Write-Host "Неизвестная подкоманда '$Command'. Доступны: $($known -join ', ')." -ForegroundColor Red
    exit $EXIT_USAGE
}

try {
    $params = @{ Command = $Command.ToLower() }
    if ($Arguments) { $params['Arguments'] = $Arguments }

    # status и config возвращают объекты: в CLI их нужно показать таблицей.
    if ($params['Command'] -in @('status', 'update', 'config')) {
        Invoke-EdtCommand @params | Format-Table -AutoSize
    } else {
        Invoke-EdtCommand @params
    }
    # vr отдаёт код возврата vrunner как есть.
    if ($params['Command'] -eq 'vr' -and $LASTEXITCODE) { exit $LASTEXITCODE }
    exit $EXIT_OK
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    # Ошибку вызова (неизвестный ключ, не указан аргумент) отличаем от сбоя работы.
    if ($_.Exception.Message -match 'Неизвестный ключ|Не указан|не найден') { exit $EXIT_USAGE }
    exit $EXIT_FAILURE
}
