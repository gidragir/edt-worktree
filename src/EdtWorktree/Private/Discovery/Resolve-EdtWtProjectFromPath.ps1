function Resolve-EdtWtProjectFromPath {
    <#
      Проект по каталогу: клон или любой его worktree. Клон определяется по
      git rev-parse --git-common-dir (родитель '.git'); его родитель должен быть
      repos_root. Возвращает Name, RepoPath, Registered либо $null.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][PSCustomObject]$Config
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $null }
    $full = [System.IO.Path]::GetFullPath($Path)

    $common = Invoke-EdtWtGit -C $full rev-parse --git-common-dir 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $common) { return $null }
    $common = ([string]@($common)[0]) -replace '/', '\'
    if (-not [System.IO.Path]::IsPathRooted($common)) { $common = Join-Path $full $common }
    $common = [System.IO.Path]::GetFullPath($common).TrimEnd('\')

    $clone = if ((Split-Path -Leaf $common) -eq '.git') { Split-Path -Parent $common } else { $common }
    $parent = Split-Path -Parent $clone
    $reposRoot = Get-EdtWtProperty (Get-EdtWtProperty $Config 'paths') 'repos_root'
    if (-not $reposRoot -or -not (Test-EdtWtSamePath -A $parent -B $reposRoot)) { return $null }

    $name = Split-Path -Leaf $clone
    $projects = Get-EdtWtProperty $Config 'projects'
    $registered = ($null -ne $projects) -and ($null -ne $projects.PSObject.Properties[$name])
    return [PSCustomObject]@{
        Name       = $name
        RepoPath   = $clone
        Registered = [bool]$registered
    }
}
