#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Запускатель edt: находит установленный модуль EdtWorktree (наибольшую версию) и передаёт ему вызов.
#>
param([Parameter(ValueFromRemainingArguments)][string[]]$Rest)

$m = Get-Module -ListAvailable -Name EdtWorktree | Sort-Object Version -Descending | Select-Object -First 1
if (-not $m) {
    [Console]::Error.WriteLine('Модуль EdtWorktree не установлен: Install-PSResource EdtWorktree')
    exit 2
}
& (Join-Path $m.ModuleBase 'bin\edt.ps1') @Rest
exit $LASTEXITCODE
