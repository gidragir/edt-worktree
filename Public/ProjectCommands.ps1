# ==============================================================================
# ProjectCommands.ps1 - Публичные команды реестра проектов: edt project ...
# ==============================================================================

Set-StrictMode -Version Latest

# ------------------------------------------------------------------------------
# Внутренние помощники
# ------------------------------------------------------------------------------

function Resolve-EdtWtExtensionRef {
    <#
      Сопоставляет ссылку (имя папки 'cfe_ad' либо относительный путь 'src/cfe_ad')
      с найденным EDT-проектом и возвращает его RelPath. Неизвестное или
      неоднозначное имя - ошибка со списком найденных.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyCollection()][object[]]$Found = @(),
        [Parameter(Mandatory)][string]$Ref
    )

    $Found = @($Found)
    $norm = $Ref.Trim().Replace('\', '/').Trim('/')
    $list = if ($Found.Count) { ($Found | ForEach-Object { "$(Split-Path $_.RelPath -Leaf) ($($_.RelPath))" }) -join ', ' } else { 'ничего' }

    $byPath = @($Found | Where-Object { $_.RelPath -ieq $norm })
    if ($byPath.Count -eq 1) { return [string]$byPath[0].RelPath }

    $byLeaf = @($Found | Where-Object { (Split-Path $_.RelPath -Leaf) -ieq $norm })
    if ($byLeaf.Count -eq 1) { return [string]$byLeaf[0].RelPath }
    if ($byLeaf.Count -gt 1) {
        throw "Имя '$Ref' неоднозначно: подходят $(($byLeaf.RelPath) -join ', '). Укажите относительный путь."
    }
    throw "Проект EDT '$Ref' не найден в клоне. Найдены: $list."
}

function Get-EdtWtCloneBranch {
    <# Текущая ветка клона; $null, если клона нет или HEAD отсоединён. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$RepoPath)

    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) { return $null }
    $branch = Invoke-EdtWtGit -C $RepoPath branch --show-current 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace("$branch")) { return $null }
    return "$branch".Trim()
}

function Assert-EdtWtProjectName {
    <# Имя проекта - имя папки клона, не путь. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -match '[\\/:]' -or $Name -in @('.', '..')) {
        throw "Недопустимое имя проекта '$Name': это имя папки клона в repos_root, а не путь."
    }
}

function Write-EdtWtNumberedList {
    <# Печатает нумерованный список найденных проектов; отмеченные помечаются [x]. #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Items = @(),
        [string[]]$Marked = @()
    )

    for ($i = 0; $i -lt @($Items).Count; $i++) {
        $mark = if ($Items[$i].RelPath -in $Marked) { '[x]' } else { '[ ]' }
        Write-Host ("  {0} {1,2}. {2}  ({3})" -f $mark, ($i + 1), (Split-Path $Items[$i].RelPath -Leaf), $Items[$i].RelPath)
    }
}

function Read-EdtWtExtensionChoice {
    <# Спрашивает номера расширений. $null - ответ пустой (ничего не менять). #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowEmptyCollection()][object[]]$Found = @(),
        [AllowEmptyString()][string]$Default
    )

    $answer = Read-EdtWtAnswer -Prompt 'Рабочие расширения (номера через пробел, диапазон 2-4, "все", "нет")' -Default $Default
    if ([string]::IsNullOrWhiteSpace($answer)) { return $null }
    $picked = ConvertFrom-EdtWtSelection -Text $answer -Count @($Found).Count
    return [string[]]@($picked | ForEach-Object { $Found[$_ - 1].RelPath })
}

# ------------------------------------------------------------------------------
# Публичные команды
# ------------------------------------------------------------------------------

function Get-EdtProject {
    <#
    .SYNOPSIS
        Показывает зарегистрированные проекты.
    .DESCRIPTION
        Для каждого проекта возвращает эталонную ветку, текущую ветку клона,
        число рабочих расширений из найденных (например, 3/7) и признак наличия
        эталонной рабочей области. Если клона нет на диске, ветка выводится как '-',
        а расширения как '?'.
    .PARAMETER Name
        Имя проекта. Без параметра выводятся все проекты.
    .EXAMPLE
        Get-EdtProject | Format-Table
    .EXAMPLE
        Get-EdtProject -Name ka-intertop-4edt
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [string]$Name
    )

    $cfg = Get-EdtWtConfig
    if ($Name) {
        Get-EdtWtProjectDef -Config $cfg -Name $Name | Out-Null
        $names = @($Name)
    } else {
        $names = @($cfg.projects.PSObject.Properties | ForEach-Object { $_.Name })
    }

    $result = foreach ($n in $names) {
        $def = $cfg.projects.$n
        $repo = Join-Path $cfg.paths.repos_root $n
        $branch = Get-EdtWtCloneBranch -RepoPath $repo
        $registered = @(Get-EdtWtProperty $def 'extensions' @())
        if (Test-Path -LiteralPath $repo) {
            $found = @(Find-EdtWtEdtProjects -RepoPath $repo | Where-Object Kind -eq 'Extension')
            $ext = '{0}/{1}' -f $registered.Count, $found.Count
        } else {
            $ext = '?'
        }
        $reference = Join-Path (Join-Path $cfg.paths.workspaces_root $n) '_reference'
        [PSCustomObject]@{
            Name        = $n
            RefBranch   = [string](Get-EdtWtProperty $def 'ref_branch' '')
            CloneBranch = if ($branch) { $branch } else { '-' }
            Extensions  = $ext
            Reference   = if (Test-Path -LiteralPath $reference) { 'есть' } else { 'нет' }
            RepoPath    = $repo
        }
    }
    return @($result)
}

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

function Set-EdtProjectExtension {
    <#
    .SYNOPSIS
        Меняет набор рабочих расширений проекта.
    .DESCRIPTION
        С -Change вносит точечные правки без диалога: '+имя' добавляет, '-имя' убирает.
        Имя - папка расширения (cfe_ad) или относительный путь (src/cfe_ad).
        Без -Change в интерактивном сеансе показывает список найденных расширений
        с отметками [x]; введённые номера заменяют набор, пустой ответ оставляет как есть.
    .PARAMETER Name
        Имя зарегистрированного проекта.
    .PARAMETER Change
        Правки вида '+cfe_new', '-cfe_old'.
    .EXAMPLE
        Set-EdtProjectExtension ka -Change '+cfe_new','-cfe_old'
    .EXAMPLE
        Set-EdtProjectExtension ka
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [string[]]$Change
    )

    $cfg = Get-EdtWtConfig
    $def = Get-EdtWtProjectDef -Config $cfg -Name $Name
    $repo = Join-Path $cfg.paths.repos_root $Name
    if (-not (Test-Path -LiteralPath $repo)) { throw "Клон проекта '$Name' не найден: $repo." }

    $found = @(Find-EdtWtEdtProjects -RepoPath $repo | Where-Object Kind -eq 'Extension')
    $current = [string[]]@(Get-EdtWtProperty $def 'extensions' @())

    if ($Change) {
        $set = [System.Collections.Generic.List[string]]::new()
        $set.AddRange([string[]]$current)
        foreach ($item in $Change) {
            $text = $item.Trim()
            if ($text -notmatch '^([+-])(.+)$') {
                throw "Правка '$item' неверна: ожидается '+имя' или '-имя'."
            }
            $sign = $Matches[1]
            $ref = $Matches[2]
            if ($sign -eq '-') {
                # Убрать можно и расширение, которого уже нет на диске.
                $rel = $null
                try { $rel = Resolve-EdtWtExtensionRef -Found $found -Ref $ref } catch {
                    $norm = $ref.Trim().Replace('\', '/').Trim('/')
                    $rel = $set | Where-Object { $_ -ieq $norm -or (Split-Path $_ -Leaf) -ieq $norm } | Select-Object -First 1
                    if (-not $rel) { throw }
                }
                [void]$set.RemoveAll([Predicate[string]] { param($s) $s -ieq $rel })
            } else {
                $rel = Resolve-EdtWtExtensionRef -Found $found -Ref $ref
                if (-not ($set | Where-Object { $_ -ieq $rel })) { $set.Add($rel) }
            }
        }
        $new = [string[]]$set.ToArray()
    } elseif (Test-EdtWtInteractive) {
        Write-EdtWtNumberedList -Items $found -Marked $current
        $new = Read-EdtWtExtensionChoice -Found $found
        if ($null -eq $new) {
            Write-Host 'Набор расширений не изменён.' -ForegroundColor Gray
            return
        }
    } else {
        throw "Проект '$Name': неинтерактивный сеанс, укажите -Change '+имя','-имя'. Найдены: $(($found | ForEach-Object { Split-Path $_.RelPath -Leaf }) -join ', ')."
    }

    if ($PSCmdlet.ShouldProcess($Name, "Рабочие расширения: $(@($new) -join ', ')")) {
        $def.extensions = [string[]]@($new)
        Save-EdtWtConfig -Config $cfg | Out-Null
        Write-Host "✓ Рабочие расширения проекта '$Name': $(@($new).Count)." -ForegroundColor Green
    }
}

function Set-EdtProject {
    <#
    .SYNOPSIS
        Меняет эталонную ветку или конфигурацию проекта.
    .PARAMETER Name
        Имя зарегистрированного проекта.
    .PARAMETER RefBranch
        Новая эталонная ветка.
    .PARAMETER CfProject
        Конфигурация (папка или относительный путь), найденная в клоне.
    .EXAMPLE
        Set-EdtProject ka -RefBranch pre-prod
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [string]$RefBranch,
        [string]$CfProject
    )

    if (-not $RefBranch -and -not $CfProject) { throw 'Укажите -RefBranch <ветка> и/или -CfProject <путь>.' }

    $cfg = Get-EdtWtConfig
    $def = Get-EdtWtProjectDef -Config $cfg -Name $Name

    $cf = $null
    if ($CfProject) {
        $repo = Join-Path $cfg.paths.repos_root $Name
        if (-not (Test-Path -LiteralPath $repo)) { throw "Клон проекта '$Name' не найден: $repo." }
        $configs = @(Find-EdtWtEdtProjects -RepoPath $repo | Where-Object Kind -eq 'Configuration')
        $cf = Resolve-EdtWtExtensionRef -Found $configs -Ref $CfProject
    }

    $what = @()
    if ($RefBranch) { $what += "ветка $RefBranch" }
    if ($cf) { $what += "конфигурация $cf" }
    if ($PSCmdlet.ShouldProcess($Name, "Изменить: $($what -join ', ')")) {
        if ($RefBranch) { $def.ref_branch = $RefBranch }
        if ($cf) { $def.cf_project = $cf }
        Save-EdtWtConfig -Config $cfg | Out-Null
        Write-Host "✓ Проект '$Name' обновлён." -ForegroundColor Green
    }
}

function Remove-EdtProject {
    <#
    .SYNOPSIS
        Убирает проект из конфига.
    .DESCRIPTION
        Клон, рабочие области и эталон на диске не затрагиваются.
    .PARAMETER Name
        Имя зарегистрированного проекта.
    .EXAMPLE
        Remove-EdtProject ka
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name
    )

    $cfg = Get-EdtWtConfig
    Get-EdtWtProjectDef -Config $cfg -Name $Name | Out-Null

    if ($PSCmdlet.ShouldProcess($Name, 'Убрать проект из конфига (файлы не удаляются)')) {
        $cfg.projects.PSObject.Properties.Remove($Name)
        Save-EdtWtConfig -Config $cfg | Out-Null
        Write-Host "✓ Проект '$Name' убран из конфига; файлы не тронуты." -ForegroundColor Green
    }
}
