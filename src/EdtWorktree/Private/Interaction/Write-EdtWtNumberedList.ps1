function Write-EdtWtNumberedList {
    <# Печатает нумерованный список найденных проектов; отмеченные помечаются [x]. #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Items = @(),
        [string[]]$Marked = @()
    )

    for ($i = 0; $i -lt @($Items).Count; $i++) {
        $mark = if ($Items[$i].RelPath -in $Marked) { '[x]' } else { '[ ]' }
        Write-Host ("  {0} {1,2}. {2}  ({3})" -f $mark, ($i + 1), (Split-Path $Items[$i].RelPath -Leaf), $Items[$i].RelPath)
    }
}
