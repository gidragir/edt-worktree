function Get-EdtWtWorktreePathForBranch {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$Branch
    )
    Push-Location -LiteralPath $RepoPath
    try {
        $lines = Invoke-EdtWtGit worktree list --porcelain 2>$null
    } finally {
        Pop-Location
    }
    if (-not $lines) { return $null }

    $current = $null
    foreach ($line in $lines) {
        if ($line -match '^worktree\s+(.+)$') {
            $current = ($matches[1] -replace '/', '\')
        } elseif ($line -match '^branch\s+refs/heads/(.+)$') {
            if ($matches[1] -eq $Branch) { return $current }
        }
    }
    return $null
}
