function Invoke-EdtWtCli {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$WorkspaceDir,
        [Parameter(Mandatory)][string[]]$Commands,
        [string]$BatchName = "edt_wt_batch.txt",
        [string]$MaxHeap
    )

    if (-not (Test-Path -LiteralPath $WorkspaceDir)) {
        New-Item -ItemType Directory -Force -Path $WorkspaceDir | Out-Null
    }

    $batchFile = Join-Path $WorkspaceDir $BatchName
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($batchFile, ($Commands -join "`n"), $utf8NoBom)

    Write-Host "    -> 1cedtcli batch:" -ForegroundColor Gray
    $Commands | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray }

    $jvm = Resolve-EdtWtJvmArgs -JvmArgs $Context.JvmArgs -MaxHeap $MaxHeap
    Write-Host "    -> JVM: -Xmx$($jvm.MaxHeapGb)g -Xms$($jvm.MinHeapGb)g (свободный commit: $($jvm.FreeCommitGb) ГБ)" -ForegroundColor Gray

    $edtArgs = "-data `"$WorkspaceDir`" -timeout $($Context.TimeoutSec) -file `"$batchFile`" -vmargs $($jvm.Args) -Dorg.eclipse.core.resources.refresh=true"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Context.EdtCliPath
    $psi.Arguments = $edtArgs
    $psi.WorkingDirectory = $WorkspaceDir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    # 1cedtcli не принимает -vm (передаёт его в java), а лончер без -vm берёт первый
    # javaw из PATH (шим mise, Oracle java8path) или Java 8 из реестра и падает с
    # "Incompatible JVM" (ExitCode 14). Поэтому JDK кладётся первой в PATH процесса.
    $cliJvm = Resolve-EdtWtGuiJvm -EdtGuiPath (Join-Path (Split-Path -Parent $Context.EdtCliPath) '1cedt.exe') -VmPath (Get-EdtWtProperty $Context 'VmPath')
    if ($cliJvm.Path) {
        $jdkBin = Split-Path -Parent (Split-Path -Parent $cliJvm.Path)
        $psi.Environment['PATH'] = "$jdkBin;$($psi.Environment['PATH'])"
        $psi.Environment['JAVA_HOME'] = Split-Path -Parent $jdkBin
    } elseif ($cliJvm.Reason -eq 'none') {
        Write-Warning "JDK 17 с JavaFX не найдена, см. edt doctor. 1cedtcli возьмёт JVM из PATH или реестра."
    }

    $started = [Diagnostics.Stopwatch]::StartNew()
    $proc = [System.Diagnostics.Process]::Start($psi)
    # stderr читается асинхронно ДО синхронного чтения stdout: иначе переполнение
    # буфера любого из потоков вешает процесс и вызывающего.
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        if ([string]::IsNullOrWhiteSpace($stdout) -and [string]::IsNullOrWhiteSpace($stderr)) {
            Write-Host '    (вывод пуст: причина - в журналах рабочей области .metadata\.log и 1cedtcli.log)' -ForegroundColor Yellow
        } else {
            Write-Host $stdout
            Write-Host $stderr -ForegroundColor Red
        }
        throw "1cedtcli завершился с ошибкой (ExitCode $($proc.ExitCode)) через $([int]$started.Elapsed.TotalSeconds) с"
    }
    Write-Host $stdout
}
