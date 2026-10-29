BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    # Защита реальной среды: конфиг, shim, Modules и PATH - только временные (EDT_PATH_SCOPE=Process).
    $script:TestCfg = Enter-EdtWtTestConfig
    $script:PrevNoAutorun = $env:EDT_INSTALL_NO_AUTORUN
    $script:PrevPath = $env:Path
    $script:RepoRoot = Get-EdtWtTestRepoRoot
    # Профиль с пробелом и кириллицей, как у реального пользователя.
    $script:UserHome = Join-Path $script:TestCfg.Root 'Иван Петров'
    $env:EDT_SHIM_DIR = Join-Path $script:UserHome 'AppData\Local\EdtWorktree\bin'

    # Сборка выпуска во временный каталог: zip и установщик как в релизе.
    $script:BuildDir = Join-Path $script:UserHome 'сборка out'
    $script:Build = & (Join-Path $script:RepoRoot 'scripts\build.ps1') -OutputDir $script:BuildDir 6>$null
    $script:Version = $script:Build.Version

    # Архив ветки в раскладке GitHub: <repo>-<ветка>\src\EdtWorktree\...
    $branchRoot = Join-Path $script:UserHome 'branch-src'
    $branchModule = Join-Path $branchRoot 'edt-worktree-feature-x\src\EdtWorktree'
    New-Item -ItemType Directory -Path (Split-Path -Parent $branchModule) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'src\EdtWorktree') -Destination $branchModule -Recurse
    New-Item -ItemType Directory -Path (Join-Path $branchRoot 'edt-worktree-feature-x\Tests') -Force | Out-Null
    $script:BranchZip = Join-Path $script:UserHome 'branch.zip'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($branchRoot, $script:BranchZip)

    # Копия установщика вне клона: $PSScriptRoot без src\, как под irm | iex.
    $script:StandaloneDir = Join-Path $script:UserHome 'standalone'
    New-Item -ItemType Directory -Path $script:StandaloneDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'scripts\install.ps1') -Destination $script:StandaloneDir

    $env:EDT_INSTALL_NO_AUTORUN = '1'
    . (Join-Path $script:StandaloneDir 'install.ps1')

    $script:Pwsh = (Get-Process -Id $PID).Path
    $script:NewCase = {
        $case = Join-Path $script:UserHome ('случай ' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $case -Force | Out-Null
        return $case
    }
}

AfterAll {
    $env:EDT_INSTALL_NO_AUTORUN = $script:PrevNoAutorun
    $env:Path = $script:PrevPath
    Exit-EdtWtTestConfig -State $script:TestCfg
}

Describe 'Install-EdtWorktree из zip' {
    BeforeEach {
        $env:EDT_PATH_SCOPE | Should -BeExactly 'Process'
        $script:case = & $script:NewCase
        $script:mods = Join-Path $script:case 'Документы\PowerShell\Modules'
    }
    AfterEach { $env:Path = $script:PrevPath }

    It 'ставит из -ZipPath в Modules\EdtWorktree\{версия}' {
        Install-EdtWorktree -ZipPath $script:Build.ZipPath -ModulesDir $mods -NoSetup -NoPath 6>$null
        $psd1 = Join-Path $mods "EdtWorktree\$($script:Version)\EdtWorktree.psd1"
        Test-Path -LiteralPath $psd1 | Should -BeTrue
        $v = & $script:Pwsh -NoProfile -Command { param($p) (Import-Module $p -PassThru -DisableNameChecking).Version.ToString() } -args $psd1
        $v | Should -Be $script:Version
    }

    It 'повторная установка той же версии заменяет каталог, другие версии остаются' {
        $old = Join-Path $mods 'EdtWorktree\0.0.1'
        New-Item -ItemType Directory -Path $old -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $old 'marker.txt') -Value 'x'
        Install-EdtWorktree -ZipPath $script:Build.ZipPath -ModulesDir $mods -NoSetup -NoPath 6>$null
        $cur = Join-Path $mods "EdtWorktree\$($script:Version)"
        Set-Content -LiteralPath (Join-Path $cur 'stale.txt') -Value 'x'
        Install-EdtWorktree -ZipPath $script:Build.ZipPath -ModulesDir $mods -NoSetup -NoPath 6>$null
        Test-Path -LiteralPath (Join-Path $cur 'stale.txt') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $cur 'EdtWorktree.psd1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $old 'marker.txt') | Should -BeTrue
        @(Get-ChildItem -LiteralPath (Join-Path $mods 'EdtWorktree') -Force).Name | Sort-Object | Should -Be (@('0.0.1', $script:Version) | Sort-Object)
    }

    It 'снимает старую ссылку 3.0, не трогая грязный клон' {
        $clone = Join-Path $script:case 'клон 3.0'
        New-Item -ItemType Directory -Path (Join-Path $clone 'bin') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $clone 'EdtWorktree.psd1') -Value '@{}'
        Set-Content -LiteralPath (Join-Path $clone 'bin\edt.cmd') -Value '@echo off'
        $gitExe = (Get-Command git -CommandType Application | Select-Object -First 1).Source
        $null = & $gitExe -C $clone init -q 2>&1
        Set-Content -LiteralPath (Join-Path $clone 'незакоммиченное.txt') -Value 'работа'
        New-Item -ItemType Directory -Path $mods -Force | Out-Null
        New-Item -ItemType Junction -Path (Join-Path $mods 'EdtWorktree') -Target $clone | Out-Null
        $cloneBin = Join-Path $clone 'bin'
        $env:Path = 'C:\edtwt-test-a;' + $cloneBin + ';C:\edtwt-test-b'

        $out = Install-EdtWorktree -ZipPath $script:Build.ZipPath -ModulesDir $mods -NoSetup -NoPath 6>&1 | Out-String

        $item = Get-Item -LiteralPath (Join-Path $mods 'EdtWorktree') -Force
        [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint) | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $mods "EdtWorktree\$($script:Version)\EdtWorktree.psd1") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $clone '.git') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $clone 'EdtWorktree.psd1') | Should -BeTrue
        Get-Content -LiteralPath (Join-Path $clone 'незакоммиченное.txt') | Should -Be 'работа'
        (& $gitExe -C $clone status --porcelain 2>$null) -join "`n" | Should -Match 'txt'
        @($env:Path -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ieq $cloneBin }).Count | Should -Be 0
        $env:Path | Should -Be 'C:\edtwt-test-a;C:\edtwt-test-b'
        $out | Should -Match 'Старая установка 3\.0 снята'
        $out | Should -Match ([regex]::Escape($clone))
    }

    It 'ставит shim, если не задан -NoPath' {
        $env:EDT_PATH_SCOPE | Should -BeExactly 'Process'
        Install-EdtWorktree -ZipPath $script:Build.ZipPath -ModulesDir $mods -NoSetup 6>$null
        Test-Path -LiteralPath (Join-Path $env:EDT_SHIM_DIR 'edt.cmd') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $env:EDT_SHIM_DIR 'edt.ps1') | Should -BeTrue
        @($env:Path -split ';' | Where-Object { $_ -eq $env:EDT_SHIM_DIR }).Count | Should -Be 1
    }

    It 'при -NoPath не меняет PATH и не ставит shim' {
        $shim = Join-Path $script:case 'shim'
        $prevShim = $env:EDT_SHIM_DIR
        $env:EDT_SHIM_DIR = $shim
        try {
            $before = $env:Path
            Install-EdtWorktree -ZipPath $script:Build.ZipPath -ModulesDir $mods -NoSetup -NoPath 6>$null
            $env:Path | Should -BeExactly $before
            Test-Path -LiteralPath $shim | Should -BeFalse
        } finally { $env:EDT_SHIM_DIR = $prevShim }
    }

    It 'git для установки не нужен' {
        $env:Path = 'C:\edtwt-no-git'
        Install-EdtWorktree -ZipPath $script:Build.ZipPath -ModulesDir $mods -NoSetup -NoPath 6>$null
        Test-Path -LiteralPath (Join-Path $mods "EdtWorktree\$($script:Version)\EdtWorktree.psd1") | Should -BeTrue
    }

    It '-ZipPath вместе с -Branch - ошибка' {
        { Install-EdtWorktree -ZipPath $script:Build.ZipPath -Branch main -ModulesDir $mods -NoSetup -NoPath 6>$null } |
            Should -Throw '*взаимоисключающ*'
        Test-Path -LiteralPath $mods | Should -BeFalse
    }

    It '-Dev вместе с -ZipPath - ошибка' {
        { Install-EdtWorktree -Dev -ZipPath $script:Build.ZipPath -ModulesDir $mods -NoSetup -NoPath 6>$null } |
            Should -Throw '*взаимоисключающ*'
    }

    It 'по умолчанию скачивает EdtWorktree.zip из EDT_RELEASE_URL' {
        $prev = $env:EDT_RELEASE_URL
        $env:EDT_RELEASE_URL = ([Uri]$script:BuildDir).AbsoluteUri
        try {
            Install-EdtWorktree -ModulesDir $mods -NoSetup -NoPath 6>$null
        } finally { $env:EDT_RELEASE_URL = $prev }
        Test-Path -LiteralPath (Join-Path $mods "EdtWorktree\$($script:Version)\EdtWorktree.psd1") | Should -BeTrue
    }

    It '-Branch скачивает архив ветки и ставит src\EdtWorktree' {
        Mock Get-EdtWtInstallDownload { Copy-Item -LiteralPath $script:BranchZip -Destination $OutFile } -ParameterFilter {
            $Url -eq 'https://github.com/gidragir/edt-worktree/archive/refs/heads/feature/x.zip'
        }
        Install-EdtWorktree -Branch 'feature/x' -ModulesDir $mods -NoSetup -NoPath 6>$null
        Should -Invoke Get-EdtWtInstallDownload -Times 1 -Exactly
        $srcVersion = (Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'src\EdtWorktree\EdtWorktree.psd1')).ModuleVersion
        Test-Path -LiteralPath (Join-Path $mods "EdtWorktree\$srcVersion\EdtWorktree.psd1") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $mods "EdtWorktree\$srcVersion\Private") | Should -BeTrue
    }

    It 'форма scriptblock передаёт ключи в Install-EdtWorktree' {
        # Если ключи потеряются, установка уйдёт в каталог из переменной окружения.
        $names = 'EDT_INSTALL_NO_AUTORUN', 'EDT_INSTALL_NOSETUP', 'EDT_MODULES_DIR', 'EDT_INSTALL_ZIP'
        $prev = @{}
        foreach ($n in $names) { $prev[$n] = [Environment]::GetEnvironmentVariable($n) }
        $env:EDT_INSTALL_NO_AUTORUN = $null
        $env:EDT_INSTALL_NOSETUP = '1'
        $env:EDT_MODULES_DIR = Join-Path $script:case 'env-mods'
        $env:EDT_INSTALL_ZIP = Join-Path $script:case 'нет такого.zip'
        try {
            $text = Get-Content -LiteralPath (Join-Path $script:StandaloneDir 'install.ps1') -Raw
            & ([scriptblock]::Create($text)) -ZipPath $script:Build.ZipPath -ModulesDir $mods -NoSetup -NoPath 6>$null
        } finally {
            foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $prev[$n]) }
        }
        Test-Path -LiteralPath (Join-Path $mods "EdtWorktree\$($script:Version)\EdtWorktree.psd1") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:case 'env-mods') | Should -BeFalse
    }

    It 'под iex берёт EDT_INSTALL_ZIP и EDT_INSTALL_NOSETUP' {
        $names = 'EDT_INSTALL_NO_AUTORUN', 'EDT_INSTALL_NOSETUP', 'EDT_MODULES_DIR', 'EDT_INSTALL_ZIP'
        $prev = @{}
        foreach ($n in $names) { $prev[$n] = [Environment]::GetEnvironmentVariable($n) }
        $env:EDT_INSTALL_NO_AUTORUN = $null
        $env:EDT_INSTALL_NOSETUP = '1'
        $env:EDT_MODULES_DIR = $mods
        $env:EDT_INSTALL_ZIP = $script:Build.ZipPath
        try {
            $text = Get-Content -LiteralPath (Join-Path $script:StandaloneDir 'install.ps1') -Raw
            # Как под irm | iex: без ключей, $args пуст.
            & ([scriptblock]::Create($text)) 6>$null
        } finally {
            foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $prev[$n]) }
        }
        Test-Path -LiteralPath (Join-Path $mods "EdtWorktree\$($script:Version)\EdtWorktree.psd1") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $env:EDT_SHIM_DIR 'edt.cmd') | Should -BeTrue
    }
}

Describe 'Install-EdtWorktree -Dev' {
    BeforeEach {
        $script:case = & $script:NewCase
        $script:mods = Join-Path $script:case 'Документы\PowerShell\Modules'
        $script:SrcModule = Join-Path $script:RepoRoot 'src\EdtWorktree'
        $script:RunDev = {
            param([string]$Mods)
            & $script:Pwsh -NoProfile -Command {
                param($Installer, $Mods)
                $env:EDT_INSTALL_NO_AUTORUN = '1'
                . $Installer
                Install-EdtWorktree -Dev -ModulesDir $Mods -NoSetup -NoPath 6>$null
                [string](Get-Item -LiteralPath (Join-Path $Mods 'EdtWorktree') -Force).Target
            } -args (Join-Path $script:RepoRoot 'scripts\install.ps1'), $Mods
        }
    }

    It '-Dev ставит Junction на src\EdtWorktree' {
        $target = & $script:RunDev $mods | Select-Object -Last 1
        $target | Should -Be $script:SrcModule
        (Get-Item -LiteralPath (Join-Path $mods 'EdtWorktree') -Force).LinkType | Should -Be 'Junction'
        Test-Path -LiteralPath (Join-Path $mods 'EdtWorktree\EdtWorktree.psd1') | Should -BeTrue
    }

    It 'повторный -Dev пересоздаёт ссылку, не трогая src' {
        & $script:RunDev $mods | Out-Null
        $target = & $script:RunDev $mods | Select-Object -Last 1
        $target | Should -Be $script:SrcModule
        Test-Path -LiteralPath (Join-Path $script:SrcModule 'EdtWorktree.psd1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:SrcModule 'Public') | Should -BeTrue
    }

    It '-Dev вне клона - ошибка' {
        { Install-EdtWorktree -Dev -ModulesDir $mods -NoSetup -NoPath 6>$null } | Should -Throw '*клон*'
        Test-Path -LiteralPath $mods | Should -BeFalse
    }

    It '-Dev поверх установленных версий - ошибка, версии на месте' {
        $ver = Join-Path $mods 'EdtWorktree\4.0.0'
        New-Item -ItemType Directory -Path $ver -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $ver 'EdtWorktree.psd1') -Value '@{}'
        $out = & $script:Pwsh -NoProfile -Command {
            param($Installer, $Mods)
            $env:EDT_INSTALL_NO_AUTORUN = '1'
            . $Installer
            try { Install-EdtWorktree -Dev -ModulesDir $Mods -NoSetup -NoPath 6>$null; 'NO-ERROR' } catch { 'ERROR: ' + $_.Exception.Message }
        } -args (Join-Path $script:RepoRoot 'scripts\install.ps1'), $mods
        ($out | Select-Object -Last 1) | Should -BeLike 'ERROR: *'
        Test-Path -LiteralPath (Join-Path $ver 'EdtWorktree.psd1') | Should -BeTrue
    }

    It 'zip поверх ссылки -Dev снимает ссылку и не трогает src' {
        & $script:RunDev $mods | Out-Null
        Install-EdtWorktree -ZipPath $script:Build.ZipPath -ModulesDir $mods -NoSetup -NoPath 6>$null
        $item = Get-Item -LiteralPath (Join-Path $mods 'EdtWorktree') -Force
        [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint) | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $mods "EdtWorktree\$($script:Version)\EdtWorktree.psd1") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:SrcModule 'EdtWorktree.psd1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:SrcModule "$($script:Version)") | Should -BeFalse
    }
}

Describe 'Add-EdtWtInstallPathEntry и Remove-EdtWtInstallPathEntry' {
    It 'добавляет bin в PATH без дублей' {
        Add-EdtWtInstallPathEntry -PathValue 'C:\a;D:\x\bin\' -Entry 'd:\x\bin' | Should -Be 'C:\a;D:\x\bin\'
    }
    It 'добавляет новую запись в конец' {
        Add-EdtWtInstallPathEntry -PathValue 'C:\a' -Entry 'D:\x\bin' | Should -Be 'C:\a;D:\x\bin'
    }
    It 'работает с пустым PATH' {
        Add-EdtWtInstallPathEntry -PathValue '' -Entry 'D:\x\bin' | Should -Be 'D:\x\bin'
    }
    It 'убирает все записи без учёта регистра и хвостового слеша' {
        Remove-EdtWtInstallPathEntry -PathValue 'C:\a;D:\X\BIN\;C:\b;d:\x\bin' -Entry 'D:\x\bin' | Should -Be 'C:\a;C:\b'
    }
    It 'не трогает PATH без записи' {
        Remove-EdtWtInstallPathEntry -PathValue 'C:\a;C:\b' -Entry 'D:\x\bin' | Should -Be 'C:\a;C:\b'
    }
}

Describe 'Get-EdtWtInstallChecks' {
    It 'git нужен для работы модуля, но не для установки' {
        $prev = $env:Path
        $env:Path = 'C:\edtwt-no-git'
        try { $rows = Get-EdtWtInstallChecks } finally { $env:Path = $prev }
        $git = $rows | Where-Object { $_.Проверка -like 'git*' }
        $git.Статус | Should -Be 'нет'
        $git.Детали | Should -Match 'не для установки'
    }
}

Describe 'install.ps1 как файл' {
    It 'файл парсится в Windows PowerShell 5.1' -Skip:(-not [bool](Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
        $file = Join-Path $script:RepoRoot 'scripts\install.ps1'
        powershell.exe -NoProfile -Command "`$e=`$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$file',[ref]`$null,[ref]`$e); `$e.Count" | Should -Be '0'
    }
    It 'в Windows PowerShell 5.1 выводит сообщение про PowerShell 7 и ничего не делает' -Skip:(-not [bool](Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
        $file = Join-Path $script:RepoRoot 'scripts\install.ps1'
        # Версия < 7: ветка выхода срабатывает до любых действий (в т.ч. при EDT_INSTALL_NO_AUTORUN, которого здесь нет).
        $text = (& powershell.exe -NoProfile -File $file 2>&1 | Out-String)
        $text | Should -Match 'winget install Microsoft.PowerShell'
    }
    It 'файл в UTF-8 с BOM' {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $script:RepoRoot 'scripts\install.ps1'))
        ($bytes[0..2] -join ',') | Should -Be '239,187,191'
    }
    It 'импортирует модуль только в дочернем pwsh и указывает следующий шаг edt setup' {
        $file = Join-Path $script:RepoRoot 'scripts\install.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
        $imports = @($ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Import-Module'
                }, $true))
        foreach ($imp in $imports) {
            # Предок - блок-скрипт, переданный аргументом дочернему pwsh.
            $p = $imp.Parent
            $inChild = $false
            while ($p) {
                if ($p -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -and
                    $p.Parent -is [System.Management.Automation.Language.CommandAst] -and
                    ($p.Parent.CommandElements[0].Extent.Text -match 'pwsh|\$pwsh')) { $inChild = $true; break }
                $p = $p.Parent
            }
            $inChild | Should -BeTrue -Because "Import-Module в строке $($imp.Extent.StartLineNumber) вне дочернего pwsh"
        }
        $src = Get-Content -LiteralPath $file -Raw
        $src | Should -Not -Match 'edt config init'
        $src | Should -Not -Match 'git clone'
        $src | Should -Match 'edt setup'
    }
    It 'установщик лежит в scripts/, а не в корне' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'install.ps1') | Should -BeFalse
    }
}
