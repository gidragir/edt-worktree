function Get-EdtWtWorktreeDir {
    <#
      Каталог worktree ветки. Короткое имя дополняется git.branch_prefix, полное
      (со слешем) берётся как есть. Сначала спрашивается git (worktree может лежать
      где угодно), затем проверяется ожидаемый путь; при -CreateIfMissing
      недостающий worktree создаётся.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$Branch,
        [switch]$CreateIfMissing
    )

    $cfg = Get-EdtWtConfig
    $full = Resolve-EdtWtBranchName -Name $Branch -Prefix (Get-EdtWtProperty $cfg.git 'branch_prefix' '')
    $repo = Join-Path $cfg.paths.repos_root $Project
    if (-not (Test-Path -LiteralPath $repo)) { throw "Каталог проекта не найден: $repo" }

    $existing = Get-EdtWtWorktreePathForBranch -RepoPath $repo -Branch $full
    if ($existing -and (Test-Path -LiteralPath $existing)) { return $existing }

    $path = Join-Path (Join-Path $cfg.paths.worktrees_root $Project) (ConvertTo-EdtWtSafeName $full)
    if (Test-Path -LiteralPath $path) { return $path }

    if ($CreateIfMissing) {
        return (New-EdtWtWorktree -Project $Project -Branch $full)
    }

    throw "Worktree не найден: ветка '$full' проекта '$Project' (ожидался $path)"
}
