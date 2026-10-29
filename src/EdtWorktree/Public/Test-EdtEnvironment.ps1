function Test-EdtEnvironment {
    <#
    .SYNOPSIS
        Проверяет окружение и зарегистрированные проекты; для каждой проблемы даёт команду исправления.
    .DESCRIPTION
        Только чтение: не запускает процессов, не ходит в сеть и ничего не пишет,
        кроме однократного переноса конфига 2.x в v3 (как любая команда edt).
        Возвращает строки Check, Status (ok|warn|error), Detail, Fix. Не бросает
        исключений на пустом или повреждённом состоянии - такое состояние это
        строка error. Код возврата 1 при наличии error выставляет bin/edt.ps1.
    .EXAMPLE
        Test-EdtEnvironment | Format-Table -AutoSize
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()
    $add = {
        param([string]$Check, [string]$Status, [string]$Detail = '', [string]$Fix = '')
        $rows.Add([PSCustomObject]@{ PSTypeName = 'EdtWorktree.DoctorCheck'; Check = $Check; Status = $Status; Detail = $Detail; Fix = $Fix })
    }
    $quote = { param([string]$p) if ($p -match '\s') { "`"$p`"" } else { $p } }

    # Повреждённый конфиг - единственная строка отчёта.
    try {
        $cfg = Get-EdtWtConfig
    } catch {
        & $add 'Конфиг' 'error' $_.Exception.Message 'Исправьте файл или удалите его и выполните edt setup'
        return $rows.ToArray()
    }
    # PowerShell и git
    $psVer = $PSVersionTable.PSVersion
    if ($psVer.Major -ge 7) { & $add 'PowerShell 7+' 'ok' "$psVer" }
    else { & $add 'PowerShell 7+' 'error' "Версия $psVer" 'winget install Microsoft.PowerShell' }

    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($git) { & $add 'git в PATH' 'ok' $git.Source }
    else { & $add 'git в PATH' 'error' 'git не найден' 'winget install Git.Git' }

    # EDT
    $edtCli = $null
    $edtDetail = ''
    $cliPath = Get-EdtWtProperty $cfg.edt 'cli_path'
    if ($cliPath) {
        if (Test-Path -LiteralPath $cliPath) {
            $edtCli = $cliPath
            $edtDetail = "$cliPath (edt.cli_path)"
        } else {
            & $add 'EDT' 'error' "edt.cli_path указывает на несуществующий файл: $cliPath" 'edt config set edt.cli_path null'
        }
    } else {
        $found = @(Find-EdtWtCli)
        if ($found.Count -gt 0) {
            $edtCli = $found[0].Path
            $edtDetail = "$($found[0].Path) (версия $($found[0].Version), автопоиск)"
        } else {
            & $add 'EDT' 'error' '1cedtcli не найден' 'edt config set edt.cli_path <путь к 1cedtcli.exe>'
        }
    }
    if ($edtCli) { & $add 'EDT' 'ok' $edtDetail }

    # JVM для GUI
    $vmPath = Get-EdtWtProperty $cfg.edt 'vm_path'
    if ($edtCli) {
        $gui = Join-Path (Split-Path -Parent ($edtCli -replace '/', '\')) '1cedt.exe'
        try {
            $jvm = Resolve-EdtWtGuiJvm -EdtGuiPath $gui -VmPath $vmPath
            if ($jvm.Reason -eq 'none') {
                & $add 'JVM для GUI' 'warn' 'JDK 17 с JavaFX не найдена, EDT запустится без -vm' 'edt config set edt.vm_path <путь к JDK с JavaFX>'
            } else {
                $what = if ($jvm.Path) { $jvm.Path } else { 'без -vm (задан в 1cedt.ini)' }
                & $add 'JVM для GUI' 'ok' "$what (причина: $($jvm.Reason))"
            }
        } catch {
            & $add 'JVM для GUI' 'error' "Не удалось определить JVM: $($_.Exception.Message)" 'edt config set edt.vm_path <путь к JDK с JavaFX>'
        }
    }
    if ($vmPath) {
        $dll = ($vmPath -replace '/', '\')
        if ($dll -notmatch '\.dll$') { $dll = Join-Path $dll 'bin\server\jvm.dll' }
        if (-not (Test-Path -LiteralPath $dll)) {
            & $add 'edt.vm_path' 'warn' "jvm.dll не найден по edt.vm_path: $vmPath" 'edt config set edt.vm_path <путь> (или edt config set edt.vm_path null)'
        }
    }

    # Пути конфига
    foreach ($key in 'repos_root', 'worktrees_root', 'workspaces_root') {
        $dir = [string](Get-EdtWtProperty $cfg.paths $key '')
        if ($dir -and (Test-Path -LiteralPath $dir)) { & $add "paths.$key" 'ok' $dir }
        else { & $add "paths.$key" 'error' "Каталог не существует: $dir" 'edt setup' }
    }

    # Проекты
    $names = @($cfg.projects.PSObject.Properties | ForEach-Object { $_.Name })
    if ($names.Count -eq 0) {
        & $add 'Проекты' 'warn' 'Нет зарегистрированных проектов' 'edt project add'
    }
    foreach ($n in $names) {
        # Сбой одной проверки - строка error, остальные проекты проверяются дальше.
        try {
            $def = $cfg.projects.$n
            $repo = Join-Path ([string]$cfg.paths.repos_root) $n
            $ref = [string](Get-EdtWtProperty $def 'ref_branch' '')

            if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) {
                & $add "[$n] клон" 'error' "Клон не найден: $repo" "edt project remove $n (или клонируйте репозиторий в $repo)"
                continue
            }
            & $add "[$n] клон" 'ok' $repo

            $branch = Get-EdtWtCloneBranch -RepoPath $repo
            if ($branch -eq $ref) {
                & $add "[$n] ветка клона" 'ok' $branch
            } else {
                $shown = if ($branch) { $branch } else { 'HEAD отсоединён' }
                & $add "[$n] ветка клона" 'error' "Клон на '$shown', ожидается '$ref'" "git -C $(& $quote $repo) switch $ref"
            }

            $working = @(@(Get-EdtWtProperty $def 'extensions' @()) | Where-Object { $_ })
            foreach ($ext in $working) {
                if (-not (Test-Path -LiteralPath (Join-Path $repo $ext))) {
                    & $add "[$n] расширение $ext" 'warn' "Рабочее расширение отсутствует на диске: $ext" "edt project ext $n -$(Split-Path -Leaf $ext)"
                }
            }

            $context = [PSCustomObject]@{ RepoPath = $repo; Extensions = [string[]]$working }
            $unused = @(Get-EdtWtUnusedExtensions -Context $context)
            if ($unused.Count -gt 0) {
                & $add "[$n] новые расширения" 'warn' "Не в списке рабочих: $($unused -join ', ')" "edt project ext $n"
            }

            $projectWs = Join-Path ([string]$cfg.paths.workspaces_root) $n
            $reference = Join-Path $projectWs '_reference'
            if (Test-Path -LiteralPath $reference) { & $add "[$n] эталон" 'ok' $reference }
            elseif (Test-Path -LiteralPath (Join-Path $projectWs '_reference_preprod')) {
                & $add "[$n] эталон" 'warn' 'Эталон 2.x _reference_preprod: warmup переименует его в _reference и пересоберёт' "edt warmup $n"
            }
            else { & $add "[$n] эталон" 'warn' 'Эталонная рабочая область не собрана' "edt warmup $n" }
        } catch {
            & $add "[$n] проверка" 'error' "Проверка проекта прервалась: $($_.Exception.Message)" "edt project list"
        }
    }

    return $rows.ToArray()
}
