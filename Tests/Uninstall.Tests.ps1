BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
    # Защита реальной среды: модули и PATH - только временные/процессные.
    $script:PrevModulesDir = $env:EDT_MODULES_DIR
    $script:PrevPathScope = $env:EDT_PATH_SCOPE
    $script:PrevPath = $env:Path
    $script:ModulesDir = Join-Path $script:TestCfg.Root 'Modules'
    New-Item -ItemType Directory -Path $script:ModulesDir -Force | Out-Null
    $env:EDT_MODULES_DIR = $script:ModulesDir
    $env:EDT_PATH_SCOPE = 'Process'
    Import-Module (Join-Path $PSScriptRoot '..\EdtWorktree.psd1') -Force -DisableNameChecking
    $script:m = Get-Module EdtWorktree

    function script:New-FakeInstall {
        # Временный клон с манифестом, bin и junction в EDT_MODULES_DIR.
        $clone = Join-Path $script:TestCfg.Root ('clone_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $clone 'bin') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $clone 'EdtWorktree.psd1') -Value '@{}'
        Set-Content -LiteralPath (Join-Path $clone 'bin\edt.cmd') -Value 'x'
        $link = Join-Path $script:ModulesDir 'EdtWorktree'
        if (Test-Path -LiteralPath $link) { ([System.IO.DirectoryInfo]$link).Delete() }
        New-Item -ItemType Junction -Path $link -Target $clone | Out-Null
        [pscustomobject]@{ Clone = $clone; Link = $link }
    }
}

AfterAll {
    $env:EDT_MODULES_DIR = $script:PrevModulesDir
    $env:EDT_PATH_SCOPE = $script:PrevPathScope
    $env:Path = $script:PrevPath
    Exit-EdtWtTestConfig -State $script:TestCfg
}

Describe 'Remove-EdtWtPathEntry' {
    It 'убирает запись PATH без учёта регистра и слеша' {
        & $m { Remove-EdtWtPathEntry -PathValue 'C:\a;D:\Tools\edt\bin\;C:\b' -Entry 'd:\tools\EDT\bin' } | Should -Be 'C:\a;C:\b'
    }
    It 'убирает все совпадения и пустые элементы' {
        & $m { Remove-EdtWtPathEntry -PathValue ';C:\a;;D:\x\bin;D:\x\bin\;' -Entry 'D:\x\bin' } | Should -Be 'C:\a'
    }
}

Describe 'Get-EdtWtInstallInfo' {
    BeforeEach { $script:fx = New-FakeInstall }
    AfterEach { if (Test-Path -LiteralPath $script:fx.Link) { ([System.IO.DirectoryInfo]$script:fx.Link).Delete() } }

    It 'для junction берёт цель как InstallDir' {
        $i = & $m { Get-EdtWtInstallInfo }
        $i.ModuleLink | Should -Be $script:fx.Link
        $i.InstallDir | Should -Be $script:fx.Clone
        $i.BinDir | Should -Be (Join-Path $script:fx.Clone 'bin')
        $i.ConfigDir | Should -Be $script:TestCfg.Root
    }
}

Describe 'Uninstall-EdtWorktree' {
    BeforeEach {
        $script:fx = New-FakeInstall
        $script:bin = Join-Path $script:fx.Clone 'bin'
        $env:Path = "C:\keep;$($script:bin)\;C:\other"
        Set-Content -LiteralPath $script:TestCfg.Path -Value '{}'
    }
    AfterEach {
        if (Test-Path -LiteralPath $script:fx.Link) { ([System.IO.DirectoryInfo]$script:fx.Link).Delete() }
        $env:Path = $script:PrevPath
    }

    It 'удаляет только ссылку, исходники остаются' {
        Uninstall-EdtWorktree -Confirm:$false 6>$null
        Test-Path -LiteralPath $script:fx.Link | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:fx.Clone 'EdtWorktree.psd1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:fx.Clone 'bin\edt.cmd') | Should -BeTrue
        $env:Path | Should -Not -Match ([regex]::Escape($script:bin))
        $env:Path | Should -Be 'C:\keep;C:\other'
        Test-Path -LiteralPath $script:TestCfg.Path | Should -BeTrue
    }

    It '-WhatIf ничего не меняет' {
        $before = $env:Path
        Uninstall-EdtWorktree -WhatIf -Purge *>$null
        Test-Path -LiteralPath $script:fx.Link | Should -BeTrue
        Test-Path -LiteralPath $script:fx.Clone | Should -BeTrue
        $env:Path | Should -Be $before
        Test-Path -LiteralPath $script:TestCfg.Path | Should -BeTrue
    }

    It 'печатает список удаляемого' {
        $out = Uninstall-EdtWorktree -WhatIf *>&1 | Out-String
        $out | Should -Match ([regex]::Escape($script:fx.Link))
    }

    It '-Purge удаляет каталог установки и конфиг, но не соседние каталоги' {
        $ws = Join-Path (Split-Path $script:TestCfg.Root) ('ws_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $ws -Force | Out-Null
        try {
            Uninstall-EdtWorktree -Purge -Confirm:$false 6>$null
            Test-Path -LiteralPath $script:fx.Link | Should -BeFalse
            Test-Path -LiteralPath $script:fx.Clone | Should -BeFalse
            Test-Path -LiteralPath $script:TestCfg.Path | Should -BeFalse
            Test-Path -LiteralPath $ws | Should -BeTrue
        } finally {
            Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Path $script:TestCfg.Root -Force | Out-Null
        }
    }

    It 'удаление junction не затрагивает содержимое цели' {
        $deep = Join-Path $script:fx.Clone 'sub\deep'
        New-Item -ItemType Directory -Path $deep -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $deep 'f.txt') -Value 'keep'
        & $m { param($l) Remove-EdtWtModuleLink -Path $l } $script:fx.Link
        Test-Path -LiteralPath $script:fx.Link | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $deep 'f.txt') | Should -Be 'keep'
        Test-Path -LiteralPath (Join-Path $script:fx.Clone 'EdtWorktree.psd1') | Should -BeTrue
    }
}

Describe 'Update-EdtSelf без git' {
    It 'бросает понятную ошибку, если git не найден' {
        Mock -ModuleName EdtWorktree -CommandName Get-Command -ParameterFilter { $Name -eq 'git' } -MockWith { $null }
        { Update-EdtSelf -Confirm:$false } | Should -Throw '*git не найден в PATH. Установите: winget install Git.Git*'
    }
}
