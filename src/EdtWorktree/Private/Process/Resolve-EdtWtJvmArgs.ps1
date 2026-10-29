function Resolve-EdtWtJvmArgs {
    <#
      Подгоняет -Xmx/-Xms под фактически доступную память.
      JVM резервирует всю кучу как virtual space при старте, поэтому -Xmx больше
      свободного commit-лимита падает с "insufficient memory ... G1 virtual space".
    #>
    param(
        [Parameter(Mandatory)][string]$JvmArgs,
        [string]$MaxHeap
    )

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $freeCommitGb = if ($os) { [math]::Floor($os.FreeVirtualMemory / 1MB) } else { 0 }

    if ($MaxHeap) {
        $targetGb = ConvertTo-EdtWtHeapGb -Value $MaxHeap
    } else {
        $currentGb = 0
        if ($JvmArgs -match '-Xmx(\d+)g') { $currentGb = [int]$matches[1] }
        # Оставляем 4 ГБ запаса под саму JVM, EDT и остальную систему
        $budgetGb = $freeCommitGb - 4
        if ($budgetGb -lt 2) { $budgetGb = 2 }
        $targetGb = if ($currentGb -gt 0 -and $currentGb -le $budgetGb) { $currentGb } else { $budgetGb }
    }
    if ($targetGb -lt 2) { $targetGb = 2 }

    $minGb = [math]::Max(1, [math]::Min(2, [math]::Floor($targetGb / 4)))

    $result = $JvmArgs -replace '-Xmx\d+[gGmM]', "-Xmx${targetGb}g"
    if ($result -notmatch '-Xmx') { $result = "$result -Xmx${targetGb}g".Trim() }
    $result = $result -replace '-Xms\d+[gGmM]', "-Xms${minGb}g"

    return [PSCustomObject]@{
        Args        = $result
        MaxHeapGb   = $targetGb
        MinHeapGb   = $minGb
        FreeCommitGb = $freeCommitGb
    }
}
