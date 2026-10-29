function Update-EdtWtBranch {
    <#
      Подтягивает ветку в рабочем каталоге: fetch и перемотка вперёд.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$WorktreePath,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$Remote
    )

    Push-Location -LiteralPath $WorktreePath
    try {
        $dirty = @(Invoke-EdtWtGit status --porcelain 2>$null)
        if ($dirty.Count -gt 0) {
            return [PSCustomObject]@{ Success = $false; Message = "в каталоге ветки есть незакоммиченные изменения ($($dirty.Count) файлов)" }
        }

        $current = (Invoke-EdtWtGit rev-parse --abbrev-ref HEAD 2>$null)
        if ($current -ne $Branch) {
            return [PSCustomObject]@{ Success = $false; Message = "в каталоге ветки checkout на '$current', ожидалась '$Branch'" }
        }

        $fetch = (Invoke-EdtWtGit fetch --prune $Remote 2>&1)
        if ($LASTEXITCODE -ne 0) {
            return [PSCustomObject]@{ Success = $false; Message = "git fetch не удался: $fetch" }
        }

        $behind = (Invoke-EdtWtGit rev-list --count "HEAD..$Remote/$Branch" 2>$null)
        if (-not $behind) { $behind = '0' }
        if ($behind -eq '0') {
            return [PSCustomObject]@{ Success = $true; Message = 'ветка уже актуальна' }
        }

        $merge = (Invoke-EdtWtGit merge --ff-only "$Remote/$Branch" 2>&1)
        if ($LASTEXITCODE -ne 0) {
            return [PSCustomObject]@{ Success = $false; Message = "перемотка невозможна (нужен ручной merge): $merge" }
        }

        return [PSCustomObject]@{ Success = $true; Message = "подтянуто коммитов: $behind" }
    } finally {
        Pop-Location
    }
}
