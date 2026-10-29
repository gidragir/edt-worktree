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
