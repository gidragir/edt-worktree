# ==============================================================================
# EdtWorktree - управление рабочими областями 1C:EDT для git worktree
# ==============================================================================
# Загрузчик модуля: переменные, приватные помощники, публичные операции,
# автодополнение и алиасы. Логика лежит в Private/ и Public/ по файлу на функцию.
# ==============================================================================

Set-StrictMode -Version Latest

$script:EdtWtModuleRoot = $PSScriptRoot

# Порядок важен: переменные и конфигурация читаются первыми, затем остальные подсистемы.
$loadOrder = @(
    # Приватные доменные подсистемы
    (Join-Path $PSScriptRoot 'Private\Configuration.ps1')
    (Join-Path $PSScriptRoot 'Private\EclipseLocation.ps1')
    (Join-Path $PSScriptRoot 'Private\EdtProcess.ps1')
    (Join-Path $PSScriptRoot 'Private\GitWorktree.ps1')
    (Join-Path $PSScriptRoot 'Private\Workspace.ps1')

    # Публичные команды
    (Join-Path $PSScriptRoot 'Public\Invoke-EdtCommand.ps1')
    (Join-Path $PSScriptRoot 'Public\WorktreeCommands.ps1')
    (Join-Path $PSScriptRoot 'Public\ConfigCommands.ps1')
    (Join-Path $PSScriptRoot 'Public\LifecycleCommands.ps1')

    # Автодополнение
    (Join-Path $PSScriptRoot 'Completers\Register-EdtWtCompleters.ps1')
)

foreach ($file in $loadOrder) {
    if (Test-Path -LiteralPath $file) {
        . $file
    }
}

# Единственное короткое имя: подкоманды вместо отдельных команд.
Set-Alias -Name edt -Value Invoke-EdtCommand

# Прежние имена остаются временно и подсказывают замену. Функции создаются
# динамически: имена вида 'wt-open' не подчиняются правилу Глагол-Существительное,
# и объявлять полтора десятка почти одинаковых функций вручную незачем.
$script:EdtWtLegacyMap = [ordered]@{
    'wt-open'       = 'open'
    'wt-warmup'     = 'warmup'
    'wt-add'        = 'add'
    'wt-clean'      = 'remove'
    'wt-list'       = 'status'
    'edt-wt-open'   = 'open'
    'edt-wt-warmup' = 'warmup'
    'edt-wt-add'    = 'add'
    'edt-wt-clean'  = 'remove'
    'edt-wt-list'   = 'status'
}

foreach ($legacy in $script:EdtWtLegacyMap.GetEnumerator()) {
    $body = @"
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(ValueFromRemainingArguments = `$true)][string[]]`$Arguments)
`$p = @{ LegacyName = '$($legacy.Key)'; Subcommand = '$($legacy.Value)' }
if (`$Arguments) { `$p['Arguments'] = `$Arguments }
if (`$PSBoundParameters.ContainsKey('WhatIf')) { `$p['WhatIf'] = `$PSBoundParameters['WhatIf'] }
if (`$PSBoundParameters.ContainsKey('Confirm')) { `$p['Confirm'] = `$PSBoundParameters['Confirm'] }
Invoke-EdtWtLegacyCommand @p
"@
    Set-Item -Path "function:script:$($legacy.Key)" -Value ([scriptblock]::Create($body))
}

Register-EdtWtCompleters
