function Add-EdtProject {
    <#
    .SYNOPSIS
        Регистрирует клон из repos_root как проект.
    .DESCRIPTION
        Находит в клоне конфигурацию и расширения EDT, выбирает рабочие расширения
        и запоминает эталонную ветку (по умолчанию текущую ветку клона).
        Без -Name обрабатываются все незарегистрированные клоны repos_root.
        В неинтерактивном сеансе вопросов нет: нужны -Extensions и, если в клоне
        несколько конфигураций, -CfProject.
    .PARAMETER Name
        Имя папки клона в repos_root.
    .PARAMETER Extensions
        'all', 'none' либо имена расширений (папка или относительный путь). Без параметра
        в интерактивном сеансе показывается нумерованный список.
    .PARAMETER RefBranch
        Эталонная ветка. По умолчанию текущая ветка клона (интерактивно с вопросом).
    .PARAMETER CfProject
        Конфигурация (папка или относительный путь), если в клоне их несколько.
    .EXAMPLE
        Add-EdtProject ka-intertop-4edt
    .EXAMPLE
        Add-EdtProject -Name ka -Extensions cfe,cfe_ad -RefBranch pre-prod
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [string]$Name,
        [string[]]$Extensions,
        [string]$RefBranch,
        [string]$CfProject
    )

    $cfg = Get-EdtWtConfig
    $reposRoot = $cfg.paths.repos_root
    $interactive = Test-EdtWtInteractive

    if ($Name) {
        Assert-EdtWtProjectName -Name $Name
        $names = @($Name)
    } else {
        $names = @()
        if (Test-Path -LiteralPath $reposRoot) {
            $names = @(Get-ChildItem -LiteralPath $reposRoot -Directory -Force |
                    Where-Object { (Test-Path -LiteralPath (Join-Path $_.FullName '.git')) -and ($null -eq $cfg.projects.PSObject.Properties[$_.Name]) } |
                    ForEach-Object { $_.Name })
        }
        if (-not $names.Count) {
            Write-Host "Нет незарегистрированных клонов в $reposRoot." -ForegroundColor Gray
            return
        }
    }

    foreach ($n in $names) {
        if ($null -ne $cfg.projects.PSObject.Properties[$n]) {
            Write-Warning "Проект '$n' уже зарегистрирован, пропущен. Изменить: edt project set / edt project ext."
            continue
        }
        $repo = Join-Path $reposRoot $n
        if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) {
            throw "Клон '$n' не найден: нет $repo (с каталогом .git). Склонируйте репозиторий в repos_root."
        }

        $found = @(Find-EdtWtEdtProjects -RepoPath $repo)
        $configs = @($found | Where-Object Kind -eq 'Configuration')
        $exts = @($found | Where-Object Kind -eq 'Extension')
        Write-Host "Проект '$n':" -ForegroundColor Cyan

        # Конфигурация
        if (-not $configs.Count) { throw "В клоне '$n' не найдена конфигурация 1С (.project с V8ConfigurationNature)." }
        if ($CfProject) {
            $cf = Resolve-EdtWtExtensionRef -Found $configs -Ref $CfProject
        } elseif ($configs.Count -eq 1) {
            $cf = [string]$configs[0].RelPath
        } elseif ($interactive) {
            for ($i = 0; $i -lt $configs.Count; $i++) { Write-Host ("  {0}. {1}" -f ($i + 1), $configs[$i].RelPath) }
            $answer = Read-EdtWtAnswer -Prompt 'Конфигурация (номер)' -Default '1'
            $idx = 0
            if (-not [int]::TryParse($answer, [ref]$idx) -or $idx -lt 1 -or $idx -gt $configs.Count) {
                throw "Неверный номер конфигурации '$answer': ожидается 1-$($configs.Count)."
            }
            $cf = [string]$configs[$idx - 1].RelPath
        } else {
            throw "В клоне '$n' несколько конфигураций ($(($configs.RelPath) -join ', ')): укажите -CfProject <путь>."
        }

        # Расширения
        $picked = $null
        if ($Extensions) {
            if ($Extensions.Count -eq 1 -and $Extensions[0] -in @('all', 'все')) {
                $picked = [string[]]@($exts.RelPath)
            } elseif ($Extensions.Count -eq 1 -and $Extensions[0] -in @('none', 'нет')) {
                $picked = [string[]]@()
            } else {
                $picked = [string[]]@($Extensions | ForEach-Object { Resolve-EdtWtExtensionRef -Found $exts -Ref $_ } | Select-Object -Unique)
            }
        } elseif (-not $exts.Count) {
            $picked = [string[]]@()
        } elseif ($interactive) {
            Write-EdtWtNumberedList -Items $exts
            $picked = Read-EdtWtExtensionChoice -Found $exts
            if ($null -eq $picked) { $picked = [string[]]@() }
        } else {
            throw "Проект '$n': неинтерактивный сеанс, укажите -Extensions all|none|<имена>. Найдены: $(($exts | ForEach-Object { Split-Path $_.RelPath -Leaf }) -join ', ')."
        }

        # Эталонная ветка
        $ref = $RefBranch
        if (-not $ref) {
            $current = Get-EdtWtCloneBranch -RepoPath $repo
            if ($interactive) {
                $ref = Read-EdtWtAnswer -Prompt 'Эталонная ветка' -Default $current
            } else {
                $ref = $current
            }
            if (-not $ref) { throw "Проект '$n': не удалось определить эталонную ветку (HEAD отсоединён?): укажите -RefBranch." }
        }

        if ($PSCmdlet.ShouldProcess($n, "Зарегистрировать проект (ветка $ref, конфигурация $cf, расширений: $(@($picked).Count))")) {
            $def = [PSCustomObject]@{
                ref_branch = $ref
                cf_project = $cf
                extensions = [string[]]@($picked)
            }
            Add-Member -InputObject $cfg.projects -MemberType NoteProperty -Name $n -Value $def
            Save-EdtWtConfig -Config $cfg | Out-Null
            Write-Host "✓ Проект '$n' зарегистрирован." -ForegroundColor Green
        }
    }
}
