function ConvertFrom-EdtWtSelection {
    <# Разбирает выбор вида '1 3', '2-4', 'все', 'нет'; возвращает номера с 1 по возрастанию без дублей. #>
    [OutputType([int[]])]
    param(
        [AllowEmptyString()][AllowNull()][string]$Text,
        [Parameter(Mandatory)][int]$Count
    )

    $bad = "Неверный выбор '$Text': ожидаются номера 1-$Count, диапазоны (2-4), 'все' или 'нет'."
    $t = if ($null -eq $Text) { '' } else { $Text.Trim().ToLowerInvariant() }
    if ($t -in @('', 'нет', 'none')) { return [int[]]@() }
    if ($t -in @('все', 'all', '*')) { return [int[]](1..$Count) }

    $picked = [System.Collections.Generic.SortedSet[int]]::new()
    foreach ($token in ($t -split '[\s,]+' | Where-Object { $_ })) {
        if ($token -match '^(\d+)-(\d+)$') {
            $from = [int]$Matches[1]; $to = [int]$Matches[2]
            if ($from -lt 1 -or $to -gt $Count -or $from -gt $to) { throw $bad }
            foreach ($i in $from..$to) { [void]$picked.Add($i) }
        } elseif ($token -match '^\d+$') {
            $n = [int]$token
            if ($n -lt 1 -or $n -gt $Count) { throw $bad }
            [void]$picked.Add($n)
        } else {
            throw $bad
        }
    }
    return [int[]]@($picked)
}
