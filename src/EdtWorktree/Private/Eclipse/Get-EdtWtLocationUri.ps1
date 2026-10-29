function Get-EdtWtLocationUri {
    <#
      Читает .location проекта Eclipse.
      Формат: 16 байт BEGIN_CHUNK, затем writeUTF (2 байта длины + строка),
      затем постоянный хвост (END_CHUNK и служебные поля).
    #>
    param([Parameter(Mandatory)][string]$LocationFile)

    $bytes = [System.IO.File]::ReadAllBytes($LocationFile)
    if ($bytes.Length -lt 20) { return $null }

    $len = ([int]$bytes[16] * 256) + [int]$bytes[17]
    if ($len -le 0 -or (18 + $len) -gt $bytes.Length) { return $null }

    $value = [System.Text.Encoding]::UTF8.GetString($bytes, 18, $len)
    return [PSCustomObject]@{
        Bytes  = $bytes
        Offset = 18
        Length = $len
        Value  = $value
    }
}
