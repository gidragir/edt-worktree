BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
    Import-Module (Get-EdtWtTestModulePath) -Force -DisableNameChecking

    $script:Root = $script:TestCfg.Root
    # Профиль с пробелом и кириллицей, как у реального пользователя.
    $script:UserHome = Join-Path $script:Root 'Иван Петров'
    $script:ShimDir = Join-Path $script:UserHome 'bin'
    $script:Modules = Join-Path $script:UserHome 'Modules'
    $script:PrevShim = $env:EDT_SHIM_DIR
    $script:PrevScope = $env:EDT_PATH_SCOPE
    $script:PrevPath = $env:Path
    $script:PrevPsModulePath = $env:PSModulePath
    $env:EDT_SHIM_DIR = $script:ShimDir
    $env:EDT_PATH_SCOPE = 'Process'

    # Поддельный модуль EdtWorktree двух версий: bin\edt.ps1 печатает версию и аргументы, код - из первого аргумента.
    foreach ($v in '4.0.0', '4.1.0') {
        $base = Join-Path $script:Modules "EdtWorktree\$v"
        New-Item -ItemType Directory -Path (Join-Path $base 'bin') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $base 'EdtWorktree.psd1'), "@{ ModuleVersion = '$v'; RootModule = 'EdtWorktree.psm1'; GUID = '5b0c1a52-7c52-4a49-9d2e-0a3f5f7d1c11' }", [Text.UTF8Encoding]::new($true))
        [IO.File]::WriteAllText((Join-Path $base 'EdtWorktree.psm1'), '', [Text.UTF8Encoding]::new($true))
        $fake = "param([Parameter(ValueFromRemainingArguments)][string[]]`$A)`nWrite-Output ('VERSION=$v ARGS=' + (`$A -join '|'))`nexit ([int]`$A[0])`n"
        [IO.File]::WriteAllText((Join-Path $base 'bin\edt.ps1'), $fake, [Text.UTF8Encoding]::new($true))
    }
    $script:M = Get-Module EdtWorktree
    function script:Install-Shim { & $script:M { Install-EdtWtShim } }
    function script:Remove-Shim { & $script:M { Remove-EdtWtShim } }

    # Запуск shim через cmd с PSModulePath, указывающим на поддельные Modules.
    $script:RunShim = {
        param([string]$Modules, [string[]]$ShimArgs)
        $env:PSModulePath = $Modules
        try {
            $quoted = ($ShimArgs | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
            $out = & cmd /c "`"$(Join-Path $script:ShimDir 'edt.cmd')`" $quoted 2>&1" | Out-String
            [PSCustomObject]@{ Output = $out; ExitCode = $LASTEXITCODE }
        } finally { $env:PSModulePath = $script:PrevPsModulePath }
    }
}

AfterAll {
    $env:EDT_SHIM_DIR = $script:PrevShim
    $env:EDT_PATH_SCOPE = $script:PrevScope
    $env:Path = $script:PrevPath
    $env:PSModulePath = $script:PrevPsModulePath
    Exit-EdtWtTestConfig -State $script:TestCfg
}

Describe 'Постоянный shim edt' {
    It 'Install-EdtWtShim кладёт edt.cmd и edt.ps1 и добавляет каталог в PATH процесса один раз' {
        $d1 = Install-Shim
        $d2 = Install-Shim
        $d1 | Should -Be $script:ShimDir
        $d2 | Should -Be $script:ShimDir
        Test-Path -LiteralPath (Join-Path $script:ShimDir 'edt.cmd') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:ShimDir 'edt.ps1') | Should -BeTrue
        @($env:Path -split ';' | Where-Object { $_ -eq $script:ShimDir }).Count | Should -Be 1
    }

    It 'edt.cmd вызывает наибольшую версию' {
        Install-Shim | Out-Null
        $r = & $script:RunShim $script:Modules @('0')
        $r.Output | Should -Match '4\.1\.0'
        $r.Output | Should -Not -Match '4\.0\.0'
    }

    It 'аргументы с пробелами доходят без искажений' {
        Install-Shim | Out-Null
        $r = & $script:RunShim $script:Modules @('0', 'my proj', 'feature/x')
        $r.Output | Should -Match 'my proj\|feature/x'
    }

    It 'код возврата передаётся' {
        Install-Shim | Out-Null
        $r = & $script:RunShim $script:Modules @('2')
        $r.ExitCode | Should -Be 2
    }

    It 'без модуля - код 2 и подсказка Install-PSResource' {
        # pwsh сам добавляет в PSModulePath каталоги пользователя и машины, поэтому реально
        # установленный EdtWorktree спрятать нельзя: запускатель ищет модуль с другим именем.
        Install-Shim | Out-Null
        $alt = Join-Path $script:UserHome 'altshim'
        New-Item -ItemType Directory -Path $alt -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:ShimDir 'edt.cmd') -Destination $alt
        $ps1 = [IO.File]::ReadAllText((Join-Path $script:ShimDir 'edt.ps1'))
        $ps1.Contains('-Name EdtWorktree ') | Should -BeTrue
        [IO.File]::WriteAllText((Join-Path $alt 'edt.ps1'), $ps1.Replace('-Name EdtWorktree ', '-Name EdtWorktreeAbsent '), [Text.UTF8Encoding]::new($true))
        $env:PSModulePath = $script:Modules
        try {
            $out = & cmd /c "`"$(Join-Path $alt 'edt.cmd')`" 0 2>&1" | Out-String
            $code = $LASTEXITCODE
        } finally { $env:PSModulePath = $script:PrevPsModulePath }
        $code | Should -Be 2
        $out | Should -Match 'Install-PSResource EdtWorktree'
    }
    It 'Remove-EdtWtShim убирает файлы и запись PATH' {
        Install-Shim | Out-Null
        Remove-Shim
        Test-Path -LiteralPath $script:ShimDir | Should -BeFalse
        @($env:Path -split ';' | Where-Object { $_ -eq $script:ShimDir }).Count | Should -Be 0
    }

    It 'doctor: warn без shim, ok с shim' {
        Remove-Shim
        $row = Test-EdtEnvironment | Where-Object Check -Eq 'shim'
        $row.Status | Should -Be 'warn'
        $row.Fix | Should -Be 'edt setup'
        Install-Shim | Out-Null
        (Test-EdtEnvironment | Where-Object Check -Eq 'shim').Status | Should -Be 'ok'
    }

    It 'каталог shim по умолчанию не лежит в клоне 3.0 (LOCALAPPDATA\EdtWorktree)' {
        $local = Join-Path $script:UserHome 'AppData\Local'
        $prevLocal = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $local
        $env:EDT_SHIM_DIR = $null
        try {
            $dir = & $script:M { Get-EdtWtShimDir }
        } finally {
            $env:LOCALAPPDATA = $prevLocal
            $env:EDT_SHIM_DIR = $script:ShimDir
        }
        $dir | Should -Be (Join-Path $local 'Programs\EdtWorktree\bin')
        $dir | Should -Not -BeLike ((Join-Path $local 'EdtWorktree') + '\*')
    }

    It 'Install-EdtWtShim отказывается ставить shim внутрь git-репозитория' {
        $repo = Join-Path $script:UserHome 'репо с git'
        New-Item -ItemType Directory -Path (Join-Path $repo '.git'), (Join-Path $repo 'bin') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'bin\edt.cmd') -Value 'tracked'
        $env:EDT_SHIM_DIR = Join-Path $repo 'bin'
        try {
            { Install-Shim } | Should -Throw '*git*'
        } finally { $env:EDT_SHIM_DIR = $script:ShimDir }
        Get-Content -LiteralPath (Join-Path $repo 'bin\edt.cmd') | Should -Be 'tracked'
    }
}
