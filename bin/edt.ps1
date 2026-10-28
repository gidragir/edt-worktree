#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Точка входа edt для любых оболочек.

.DESCRIPTION
    Тонкий запуск модуля EdtWorktree без профиля оболочки:

        pwsh -NoProfile -File edt.ps1 <подкоманда> [аргументы]

    Годится для nushell, cmd, планировщика задач и CI. Разбор аргументов и вся
    логика живут в модуле; здесь только загрузка, вывод таблиц и коды возврата:
    0 - успех, 1 - ошибка выполнения (или ошибки в отчёте doctor), 2 - ошибка вызова.

.EXAMPLE
    edt.ps1 open my-project TASK-123

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
    # bin лежит в клоне модуля: сначала берём модуль рядом (ту же версию, что и этот скрипт),
    # затем найденный через PSModulePath.
    $adjacent = Join-Path $PSScriptRoot '..\EdtWorktree.psd1'
    if (Test-Path -LiteralPath $adjacent) {
        Import-Module $adjacent -Force -DisableNameChecking
    } else {
        $foundModule = Get-Module -ListAvailable -Name EdtWorktree | Select-Object -First 1
        if (-not $foundModule) {
            Write-Host "Модуль EdtWorktree не найден рядом с bin/ и в PSModulePath." -ForegroundColor Red
            exit $EXIT_USAGE
        }
        Import-Module $foundModule -Force -DisableNameChecking
    }
} catch {
    Write-Host "Не удалось загрузить модуль EdtWorktree: $($_.Exception.Message)" -ForegroundColor Red
    exit $EXIT_USAGE
}

$known = @('open', 'warmup', 'add', 'remove', 'status', 'update', 'vr', 'setup', 'project', 'config', 'doctor', 'self-update', 'uninstall', 'help')
if ($known -notcontains $Command.ToLower()) {
    Write-Host "Неизвестная подкоманда '$Command'. Доступны: $($known -join ', ')." -ForegroundColor Red
    exit $EXIT_USAGE
}

try {
    $params = @{ Command = $Command.ToLower() }
    if ($Arguments) { $params['Arguments'] = $Arguments }

    # Подкоманды-таблицы возвращают объекты: в CLI их показывают таблицей. Строки
    # (config path) выводятся как есть. Остальное (vr, open) идёт потоком, без буфера.
    $objects = @()
    if ($params['Command'] -in @('status', 'update', 'setup', 'project', 'config', 'doctor')) {
        $output = @(Invoke-EdtCommand @params)
        $objects = @($output | Where-Object { $_ -is [PSCustomObject] })
        if ($objects.Count -gt 0) {
            $objects | Format-Table -AutoSize | Out-String -Width 4096 | Write-Host
        }
        foreach ($line in @($output | Where-Object { $_ -isnot [PSCustomObject] })) {
            $line
        }
    } else {
        Invoke-EdtCommand @params
    }

    # doctor: любая строка со статусом error - код 1.
    if ($params['Command'] -eq 'doctor' -and @($objects | Where-Object { $_.Status -eq 'error' }).Count -gt 0) {
        exit $EXIT_FAILURE
    }
    # vr отдаёт код возврата vrunner как есть.
    if ($params['Command'] -eq 'vr' -and $LASTEXITCODE) { exit $LASTEXITCODE }
    exit $EXIT_OK
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    # Ошибку вызова (неизвестный ключ, не указан аргумент) отличаем от сбоя работы.
    if ($_.Exception.Message -match 'Неизвестный ключ|Неизвестная подкоманда|Не указан|Использование|Лишние аргументы') { exit $EXIT_USAGE }
    exit $EXIT_FAILURE
}
