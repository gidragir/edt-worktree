# ==============================================================================
# EdtWorktree - управление рабочими областями 1C:EDT для git worktree
# ==============================================================================
# Загрузчик модуля: переменные, приватные помощники, публичные операции,
# автодополнение и алиас edt. Логика лежит в Private/ и Public/ по файлу на функцию.
# ==============================================================================

Set-StrictMode -Version Latest

$script:EdtWtModuleRoot = $PSScriptRoot

# Порядок важен: переменные и конфигурация читаются первыми, затем остальные подсистемы.
$loadOrder = @(
    # Приватные доменные подсистемы
    (Join-Path $PSScriptRoot 'Private\Interaction.ps1')
    (Join-Path $PSScriptRoot 'Private\GitWorktree.ps1')
    (Join-Path $PSScriptRoot 'Private\Configuration.ps1')
    (Join-Path $PSScriptRoot 'Private\ConfigMigration.ps1')
    (Join-Path $PSScriptRoot 'Private\ProjectDiscovery.ps1')
    (Join-Path $PSScriptRoot 'Private\EclipseLocation.ps1')
    (Join-Path $PSScriptRoot 'Private\EdtProcess.ps1')
    (Join-Path $PSScriptRoot 'Private\Workspace.ps1')

    # Публичные команды
    (Join-Path $PSScriptRoot 'Public\Invoke-EdtCommand.ps1')
    (Join-Path $PSScriptRoot 'Public\WorktreeCommands.ps1')
    (Join-Path $PSScriptRoot 'Public\ConfigCommands.ps1')
    (Join-Path $PSScriptRoot 'Public\ProjectCommands.ps1')
    (Join-Path $PSScriptRoot 'Public\LifecycleCommands.ps1')
    (Join-Path $PSScriptRoot 'Public\DoctorCommand.ps1')

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

Register-EdtWtCompleters
