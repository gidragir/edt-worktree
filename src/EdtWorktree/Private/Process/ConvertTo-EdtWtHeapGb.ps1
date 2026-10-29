function ConvertTo-EdtWtHeapGb {
    <#
      Размер кучи из конфига ('16g', '8192m') в целые гигабайты.
      Мегабайты округляются вниз: Xmx больше заданного превысил бы лимит пользователя.
    #>
    [OutputType([int])]
    param([Parameter(Mandatory)][string]$Value)

    if ($Value -notmatch '^\s*(\d+)\s*([gGmM])\s*$') {
        throw "Неверный размер кучи '$Value': ожидается число с g или m, например 16g."
    }
    $n = [int64]$Matches[1]
    if ($Matches[2] -in 'm', 'M') { return [int][math]::Floor($n / 1024) }
    return [int]$n
}
