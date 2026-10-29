function Update-EdtSelf {
    <#
    .SYNOPSIS
        Обновляет модуль EdtWorktree способом, подходящим виду установки.

    .DESCRIPTION
        Gallery - Update-PSResource (или Update-Module). Zip - скачивает install.ps1
        последнего выпуска и запускает его с -NoSetup. Dev - git pull --ff-only в клоне
        разработчика. Legacy (клон 3.0) - просит переустановить модуль. После обновления
        модуль перезагружается в сессии.

    .EXAMPLE
        Update-EdtSelf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $info = Get-EdtWtInstallInfo
    $installerUrl = 'https://github.com/gidragir/edt-worktree/releases/latest/download/install.ps1'

    switch ($info.Kind) {
        'Legacy' {
            throw "Установка 3.0 через клон. Переустановите: irm $installerUrl | iex"
        }
        'Gallery' {
            if (-not $PSCmdlet.ShouldProcess('EdtWorktree', 'Обновить модуль из PowerShell Gallery')) { return }
            Write-Host '==> Обновление модуля EdtWorktree из PowerShell Gallery...' -ForegroundColor Cyan
            if (Get-Command -Name Update-PSResource -ErrorAction SilentlyContinue) {
                Update-PSResource -Name EdtWorktree -Repository PSGallery
            } else {
                Update-Module -Name EdtWorktree
            }
            Write-Host '==> Перезагрузка модуля в сессии...' -ForegroundColor Cyan
            Import-Module EdtWorktree -Force -DisableNameChecking
        }
        'Zip' {
            $base = if ($env:EDT_RELEASE_URL) { $env:EDT_RELEASE_URL.TrimEnd('/') } else { 'https://github.com/gidragir/edt-worktree/releases/latest/download' }
            $url = "$base/install.ps1"
            if (-not $PSCmdlet.ShouldProcess('EdtWorktree', "Обновить модуль установщиком из $url")) { return }
            Write-Host "==> Обновление модуля EdtWorktree: $url" -ForegroundColor Cyan
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('edtwt-install-' + [guid]::NewGuid().ToString('N') + '.ps1')
            try {
                Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
                & pwsh -NoProfile -File $tmp -NoSetup
                if ($LASTEXITCODE -ne 0) { throw "Установщик завершился с кодом $LASTEXITCODE." }
            } finally {
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }
            Write-Host '==> Перезагрузка модуля в сессии...' -ForegroundColor Cyan
            Import-Module EdtWorktree -Force -DisableNameChecking
        }
        'Dev' {
            if (-not (Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue)) {
                throw 'git не найден в PATH. Установите: winget install Git.Git'
            }
            $repoDir = $info.CloneDir
            if (-not $PSCmdlet.ShouldProcess($repoDir, 'Обновить модуль из Git-репозитория')) { return }
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
        }
    }

    Write-Host 'Модуль EdtWorktree обновлён.' -ForegroundColor Green
}