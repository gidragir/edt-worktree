function ConvertTo-EdtWtEclipseLocationUri {
    <#
      Формирует канонический URI для файла .location Eclipse.
      Формат: 'URI//file:/' + путь с прямыми слешами и экранированными пробелами (%20).
      Eclipse LocalMetaArea.readPrivateDescription парсит URI через java.net.URI.create(),
      поэтому неэкранированные пробелы вызывают IllegalArgumentException.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $normalized = $Path.TrimEnd('\') -replace '\\', '/'
    # '%' экранируется первым, иначе повторно закодируются уже вставленные последовательности.
    $escaped = $normalized.Replace('%', '%25')
    foreach ($pair in @(' ', '#', '[', ']', '{', '}', '^', '`', '"', '<', '>', '|')) {
        $escaped = $escaped.Replace($pair, ('%{0:X2}' -f [int][char]$pair))
    }    return "URI//file:/$($escaped.TrimStart('/'))"
}
