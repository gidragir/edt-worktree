function Update-EdtSelf {
    <#
    .SYNOPSIS
        Обновляет модуль EdtWorktree из исходного Git-репозитория.

    .DESCRIPTION
        Находит клон модуля (с переходом по junction/symlink), выполняет
        git pull --ff-only и перезагружает модуль. Требует git в PATH.

    .EXAMPLE
        Update-EdtSelf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (-not (Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'git не найден в PATH. Установите: winget install Git.Git'
    }

    $mod = Get-Module -Name EdtWorktree
    $modBase = if ($mod) { $mod.ModuleBase } else { $script:EdtWtModuleRoot }

    $targetPath = $modBase
    $item = Get-Item -LiteralPath $modBase -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -and $item.Target) {
        $targetPath = @($item.Target)[0]
    }

    $curr = $targetPath
    $repoDir = $null
    while ($curr) {
        if (Test-Path -LiteralPath (Join-Path $curr '.git')) {
            $repoDir = $curr
            break
        }
        $parent = Split-Path -Parent $curr
        if (-not $parent -or $parent -eq $curr) { break }
        $curr = $parent
    }

    if (-not $repoDir) {
        throw "Не удалось найти Git-репозиторий для модуля в '$targetPath'. Убедитесь, что модуль установлен из git-репозитория."
    }

    if (-not $PSCmdlet.ShouldProcess($repoDir, 'Обновить модуль из Git-репозитория')) {
        return
    }

    Write-Host "==> Обновление модуля EdtWorktree из: $repoDir" -ForegroundColor Cyan

    $remotes = Invoke-EdtWtGit -C $repoDir remote
    if (-not $remotes) {
        Write-Host '    ! В репозитории не настроен remote (удалённый сервер).' -ForegroundColor Yellow
        Write-Host '    Для включения автообновлений добавьте remote: git remote add origin <url>' -ForegroundColor Yellow
        return
    }

    $out = Invoke-EdtWtGit -C $repoDir pull --ff-only 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    Ошибка git pull: $out" -ForegroundColor Red
        throw "Не удалось обновить репозиторий: $out"
    }
    Write-Host "    $out" -ForegroundColor Gray

    Write-Host '==> Перезагрузка модуля в сессии...' -ForegroundColor Cyan
    $manifest = Join-Path $repoDir 'src\EdtWorktree\EdtWorktree.psd1'
    if (Test-Path -LiteralPath $manifest) {
        Import-Module $manifest -Force -DisableNameChecking
    } else {
        Import-Module EdtWorktree -Force -DisableNameChecking
    }

    Write-Host 'Модуль EdtWorktree обновлён.' -ForegroundColor Green
}
