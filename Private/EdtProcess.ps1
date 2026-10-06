# ==============================================================================
# EdtProcess.ps1 - Поиск, аргументы, управление процессами и запуск EDT / vrunner
# ==============================================================================

Set-StrictMode -Version Latest

# ------------------------------------------------------------------------------
# 1. Поиск исполняемых файлов EDT
# ------------------------------------------------------------------------------

function Find-EdtWtCli {
    <#
    .SYNOPSIS
        Ищет установленные версии 1C:EDT на машине.
    .DESCRIPTION
        Сканирует стандартные каталоги установки 1C:EDT и системный PATH в поисках 1cedtcli.bat.
        Возвращает массив объектов с версией и полным путём.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # 1. Поиск в PATH
    foreach ($name in @('1cedtcli.exe', '1cedtcli.bat')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and (Test-Path -LiteralPath $cmd.Source)) {
            $fullPath = $cmd.Source
            if ($seenPaths.Add($fullPath)) {
                $folder = Split-Path -Parent $fullPath
                $version = if ($folder -match '(\d+\.\d+(\.\d+)?)') { $Matches[1] } else { 'PATH' }
                $results.Add([PSCustomObject]@{
                    Version = $version
                    Path    = $fullPath
                    Folder  = $folder
                })
            }
        }
    }

    # 2. Стандартные каталоги установки
    $searchRoots = @(
        "$env:ProgramFiles\1C",
        "$env:LOCALAPPDATA\Programs\1C",
        "${env:ProgramFiles(x86)}\1C"
    )

    foreach ($root in $searchRoots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        $cliFiles = Get-ChildItem -LiteralPath $root -Filter "1cedtcli.*" -Recurse -Depth 5 -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.exe', '.bat') }
        foreach ($file in $cliFiles) {
            $fullPath = $file.FullName
            if ($seenPaths.Add($fullPath)) {
                $folder = $file.DirectoryName
                $version = if ($folder -match '(\d+\.\d+(\.\d+)?)') { $Matches[1] } else { Split-Path -Leaf $folder }
                $results.Add([PSCustomObject]@{
                    Version = $version
                    Path    = $fullPath
                    Folder  = $folder
                })
            }
        }
    }

    return @($results | Sort-Object Version -Descending)
}

# ------------------------------------------------------------------------------
# 2. Разбор аргументов JVM и CLI-оболочки
# ------------------------------------------------------------------------------

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
        $targetGb = [int]($MaxHeap -replace '[^\d]', '')
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
    $result = $result -replace '-Xms\d+[gGmM]', "-Xms${minGb}g"

    return [PSCustomObject]@{
        Args        = $result
        MaxHeapGb   = $targetGb
        MinHeapGb   = $minGb
        FreeCommitGb = $freeCommitGb
    }
}

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
        $targetGb = [int]($MaxHeap -replace '[^\d]', '')
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

function Split-EdtWtArguments {
    <#
      Разбор аргументов командной строки на позиционные и ключи.
      Ключи со значением забирают следующий аргумент.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [string[]]$Arguments,

        [string[]]$ValueKeys = @('-GuiMaxHeap', '-MaxHeap', '-Extensions', '-ProjectName', '-WorktreeId')
    )

    $positional = @()
    $switches = @()
    $items = @($Arguments | Where-Object { $_ })

    for ($i = 0; $i -lt $items.Count; $i++) {
        $item = $items[$i]
        if (-not $item.StartsWith('-')) {
            $positional += $item
            continue
        }

        $switches += $item
        $takesValue = @($ValueKeys | Where-Object { $item -ieq $_ }).Count -gt 0
        $hasNext = ($i + 1) -lt $items.Count
        if ($takesValue -and $hasNext -and -not $items[$i + 1].StartsWith('-')) {
            $i++
            $switches += $items[$i]
        }
    }

    return [PSCustomObject]@{
        Positional = $positional
        Switches   = $switches
    }
}

function Resolve-EdtWtWrapperArgs {
    <#
      Разбирает аргументы быстрых обёрток (wt-open, wt-add, wt-warmup).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)][AllowEmptyCollection()][string[]]$Items,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Allowed
    )

    $flags = @{ Refresh = $false; NoGui = $false; Force = $false; Validate = $false; WhatIf = $false; Yes = $false; SkipGit = $false }
    $values = @{ MaxHeap = $null; GuiMaxHeap = $null }
    $extensions = @()

    $list = @($Items | Where-Object { $_ })
    for ($i = 0; $i -lt $list.Count; $i++) {
        $item = $list[$i]

        if (-not $item.StartsWith('-')) {
            $extensions += $item
            continue
        }

        $name = $item.ToLower()
        $takeValue = {
            if (($i + 1) -ge $list.Count) { throw "Ключ '$item' требует значения." }
            $script:__i = $i + 1
            return $list[$i + 1]
        }

        switch -Regex ($name) {
            '^--?refresh$|^-r$' { $flags.Refresh = $true; break }
            '^--?no-?gui$' { $flags.NoGui = $true; break }
            '^--?force$|^-f$' { $flags.Force = $true; break }
            '^--?validate$' { $flags.Validate = $true; break }
            '^--?skip-?git$' { $flags.SkipGit = $true; break }
            '^--?what-?if$|^--?dry-?run$' { $flags.WhatIf = $true; break }
            '^--?yes$|^--?confirm:\$false$' { $flags.Yes = $true; break }
            '^--?gui-?max-?heap$|^--?gui-?heap$' { $values.GuiMaxHeap = & $takeValue; $i++; break }
            '^--?max-?heap$' { $values.MaxHeap = & $takeValue; $i++; break }
            '^--?extensions$' { $extensions += (& $takeValue); $i++; break }
            default {
                $hint = if ($Allowed.Count -gt 0) { "Доступны: $($Allowed -join ', ')." } else { 'Эта подкоманда ключей не принимает.' }
                throw "Неизвестный ключ '$item'. $hint"
            }
        }
    }

    return [PSCustomObject]@{
        Extensions = $extensions
        Flags      = $flags
        Values     = $values
    }
}

# ------------------------------------------------------------------------------
# 3. Управление процессами EDT
# ------------------------------------------------------------------------------

function Get-EdtWtWorkspaceProcesses {
    <#
      Процессы, занимающие рабочую область: EDT держит .metadata/.lock, поэтому
      headless-импорт при запущенной IDE невозможен.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$WorkspaceDir,
        [switch]$IncludeHeadless
    )

    $names = @('1cedt.exe', '1cedtc.exe', 'javaw.exe', 'java.exe')
    if ($IncludeHeadless) { $names += '1cedtcli.exe' }

    $filter = ($names | ForEach-Object { "Name = '$_'" }) -join ' OR '

    return @(Get-CimInstance -ClassName Win32_Process -Filter $filter -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*$WorkspaceDir*" })
}

function Stop-EdtWtProcesses {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceDir)

    $procs = @(Get-EdtWtWorkspaceProcesses -WorkspaceDir $WorkspaceDir -IncludeHeadless)

    if ($procs.Count -eq 0) {
        Write-Host "    Активных процессов EDT на этой рабочей области не найдено." -ForegroundColor Gray
        return 0
    }

    foreach ($p in $procs) {
        Write-Host "    Завершение процесса $($p.Name) (PID $($p.ProcessId))..." -ForegroundColor Yellow
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1
    return $procs.Count
}

# ------------------------------------------------------------------------------
# 4. Запуск EDT CLI, EDT GUI и vrunner
# ------------------------------------------------------------------------------

function Start-EdtWtGui {
    <#
      Запускает IDE на указанной рабочей области, подняв размер кучи.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Context,
        [string]$GuiMaxHeap
    )

    if (-not (Test-Path -LiteralPath $Context.EdtGuiPath)) {
        throw "Не найден GUI 1C:EDT: $($Context.EdtGuiPath)"
    }

    $guiArgs = @("-data", "`"$($Context.WorkspaceDir)`"")
    $guiVm = Resolve-EdtWtGuiVmArgs -Context $Context -MaxHeap $GuiMaxHeap
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

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        Write-Host $stdout
        Write-Host $stderr -ForegroundColor Red
        throw "1cedtcli завершился с ошибкой (ExitCode $($proc.ExitCode))"
    }
    Write-Host $stdout
}

function Resolve-EdtWtVrunnerPlan {
    <#
      Готовит запуск vrunner: аргументы, окружение и рабочий каталог.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]$Context,
        [AllowEmptyCollection()][string[]]$Arguments = @(),
        [AllowEmptyCollection()][string[]]$PresetEnv = @()
    )

    $hasSettings = [bool]($Arguments | Where-Object { $_ -match '^--settings(=.*)?$' })
    $settingsFile = Join-Path $Context.WorktreePath 'autumn-properties.json'
    if (-not $hasSettings -and -not (Test-Path -LiteralPath $settingsFile)) {
        throw "Файл autumn-properties.json не найден в $($Context.WorktreePath): vrunner не получит настройки базы."
    }
    if (-not (Test-Path -LiteralPath $Context.WorkspaceDir)) {
        throw "Рабочая область EDT не найдена: $($Context.WorkspaceDir). Создайте её: edt open -NoGui"
    }

    $notes = @()
    $full = $false
    $vrArgs = @()
    foreach ($item in @($Arguments | Where-Object { $_ })) {
        if ($item -match '^--?full$') { $full = $true } else { $vrArgs += $item }
    }

    $findLoad = {
        param($list)
        for ($i = 0; $i -lt ($list.Count - 1); $i++) {
            if ($list[$i] -in @('cf', 'cfe') -and $list[$i + 1] -eq 'load') { return $i + 1 }
        }
        return -1
    }
    if ((& $findLoad $vrArgs) -ge 0) {
        $explicit = [bool]($vrArgs | Where-Object { $_ -eq '--increment' })
        $vrArgs = @($vrArgs | Where-Object { $_ -ne '--increment' })
        if (-not $full) {
            $loadAt = & $findLoad $vrArgs
            $vrArgs = @($vrArgs[0..$loadAt]) + '--increment' + @($vrArgs | Select-Object -Skip ($loadAt + 1))
            if (-not $explicit) { $notes += 'инкрементальная загрузка (отключить: -Full)' }
        }
    }

    $jvm = Resolve-EdtWtJvmArgs -JvmArgs $Context.JvmArgs
    $wanted = [ordered]@{
        VRUNNER_EDT_WORKSPACE = $Context.WorkspaceDir
        VRUNNER_EDT_PATH      = $Context.EdtCliPath
        VRUNNER_EDT_VMARGS    = "-Xmx$($jvm.MaxHeapGb)g"
        VRUNNER_EDT_TIMEOUT   = [string]$Context.TimeoutSec
    }
    $envVars = [ordered]@{}
    foreach ($name in $wanted.Keys) {
        if ($PresetEnv -notcontains $name) { $envVars[$name] = $wanted[$name] }
    }

    return [PSCustomObject]@{
        WorkingDirectory = $Context.WorktreePath
        Arguments        = $vrArgs
        Env              = $envVars
        Notes            = $notes
    }
}

function Invoke-EdtWtVrunner {
    <#
      Запускает vrunner в текущем worktree с рабочей областью EDT этого worktree.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][string[]]$Arguments = @()
    )

    $context = Get-EdtWtContext
    $preset = @(Get-ChildItem Env: | Where-Object { $_.Name -like 'VRUNNER_EDT_*' } | Select-Object -ExpandProperty Name)
    $plan = Resolve-EdtWtVrunnerPlan -Context $context -Arguments $Arguments -PresetEnv $preset

    foreach ($note in $plan.Notes) { Write-Host "    -> $note" -ForegroundColor Gray }

    Push-Location -LiteralPath $plan.WorkingDirectory
    try {
        foreach ($name in $plan.Env.Keys) { Set-Item -Path "Env:$name" -Value $plan.Env[$name] }
        & vrunner @($plan.Arguments) | Out-Host
    } finally {
        foreach ($name in $plan.Env.Keys) { Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue }
        Pop-Location
    }
}
