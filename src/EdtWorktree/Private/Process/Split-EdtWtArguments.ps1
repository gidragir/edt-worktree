function Split-EdtWtArguments {
    <#
      Разбор аргументов командной строки на позиционные и ключи.
      Ключи со значением забирают следующий аргумент.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [string[]]$Arguments,

        [string[]]$ValueKeys = @('-Extensions', '-RefBranch', '-CfProject', '-ReposRoot', '-WorktreesRoot', '-WorkspacesRoot')
    )

    $positional = @()
    $switches = @()
    $items = @($Arguments | Where-Object { $_ })

    for ($i = 0; $i -lt $items.Count; $i++) {
        $item = $items[$i]
        if (-not $item.StartsWith('-')) {
            $positional += $item
            continue
        }

        $switches += $item
        $takesValue = @($ValueKeys | Where-Object { $item -ieq $_ }).Count -gt 0
        $hasNext = ($i + 1) -lt $items.Count
        if ($takesValue -and $hasNext -and -not $items[$i + 1].StartsWith('-')) {
            $i++
            $switches += $items[$i]
        }
    }

    return [PSCustomObject]@{
        Positional = $positional
        Switches   = $switches
    }
}
