function Get-EdtWorktreeList {
    <#
    .SYNOPSIS
        Возвращает сводку по рабочим областям 1C:EDT.

    .DESCRIPTION
        Для каждой области показывает проект, worktree, путь к исходникам,
        каталог области, признак блокировки (.metadata/.lock) и процессы,
        которые её занимают.

    .PARAMETER ProjectName
        Ограничить выборку одним проектом из projects.json.

    .EXAMPLE
        Get-EdtWorktreeList | Format-Table

    .EXAMPLE
        Get-EdtWorktreeList | Where-Object Locked -eq 'LOCK'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([string]$ProjectName)

    $cfg = Get-EdtWtConfig
    $root = ($cfg.paths.workspaces_root -replace '/', '\')

    if (-not (Test-Path -LiteralPath $root)) {
        Write-Host "Корень рабочих областей не найден: $root" -ForegroundColor Yellow
        return
    }

    $wtMap = @{}
    foreach ($prop in $cfg.projects.PSObject.Properties) {
        $pid_ = $prop.Name
        if ($ProjectName -and $pid_ -ne $ProjectName) { continue }
        $wtMap[$pid_] = @{}
    }

    $procs = @(Get-CimInstance -ClassName Win32_Process `
        -Filter "Name = '1cedt.exe' OR Name = '1cedtc.exe' OR Name = '1cedtcli.exe' OR Name = 'javaw.exe' OR Name = 'java.exe'" `
        -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine })

    $rows = @()

    foreach ($projDir in (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $pid_ = $projDir.Name
        if ($ProjectName -and $pid_ -ne $ProjectName) { continue }

        foreach ($wsDir in (Get-ChildItem -LiteralPath $projDir.FullName -Directory -ErrorAction SilentlyContinue)) {
            $wsPath = $wsDir.FullName
            $locked = Test-Path -LiteralPath (Join-Path $wsPath ".metadata\.lock")

            $matching = @($procs | Where-Object { (Test-EdtWtProcessOnWorkspace -CommandLine $_.CommandLine -WorkspaceDir $wsPath) })
            $pidList = if ($matching.Count -gt 0) { ($matching | ForEach-Object { "$($_.Name):$($_.ProcessId)" }) -join ', ' } else { '' }

            $rows += [PSCustomObject]@{
                Project   = $pid_
                Worktree  = $wsDir.Name
                Workspace = $wsPath
                Locked    = if ($locked) { 'LOCK' } else { '' }
                Processes = $pidList
            }
        }
    }

    try {
        $ctx = Get-EdtWtContext -ErrorAction SilentlyContinue
    } catch { $ctx = $null }

    if ($ctx) {
        Push-Location -LiteralPath $ctx.WorktreePath
        try { $lines = Invoke-EdtWtGit worktree list --porcelain 2>$null } finally { Pop-Location }
        $cur = $null
        $map = @{}
        foreach ($line in $lines) {
            if ($line -match '^worktree\s+(.+)$') { $cur = ($matches[1] -replace '/', '\') }
            elseif ($line -match '^branch\s+refs/heads/(.+)$') { $map[(ConvertTo-EdtWtSafeName $matches[1])] = $cur }
        }
        foreach ($r in $rows) {
            if ($r.Project -eq $ctx.ProjectId -and $map.ContainsKey($r.Worktree)) {
                $r | Add-Member -NotePropertyName CodePath -NotePropertyValue $map[$r.Worktree] -Force
            }
        }
    }

    foreach ($r in $rows) {
        if ($null -eq $r.PSObject.Properties['CodePath']) {
            $r | Add-Member -NotePropertyName CodePath -NotePropertyValue '' -Force
        }
    }

    if ($rows.Count -eq 0) {
        Write-Host "Рабочие области не найдены в $root" -ForegroundColor Yellow
        return
    }

    return $rows | Select-Object Project, Worktree, CodePath, Workspace, Locked, Processes
}
