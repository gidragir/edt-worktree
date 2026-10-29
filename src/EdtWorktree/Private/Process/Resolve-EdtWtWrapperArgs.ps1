function Resolve-EdtWtWrapperArgs {
    <#
      Разбирает ключи подкоманд edt (стили -NoGui и --no-gui). Возвращает:
      Extensions - позиционные значения (имя историческое), Flags - переключатели,
      Values - ключи со значением, Used - имена заданных ключей (для проверки
      допустимости в диспетчере). Allowed нужен только для подсказки в ошибке.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)][AllowEmptyCollection()][string[]]$Items,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Allowed
    )

    $flags = @{
        Refresh = $false; NoGui = $false; SkipGit = $false; Purge = $false
        WhatIf = $false; Yes = $false; NoProjects = $false
    }
    $values = @{
        Extensions = $null; RefBranch = $null; CfProject = $null
        ReposRoot = $null; WorktreesRoot = $null; WorkspacesRoot = $null
    }
    $positional = @()
    $used = [System.Collections.Generic.List[string]]::new()

    # Ключи-переключатели: регулярное выражение имени -> имя в Flags.
    $flagMap = [ordered]@{
        '^--?refresh$|^-r$'            = 'Refresh'
        '^--?no-?gui$'                 = 'NoGui'
        '^--?skip-?git$'               = 'SkipGit'
        '^--?purge$'                   = 'Purge'
        '^--?what-?if$|^--?dry-?run$'  = 'WhatIf'
        '^--?yes$'                     = 'Yes'
        '^--?no-?projects$'            = 'NoProjects'
    }
    # Ключи со значением.
    $valueMap = [ordered]@{
        '^--?extensions$'                = 'Extensions'
        '^--?ref-?branch$'               = 'RefBranch'
        '^--?cf-?project$'               = 'CfProject'
        '^--?repos-?root$'               = 'ReposRoot'
        '^--?worktrees-?root$'           = 'WorktreesRoot'
        '^--?workspaces-?root$'          = 'WorkspacesRoot'
    }

    $list = @($Items | Where-Object { $_ })
    for ($i = 0; $i -lt $list.Count; $i++) {
        $item = $list[$i]

        if (-not $item.StartsWith('-')) {
            $positional += $item
            continue
        }

        $name = $item.ToLower()
        $matched = $false

        foreach ($entry in $flagMap.GetEnumerator()) {
            if ($name -match $entry.Key) {
                $flags[$entry.Value] = $true
                if (-not $used.Contains($entry.Value)) { $used.Add($entry.Value) }
                $matched = $true
                break
            }
        }
        if ($matched) { continue }

        foreach ($entry in $valueMap.GetEnumerator()) {
            if ($name -match $entry.Key) {
                if (($i + 1) -ge $list.Count -or $list[$i + 1].StartsWith('-')) { throw "Ключ '$item' требует значения." }
                $i++
                $values[$entry.Value] = if ($entry.Value -eq 'Extensions') { [string[]]@($list[$i] -split '[,\s]+' | Where-Object { $_ }) } else { $list[$i] }
                if (-not $used.Contains($entry.Value)) { $used.Add($entry.Value) }
                $matched = $true
                break
            }
        }
        if ($matched) { continue }

        $hint = if ($Allowed.Count -gt 0) { "Доступны: $($Allowed -join ', ')." } else { 'Эта подкоманда ключей не принимает.' }
        throw "Неизвестный ключ '$item'. $hint"
    }

    return [PSCustomObject]@{
        Extensions = $positional
        Flags      = $flags
        Values     = $values
        Used       = $used.ToArray()
    }
}
