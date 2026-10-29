BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    # Защита реальной среды: конфиг, корни и PATH - только временные; установщик всегда -NoPath -NoSetup.
    $script:TestCfg = Enter-EdtWtTestConfig
    $script:PrevNoAutorun = $env:EDT_INSTALL_NO_AUTORUN
    $script:PrevPath = $env:Path
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $root = $script:TestCfg.Root

    # Копия установщика вне клона: $PSScriptRoot без манифеста, значит источник - git clone.
    $script:StandaloneDir = Join-Path $root 'standalone'
    New-Item -ItemType Directory -Path $script:StandaloneDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'install.ps1') -Destination $script:StandaloneDir -ErrorAction SilentlyContinue

    # Локальный bare-клон текущего репозитория: сеть не нужна.
    $script:Bare = Join-Path $root 'origin.git'
    $out = & git clone --bare -q $script:RepoRoot $script:Bare 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git clone --bare: $out" }

    $env:EDT_INSTALL_NO_AUTORUN = '1'
    . (Join-Path $script:StandaloneDir 'install.ps1')
}

AfterAll {
    $env:EDT_INSTALL_NO_AUTORUN = $script:PrevNoAutorun
    $env:Path = $script:PrevPath
    Exit-EdtWtTestConfig -State $script:TestCfg
}

Describe 'Install-EdtWorktree' {
    BeforeEach {
        $script:case = Join-Path $script:TestCfg.Root ('case_' + [guid]::NewGuid().ToString('N'))
        $script:inst = Join-Path $script:case 'inst dir'
        $script:mods = Join-Path $script:case 'Modules'
    }

    It 'ставит модуль из репозитория и он импортируется' {
        Install-EdtWorktree -InstallDir $inst -RepoUrl $script:Bare -ModulesDir $mods -NoSetup -NoPath 6>$null
        (Get-Item "$mods\EdtWorktree").LinkType | Should -Be 'Junction'
        Test-Path -LiteralPath (Join-Path $inst '.git') | Should -BeTrue
        $v = pwsh -NoProfile -Command "Import-Module '$mods\EdtWorktree\EdtWorktree.psd1'; (Get-Module EdtWorktree).Version.ToString()"
        $v | Should -Be '3.0.0'
    }

    It 'повторный запуск обновляет, не ломая' {
        Install-EdtWorktree -InstallDir $inst -RepoUrl $script:Bare -ModulesDir $mods -NoSetup -NoPath 6>$null
        Install-EdtWorktree -InstallDir $inst -RepoUrl $script:Bare -ModulesDir $mods -NoSetup -NoPath 6>$null
        Test-Path "$mods\EdtWorktree\EdtWorktree.psd1" | Should -BeTrue
        (Get-Item "$mods\EdtWorktree").LinkType | Should -Be 'Junction'
    }

    It 'заменяет существующую копию модуля ссылкой' {
        New-Item -ItemType Directory -Path "$mods\EdtWorktree" -Force | Out-Null
        Set-Content -LiteralPath "$mods\EdtWorktree\old.txt" -Value 'x'
        Install-EdtWorktree -InstallDir $inst -RepoUrl $script:Bare -ModulesDir $mods -NoSetup -NoPath 6>$null
        (Get-Item "$mods\EdtWorktree").LinkType | Should -Be 'Junction'
        Test-Path "$mods\EdtWorktree\old.txt" | Should -BeFalse
    }

    It 'замена существующей ссылки не удаляет содержимое её цели' {
        $other = Join-Path $script:case 'other'
        New-Item -ItemType Directory -Path $other -Force | Out-Null
        Set-Content -LiteralPath "$other\keep.txt" -Value 'x'
        New-Item -ItemType Directory -Path $mods -Force | Out-Null
        New-Item -ItemType Junction -Path "$mods\EdtWorktree" -Target $other | Out-Null
        Install-EdtWorktree -InstallDir $inst -RepoUrl $script:Bare -ModulesDir $mods -NoSetup -NoPath 6>$null
        Test-Path "$other\keep.txt" | Should -BeTrue
        Test-Path "$mods\EdtWorktree\EdtWorktree.psd1" | Should -BeTrue
    }

    It 'при -NoPath не меняет PATH текущей сессии' {
        $before = $env:Path
        Install-EdtWorktree -InstallDir $inst -RepoUrl $script:Bare -ModulesDir $mods -NoSetup -NoPath 6>$null
        $env:Path | Should -BeExactly $before
    }

    It 'форма scriptblock передаёт ключи в Install-EdtWorktree' {
        # Если ключи потеряются, установка уйдёт во временные каталоги из переменных, а не в реальные.
        $names = 'EDT_INSTALL_NO_AUTORUN', 'EDT_INSTALL_DIR', 'EDT_INSTALL_NOSETUP', 'EDT_MODULES_DIR', 'EDT_PATH_SCOPE'
        $prev = @{}
        foreach ($n in $names) { $prev[$n] = [Environment]::GetEnvironmentVariable($n) }
        $env:EDT_INSTALL_NO_AUTORUN = $null
        $env:EDT_INSTALL_DIR = Join-Path $script:case 'env-inst'
        $env:EDT_INSTALL_NOSETUP = '1'
        $env:EDT_MODULES_DIR = Join-Path $script:case 'env-mods'
        $env:EDT_PATH_SCOPE = 'Process'
        try {
            $text = Get-Content -LiteralPath (Join-Path $script:StandaloneDir 'install.ps1') -Raw
            & ([scriptblock]::Create($text)) -NoSetup -NoPath -InstallDir $inst -RepoUrl $script:Bare -ModulesDir $mods 6>$null
        } finally {
            foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $prev[$n]) }
            $env:Path = $script:PrevPath
        }
        (Get-Item "$mods\EdtWorktree").LinkType | Should -Be 'Junction'
        Test-Path -LiteralPath (Join-Path $inst '.git') | Should -BeTrue
    }

    It 'использует клон, из которого запущен установщик' {
        $dev = Join-Path $script:case 'dev'
        New-Item -ItemType Directory -Path "$dev\bin" -Force | Out-Null
        Set-Content -LiteralPath "$dev\EdtWorktree.psd1" -Value '@{}'
        Copy-Item -LiteralPath (Join-Path $script:StandaloneDir 'install.ps1') -Destination $dev
        $env:EDT_INSTALL_NO_AUTORUN = '1'
        $out = pwsh -NoProfile -Command ". '$dev\install.ps1'; Install-EdtWorktree -InstallDir '$inst' -RepoUrl 'file:///nonexistent' -ModulesDir '$mods' -NoSetup -NoPath 6>`$null; (Get-Item '$mods\EdtWorktree').Target"
        ($out | Select-Object -Last 1) | Should -Be $dev
        Test-Path -LiteralPath $inst | Should -BeFalse
    }
}

Describe 'Install-EdtWorktree: PATH при EDT_PATH_SCOPE=Process' {
    BeforeAll {
        $script:PrevScope = $env:EDT_PATH_SCOPE
        $env:EDT_PATH_SCOPE = 'Process'
    }
    AfterAll {
        $env:EDT_PATH_SCOPE = $script:PrevScope
        $env:Path = $script:PrevPath
    }
    BeforeEach {
        # Защита пользовательского PATH: без этого шва установщик без -NoPath вызывать нельзя.
        $env:EDT_PATH_SCOPE | Should -BeExactly 'Process'
        # Каталог git остаётся в PATH: без него установщик выходит до шага PATH.
        $script:GitDir = Split-Path -Parent (Get-Command git -CommandType Application | Select-Object -First 1).Source
        $env:Path = 'C:\edtwt-test-a;' + $script:GitDir
        $script:case = Join-Path $script:TestCfg.Root ('case_' + [guid]::NewGuid().ToString('N'))
        $script:inst = Join-Path $script:case 'inst'
        $script:mods = Join-Path $script:case 'Modules'
        $script:bin = Join-Path $script:inst 'bin'
    }
    AfterEach { $env:Path = $script:PrevPath }

    It 'добавляет bin в PATH процесса один раз и повторный запуск не дублирует' {
        $env:EDT_PATH_SCOPE | Should -BeExactly 'Process'
        Install-EdtWorktree -InstallDir $inst -RepoUrl $script:Bare -ModulesDir $mods -NoSetup 6>$null
        Install-EdtWorktree -InstallDir $inst -RepoUrl $script:Bare -ModulesDir $mods -NoSetup 6>$null
        Test-Path -LiteralPath "$mods\EdtWorktree\EdtWorktree.psd1" | Should -BeTrue
        @($env:Path -split ';' | Where-Object { $_ -eq $script:bin }).Count | Should -Be 1
        $env:Path | Should -BeLike 'C:\edtwt-test-a;*'
    }

    It 'не дублирует запись, отличающуюся регистром и хвостовым слешем' {
        $env:EDT_PATH_SCOPE | Should -BeExactly 'Process'
        $env:Path = 'C:\edtwt-test-a;' + $script:GitDir + ';' + $script:bin.ToUpperInvariant() + '\'
        Install-EdtWorktree -InstallDir $inst -RepoUrl $script:Bare -ModulesDir $mods -NoSetup 6>$null
        Test-Path -LiteralPath "$mods\EdtWorktree\EdtWorktree.psd1" | Should -BeTrue
        @($env:Path -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ieq $script:bin }).Count | Should -Be 1
    }
}

Describe 'Install-EdtWorktree: запуск через ссылку модуля' {
    It 'пересоздаёт ссылку и не удаляет собственный источник' {
        $case = Join-Path $script:TestCfg.Root ('case_' + [guid]::NewGuid().ToString('N'))
        $dev = Join-Path $case 'dev'
        $mods = Join-Path $case 'Modules'
        New-Item -ItemType Directory -Path "$dev\bin" -Force | Out-Null
        New-Item -ItemType Directory -Path $mods -Force | Out-Null
        Set-Content -LiteralPath "$dev\EdtWorktree.psd1" -Value '@{}'
        Set-Content -LiteralPath "$dev\marker.txt" -Value 'x'
        Copy-Item -LiteralPath (Join-Path $script:StandaloneDir 'install.ps1') -Destination $dev
        New-Item -ItemType Junction -Path "$mods\EdtWorktree" -Target $dev | Out-Null
        $out = pwsh -NoProfile -Command ". '$mods\EdtWorktree\install.ps1'; Install-EdtWorktree -InstallDir '$case\inst' -RepoUrl 'file:///nonexistent' -ModulesDir '$mods' -NoSetup -NoPath 6>`$null; (Get-Item '$mods\EdtWorktree').Target"
        ($out | Select-Object -Last 1) | Should -Be $dev
        Test-Path "$dev\marker.txt" | Should -BeTrue
        Test-Path "$mods\EdtWorktree\EdtWorktree.psd1" | Should -BeTrue
    }
}

Describe 'Add-EdtWtInstallPathEntry' {
    It 'добавляет bin в PATH без дублей' {
        Add-EdtWtInstallPathEntry -PathValue 'C:\a;D:\x\bin\' -Entry 'd:\x\bin' | Should -Be 'C:\a;D:\x\bin\'
    }
    It 'добавляет новую запись в конец' {
        Add-EdtWtInstallPathEntry -PathValue 'C:\a' -Entry 'D:\x\bin' | Should -Be 'C:\a;D:\x\bin'
    }
    It 'работает с пустым PATH' {
        Add-EdtWtInstallPathEntry -PathValue '' -Entry 'D:\x\bin' | Should -Be 'D:\x\bin'
    }
}

Describe 'install.ps1 как файл' {
    It 'парсится в Windows PowerShell 5.1' {
        if (-not (Get-Command powershell.exe -ErrorAction SilentlyContinue)) { Set-ItResult -Skipped -Because 'нет powershell.exe'; return }
        $file = Join-Path $script:RepoRoot 'install.ps1'
        powershell.exe -NoProfile -Command "`$e=`$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$file',[ref]`$null,[ref]`$e); `$e.Count" | Should -Be '0'
    }
    It 'в Windows PowerShell 5.1 выводит сообщение про PowerShell 7 и ничего не делает' {
        if (-not (Get-Command powershell.exe -ErrorAction SilentlyContinue)) { Set-ItResult -Skipped -Because 'нет powershell.exe'; return }
        $file = Join-Path $script:RepoRoot 'install.ps1'
        # Версия < 7: ветка выхода срабатывает до любых действий (в т.ч. при EDT_INSTALL_NO_AUTORUN, которого здесь нет).
        $text = (& powershell.exe -NoProfile -File $file 2>&1 | Out-String)
        $text | Should -Match 'winget install Microsoft.PowerShell'
    }
    It 'не импортирует модуль и указывает следующий шаг edt setup' {
        $src = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'install.ps1') -Raw
        $src | Should -Not -Match 'Import-Module'
        $src | Should -Not -Match 'edt config init'
        $src | Should -Match 'edt setup'
    }
    It 'старый scripts/install.ps1 удалён' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'scripts') | Should -BeFalse
    }
}
