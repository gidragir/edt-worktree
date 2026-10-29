function Find-EdtWtCli {
    <#
    .SYNOPSIS
        Ищет установленные версии 1C:EDT на машине.
    .DESCRIPTION
        Сканирует стандартные каталоги установки 1C:EDT и системный PATH в поисках 1cedtcli.
        Возвращает объекты с версией и путём, новейшая версия первой (сортировка по [version]).
    .PARAMETER SearchRoots
        Каталоги для поиска (по умолчанию стандартные каталоги установки).
    .PARAMETER SkipPath
        Не искать в PATH.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [string[]]$SearchRoots,
        [switch]$SkipPath
    )

    if (-not $PSBoundParameters.ContainsKey('SearchRoots')) {
        $SearchRoots = @(
            "$env:ProgramFiles\1C",
            "$env:LOCALAPPDATA\Programs\1C",
            "${env:ProgramFiles(x86)}\1C"
        )
    }

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $add = {
        param([string]$fullPath)
        if (-not $seenPaths.Add($fullPath)) { return }
        $folder = Split-Path -Parent $fullPath
        $leaf = Split-Path -Leaf $folder
        $ver = if ($leaf -match '(\d+(\.\d+)+)') { $Matches[1] } else { $null }
        $sortKey = [version]'0.0'
        if ($ver) { try { $sortKey = [version]$ver } catch { $sortKey = [version]'0.0' } }
        $results.Add([PSCustomObject]@{
            Version = if ($ver) { $ver } else { $leaf }
            Path    = $fullPath
            Folder  = $folder
            SortKey = $sortKey
        })
    }

    if (-not $SkipPath) {
        foreach ($name in @('1cedtcli.exe', '1cedtcli.bat')) {
            $cmd = Get-Command $name -ErrorAction SilentlyContinue
            if ($cmd -and (Test-Path -LiteralPath $cmd.Source)) { & $add $cmd.Source }
        }
    }

    foreach ($root in $SearchRoots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        $cliFiles = Get-ChildItem -LiteralPath $root -Filter "1cedtcli.*" -Recurse -Depth 5 -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.exe', '.bat') }
        foreach ($file in $cliFiles) { & $add $file.FullName }
    }

    return @($results | Sort-Object SortKey -Descending | Select-Object Version, Path, Folder)
}
