function Get-EdtWtWorkspaceProjectNames {
    param([Parameter(Mandatory)][string]$WorkspaceDir)

    $projectsDir = Join-Path $WorkspaceDir ".metadata\.plugins\org.eclipse.core.resources\.projects"
    if (-not (Test-Path -LiteralPath $projectsDir)) { return @() }
    return @(Get-ChildItem -LiteralPath $projectsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
}
