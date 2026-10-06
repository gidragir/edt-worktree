# ==============================================================================
# EclipseLocation.ps1 - Парсинг/запись .location и управление проектами Eclipse
# ==============================================================================

Set-StrictMode -Version Latest

function Get-EdtWtLocationUri {
    <#
      Читает .location проекта Eclipse.
      Формат: 16 байт BEGIN_CHUNK, затем writeUTF (2 байта длины + строка),
      затем постоянный хвост (END_CHUNK и служебные поля).
    #>
    param([Parameter(Mandatory)][string]$LocationFile)

    $bytes = [System.IO.File]::ReadAllBytes($LocationFile)
    if ($bytes.Length -lt 20) { return $null }

    $len = ([int]$bytes[16] * 256) + [int]$bytes[17]
    if ($len -le 0 -or (18 + $len) -gt $bytes.Length) { return $null }

    $value = [System.Text.Encoding]::UTF8.GetString($bytes, 18, $len)
    return [PSCustomObject]@{
        Bytes  = $bytes
        Offset = 18
        Length = $len
        Value  = $value
    }
}

# Приватная функция: запись .location идёт внутри операции перепривязки,
# которая уже закрыта ShouldProcess вызывающей команды.
function Set-EdtWtLocationUri {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)][string]$LocationFile,
        [Parameter(Mandatory)]$Parsed,
        [Parameter(Mandatory)][string]$NewValue
    )

    $newBytes = [System.Text.Encoding]::UTF8.GetBytes($NewValue)
    $tailStart = $Parsed.Offset + $Parsed.Length

    $out = New-Object System.Collections.Generic.List[byte]
    # Нарезка массива в PowerShell даёт Object[], AddRange требует IEnumerable[byte]
    $out.AddRange([byte[]]($Parsed.Bytes[0..15]))
    $out.Add([byte](($newBytes.Length -shr 8) -band 0xFF))
    $out.Add([byte]($newBytes.Length -band 0xFF))
    $out.AddRange([byte[]]$newBytes)
    if ($tailStart -lt $Parsed.Bytes.Length) {
        $out.AddRange([byte[]]($Parsed.Bytes[$tailStart..($Parsed.Bytes.Length - 1)]))
    }

    [System.IO.File]::WriteAllBytes($LocationFile, $out.ToArray())
}

function Get-EdtWtWorkspaceProjectNames {
    param([Parameter(Mandatory)][string]$WorkspaceDir)

    $projectsDir = Join-Path $WorkspaceDir ".metadata\.plugins\org.eclipse.core.resources\.projects"
    if (-not (Test-Path -LiteralPath $projectsDir)) { return @() }
    return @(Get-ChildItem -LiteralPath $projectsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
}

function Get-EdtWtEclipseProjectName {
    param([Parameter(Mandatory)][string]$ProjectDir)

    $dotProject = Join-Path $ProjectDir ".project"
    if (Test-Path -LiteralPath $dotProject) {
        try {
            [xml]$x = Get-Content -Raw -LiteralPath $dotProject -Encoding UTF8
            $name = $x.projectDescription.name
            if ($name) { return $name.Trim() }
        } catch {
            Write-Verbose "Не удалось прочитать $dotProject, имя берётся по каталогу: $($_.Exception.Message)"
        }
    }
    return (Split-Path -Leaf $ProjectDir)
}

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

        $oldPath = $parsed.Value.Substring($prefix.Length) -replace '/', '\'

        # Уже указывает на текущий workspace/worktree — перепривязка не нужна
        if ($oldPath -like "$($WorkspaceDir.TrimEnd('\'))\*" -or $oldPath -like "$($WorktreePath.TrimEnd('\'))\*") {
            continue
        }

        $newPath = $null

        # 1. Служебные проекты внутри самого эталонного workspace (например EGit cmp)
        if ($oldPath -like "$($ReferenceWsDir.TrimEnd('\'))\*") {
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
        if ($newPath.TrimEnd('\') -ieq $oldPath.TrimEnd('\')) { continue }

        try {
            Set-EdtWtLocationUri -LocationFile $locFile -Parsed $parsed -NewValue ($prefix + ($newPath -replace '\\', '/'))
        } catch {
            throw "Не удалось перепривязать проект '$($dir.Name)' ($locFile): $($_.Exception.Message)"
        }
        Write-Host "    перепривязан проект '$($dir.Name)' -> $newPath" -ForegroundColor DarkGray
        $repaired += $dir.Name
    }

    return $repaired
}
