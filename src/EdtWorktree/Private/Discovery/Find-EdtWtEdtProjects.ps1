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
