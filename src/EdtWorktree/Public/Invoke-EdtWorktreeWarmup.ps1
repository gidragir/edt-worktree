function Invoke-EdtWorktreeWarmup {
    <#
    .SYNOPSIS
        Собирает эталонную рабочую область _reference из клона проекта.

    .DESCRIPTION
        Импортирует конфигурацию и рабочие расширения проекта прямо из клона
        (он должен стоять на эталонной ветке), затем проверяет все
        импортированные проекты (validate), чтобы индексы и derived-данные были
        готовы. Из эталона клонируются рабочие области веток. Прежний эталон
        сохраняется в <эталон>.previous и возвращается, если сборка не удалась.
        Занятый EDT эталон не пересобирается: процессы не закрываются.

    .PARAMETER ProjectName
        Проект из конфигурации. По умолчанию определяется по текущему каталогу.

    .EXAMPLE
        Invoke-EdtWorktreeWarmup -ProjectName my-project
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Position = 0)]
        [string]$ProjectName
    )

    $ctx = Get-EdtWtContext -ProjectName $ProjectName
    if ($null -eq $ctx) { return }

    Write-Host "==> Сборка эталона: $($ctx.ProjectId)" -ForegroundColor Green
    Write-Host "    Reference WS: $($ctx.ReferenceWsDir)" -ForegroundColor Cyan

    # 1. Эталон старого именования переименовывается, если он свободен.
    $legacyDir = Join-Path $ctx.ProjectWsRoot '_reference_preprod'
    if (-not (Test-Path -LiteralPath $ctx.ReferenceWsDir) -and (Test-Path -LiteralPath $legacyDir)) {
        $legacyBusy = @(Get-EdtWtWorkspaceProcesses -WorkspaceDir $legacyDir)
        if ($legacyBusy.Count -gt 0) {
            Write-Warning "Старый эталон '$legacyDir' занят ($(($legacyBusy | ForEach-Object { "$($_.Name):$($_.ProcessId)" }) -join ', ')), не переименован."
        } elseif ($PSCmdlet.ShouldProcess($legacyDir, 'Переименовать в _reference')) {
            Rename-Item -LiteralPath $legacyDir -NewName '_reference'
            Write-Host "    Старый эталон _reference_preprod переименован в _reference." -ForegroundColor Yellow
        }
    }

    # 2. Источник - сам клон на эталонной ветке.
    $cloneBranch = Get-EdtWtCloneBranch -RepoPath $ctx.RepoPath
    if ($cloneBranch -ne $ctx.RefBranch) {
        $shown = if ($cloneBranch) { $cloneBranch } else { '(detached HEAD)' }
        throw "Клон $($ctx.RepoPath) стоит на '$shown', эталон собирается с '$($ctx.RefBranch)'. Переключите: git -C $($ctx.RepoPath) switch $($ctx.RefBranch)"
    }
    Write-Host "    Источник:     $($ctx.RepoPath) [$($ctx.RefBranch)]" -ForegroundColor Cyan

    # 3. Занятый эталон не трогаем, процессы не закрываем.
    Assert-EdtWtReferenceFree -Context $ctx

    # 4. Батч: конфигурация, рабочие расширения, затем проверка всего импортированного.
    $cfDir = Join-Path $ctx.RepoPath ($ctx.CfProject -replace '/', '\')
    $batch = New-EdtWtBatch
    $batch.AddImport($cfDir) | Out-Null
    $projectDirs = @($cfDir)
    $imported = @()
    foreach ($rel in @($ctx.Extensions)) {
        $extDir = Join-Path $ctx.RepoPath ($rel -replace '/', '\')
        if (Test-Path -LiteralPath (Join-Path $extDir '.project')) {
            $batch.AddImport($extDir) | Out-Null
            $projectDirs += $extDir
            $imported += (Split-Path -Leaf $rel)
        } else {
            Write-Host "    [skip] Не EDT-проект или каталог отсутствует: $rel" -ForegroundColor Yellow
        }
    }
    Write-Host "    Расширения:   $(if ($imported.Count) { $imported -join ', ' } else { '<нет>' })" -ForegroundColor Cyan

    $projectNames = @($projectDirs | ForEach-Object { Get-EdtWtEclipseProjectName -ProjectDir $_ })
    $tsv = Join-Path $ctx.ReferenceWsDir "warmup_validation.tsv"
    $batch.AddValidate($projectNames, $tsv) | Out-Null
    Write-Host "    Проверки:     validate по всем импортированным, отчёт: $tsv" -ForegroundColor Cyan
    # Проверки должны отработать по-настоящему, иначе индексы не прогреются.
    $ctx.JvmArgs = ($ctx.JvmArgs -replace '\s*-DisableProjectChecks=true', '')

    # 7. Найденные, но не рабочие расширения.
    $unused = @(Get-EdtWtUnusedExtensions -Context $ctx | ForEach-Object { Split-Path -Leaf $_ })
    if ($unused.Count -gt 0) {
        Write-Host "    Не в рабочих: $($unused -join ', '). Включить: edt project ext $($ctx.ProjectId)" -ForegroundColor Yellow
    }

    if (-not $PSCmdlet.ShouldProcess($ctx.ReferenceWsDir, "Собрать эталон заново, импортировать проектов: $($batch.Commands.Count)")) {
        $batch.Print()
        return
    }

    # 5-6. Сборка с резервом прежнего эталона, затем настройки IDE.
    Invoke-EdtWtSafeWarmup -Context $ctx -Build {
        Invoke-EdtWtCli -Context $ctx -WorkspaceDir $ctx.ReferenceWsDir -Commands $batch.ToArray() -BatchName "warmup_batch.txt"
        Copy-EdtWtPreferences -Context $ctx -WorkspaceDir $ctx.ReferenceWsDir | Out-Null
    }

    Write-Host "✓ Эталон собран: $($ctx.ReferenceWsDir)" -ForegroundColor Green
}
