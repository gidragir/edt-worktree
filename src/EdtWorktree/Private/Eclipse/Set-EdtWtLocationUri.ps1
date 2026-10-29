# Приватная функция: запись .location идёт внутри операции перепривязки,
# которая уже закрыта ShouldProcess вызывающей команды.
function Set-EdtWtLocationUri {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)][string]$LocationFile,
        [Parameter(Mandatory)]$Parsed,
        [Parameter(Mandatory)][string]$NewValue
    )

    $newBytes = [System.Text.Encoding]::UTF8.GetBytes($NewValue)
    $tailStart = $Parsed.Offset + $Parsed.Length

    $out = New-Object System.Collections.Generic.List[byte]
    # Нарезка массива в PowerShell даёт Object[], AddRange требует IEnumerable[byte]
    $out.AddRange([byte[]]($Parsed.Bytes[0..15]))
    $out.Add([byte](($newBytes.Length -shr 8) -band 0xFF))
    $out.Add([byte]($newBytes.Length -band 0xFF))
    $out.AddRange([byte[]]$newBytes)
    if ($tailStart -lt $Parsed.Bytes.Length) {
        $out.AddRange([byte[]]($Parsed.Bytes[$tailStart..($Parsed.Bytes.Length - 1)]))
    }

    [System.IO.File]::WriteAllBytes($LocationFile, $out.ToArray())
}
