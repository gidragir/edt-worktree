function Get-EdtConfig {
    <#
    .SYNOPSIS
        Возвращает сводку текущей конфигурации EdtWorktree.
    .DESCRIPTION
        Показывает пути, EDT и зарегистрированные проекты. С -Path возвращает только
        путь к файлу конфигурации.
    .PARAMETER Path
        Вернуть только путь к config.json.
    .PARAMETER AsJson
        Вернуть сводку в виде JSON.
    .EXAMPLE
        Get-EdtConfig
    .EXAMPLE
        Get-EdtConfig -Path
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject], [string])]
    param(
        [switch]$Path,
        [switch]$AsJson
    )

    $file = Get-EdtWtUserConfigPath
    if ($Path) { return $file }

    $cfg = Get-EdtWtConfig
    $edtCli = $cfg.edt.cli_path
    if (-not $edtCli) {
        $found = @(Find-EdtWtCli)
        $edtCli = if ($found.Count -gt 0) { "авто: $($found[0].Path)" } else { 'авто: не найден' }
    }

    $summary = [PSCustomObject]@{
        PSTypeName     = 'EdtWorktree.ConfigSummary'
        ConfigFile     = $file
        ReposRoot      = $cfg.paths.repos_root
        WorktreesRoot  = $cfg.paths.worktrees_root
        WorkspacesRoot = $cfg.paths.workspaces_root
        EdtCli         = $edtCli
        Projects       = @($cfg.projects.PSObject.Properties | ForEach-Object { $_.Name })
    }

    if ($AsJson) {
        return (ConvertTo-Json -InputObject $summary -Depth 5)
    }
    return $summary
}
