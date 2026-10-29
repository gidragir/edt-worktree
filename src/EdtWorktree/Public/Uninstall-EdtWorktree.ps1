function Uninstall-EdtWorktree {
    <#
    .SYNOPSIS
        Удаляет установку модуля: ссылку в Modules и запись bin из PATH пользователя.

    .DESCRIPTION
        Сначала печатает список удаляемого, затем (после подтверждения) удаляет ссылку
        модуля и каталог bin из PATH. Конфиг, клоны, worktree и рабочие области не
        трогает. -Purge дополнительно удаляет каталог установки и каталог конфигурации.
        EDT_PATH_SCOPE=Process (для тестов) ограничивает правку PATH процессом.

    .PARAMETER Purge
        Удалить также каталог установки и каталог конфигурации.

    .EXAMPLE
        Uninstall-EdtWorktree -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([switch]$Purge)

    $info = Get-EdtWtInstallInfo
    $processOnly = ($env:EDT_PATH_SCOPE -eq 'Process')

    Write-Host '==> Будет удалено:' -ForegroundColor Cyan
    Write-Host "    ссылка модуля:  $($info.ModuleLink)"
    Write-Host "    запись в PATH:  $($info.BinDir)$(if ($processOnly) { ' (только процесс)' } else { ' (пользователь)' })"
    if ($Purge) {
        Write-Host "    каталог установки: $($info.InstallDir)"
        Write-Host "    каталог конфигурации: $($info.ConfigDir)"
    }
    Write-Host '    Клоны, worktree и рабочие области не затрагиваются.' -ForegroundColor Gray

    if (-not $PSCmdlet.ShouldProcess($info.ModuleLink, 'Удалить установку EdtWorktree')) { return }

    # Решение о каталоге установки принимается до удаления ссылки (для копии каталог и есть ссылка).
    $purgeInstall = $false
    if ($Purge) {
        if (-not $info.ViaLink) {
            Write-Warning "Каталог установки не удалён: ссылки модуля нет, а текущий каталог модуля ($($info.InstallDir)) может быть рабочим клоном. Удалите его вручную."
        } else {
            switch (Test-EdtWtDirtyWorkTree -Path $info.InstallDir) {
                'dirty' { Write-Warning "Каталог установки не удалён: в нём есть незафиксированные изменения git ($($info.InstallDir)). Закоммитьте или уберите их (stash) либо удалите каталог вручную." }
                'unverified' { Write-Warning "Каталог установки не удалён: не удалось проверить состояние git ($($info.InstallDir)). Проверьте каталог и удалите его вручную." }
                default { $purgeInstall = $true }
            }
        }
    }

    if (Get-Item -LiteralPath $info.ModuleLink -Force -ErrorAction SilentlyContinue) {
        Remove-EdtWtModuleLink -Path $info.ModuleLink
    }

    if (-not $processOnly) {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($userPath) {
            $newUser = Remove-EdtWtPathEntry -PathValue $userPath -Entry $info.BinDir
            if ($newUser -ne $userPath) { [Environment]::SetEnvironmentVariable('Path', $newUser, 'User') }
        }
    }
    $env:Path = Remove-EdtWtPathEntry -PathValue $env:Path -Entry $info.BinDir

    if ($Purge) {
        if ($purgeInstall -and (Get-Item -LiteralPath $info.InstallDir -Force -ErrorAction SilentlyContinue)) {
            Remove-EdtWtModuleLink -Path $info.InstallDir
        }
        # Только файлы конфигурации; каталог удаляется, лишь если после этого пуст.
        $cfgFile = Get-EdtWtUserConfigPath
        $cfgDir = $info.ConfigDir
        if ($cfgDir -and (Test-Path -LiteralPath $cfgDir -PathType Container)) {
            $leaf = Split-Path -Leaf $cfgFile
            $owned = Get-ChildItem -LiteralPath $cfgDir -Force -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq $leaf -or $_.Name -like "$leaf.v2.bak*" -or $_.Name -eq "$leaf.tmp" }
            foreach ($f in $owned) { Remove-Item -LiteralPath $f.FullName -Force }
            if (-not (Get-ChildItem -LiteralPath $cfgDir -Force -ErrorAction SilentlyContinue) -and (Split-Path -Parent $cfgDir)) {
                Remove-Item -LiteralPath $cfgDir -Force
            }
        }
    }

    Write-Host '==> EdtWorktree удалён. Откройте новую сессию PowerShell.' -ForegroundColor Green
}
