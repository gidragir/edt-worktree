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
        Set-EdtWtProjectProperty -Def $def -Name 'extensions' -Value ([string[]]@($new))
        Save-EdtWtConfig -Config $cfg | Out-Null
        Write-Host "✓ Рабочие расширения проекта '$Name': $(@($new).Count)." -ForegroundColor Green
    }
}
