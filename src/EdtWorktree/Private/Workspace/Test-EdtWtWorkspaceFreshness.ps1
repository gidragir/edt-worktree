function Test-EdtWtWorkspaceFreshness {
    <#
      Сравнивает состав рабочей области с эталоном.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]$Context,
        [switch]$Quiet
    )

    $refProjects = @(Get-EdtWtWorkspaceProjectNames -WorkspaceDir $Context.ReferenceWsDir)
    $wsProjects = @(Get-EdtWtWorkspaceProjectNames -WorkspaceDir $Context.WorkspaceDir)
    $missing = @($refProjects | Where-Object { $wsProjects -notcontains $_ })

    if ($missing.Count -gt 0 -and -not $Quiet) {
        Write-Host "    [warn] Рабочая область отстала от эталона: нет проектов $($missing -join ', ')" -ForegroundColor Yellow
        Write-Host "           Быстрее пересобрать её из эталона: edt open <проект> <ветка> -Refresh" -ForegroundColor Yellow
    }

    return , $missing
}
