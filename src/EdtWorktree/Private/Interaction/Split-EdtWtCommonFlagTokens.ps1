function Split-EdtWtCommonFlagTokens {
    <#
      Отделяет общие ключи (-Yes, -WhatIf, --dry-run) от остальных слов. Нужна
      подкомандам со свободным вводом (project ext: +имя/-имя; config set: значение
      может начинаться с дефиса), где общий разбор ключей принял бы такое слово за ключ.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([Parameter(Position = 0)][AllowEmptyCollection()][string[]]$Items)

    $flags = @()
    $rest = @()
    foreach ($item in @($Items | Where-Object { $_ })) {
        if ($item -match '^--?(what-?if|dry-?run|yes)$') { $flags += $item } else { $rest += $item }
    }
    return [PSCustomObject]@{ Flags = $flags; Rest = $rest }
}
