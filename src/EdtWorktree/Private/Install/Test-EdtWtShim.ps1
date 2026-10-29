function Test-EdtWtShim {
    <# Shim на месте: edt.cmd лежит в Get-EdtWtShimDir, а каталог есть в PATH процесса. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $dir = Get-EdtWtShimDir
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'edt.cmd') -PathType Leaf)) { return $false }
    foreach ($part in $env:Path -split ';') {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        try { if (Test-EdtWtSamePath -A $part -B $dir) { return $true } } catch { Write-Verbose $_.Exception.Message }
    }
    return $false
}
