function Resolve-EdtWtExtensionRef {
    <#
      Сопоставляет ссылку (имя папки 'cfe_ad' либо относительный путь 'src/cfe_ad')
      с найденным EDT-проектом и возвращает его RelPath. Неизвестное или
      неоднозначное имя - ошибка со списком найденных.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyCollection()][object[]]$Found = @(),
        [Parameter(Mandatory)][string]$Ref
    )

    $Found = @($Found)
    $norm = $Ref.Trim().Replace('\', '/').Trim('/')
    $list = if ($Found.Count) { ($Found | ForEach-Object { "$(Split-Path $_.RelPath -Leaf) ($($_.RelPath))" }) -join ', ' } else { 'ничего' }

    $byPath = @($Found | Where-Object { $_.RelPath -ieq $norm })
    if ($byPath.Count -eq 1) { return [string]$byPath[0].RelPath }

    $byLeaf = @($Found | Where-Object { (Split-Path $_.RelPath -Leaf) -ieq $norm })
    if ($byLeaf.Count -eq 1) { return [string]$byLeaf[0].RelPath }
    if ($byLeaf.Count -gt 1) {
        throw "Имя '$Ref' неоднозначно: подходят $(($byLeaf.RelPath) -join ', '). Укажите относительный путь."
    }
    throw "Проект EDT '$Ref' не найден в клоне. Найдены: $list."
}
