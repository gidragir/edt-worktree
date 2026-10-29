function New-EdtWtDefaultConfig {
    <#
      Схема конфига v3 (spec 5.1) со значениями по умолчанию. null означает
      «определять автоматически при каждом запуске».
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $profileDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    $pick = {
        param($Preferred, $Fallback)
        if (Test-Path -LiteralPath $Preferred) { $Preferred } else { $Fallback }
    }

    return [PSCustomObject]@{
        version  = 3
        paths    = [PSCustomObject]@{
            repos_root      = & $pick 'D:\projects\default' (Join-Path $profileDir 'projects')
            worktrees_root  = & $pick 'D:\projects\worktree' (Join-Path $profileDir 'projects\worktree')
            workspaces_root = & $pick 'D:\workspaces\worktree' (Join-Path $profileDir 'edt-workspaces')
        }
        edt      = [PSCustomObject]@{
            cli_path     = $null
            vm_path      = $null
            prefs_source = $null
            max_heap     = $null
            gui_max_heap = $null
            extra_vmargs = ''
            timeout_sec  = 7200
        }
        git      = [PSCustomObject]@{
            remote        = 'origin'
            branch_prefix = 'feature/'
        }
        projects = [PSCustomObject]@{}
    }
}
