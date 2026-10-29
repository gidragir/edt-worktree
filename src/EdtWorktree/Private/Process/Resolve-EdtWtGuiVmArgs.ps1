function Resolve-EdtWtGuiVmArgs {
    <#
      1cedt.ini задаёт GUI жёсткие -Xmx4096m, чего на конфигурации уровня ERP
      с десятком расширений не хватает: журнал рабочей области пишет
      "Sustained CPU overload. Memory ... used of 4294967296", а первый старт
      уходит в постоянную сборку мусора. Аргументы после -vmargs в командной
      строке ПОЛНОСТЬЮ заменяют секцию из ini, поэтому список читается из ini
      целиком и в нём подменяется только размер кучи.
    #>
    param(
        [Parameter(Mandatory)]$Context,
        [string]$MaxHeap
    )

    $ini = Join-Path (Split-Path -Parent $Context.EdtGuiPath) "1cedt.ini"
    if (-not (Test-Path -LiteralPath $ini)) { return $null }

    $lines = @(Get-Content -LiteralPath $ini -Encoding UTF8)
    $idx = [array]::IndexOf($lines, '-vmargs')
    if ($idx -lt 0) { return $null }

    $vmargs = @($lines[($idx + 1)..($lines.Count - 1)] | Where-Object { $_ -and $_.Trim() })

    if ($MaxHeap) {
        $targetGb = ConvertTo-EdtWtHeapGb -Value $MaxHeap
    } else {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $freeCommitGb = if ($os) { [math]::Floor($os.FreeVirtualMemory / 1MB) } else { 0 }
        # Половина свободного commit-лимита, но не больше 16 ГБ: GUI должен
        # оставить место платформе 1С и конфигуратору, запускаемым рядом.
        $targetGb = [math]::Min(16, [math]::Floor($freeCommitGb / 2))
    }
    if ($targetGb -lt 4) { return $null }   # меньше штатных 4 ГБ поднимать нечего

    $vmargs = @($vmargs | Where-Object { $_ -notmatch '^-Xmx' })
    $vmargs += "-Xmx${targetGb}g"

    return [PSCustomObject]@{
        Args      = $vmargs
        MaxHeapGb = $targetGb
    }
}
