function Get-EdtProject {
    <#
    .SYNOPSIS
        Показывает зарегистрированные проекты.
    .DESCRIPTION
        Для каждого проекта возвращает эталонную ветку, текущую ветку клона,
        число рабочих расширений из найденных (например, 3/7) и признак наличия
        эталонной рабочей области. Если клона нет на диске, ветка выводится как '-',
        а расширения как '?'.
    .PARAMETER Name
        Имя проекта. Без параметра выводятся все проекты.
    .EXAMPLE
        Get-EdtProject | Format-Table
    .EXAMPLE
        Get-EdtProject -Name ka-intertop-4edt
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [string]$Name
    )

    $cfg = Get-EdtWtConfig
    if ($Name) {
        Get-EdtWtProjectDef -Config $cfg -Name $Name | Out-Null
        $names = @($Name)
    } else {
        $names = @($cfg.projects.PSObject.Properties | ForEach-Object { $_.Name })
    }

    $result = foreach ($n in $names) {
        $def = $cfg.projects.$n
        $repo = Join-Path $cfg.paths.repos_root $n
        $branch = Get-EdtWtCloneBranch -RepoPath $repo
        $registered = @(Get-EdtWtProperty $def 'extensions' @())
        if (Test-Path -LiteralPath $repo) {
            $found = @(Find-EdtWtEdtProjects -RepoPath $repo | Where-Object Kind -eq 'Extension')
            $ext = '{0}/{1}' -f $registered.Count, $found.Count
        } else {
            $ext = '?'
        }
        $reference = Join-Path (Join-Path $cfg.paths.workspaces_root $n) '_reference'
        [PSCustomObject]@{
            Name        = $n
            RefBranch   = [string](Get-EdtWtProperty $def 'ref_branch' '')
            CloneBranch = if ($branch) { $branch } else { '-' }
            Extensions  = $ext
            Reference   = if (Test-Path -LiteralPath $reference) { 'есть' } else { 'нет' }
            RepoPath    = $repo
        }
    }
    return @($result)
}
