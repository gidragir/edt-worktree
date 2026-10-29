function Repair-EdtWtWorkspaceLocations {
    <#
      После клонирования эталона все проекты в workspace указывают на пути
      исходного (pre-prod) worktree и на каталог самого эталона. Eclipse хранит
      эти пути абсолютными, поэтому повторный `import` того же проекта из другого
      каталога падает с "В рабочей области уже существует другой проект с таким
      именем". Здесь привязки переписываются на текущий worktree и workspace.
    #>
    param(
        [Parameter(Mandatory)][string]$WorkspaceDir,
        [Parameter(Mandatory)][string]$WorktreePath,
        [Parameter(Mandatory)][string]$ReferenceWsDir
    )

    $projectsDir = Join-Path $WorkspaceDir ".metadata\.plugins\org.eclipse.core.resources\.projects"
    if (-not (Test-Path -LiteralPath $projectsDir)) { return @() }

    $prefix = 'URI//file:/'
    $repaired = @()

    foreach ($dir in (Get-ChildItem -LiteralPath $projectsDir -Directory -ErrorAction SilentlyContinue)) {
        $locFile = Join-Path $dir.FullName ".location"
        if (-not (Test-Path -LiteralPath $locFile)) { continue }

        $parsed = Get-EdtWtLocationUri -LocationFile $locFile
        if (-not $parsed -or -not $parsed.Value.StartsWith($prefix)) { continue }

        $oldPath = ConvertFrom-EdtWtEclipseLocationUri -UriValue $parsed.Value
        if (-not $oldPath) { continue }

        # Проверяем, указывает ли путь уже на текущий worktree или workspace
        $isTargetWs = $oldPath.StartsWith($WorkspaceDir.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)
        $isTargetWt = $oldPath.StartsWith($WorktreePath.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)
        # URI невалиден, если повторное кодирование декодированного пути даёт другую строку
        $hasIllegalChars = ((ConvertTo-EdtWtEclipseLocationUri -Path $oldPath) -cne $parsed.Value)
        # Если путь уже верный и формат URI валиден (нет пробелов) — перепривязка не нужна
        if (($isTargetWs -or $isTargetWt) -and -not $hasIllegalChars) {
            continue
        }

        $newPath = $null

        if ($isTargetWs -or $isTargetWt) {
            # Путь уже правильный по смыслу, но в .location сохранён невалидный URI (например, с сырыми пробелами)
            $newPath = $oldPath
        } elseif ($oldPath.StartsWith($ReferenceWsDir.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            # 1. Служебные проекты внутри самого эталонного workspace (например EGit cmp)
            $newPath = Join-Path $WorkspaceDir $oldPath.Substring($ReferenceWsDir.TrimEnd('\').Length + 1)
        } else {
            # 2. Проекты исходников: ищем самый длинный хвост пути,
            #    который существует в текущем worktree (src/cf, src/cfe, ...)
            $segments = @($oldPath -split '\\' | Where-Object { $_ })
            for ($i = 1; $i -le $segments.Count; $i++) {
                $suffix = ($segments[($segments.Count - $i)..($segments.Count - 1)]) -join '\'
                $candidate = Join-Path $WorktreePath $suffix
                if (Test-Path -LiteralPath (Join-Path $candidate ".project")) { $newPath = $candidate }
            }
        }

        if (-not $newPath) {
            Write-Host "    [warn] Не удалось перепривязать проект '$($dir.Name)': $oldPath" -ForegroundColor Yellow
            continue
        }

        $newUri = ConvertTo-EdtWtEclipseLocationUri -Path $newPath
        if ($newUri -ieq $parsed.Value) { continue }

        try {
            Set-EdtWtLocationUri -LocationFile $locFile -Parsed $parsed -NewValue $newUri
        } catch {
            throw "Не удалось перепривязать проект '$($dir.Name)' ($locFile): $($_.Exception.Message)"
        }
        Write-Host "    перепривязан проект '$($dir.Name)' -> $newPath" -ForegroundColor DarkGray
        $repaired += $dir.Name

        # Привязка EGit (.gitdir относительно старого места) после переноса ведёт
        # не туда: в worktree .git - файл, и EGit при старте удаляет её с ошибкой.
        $egit = Join-Path $dir.FullName 'org.eclipse.egit.core'
        if (-not $isTargetWs -and -not $isTargetWt -and (Test-Path -LiteralPath $egit)) {
            Remove-Item -LiteralPath $egit -Recurse -Force
        }
    }

    return $repaired
}
