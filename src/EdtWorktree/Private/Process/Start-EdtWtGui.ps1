function Start-EdtWtGui {
    <#
      Единая точка запуска IDE на рабочей области. Куча - edt.gui_max_heap
      (Context.GuiMaxHeap) либо авто; JVM - Resolve-EdtWtGuiJvm.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Context
    )

    if (-not (Test-Path -LiteralPath $Context.EdtGuiPath)) {
        throw "Не найден GUI 1C:EDT: $($Context.EdtGuiPath)"
    }

    $guiArgs = @()
    $jvm = Resolve-EdtWtGuiJvm -EdtGuiPath $Context.EdtGuiPath -VmPath (Get-EdtWtProperty $Context 'VmPath')
    if ($jvm.Path) {
        $guiArgs += @("-vm", "`"$($jvm.Path)`"")
    } elseif ($jvm.Reason -eq 'none') {
        Write-Warning "JDK 17 с JavaFX не найдена, см. edt doctor. EDT запускается без -vm."
    }
    $guiArgs += @("-data", "`"$($Context.WorkspaceDir)`"")
    $guiVm = Resolve-EdtWtGuiVmArgs -Context $Context -MaxHeap (Get-EdtWtProperty $Context 'GuiMaxHeap')
    if ($guiVm) {
        Write-Host "    JVM GUI: -Xmx$($guiVm.MaxHeapGb)g (в 1cedt.ini задано 4g)" -ForegroundColor Gray
        $guiArgs += "-vmargs"
        $guiArgs += $guiVm.Args
    }

    if (-not $PSCmdlet.ShouldProcess($Context.WorkspaceDir, 'Запустить 1C:EDT')) {
        return
    }

    Write-Host "==> Запуск 1C:EDT..." -ForegroundColor Cyan
    Start-Process -FilePath $Context.EdtGuiPath -ArgumentList $guiArgs
    Write-Host "✓ 1C:EDT запущен на рабочей области $($Context.WorkspaceDir)" -ForegroundColor Green
}
