function Remove-EdtWtPathEntry {
    <#
      Убирает из значения PATH все записи, равные Entry (Test-EdtWtSamePath: без учёта
      регистра и хвостового слеша). Пустые элементы выбрасываются.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$PathValue,
        [Parameter(Mandatory)][string]$Entry
    )

    $kept = foreach ($part in $PathValue -split ';') {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $same = $false
        try { $same = Test-EdtWtSamePath -A $part -B $Entry } catch { $same = $false }
        if (-not $same) { $part }
    }
    return (@($kept) -join ';')
}
