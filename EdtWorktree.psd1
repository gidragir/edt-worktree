@{
    RootModule        = 'EdtWorktree.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = '8f3b6f41-9d8a-4f2e-9a7c-2c6d1b5a4e10'
    Author            = 'Balter'
    Description       = 'Управление рабочими областями 1C:EDT для git worktree: прогрев эталона, клонирование, синхронизация, запуск IDE.'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        # Основная команда
        'Invoke-EdtCommand'

        # Операции (вызываются и напрямую, и через подкоманды edt)
        'Invoke-EdtWorktreeOpen'
        'Invoke-EdtWorktreeWarmup'
        'Invoke-EdtWorktreeAdd'
        'Invoke-EdtWorktreeClean'
        'Get-EdtWorktreeList'
        'Get-EdtWtContext'
        'Update-EdtWtReference'
        'Get-EdtConfig'
        'Set-EdtConfig'
        'Initialize-EdtConfig'
        'New-EdtProjectConfig'
        'Update-EdtSelf'

        # Совместимость со старыми именами
        'Invoke-EdtWtLegacyCommand'
        'wt-open'
        'wt-warmup'
        'wt-add'
        'wt-clean'
        'wt-list'
        'edt-wt-open'
        'edt-wt-warmup'
        'edt-wt-add'
        'edt-wt-clean'
        'edt-wt-list'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()

    AliasesToExport   = @(
        'edt'
    )

    PrivateData = @{
        PSData = @{
            Tags = @('1C', 'EDT', 'git-worktree')
        }
    }
}
