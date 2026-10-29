function Read-EdtWtExtensionChoice {
    <# Спрашивает номера расширений. $null - ответ пустой (ничего не менять). #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowEmptyCollection()][object[]]$Found = @(),
        [AllowEmptyString()][string]$Default
    )

    $answer = Read-EdtWtAnswer -Prompt 'Рабочие расширения (номера через пробел, диапазон 2-4, "все", "нет")' -Default $Default
    if ([string]::IsNullOrWhiteSpace($answer)) { return $null }
    $picked = ConvertFrom-EdtWtSelection -Text $answer -Count @($Found).Count
    return [string[]]@($picked | ForEach-Object { $Found[$_ - 1].RelPath })
}
