# ==============================================================================
# Поиск EDT-проектов в клоне и разбор выбора пользователя
# ==============================================================================

function Find-EdtWtEdtProjects {
    <# Ищет .project на глубину до 3 уровней (без .git); возвращает конфигурации и расширения. #>
    [OutputType([PSCustomObject[]])]
    param([Parameter(Mandatory)][string]$RepoPath)

    $kinds = @{
        'com._1c.g5.v8.dt.core.V8ConfigurationNature' = 'Configuration'
        'com._1c.g5.v8.dt.core.V8ExtensionNature'     = 'Extension'
    }
    $base = [System.IO.Path]::GetFullPath($RepoPath).TrimEnd('\', '/')
    $result = [System.Collections.Generic.List[PSCustomObject]]::new()

    $scan = {
        param([string]$Dir, [int]$Depth)
        $projectFile = Join-Path $Dir '.project'
        if (($Depth -gt 0) -and (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
            try {
                $xml = [xml](Get-Content -LiteralPath $projectFile -Raw -Encoding utf8)
                $natures = @($xml.projectDescription.natures.nature)
                $kind = $null
                foreach ($n in $natures) {
                    if ($kinds.ContainsKey([string]$n)) { $kind = $kinds[[string]$n]; break }
                }
                if ($kind) {
                    $rel = $Dir.Substring($base.Length).TrimStart('\', '/').Replace('\', '/')
                    $result.Add([PSCustomObject]@{
                            RelPath = $rel
                            Name    = [string]$xml.projectDescription.name
                            Kind    = $kind
                        })
                }
            } catch {
                Write-Verbose "Не удалось разобрать '$projectFile': $($_.Exception.Message)"
            }
        }
        if ($Depth -ge 3) { return }
        foreach ($sub in Get-ChildItem -LiteralPath $Dir -Directory -Force -ErrorAction SilentlyContinue) {
            if ($sub.Name -eq '.git') { continue }
            & $scan $sub.FullName ($Depth + 1)
        }
    }
    & $scan $base 0

    return @($result | Sort-Object -Property RelPath -Culture ([cultureinfo]::InvariantCulture) -CaseSensitive)
}

function ConvertFrom-EdtWtSelection {
    <# Разбирает выбор вида '1 3', '2-4', 'все', 'нет'; возвращает номера с 1 по возрастанию без дублей. #>
    [OutputType([int[]])]
    param(
        [AllowEmptyString()][AllowNull()][string]$Text,
        [Parameter(Mandatory)][int]$Count
    )

    $bad = "Неверный выбор '$Text': ожидаются номера 1-$Count, диапазоны (2-4), 'все' или 'нет'."
    $t = if ($null -eq $Text) { '' } else { $Text.Trim().ToLowerInvariant() }
    if ($t -in @('', 'нет', 'none')) { return [int[]]@() }
    if ($t -in @('все', 'all', '*')) { return [int[]](1..$Count) }

    $picked = [System.Collections.Generic.SortedSet[int]]::new()
    foreach ($token in ($t -split '[\s,]+' | Where-Object { $_ })) {
        if ($token -match '^(\d+)-(\d+)$') {
            $from = [int]$Matches[1]; $to = [int]$Matches[2]
            if ($from -lt 1 -or $to -gt $Count -or $from -gt $to) { throw $bad }
            foreach ($i in $from..$to) { [void]$picked.Add($i) }
        } elseif ($token -match '^\d+$') {
            $n = [int]$token
            if ($n -lt 1 -or $n -gt $Count) { throw $bad }
            [void]$picked.Add($n)
        } else {
            throw $bad
        }
    }
    return [int[]]@($picked)
}
