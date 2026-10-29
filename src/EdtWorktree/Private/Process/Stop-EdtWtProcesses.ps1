function Stop-EdtWtProcesses {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceDir)

    $procs = @(Get-EdtWtWorkspaceProcesses -WorkspaceDir $WorkspaceDir -IncludeHeadless)

    if ($procs.Count -eq 0) {
        Write-Host "    Активных процессов EDT на этой рабочей области не найдено." -ForegroundColor Gray
        return 0
    }

    foreach ($p in $procs) {
        Write-Host "    Завершение процесса $($p.Name) (PID $($p.ProcessId))..." -ForegroundColor Yellow
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1
    return $procs.Count
}
