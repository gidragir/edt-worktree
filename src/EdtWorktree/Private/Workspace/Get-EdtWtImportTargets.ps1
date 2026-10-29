function Get-EdtWtImportTargets {
    <#
      Каталоги проектов, которые нужно импортировать в рабочую область.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Extensions,
        [switch]$IncludeConfiguration,
        [string]$WorkspaceDir
    )

    $ws = if ($WorkspaceDir) { $WorkspaceDir } else { $Context.WorkspaceDir }
    $existing = @(Get-EdtWtWorkspaceProjectNames -WorkspaceDir $ws)

    $candidates = @()
    if ($IncludeConfiguration) {
        $candidates += (Join-Path $Context.WorktreePath $Context.CfProject)
    }
    foreach ($ext in $Extensions) {
        # Имя расширения -> путь из конфига проекта; иначе имя трактуется как путь от корня worktree.
        $rel = @($Context.Extensions) | Where-Object { (Split-Path -Leaf $_) -ieq $ext } | Select-Object -First 1
        if (-not $rel) { $rel = $ext }
        $candidates += (Join-Path $Context.WorktreePath ($rel -replace '/', '\'))
    }

    $targets = @()
    $skipped = @()

    foreach ($dir in $candidates) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir '.project'))) {
            Write-Host "    [skip] Не EDT-проект или каталог отсутствует: $dir" -ForegroundColor Yellow
            $skipped += $dir
            continue
        }

        $name = Get-EdtWtEclipseProjectName -ProjectDir $dir
        if ($existing -contains $name) {
            Write-Host "    [skip] Проект '$name' уже в рабочей области." -ForegroundColor DarkGray
            $skipped += $dir
            continue
        }

        $targets += $dir
    }

    return [PSCustomObject]@{
        Targets  = $targets
        Skipped  = $skipped
        Existing = $existing
    }
}
