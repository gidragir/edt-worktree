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
    $script:PrevShimDir = $env:EDT_SHIM_DIR
    $env:EDT_SHIM_DIR = Join-Path $script:TestCfg.Root 'shim'
    Import-Module (Get-EdtWtTestModulePath) -Force -DisableNameChecking
    $script:m = Get-Module EdtWorktree

    function script:New-ShimFiles {
        $d = $env:EDT_SHIM_DIR
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        foreach ($n in 'edt.cmd', 'edt.ps1') { Set-Content -LiteralPath (Join-Path $d $n) -Value 'x' }
    }

    function script:New-LinkTo {
        param([string]$Target)
        $link = Join-Path $script:ModulesDir 'EdtWorktree'
        if (Test-Path -LiteralPath $link) { ([System.IO.DirectoryInfo]$link).Delete() }
        New-Item -ItemType Junction -Path $link -Target $Target | Out-Null
        $link
    }

    function script:New-DevInstall {
        # Клон разработчика: <клон>\src\EdtWorktree, ссылка ведёт на него.
        $repo = (New-EdtWtTestRepo -Root $script:TestCfg.Root -Name ('dev_' + [guid]::NewGuid().ToString('N'))).RepoPath
        $src = Join-Path $repo 'src\EdtWorktree'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'EdtWorktree.psd1') -Value '@{}'
        git -C $repo add -A | Out-Null
        git -C $repo -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m 'src' | Out-Null
        [pscustomobject]@{ Clone = $repo; Link = New-LinkTo $src }
    }

    function script:New-LegacyInstall {
        # Клон 3.0: модуль в корне, ссылка ведёт на корень клона.
        $repo = (New-EdtWtTestRepo -Root $script:TestCfg.Root -Name ('legacy_' + [guid]::NewGuid().ToString('N'))).RepoPath
        New-Item -ItemType Directory -Path (Join-Path $repo 'bin') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'EdtWorktree.psd1') -Value '@{}'
        Set-Content -LiteralPath (Join-Path $repo 'bin\edt.cmd') -Value 'x'
        git -C $repo add -A | Out-Null
        git -C $repo -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m 'legacy' | Out-Null
        [pscustomobject]@{ Clone = $repo; Link = New-LinkTo $repo }
    }

    function script:New-ZipInstall {
        $link = Join-Path $script:ModulesDir 'EdtWorktree'
        if (Test-Path -LiteralPath $link) { ([System.IO.DirectoryInfo]$link).Delete() }
        New-Item -ItemType Directory -Path (Join-Path $link '4.0.0') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $link '4.0.0\EdtWorktree.psd1') -Value '@{}'
        [pscustomobject]@{ Link = $link }
    }

    function script:Remove-AnyLink {
        $link = Join-Path $script:ModulesDir 'EdtWorktree'
        $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
        if (-not $item) { return }
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { ([System.IO.DirectoryInfo]$link).Delete() }
        else { Remove-Item -LiteralPath $link -Recurse -Force }
    }
}
AfterAll {
    $env:EDT_MODULES_DIR = $script:PrevModulesDir
    $env:EDT_PATH_SCOPE = $script:PrevPathScope
    $env:EDT_SHIM_DIR = $script:PrevShimDir
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
    AfterEach { Remove-AnyLink }

    It 'Dev: ссылка на src\EdtWorktree клона' {
        $fx = New-DevInstall
        $i = & $m { Get-EdtWtInstallInfo }
        $i.Kind | Should -Be 'Dev'
        $i.ModuleLink | Should -Be $fx.Link
        $i.CloneDir | Should -Be $fx.Clone
        $i.ModulesDir | Should -Be $script:ModulesDir
        $i.ShimDir | Should -Be $env:EDT_SHIM_DIR
        $i.ConfigDir | Should -Be $script:TestCfg.Root
    }

    It 'Legacy: ссылка на корень клона с .git' {
        $fx = New-LegacyInstall
        $i = & $m { Get-EdtWtInstallInfo }
        $i.Kind | Should -Be 'Legacy'
        $i.CloneDir | Should -Be $fx.Clone
    }

    It 'Gallery: обычный каталог и Get-EdtWtGalleryInstall даёт true' {
        New-ZipInstall | Out-Null
        Mock -ModuleName EdtWorktree -CommandName Get-EdtWtGalleryInstall -MockWith { $true }
        $i = & $m { Get-EdtWtInstallInfo }
        $i.Kind | Should -Be 'Gallery'
        $i.CloneDir | Should -BeNullOrEmpty
    }

    It 'Zip: обычный каталог и Get-EdtWtGalleryInstall даёт false' {
        New-ZipInstall | Out-Null
        Mock -ModuleName EdtWorktree -CommandName Get-EdtWtGalleryInstall -MockWith { $false }
        $i = & $m { Get-EdtWtInstallInfo }
        $i.Kind | Should -Be 'Zip'
        $i.CloneDir | Should -BeNullOrEmpty
    }

    It 'свойств InstallDir, ViaLink, BinDir больше нет' {
        New-ZipInstall | Out-Null
        $i = & $m { Get-EdtWtInstallInfo }
        foreach ($n in 'InstallDir', 'ViaLink', 'BinDir') { $i.PSObject.Properties.Name | Should -Not -Contain $n }
    }
}

Describe 'Get-EdtWtGalleryInstall' {
    It 'ошибка запроса даёт false' {
        Mock -ModuleName EdtWorktree -CommandName Get-InstalledPSResource -MockWith { throw 'boom' }
        & $m { Get-EdtWtGalleryInstall -Version '4.0.0' } | Should -BeFalse
    }
    It 'найденный ресурс даёт true' {
        Mock -ModuleName EdtWorktree -CommandName Get-InstalledPSResource -MockWith { [pscustomobject]@{ Name = 'EdtWorktree' } }
        & $m { Get-EdtWtGalleryInstall -Version '4.0.0' } | Should -BeTrue
    }
}

Describe 'Uninstall-EdtWorktree' {
    BeforeEach {
        Set-Content -LiteralPath $script:TestCfg.Path -Value '{}'
        New-ShimFiles
    }
    AfterEach {
        Remove-AnyLink
        $env:Path = $script:PrevPath
    }

    It 'Dev: удаляет ссылку и shim, цель цела' {
        $fx = New-DevInstall
        $env:Path = "C:\keep;$($env:EDT_SHIM_DIR);C:\other"
        Uninstall-EdtWorktree -Confirm:$false 6>$null
        Test-Path -LiteralPath $fx.Link | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fx.Clone 'src\EdtWorktree\EdtWorktree.psd1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $env:EDT_SHIM_DIR 'edt.cmd') | Should -BeFalse
        $env:Path | Should -Be 'C:\keep;C:\other'
        Test-Path -LiteralPath $script:TestCfg.Path | Should -BeTrue
    }

    It 'Zip: каталог модуля удалён вместе с содержимым, shim удалён' {
        $env:Path = "C:\keep;$($env:EDT_SHIM_DIR);C:\other"
        $fx = New-ZipInstall
        Mock -ModuleName EdtWorktree -CommandName Get-EdtWtGalleryInstall -MockWith { $false }
        Uninstall-EdtWorktree -Confirm:$false 6>$null
        Test-Path -LiteralPath $fx.Link | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $env:EDT_SHIM_DIR 'edt.ps1') | Should -BeFalse
    }

    It 'Gallery: вызывается Uninstall-PSResource, shim удалён' {
        New-ZipInstall | Out-Null
        Mock -ModuleName EdtWorktree -CommandName Get-EdtWtGalleryInstall -MockWith { $true }
        Mock -ModuleName EdtWorktree -CommandName Uninstall-PSResource -MockWith { }
        Uninstall-EdtWorktree -Confirm:$false 6>$null
        Should -Invoke Uninstall-PSResource -ModuleName EdtWorktree -Times 1 -Exactly
        Test-Path -LiteralPath (Join-Path $env:EDT_SHIM_DIR 'edt.cmd') | Should -BeFalse
    }

    It 'Legacy: ссылка снята, bin клона убран из PATH, клон цел' {
        $fx = New-LegacyInstall
        $env:Path = "C:\keep;$(Join-Path $fx.Clone 'bin')\;$($env:EDT_SHIM_DIR);C:\other"
        Uninstall-EdtWorktree -Confirm:$false 6>$null
        Test-Path -LiteralPath $fx.Link | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fx.Clone 'EdtWorktree.psd1') | Should -BeTrue
        $env:Path | Should -Be 'C:\keep;C:\other'
    }

    It '-WhatIf ничего не меняет' {
        $fx = New-DevInstall
        $before = $env:Path
        Uninstall-EdtWorktree -WhatIf -Purge *>$null
        Test-Path -LiteralPath $fx.Link | Should -BeTrue
        Test-Path -LiteralPath $fx.Clone | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $env:EDT_SHIM_DIR 'edt.cmd') | Should -BeTrue
        $env:Path | Should -Be $before
        Test-Path -LiteralPath $script:TestCfg.Path | Should -BeTrue
    }

    It 'печатает список удаляемого для своего вида' {
        $fx = New-DevInstall
        $out = Uninstall-EdtWorktree -WhatIf *>&1 | Out-String
        $out | Should -Match ([regex]::Escape($fx.Link))
        $out | Should -Match 'Dev'
        $out | Should -Match ([regex]::Escape($env:EDT_SHIM_DIR))
    }

    It 'удаление junction не затрагивает содержимое цели' {
        $fx = New-DevInstall
        $deep = Join-Path $fx.Clone 'src\EdtWorktree\sub\deep'
        New-Item -ItemType Directory -Path $deep -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $deep 'f.txt') -Value 'keep'
        & $m { param($l) Remove-EdtWtModuleLink -Path $l } $fx.Link
        Test-Path -LiteralPath $fx.Link | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $deep 'f.txt') | Should -Be 'keep'
    }
}

Describe 'Uninstall-EdtWorktree -Purge: защитные проверки' {
    BeforeEach { New-ShimFiles }
    AfterEach { Remove-AnyLink }

    It 'Dev, чистый клон: клон (корень, не src) удаляется' {
        $fx = New-DevInstall
        Uninstall-EdtWorktree -Purge -Confirm:$false 6>$null
        Test-Path -LiteralPath $fx.Link | Should -BeFalse
        Test-Path -LiteralPath $fx.Clone | Should -BeFalse
    }

    It 'Dev, грязный клон: клон цел, ссылка снята, предупреждение' {
        $fx = New-DevInstall
        Set-Content -LiteralPath (Join-Path $fx.Clone 'work.txt') -Value 'uncommitted'
        Uninstall-EdtWorktree -Purge -Confirm:$false -WarningVariable w -WarningAction SilentlyContinue 6>$null
        Test-Path -LiteralPath $fx.Link | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $fx.Clone 'work.txt') | Should -Be 'uncommitted'
        ($w -join ' ') | Should -Match 'незафиксированные'
    }

    It 'Legacy, грязный клон: клон и файл целы, предупреждение' {
        $fx = New-LegacyInstall
        Set-Content -LiteralPath (Join-Path $fx.Clone 'work.txt') -Value 'uncommitted'
        Uninstall-EdtWorktree -Purge -Confirm:$false -WarningVariable w -WarningAction SilentlyContinue 6>$null
        Test-Path -LiteralPath $fx.Link | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $fx.Clone 'work.txt') | Should -Be 'uncommitted'
        Test-Path -LiteralPath (Join-Path $fx.Clone '.git') | Should -BeTrue
        ($w -join ' ') | Should -Match 'незафиксированные'
    }

    It 'Legacy, чистый клон удаляется' {
        $fx = New-LegacyInstall
        Uninstall-EdtWorktree -Purge -Confirm:$false 6>$null
        Test-Path -LiteralPath $fx.Clone | Should -BeFalse
    }

    It 'Zip с -Purge не трогает ничего, кроме модуля и конфига' {
        $repo = (New-EdtWtTestRepo -Root $script:TestCfg.Root -Name 'devclone').RepoPath
        New-ZipInstall | Out-Null
        Mock -ModuleName EdtWorktree -CommandName Get-EdtWtGalleryInstall -MockWith { $false }
        Uninstall-EdtWorktree -Purge -Confirm:$false 6>$null
        Test-Path -LiteralPath (Join-Path $repo 'README.md') | Should -BeTrue
    }

    It 'если состояние git проверить нельзя, клон не удаляется (fail closed), ссылка удаляется' {
        $fx = New-DevInstall
        Mock -ModuleName EdtWorktree -CommandName Invoke-EdtWtGit -MockWith { $global:LASTEXITCODE = 128; return 'fatal: detected dubious ownership' }
        Uninstall-EdtWorktree -Purge -Confirm:$false -WarningVariable w -WarningAction SilentlyContinue 6>$null
        Test-Path -LiteralPath $fx.Link | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fx.Clone 'README.md') | Should -BeTrue
        ($w -join ' ') | Should -Match 'не удалось проверить'
    }

    It 'если git не найден, клон с .git не удаляется' {
        $fx = New-DevInstall
        Mock -ModuleName EdtWorktree -CommandName Get-Command -ParameterFilter { $Name -eq 'git' } -MockWith { $null }
        Uninstall-EdtWorktree -Purge -Confirm:$false -WarningAction SilentlyContinue 6>$null
        Test-Path -LiteralPath $fx.Link | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fx.Clone 'README.md') | Should -BeTrue
    }

    It '-Purge удаляет только файл конфига и его копии; чужие файлы и каталог остаются' {
        $shared = Join-Path $script:TestCfg.Root 'shared'
        New-Item -ItemType Directory -Path $shared | Out-Null
        $prev = $env:EDT_CONFIG_PATH
        try {
            $env:EDT_CONFIG_PATH = Join-Path $shared 'config.json'
            foreach ($n in 'config.json', 'config.json.v2.bak', 'config.json.v2.bak.1', 'config.json.tmp', 'other.txt') {
                Set-Content -LiteralPath (Join-Path $shared $n) -Value 'x'
            }
            New-ZipInstall | Out-Null
            Uninstall-EdtWorktree -Purge -Confirm:$false 6>$null
            Test-Path -LiteralPath (Join-Path $shared 'other.txt') | Should -BeTrue
            @(Get-ChildItem -LiteralPath $shared -Force).Name | Should -Be @('other.txt')
        } finally { $env:EDT_CONFIG_PATH = $prev }
    }

    It 'каталог конфига удаляется, если после очистки пуст' {
        $solo = Join-Path $script:TestCfg.Root 'solo'
        New-Item -ItemType Directory -Path $solo | Out-Null
        $prev = $env:EDT_CONFIG_PATH
        try {
            $env:EDT_CONFIG_PATH = Join-Path $solo 'config.json'
            Set-Content -LiteralPath $env:EDT_CONFIG_PATH -Value '{}'
            New-ZipInstall | Out-Null
            Uninstall-EdtWorktree -Purge -Confirm:$false 6>$null
            Test-Path -LiteralPath $solo | Should -BeFalse
        } finally { $env:EDT_CONFIG_PATH = $prev }
    }
}