function Assert-EdtWtReferenceFree {
    <#
      Эталон не должен быть занят EDT. Процессы не закрываются: занятый эталон - отказ.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)

    $busy = @(Get-EdtWtWorkspaceProcesses -WorkspaceDir $Context.ReferenceWsDir)
    if ($busy.Count -gt 0) {
        throw "Эталон занят: $(($busy | ForEach-Object { "$($_.Name):$($_.ProcessId)" }) -join ', '). Закройте EDT и повторите."
    }
}
