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

function Test-EdtWtSamePath {
    <#
      Равенство путей: полный путь, без хвостовых слешей, без учёта регистра.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$A,
        [Parameter(Mandatory)][AllowEmptyString()][string]$B
    )

    if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) { return $false }
    $na = [System.IO.Path]::GetFullPath($A).TrimEnd('\', '/')
    $nb = [System.IO.Path]::GetFullPath($B).TrimEnd('\', '/')
    return [string]::Equals($na, $nb, [System.StringComparison]::OrdinalIgnoreCase)
}

function ConvertTo-EdtWtEclipseLocationUri {
    <#
      Формирует канонический URI для файла .location Eclipse.
      Формат: 'URI//file:/' + путь с прямыми слешами и экранированными пробелами (%20).
      Eclipse LocalMetaArea.readPrivateDescription парсит URI через java.net.URI.create(),
      поэтому неэкранированные пробелы вызывают IllegalArgumentException.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $normalized = $Path.TrimEnd('\') -replace '\\', '/'
    # '%' экранируется первым, иначе повторно закодируются уже вставленные последовательности.
    $escaped = $normalized.Replace('%', '%25')
    foreach ($pair in @(' ', '#', '[', ']', '{', '}', '^', '`', '"', '<', '>', '|')) {
        $escaped = $escaped.Replace($pair, ('%{0:X2}' -f [int][char]$pair))
    }    return "URI//file:/$($escaped.TrimStart('/'))"
}

function ConvertFrom-EdtWtEclipseLocationUri {
    <#
      Декодирует URI из .location Eclipse в локальный путь Windows.
      Снимает префикс 'URI//file:/' и разэкранирует percent-encoding (%20, %D0%... и т.д.).
    #>
    param([Parameter(Mandatory)][string]$UriValue)

    $prefix = 'URI//file:/'
    if (-not $UriValue.StartsWith($prefix)) {
        return $null
    }
    $raw = $UriValue.Substring($prefix.Length)
    return ([System.Uri]::UnescapeDataString($raw) -replace '/', '\')
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
    }

    return $repaired
}
