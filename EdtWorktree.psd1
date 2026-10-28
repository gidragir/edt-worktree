@{
    RootModule        = 'EdtWorktree.psm1'
    ModuleVersion     = '3.0.0'
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
        'Invoke-EdtSetup'
        'Get-EdtProject'
        'Add-EdtProject'
        'Set-EdtProjectExtension'
        'Set-EdtProject'
        'Remove-EdtProject'
        'Update-EdtSelf'
        'Uninstall-EdtWorktree'
        'Test-EdtEnvironment'
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
