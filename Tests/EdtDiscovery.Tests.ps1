BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
    Import-Module (Get-EdtWtTestModulePath) -Force -DisableNameChecking
    $script:m = Get-Module EdtWorktree
}

AfterAll {
    Exit-EdtWtTestConfig -State $script:TestCfg
}

Describe 'Find-EdtWtCli' {
    BeforeEach {
        $script:Root = Join-Path ([System.IO.Path]::GetTempPath()) ('edtfind_' + [guid]::NewGuid().ToString('N'))
        foreach ($v in '2024.2.9+1', '2024.2.10+1', '2023.3.2+4') {
            $dir = Join-Path $script:Root "1C\1CE\components\1c-edt-$v-x86_64"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir '1cedtcli.exe') -Value 'stub'
        }
        $junk = Join-Path $script:Root '1C\1CE\components\unversioned'
        New-Item -ItemType Directory -Path $junk -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $junk '1cedtcli.exe') -Value 'stub'
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:Root) { Remove-Item -LiteralPath $script:Root -Recurse -Force }
    }

    It 'версии EDT сортируются как версии, а не как строки' {
        $r = @(& $script:m { param($r) Find-EdtWtCli -SearchRoots $r -SkipPath } $script:Root)
        $r.Count | Should -Be 4
        $r[0].Path | Should -Match '2024\.2\.10'
        $r[1].Path | Should -Match '2024\.2\.9'
        $r[2].Path | Should -Match '2023\.3\.2'
        $r[3].Path | Should -Match 'unversioned'
    }
}
