function Get-EdtWtContext {
    <#
    .SYNOPSIS
        Собирает контекст текущего worktree: проект, пути, параметры EDT.

    .DESCRIPTION
        Определяет проект по клону (git rev-parse --git-common-dir): клон и все его
        worktree относятся к проекту с именем папки клона в repos_root. Вычисляет
        каталоги рабочей области и эталона (_reference), путь к 1cedtcli и GUI,
        аргументы JVM, эталонную ветку проекта (RefBranch) и расширения
        (Extensions - пути относительно клона). Незарегистрированный клон - ошибка.

    .PARAMETER Path
        Каталог внутри клона или его worktree. По умолчанию - текущий.

    .PARAMETER ProjectName
        Явное имя проекта: клон берётся из repos_root, если Path не указан
        и текущий каталог не внутри клона.

    .EXAMPLE
        Get-EdtWtContext | Select-Object ProjectId, WorkspaceDir, Extensions
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$Path,
        [string]$ProjectName
    )

    $cfg = Get-EdtWtConfig
    $reposRoot = $cfg.paths.repos_root

    $startPath = if ($Path) { $Path } else { (Get-Location).Path }
    $resolved = Resolve-EdtWtProjectFromPath -Path $startPath -Config $cfg
    if (-not $resolved -and $ProjectName -and -not $Path) {
        # Явный проект вне клона: работаем от самого клона.
        $startPath = Join-Path $reposRoot $ProjectName
        $resolved = Resolve-EdtWtProjectFromPath -Path $startPath -Config $cfg
    }
    if (-not $resolved) {
        throw "Каталог '$startPath' не относится к клону из repos_root ($reposRoot). Перейдите в клон проекта или его worktree либо укажите -ProjectName."
    }

    $projectId = if ($ProjectName) { $ProjectName } else { $resolved.Name }
    $projDef = Get-EdtWtProjectDef -Config $cfg -Name $projectId

    Push-Location -LiteralPath $startPath
    try {
        $topLevel = (Invoke-EdtWtGit rev-parse --show-toplevel 2>$null)
        if (-not $topLevel) { throw "Каталог '$startPath' не находится внутри git-репозитория." }
        $topLevel = ($topLevel -replace '/', '\')
        $branch = (Invoke-EdtWtGit rev-parse --abbrev-ref HEAD 2>$null)
    } finally {
        Pop-Location
    }

    $repoPath = if ($projectId -ne $resolved.Name) { Join-Path $reposRoot $projectId } else { $resolved.RepoPath }
    $edtCfg = $cfg.edt

    $worktreeId = if ($branch -and $branch -ne 'HEAD') { ConvertTo-EdtWtSafeName $branch } else { ConvertTo-EdtWtSafeName (Split-Path -Leaf $topLevel) }

    $edtCli = Get-EdtWtProperty $edtCfg 'cli_path'
    if (-not $edtCli) {
        $found = @(Find-EdtWtCli)
        if ($found.Count -gt 0) { $edtCli = $found[0].Path }
    }
    if (-not $edtCli) {
        throw "Путь к 1cedtcli не настроен. Установите 1C:EDT или укажите edt.cli_path в конфигурации (edt config set edt.cli_path <путь>)."
    }
    $edtCli = ($edtCli -replace '/', '\')
    $edtGui = Join-Path (Split-Path -Parent $edtCli) "1cedt.exe"

    # Неявный max_heap = авто: без -Xmx кучу подберёт Resolve-EdtWtJvmArgs.
    $maxHeap = Get-EdtWtProperty $edtCfg 'max_heap'
    $xmx = if ($maxHeap) { "-Xmx$maxHeap " } else { '' }
    $jvmArgs = "$xmx-Xms2g $(Get-EdtWtProperty $edtCfg 'extra_vmargs' '')".Trim()

    $workspacesRoot = ($cfg.paths.workspaces_root -replace '/', '\')
    $projectRootWs = Join-Path $workspacesRoot $projectId

    return [PSCustomObject]@{
        ProjectId      = $projectId
        WorktreeId     = $worktreeId
        Branch         = $branch
        WorktreePath   = $topLevel
        RepoPath       = $repoPath
        GitCommonDir   = Join-Path $repoPath '.git'
        ProjectWsRoot  = $projectRootWs
        WorkspaceDir   = Join-Path $projectRootWs $worktreeId
        ReferenceWsDir = Join-Path $projectRootWs '_reference'
        RefBranch      = Get-EdtWtProperty $projDef 'ref_branch' 'pre-prod'
        CfProject      = Get-EdtWtProperty $projDef 'cf_project' 'src/cf'
        Extensions     = [string[]]@(Get-EdtWtProperty $projDef 'extensions' @())
        EdtCliPath     = $edtCli
        EdtGuiPath     = $edtGui
        JvmArgs        = $jvmArgs
        VmPath         = Get-EdtWtProperty $edtCfg 'vm_path'
        GuiMaxHeap     = Get-EdtWtProperty $edtCfg 'gui_max_heap'
        TimeoutSec     = Get-EdtWtProperty $edtCfg 'timeout_sec' 7200
    }
}
