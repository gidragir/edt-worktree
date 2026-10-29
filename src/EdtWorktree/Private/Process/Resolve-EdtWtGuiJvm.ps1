function Resolve-EdtWtGuiJvm {
    <#
      Выбор JVM для GUI (spec 7.3): edt.vm_path, затем -vm из 1cedt.ini (тогда
      -vm не передаётся), JAVA_HOME с JavaFX, известные каталоги JDK, иначе none.
      Path - полный путь к bin\server\jvm.dll либо $null.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$EdtGuiPath,
        [string]$VmPath,
        [string[]]$SearchRoots
    )

    $toDll = {
        param([string]$p)
        $p = $p -replace '/', '\'
        if ($p -match '\.dll$') { return $p }
        return (Join-Path $p 'bin\server\jvm.dll')
    }
    $result = { param($path, $reason) [pscustomobject]@{ Path = $path; Reason = $reason } }

    if ($VmPath) {
        $dll = & $toDll $VmPath
        if (Test-Path -LiteralPath $dll) { return (& $result $dll 'config') }
    }

    $ini = Join-Path (Split-Path -Parent $EdtGuiPath) '1cedt.ini'
    if (Test-Path -LiteralPath $ini) {
        $lines = @(Get-Content -LiteralPath $ini -Encoding UTF8 | ForEach-Object { $_.Trim() })
        $vmargsAt = [array]::IndexOf($lines, '-vmargs')
        $head = if ($vmargsAt -gt 0) { $lines[0..($vmargsAt - 1)] } elseif ($vmargsAt -eq 0) { @() } else { $lines }
        if (@($head) -contains '-vm') { return (& $result $null 'ini') }
    }

    if ($env:JAVA_HOME) {
        $javaHome = $env:JAVA_HOME -replace '/', '\'
        $dll = & $toDll $javaHome
        if ((Test-Path -LiteralPath $dll) -and (Test-EdtWtJdkHasJavaFx -JdkHome $javaHome)) {
            return (& $result $dll 'JAVA_HOME')
        }
    }

    if (-not $PSBoundParameters.ContainsKey('SearchRoots')) {
        $SearchRoots = @(
            "$env:ProgramFiles\Zulu\*",
            "$env:ProgramFiles\BellSoft\*",
            "$env:ProgramFiles\Axiom*\*",
            "$env:ProgramFiles\Java\*"
        )
    }
    foreach ($root in $SearchRoots) {
        if (-not $root) { continue }
        $pattern = if ($root -match '[\*\?]') { $root } else { Join-Path $root '*' }
        # Числа в имени дополняются нулями: zulu17.10 новее zulu17.9.
        $versionKey = { [regex]::Replace($_.Name, '\d+', { param($m) $m.Value.PadLeft(10, '0') }) }
        $dirs = @(Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue | Sort-Object $versionKey -Descending)
        foreach ($d in $dirs) {
            $dll = & $toDll $d.FullName
            if ((Test-Path -LiteralPath $dll) -and (Test-EdtWtJdkHasJavaFx -JdkHome $d.FullName)) {
                return (& $result $dll 'scan')
            }
        }
    }

    return (& $result $null 'none')
}
