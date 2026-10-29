BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
    $script:Root = $script:TestCfg.Root
    Import-Module (Get-EdtWtTestModulePath) -Force -DisableNameChecking
    $script:m = Get-Module EdtWorktree
}

AfterAll {
    Exit-EdtWtTestConfig -State $script:TestCfg
}

Describe 'Поиск EDT-проектов в клоне' {
    It 'находит конфигурацию и расширения, вложенную конфигурацию тоже' {
        $r = New-EdtWtTestRepo -Root $script:Root -Name 'p' -Projects @{ 'src/cf/Main' = 'Configuration'; 'src/cfe_a' = 'Extension'; 'src/cfe_b' = 'Extension' }
        $found = & $m { param($p) Find-EdtWtEdtProjects -RepoPath $p } $r.RepoPath
        ($found | Where-Object Kind -eq 'Configuration').RelPath | Should -Be 'src/cf/Main'
        ($found | Where-Object Kind -eq 'Extension').RelPath | Should -Be @('src/cfe_a', 'src/cfe_b')
        ($found | Where-Object Kind -eq 'Configuration').Name | Should -Be 'Main'
    }

    It 'игнорирует .project без EDT-nature и каталог .git' {
        $r = New-EdtWtTestRepo -Root $script:Root -Name 'q' -Projects @{ 'src/cf' = 'Configuration' }
        $other = Join-Path $r.RepoPath 'tools'
        New-Item -ItemType Directory -Path $other -Force | Out-Null
        '<projectDescription><name>x</name><natures><nature>org.eclipse.jdt.core.javanature</nature></natures></projectDescription>' | Set-Content (Join-Path $other '.project')
        New-Item -ItemType Directory -Path (Join-Path $r.RepoPath '.git\sub') -Force | Out-Null
        Copy-Item (Join-Path $r.RepoPath 'src\cf\.project') (Join-Path $r.RepoPath '.git\sub\.project')
        $found = @(& $m { param($p) Find-EdtWtEdtProjects -RepoPath $p } $r.RepoPath)
        $found.Count | Should -Be 1
        $found[0].RelPath | Should -Be 'src/cf'
    }

    It 'не ищет глубже 3 уровней' {
        $r = New-EdtWtTestRepo -Root $script:Root -Name 'd' -Projects @{ 'a/b/c/d' = 'Configuration'; 'a/b/c' = 'Extension' }
        $found = @(& $m { param($p) Find-EdtWtEdtProjects -RepoPath $p } $r.RepoPath)
        $found.RelPath | Should -Be @('a/b/c')
    }
}

Describe 'Разбор выбора' {
    It 'разбирает выбор "<T>"' -ForEach @(
        @{ T = '1 3'; E = @(1, 3) }, @{ T = '2-4'; E = @(2, 3, 4) }, @{ T = '1,1, 2'; E = @(1, 2) },
        @{ T = 'все'; E = @(1, 2, 3, 4, 5) }, @{ T = 'нет'; E = @() }, @{ T = ''; E = @() },
        @{ T = 'all'; E = @(1, 2, 3, 4, 5) }, @{ T = '*'; E = @(1, 2, 3, 4, 5) }, @{ T = 'none'; E = @() }
    ) {
        $r = @(& $m { param($t) ConvertFrom-EdtWtSelection -Text $t -Count 5 } $T)
        $r.Count | Should -Be $E.Count
        if ($E.Count) { $r | Should -Be $E }
    }

    It 'отклоняет "<T>"' -ForEach @(@{ T = '9' }, @{ T = '0' }, @{ T = 'abc' }, @{ T = '4-2' }, @{ T = '3-9' }) {
        { & $m { param($t) ConvertFrom-EdtWtSelection -Text $t -Count 5 } $T } | Should -Throw '*1-5*'
    }
}
