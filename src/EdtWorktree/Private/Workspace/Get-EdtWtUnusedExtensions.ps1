function Get-EdtWtUnusedExtensions {
    <#
      Расширения, найденные в клоне, но не включённые в рабочие (Context.Extensions).
      Возвращает относительные пути (RelPath). Нужна warmup и doctor.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)]$Context)

    $working = @(@($Context.Extensions) | Where-Object { $_ } | ForEach-Object { ($_ -replace '\\', '/').Trim('/') })
    $found = @(Find-EdtWtEdtProjects -RepoPath $Context.RepoPath | Where-Object { $_.Kind -eq 'Extension' })
    return [string[]]@($found | Where-Object { $working -inotcontains $_.RelPath } | ForEach-Object { $_.RelPath })
}
