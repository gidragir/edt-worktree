function Get-EdtWtCloneBranch {
    <# Текущая ветка клона; $null, если клона нет или HEAD отсоединён. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$RepoPath)

    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) { return $null }
    $branch = Invoke-EdtWtGit -C $RepoPath branch --show-current 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace("$branch")) { return $null }
    return "$branch".Trim()
}
