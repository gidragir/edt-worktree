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
        Сканирует стандартные каталоги установки 1C:EDT и системный PATH в поисках 1cedtcli.
        Возвращает объекты с версией и путём, новейшая версия первой (сортировка по [version]).
    .PARAMETER SearchRoots
        Каталоги для поиска (по умолчанию стандартные каталоги установки).
    .PARAMETER SkipPath
        Не искать в PATH.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [string[]]$SearchRoots,
        [switch]$SkipPath
    )

    if (-not $PSBoundParameters.ContainsKey('SearchRoots')) {
        $SearchRoots = @(
            "$env:ProgramFiles\1C",
            "$env:LOCALAPPDATA\Programs\1C",
            "${env:ProgramFiles(x86)}\1C"
        )
    }

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $add = {
        param([string]$fullPath)
        if (-not $seenPaths.Add($fullPath)) { return }
        $folder = Split-Path -Parent $fullPath
        $leaf = Split-Path -Leaf $folder
        $ver = if ($leaf -match '(\d+(\.\d+)+)') { $Matches[1] } else { $null }
        $sortKey = [version]'0.0'
        if ($ver) { try { $sortKey = [version]$ver } catch { $sortKey = [version]'0.0' } }
        $results.Add([PSCustomObject]@{
            Version = if ($ver) { $ver } else { $leaf }
            Path    = $fullPath
            Folder  = $folder
            SortKey = $sortKey
        })
    }

    if (-not $SkipPath) {
        foreach ($name in @('1cedtcli.exe', '1cedtcli.bat')) {
            $cmd = Get-Command $name -ErrorAction SilentlyContinue
            if ($cmd -and (Test-Path -LiteralPath $cmd.Source)) { & $add $cmd.Source }
        }
    }

    foreach ($root in $SearchRoots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        $cliFiles = Get-ChildItem -LiteralPath $root -Filter "1cedtcli.*" -Recurse -Depth 5 -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.exe', '.bat') }
        foreach ($file in $cliFiles) { & $add $file.FullName }
    }

    return @($results | Sort-Object SortKey -Descending | Select-Object Version, Path, Folder)
}

# ------------------------------------------------------------------------------
# 2. Разбор аргументов JVM и CLI-оболочки
# ------------------------------------------------------------------------------

function ConvertTo-EdtWtHeapGb {
    <#
      Размер кучи из конфига ('16g', '8192m') в целые гигабайты.
      Мегабайты округляются вниз: Xmx больше заданного превысил бы лимит пользователя.
    #>
    [OutputType([int])]
    param([Parameter(Mandatory)][string]$Value)

    if ($Value -notmatch '^\s*(\d+)\s*([gGmM])\s*$') {
        throw "Неверный размер кучи '$Value': ожидается число с g или m, например 16g."
    }
    $n = [int64]$Matches[1]
    if ($Matches[2] -in 'm', 'M') { return [int][math]::Floor($n / 1024) }
    return [int]$n
}

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

        [string[]]$ValueKeys = @('-Extensions', '-RefBranch', '-CfProject', '-ReposRoot', '-WorktreesRoot', '-WorkspacesRoot')
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
      Разбирает ключи подкоманд edt (стили -NoGui и --no-gui). Возвращает:
      Extensions - позиционные значения (имя историческое), Flags - переключатели,
      Values - ключи со значением, Used - имена заданных ключей (для проверки
      допустимости в диспетчере). Allowed нужен только для подсказки в ошибке.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)][AllowEmptyCollection()][string[]]$Items,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Allowed
    )

    $flags = @{
        Refresh = $false; NoGui = $false; SkipGit = $false; Purge = $false
        WhatIf = $false; Yes = $false; NoProjects = $false
    }
    $values = @{
        Extensions = $null; RefBranch = $null; CfProject = $null
        ReposRoot = $null; WorktreesRoot = $null; WorkspacesRoot = $null
    }
    $positional = @()
    $used = [System.Collections.Generic.List[string]]::new()

    # Ключи-переключатели: регулярное выражение имени -> имя в Flags.
    $flagMap = [ordered]@{
        '^--?refresh$|^-r$'            = 'Refresh'
        '^--?no-?gui$'                 = 'NoGui'
        '^--?skip-?git$'               = 'SkipGit'
        '^--?purge$'                   = 'Purge'
        '^--?what-?if$|^--?dry-?run$'  = 'WhatIf'
        '^--?yes$'                     = 'Yes'
        '^--?no-?projects$'            = 'NoProjects'
    }
    # Ключи со значением.
    $valueMap = [ordered]@{
        '^--?extensions$'                = 'Extensions'
        '^--?ref-?branch$'               = 'RefBranch'
        '^--?cf-?project$'               = 'CfProject'
        '^--?repos-?root$'               = 'ReposRoot'
        '^--?worktrees-?root$'           = 'WorktreesRoot'
        '^--?workspaces-?root$'          = 'WorkspacesRoot'
    }

    $list = @($Items | Where-Object { $_ })
    for ($i = 0; $i -lt $list.Count; $i++) {
        $item = $list[$i]

        if (-not $item.StartsWith('-')) {
            $positional += $item
            continue
        }

        $name = $item.ToLower()
        $matched = $false

        foreach ($entry in $flagMap.GetEnumerator()) {
            if ($name -match $entry.Key) {
                $flags[$entry.Value] = $true
                if (-not $used.Contains($entry.Value)) { $used.Add($entry.Value) }
                $matched = $true
                break
            }
        }
        if ($matched) { continue }

        foreach ($entry in $valueMap.GetEnumerator()) {
            if ($name -match $entry.Key) {
                if (($i + 1) -ge $list.Count -or $list[$i + 1].StartsWith('-')) { throw "Ключ '$item' требует значения." }
                $i++
                $values[$entry.Value] = if ($entry.Value -eq 'Extensions') { [string[]]@($list[$i] -split '[,\s]+' | Where-Object { $_ }) } else { $list[$i] }
                if (-not $used.Contains($entry.Value)) { $used.Add($entry.Value) }
                $matched = $true
                break
            }
        }
        if ($matched) { continue }

        $hint = if ($Allowed.Count -gt 0) { "Доступны: $($Allowed -join ', ')." } else { 'Эта подкоманда ключей не принимает.' }
        throw "Неизвестный ключ '$item'. $hint"
    }

    return [PSCustomObject]@{
        Extensions = $positional
        Flags      = $flags
        Values     = $values
        Used       = $used.ToArray()
    }
}

# ------------------------------------------------------------------------------
# 3. Управление процессами EDT
# ------------------------------------------------------------------------------

function Get-EdtWtDataArgument {
    <#
      Значение ключа -data из командной строки процесса: в кавычках или до пробела.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][AllowNull()][string]$CommandLine)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    $m = [regex]::Match($CommandLine, '(?i)(?:^|\s)-data\s+(?:"([^"]*)"|(\S+))')
    if (-not $m.Success) { return $null }
    if ($m.Groups[1].Success) { return $m.Groups[1].Value }
    return $m.Groups[2].Value
}

function Test-EdtWtProcessOnWorkspace {
    <# Процесс работает на рабочей области: -data равен пути (нормализованное сравнение). #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowEmptyString()][AllowNull()][string]$CommandLine,
        [Parameter(Mandatory)][string]$WorkspaceDir
    )

    $data = Get-EdtWtDataArgument -CommandLine $CommandLine
    if (-not $data) { return $false }
    try { return (Test-EdtWtSamePath $data $WorkspaceDir) } catch { return $false }
}

function Get-EdtWtWorkspaceProcesses {
    <#
      Процессы, занимающие рабочую область: EDT держит .metadata/.lock, поэтому
      headless-импорт при запущенной IDE невозможен. Совпадение - по значению -data
      (равенство нормализованных путей), а не по подстроке.
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
        Where-Object { $_.CommandLine -and (Test-EdtWtProcessOnWorkspace -CommandLine $_.CommandLine -WorkspaceDir $WorkspaceDir) })
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

function Test-EdtWtJdkHasJavaFx {
    <#
      JDK подходит для GUI EDT: версия 17+ (по файлу release) и есть JavaFX.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$JdkHome)

    $fx = (Test-Path -LiteralPath (Join-Path $JdkHome 'jmods\javafx.base.jmod')) -or
          (Test-Path -LiteralPath (Join-Path $JdkHome 'lib\javafx-swt.jar'))
    if (-not $fx) { return $false }

    $release = Join-Path $JdkHome 'release'
    if (-not (Test-Path -LiteralPath $release)) { return $false }
    $line = Get-Content -LiteralPath $release -ErrorAction SilentlyContinue | Where-Object { $_ -match '^JAVA_VERSION=' } | Select-Object -First 1
    if ($line -notmatch 'JAVA_VERSION="?(\d+)') { return $false }
    return ([int]$Matches[1] -ge 17)
}

function Resolve-EdtWtGuiJvm {
    <#
      Выбор JVM для GUI (spec 7.3): edt.vm_path, затем -vm из 1cedt.ini (тогда
      -vm не передаётся), JAVA_HOME с JavaFX, известные каталоги JDK, иначе none.
      Path - полный путь к bin\server\jvm.dll либо $null.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$EdtGuiPath,
        [string]$VmPath,
        [string[]]$SearchRoots
    )

    $toDll = {
        param([string]$p)
        $p = $p -replace '/', '\'
        if ($p -match '\.dll$') { return $p }
        return (Join-Path $p 'bin\server\jvm.dll')
    }
    $result = { param($path, $reason) [pscustomobject]@{ Path = $path; Reason = $reason } }

    if ($VmPath) {
        $dll = & $toDll $VmPath
        if (Test-Path -LiteralPath $dll) { return (& $result $dll 'config') }
    }

    $ini = Join-Path (Split-Path -Parent $EdtGuiPath) '1cedt.ini'
    if (Test-Path -LiteralPath $ini) {
        $lines = @(Get-Content -LiteralPath $ini -Encoding UTF8 | ForEach-Object { $_.Trim() })
        $vmargsAt = [array]::IndexOf($lines, '-vmargs')
        $head = if ($vmargsAt -gt 0) { $lines[0..($vmargsAt - 1)] } elseif ($vmargsAt -eq 0) { @() } else { $lines }
        if (@($head) -contains '-vm') { return (& $result $null 'ini') }
    }

    if ($env:JAVA_HOME) {
        $javaHome = $env:JAVA_HOME -replace '/', '\'
        $dll = & $toDll $javaHome
        if ((Test-Path -LiteralPath $dll) -and (Test-EdtWtJdkHasJavaFx -JdkHome $javaHome)) {
            return (& $result $dll 'JAVA_HOME')
        }
    }

    if (-not $PSBoundParameters.ContainsKey('SearchRoots')) {
        $SearchRoots = @(
            "$env:ProgramFiles\Zulu\*",
            "$env:ProgramFiles\BellSoft\*",
            "$env:ProgramFiles\Axiom*\*",
            "$env:ProgramFiles\Java\*"
        )
    }
    foreach ($root in $SearchRoots) {
        if (-not $root) { continue }
        $pattern = if ($root -match '[\*\?]') { $root } else { Join-Path $root '*' }
        # Числа в имени дополняются нулями: zulu17.10 новее zulu17.9.
        $versionKey = { [regex]::Replace($_.Name, '\d+', { param($m) $m.Value.PadLeft(10, '0') }) }
        $dirs = @(Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue | Sort-Object $versionKey -Descending)
        foreach ($d in $dirs) {
            $dll = & $toDll $d.FullName
            if ((Test-Path -LiteralPath $dll) -and (Test-EdtWtJdkHasJavaFx -JdkHome $d.FullName)) {
                return (& $result $dll 'scan')
            }
        }
    }

    return (& $result $null 'none')
}

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
    # stderr читается асинхронно ДО синхронного чтения stdout: иначе переполнение
    # буфера любого из потоков вешает процесс и вызывающего.
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $stderrTask.GetAwaiter().GetResult()
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
