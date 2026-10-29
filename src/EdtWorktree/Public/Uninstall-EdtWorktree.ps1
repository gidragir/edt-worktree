function Uninstall-EdtWorktree {
    <#
    .SYNOPSIS
        Удаляет установку модуля способом, подходящим виду установки.

    .DESCRIPTION
        Сначала печатает список удаляемого, затем (после подтверждения) удаляет модуль:
        Gallery - Uninstall-PSResource (или Uninstall-Module), Zip - каталог модуля в
        Modules, Dev и Legacy - только ссылку на клон. Во всех случаях убирается shim edt
        и его запись в PATH; для Legacy - ещё и <клон>\bin из PATH. Конфиг, клоны,
        worktree и рабочие области не трогает. -Purge дополнительно удаляет конфиг и
        (для Dev и Legacy, если в нём нет незафиксированных изменений) клон.
        EDT_PATH_SCOPE=Process (для тестов) ограничивает правку PATH процессом.

    .PARAMETER Purge
        Удалить также каталог конфигурации и клон (Dev, Legacy).

    .EXAMPLE
        Uninstall-EdtWorktree -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([switch]$Purge)

    $info = Get-EdtWtInstallInfo
    $processOnly = ($env:EDT_PATH_SCOPE -eq 'Process')
    $isClone = $info.Kind -in 'Dev', 'Legacy'
    $legacyBin = if ($info.Kind -eq 'Legacy') { Join-Path $info.CloneDir 'bin' } else { $null }
    $scope = if ($processOnly) { ' (только процесс)' } else { ' (пользователь)' }

    Write-Host "==> Будет удалено (вид установки: $($info.Kind)):" -ForegroundColor Cyan
    switch ($info.Kind) {
        'Gallery' { Write-Host '    модуль EdtWorktree из PowerShell Gallery (все версии)' }
        'Zip' { Write-Host "    каталог модуля:  $($info.ModuleLink)" }
        default { Write-Host "    ссылка модуля:  $($info.ModuleLink)" }
    }
    Write-Host "    shim edt:  $($info.ShimDir)  и запись в PATH$scope"
    if ($legacyBin) { Write-Host "    запись в PATH:  $legacyBin$scope" }
    if ($Purge) {
        if ($isClone) { Write-Host "    клон (если нет незафиксированных изменений): $($info.CloneDir)" }
        Write-Host "    каталог конфигурации: $($info.ConfigDir)"
    }
    Write-Host '    Клоны, worktree и рабочие области не затрагиваются.' -ForegroundColor Gray

    if (-not $PSCmdlet.ShouldProcess($info.ModuleLink, 'Удалить установку EdtWorktree')) { return }

    # Решение о клоне принимается до удаления ссылки.
    $purgeClone = $false
    if ($Purge -and $isClone) {
        switch (Test-EdtWtDirtyWorkTree -Path $info.CloneDir) {
            'dirty' { Write-Warning "Клон не удалён: в нём есть незафиксированные изменения git ($($info.CloneDir)). Закоммитьте или уберите их (stash) либо удалите каталог вручную." }
            'unverified' { Write-Warning "Клон не удалён: не удалось проверить состояние git ($($info.CloneDir)). Проверьте каталог и удалите его вручную." }
            default { $purgeClone = $true }
        }
    }

    switch ($info.Kind) {
        'Gallery' {
            if (Get-Command -Name Uninstall-PSResource -ErrorAction SilentlyContinue) {
                Uninstall-PSResource -Name EdtWorktree -Version '*'
            } else {
                Uninstall-Module -Name EdtWorktree -AllVersions -Force
            }
        }
        default {
            if (Get-Item -LiteralPath $info.ModuleLink -Force -ErrorAction SilentlyContinue) {
                Remove-EdtWtModuleLink -Path $info.ModuleLink
            }
        }
    }

    Remove-EdtWtShim

    if ($legacyBin) {
        if (-not $processOnly) {
            $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
            if ($userPath) {
                $newUser = Remove-EdtWtPathEntry -PathValue $userPath -Entry $legacyBin
                if ($newUser -ne $userPath) { [Environment]::SetEnvironmentVariable('Path', $newUser, 'User') }
            }
        }
        $env:Path = Remove-EdtWtPathEntry -PathValue $env:Path -Entry $legacyBin
    }

    if ($Purge) {
        if ($purgeClone -and (Get-Item -LiteralPath $info.CloneDir -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $info.CloneDir -Recurse -Force
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