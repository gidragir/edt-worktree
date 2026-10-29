function Invoke-EdtWorktreeWarmup {
    <#
    .SYNOPSIS
        Собирает эталонную рабочую область _reference из клона проекта.

    .DESCRIPTION
        Сначала актуализирует клон: fetch и перемотка эталонной ветки с remote
        (git.remote). Грязный клон, клон на другой ветке или расхождение с
        remote - отказ, эталон не трогается. Затем импортирует конфигурацию и
        рабочие расширения прямо из клона и собирает все проекты (build) и
        проверяет их (validate), чтобы индексы и derived-данные были готовы.
        Сборка идёт в соседнем каталоге <эталон>.building: прежний эталон
        доступен до конца сборки и заменяется только полностью собранным.
        Из эталона клонируются рабочие области веток. Занятый EDT эталон не
        пересобирается: процессы не закрываются.

    .PARAMETER ProjectName
        Проект из конфигурации. По умолчанию определяется по текущему каталогу.

    .PARAMETER SkipGit
        Не обновлять клон: собрать эталон из текущего состояния клона.

    .EXAMPLE
        Invoke-EdtWorktreeWarmup -ProjectName my-project
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Position = 0)]
        [string]$ProjectName,

        [switch]$SkipGit
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

    # 4. Клон актуализируется до сборки: при отказе git эталон остаётся прежним.
    if ($SkipGit) {
        Write-Host "    [skip] git: клон не обновляется (-SkipGit)." -ForegroundColor Yellow
    } else {
        $remote = Get-EdtWtProperty (Get-EdtWtConfig).git 'remote' 'origin'
        if ($PSCmdlet.ShouldProcess($ctx.RepoPath, "git fetch и перемотка ветки $($ctx.RefBranch) ($remote)")) {
            $git = Update-EdtWtBranch -WorktreePath $ctx.RepoPath -Branch $ctx.RefBranch -Remote $remote
            if (-not $git.Success) { throw "Клон не обновлён, эталон не пересобирается: $($git.Message)" }
            Write-Host "    git:          $($git.Message)" -ForegroundColor Cyan
        }
    }

    # 5. Батч: конфигурация, рабочие расширения, сборка всех проектов, проверка.
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

    # import возвращает управление, как только проект открыт: без build 1cedtcli
    # закрывается посреди фонового расчёта derived-данных и проверок, и их
    # доделывает GUI при первом открытии ветки. build без имён собирает все
    # проекты рабочей области, поэтому имя проекта ему не важно.
    $batch.AddBuild() | Out-Null

    # validate (EDT 2025.2) ищет проект по имени каталога, а не по имени из .project:
    # при расхождении он заново создаёт проект на том же месте и падает с
    # "перекрывается с расположением другого проекта". Такие проекты не проверяются.
    $allNames = @()
    $projectNames = @()
    $unchecked = @()
    foreach ($dir in $projectDirs) {
        $name = Get-EdtWtEclipseProjectName -ProjectDir $dir
        $allNames += $name
        $folder = Split-Path -Leaf $dir
        if ($name -ceq $folder) { $projectNames += $name } else { $unchecked += "$name (каталог $folder)" }
    }
    $buildDir = "$($ctx.ReferenceWsDir).building"
    if ($projectNames.Count -gt 0) {
        $batch.AddValidate($projectNames, (Join-Path $buildDir "warmup_validation.tsv")) | Out-Null
        Write-Host "    Проверки:     build, validate: $($projectNames -join ', ')" -ForegroundColor Cyan
    } else {
        Write-Host "    Проверки:     build" -ForegroundColor Cyan
    }
    if ($unchecked.Count -gt 0) {
        Write-Host "    [skip] validate: имя проекта не совпадает с каталогом, проверяется только сборкой: $($unchecked -join ', ')" -ForegroundColor Yellow
    }
    # Проверки должны отработать по-настоящему, иначе индексы не прогреются.
    $ctx.JvmArgs = ($ctx.JvmArgs -replace '\s*-DisableProjectChecks=true', '')

    # 6. Найденные, но не рабочие расширения.
    $unused = @(Get-EdtWtUnusedExtensions -Context $ctx | ForEach-Object { Split-Path -Leaf $_ })
    if ($unused.Count -gt 0) {
        Write-Host "    Не в рабочих: $($unused -join ', '). Включить: edt project ext $($ctx.ProjectId)" -ForegroundColor Yellow
    }

    if (-not $PSCmdlet.ShouldProcess($ctx.ReferenceWsDir, "Собрать эталон заново (команд 1cedtcli: $($batch.Commands.Count))")) {
        $batch.Print()
        return
    }

    # 7. Сборка рядом с прежним эталоном; на место он встаёт только собранным,
    #    с настройками IDE и отметкой, с какого коммита собран.
    $commit = (Invoke-EdtWtGit -C $ctx.RepoPath rev-parse HEAD 2>$null)
    Invoke-EdtWtSafeWarmup -Context $ctx -Build {
        param($dir)
        Invoke-EdtWtCli -Context $ctx -WorkspaceDir $dir -Commands $batch.ToArray() -BatchName "warmup_batch.txt"
        $missing = Get-EdtWtUnbuiltProjects -WorkspaceDir $dir -ProjectNames $allNames
        if ($missing.Count -gt 0) {
            throw "Эталон собран не полностью: нет результатов проверки проектов $($missing -join ', ')."
        }
        Copy-EdtWtPreferences -Context $ctx -WorkspaceDir $dir | Out-Null
        $stamp = [ordered]@{
            branch   = $ctx.RefBranch
            commit   = "$commit"
            built_at = (Get-Date).ToString('o')
            projects = [string[]]$allNames
        }
        [System.IO.File]::WriteAllText((Join-Path $dir $script:EdtWtReferenceStampName), ($stamp | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
    }

    Write-Host "✓ Эталон собран: $($ctx.ReferenceWsDir) [$($ctx.RefBranch) $("$commit".Substring(0, [Math]::Min(9, "$commit".Length)))]" -ForegroundColor Green
}
