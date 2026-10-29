function Update-EdtWtReference {
    <#
    .SYNOPSIS
        Подтягивает эталонную ветку клонов и пересобирает эталоны проектов.

    .DESCRIPTION
        Предназначена для запуска по расписанию. Для каждого проекта реестра:

          1. проверяет, что эталон не занят EDT (процессы не закрываются);
          2. в клоне <repos_root>\<проект> делает fetch и перемотку вперёд
             (merge --ff-only) ветки ref_branch с remote из git.remote;
          3. собирает эталон (Invoke-EdtWorktreeWarmup).

        Грязный клон, клон на другой ветке, занятый эталон и ошибки сборки не
        останавливают обход: проект получает статус skipped с причиной.

    .PARAMETER Project
        Какие проекты обновлять. По умолчанию - все из конфигурации.

    .PARAMETER SkipGit
        Не трогать git, только пересобрать эталоны из текущего состояния клонов.

    .EXAMPLE
        Update-EdtWtReference -WhatIf

    .EXAMPLE
        Update-EdtWtReference -Project my-project -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [string[]]$Project,

        [switch]$SkipGit
    )

    $cfg = Get-EdtWtConfig

    $knownProjects = if ($cfg.projects) { @($cfg.projects.PSObject.Properties | ForEach-Object { $_.Name }) } else { @() }
    $names = if ($Project) { $Project } else { $knownProjects }
    $remote = Get-EdtWtProperty $cfg.git 'remote' 'origin'
    $started = Get-Date
    $report = @()

    Write-Host "==> Обновление эталонов" -ForegroundColor Green

    foreach ($name in $names) {
        $row = [PSCustomObject]@{
            Project = $name
            Status  = 'skipped'
            Detail  = ''
            Seconds = 0
        }
        $stepStarted = Get-Date

        try {
            if ($name -notin $knownProjects) {
                throw "проект не зарегистрирован (edt project add $name)"
            }

            $refBranch = Get-EdtWtProperty $cfg.projects.$name 'ref_branch' 'pre-prod'
            $repo = Join-Path $cfg.paths.repos_root $name
            if (-not (Test-Path -LiteralPath $repo)) {
                throw "каталог проекта не найден: $repo"
            }

            $ctx = Get-EdtWtContext -Path $repo -ProjectName $name
            Assert-EdtWtReferenceFree -Context $ctx

            if (-not $SkipGit) {
                Write-Host "    [$name] обновление ветки $refBranch в клоне..." -ForegroundColor Cyan
                if ($PSCmdlet.ShouldProcess($repo, "git fetch и перемотка ветки $refBranch ($remote)")) {
                    $git = Update-EdtWtBranch -WorktreePath $repo -Branch $refBranch -Remote $remote
                    if (-not $git.Success) { throw $git.Message }
                    Write-Host "    [$name] $($git.Message)" -ForegroundColor Gray
                    $row.Detail = $git.Message
                }
            }

            $warmupParams = @{ ProjectName = $name }
            if ($PSBoundParameters.ContainsKey('WhatIf')) { $warmupParams['WhatIf'] = $PSBoundParameters['WhatIf'] }
            if ($PSBoundParameters.ContainsKey('Confirm')) { $warmupParams['Confirm'] = $PSBoundParameters['Confirm'] }

            Invoke-EdtWorktreeWarmup @warmupParams
            $row.Status = 'updated'
        } catch {
            $row.Status = 'skipped'
            $row.Detail = $_.Exception.Message
            Write-Host "    [$name] пропуск: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        $row.Seconds = [int]((Get-Date) - $stepStarted).TotalSeconds
        $report += $row
    }

    $total = [int]((Get-Date) - $started).TotalMinutes
    $ok = @($report | Where-Object Status -eq 'updated').Count
    Write-Host "==> Готово за $total мин: обновлено $ok из $($report.Count)" -ForegroundColor Green

    return $report
}
