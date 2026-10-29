function Save-EdtWtConfig {
    <#
      Пишет схему целиком (дефолты + переданный объект), UTF-8 без BOM:
      сначала во временный файл, затем подмена исходного.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config
    )

    $path = Get-EdtWtUserConfigPath
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $full = Merge-EdtWtConfigObject -Base (New-EdtWtDefaultConfig) -Override $Config
    $json = ConvertTo-Json -InputObject $full -Depth 10

    $tmp = "$path.tmp"
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $path -Force
    return $path
}
