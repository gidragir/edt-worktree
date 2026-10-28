BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
    Import-Module (Join-Path $PSScriptRoot '..\EdtWorktree.psd1') -Force
}

AfterAll {
    Exit-EdtWtTestConfig -State $script:TestCfg
}

Describe 'Test-EdtEnvironment (edt doctor)' {
    BeforeEach {
        $script:Root = Join-Path $script:TestCfg.Root ([guid]::NewGuid().ToString('N'))
        $script:R = Join-Path $script:Root 'repos'
        $script:W = Join-Path $script:Root 'wt'
        $script:S = Join-Path $script:Root 'ws'
        New-Item -ItemType Directory -Path $script:R, $script:W, $script:S -Force | Out-Null
        Mock -ModuleName EdtWorktree Find-EdtWtCli { @([pscustomobject]@{ Version = '2024.2'; Path = 'C:\fake\1cedtcli.exe'; Folder = 'C:\fake' }) }
        Mock -ModuleName EdtWorktree Resolve-EdtWtGuiJvm { [pscustomobject]@{ Path = 'C:\jdk\bin\server\jvm.dll'; Reason = 'scan' } }
        Mock -ModuleName EdtWorktree Start-Process { throw 'doctor не запускает процессы' }
        Mock -ModuleName EdtWorktree Save-EdtWtConfig { throw 'doctor не пишет конфиг' }
    }

    function script:Set-DoctorConfig {
        param([hashtable]$Projects = @{}, [hashtable]$Edt = @{})
        $cfg = [ordered]@{
            version  = 3
            paths    = [ordered]@{ repos_root = $script:R; worktrees_root = $script:W; workspaces_root = $script:S }
            edt      = $Edt
            projects = $Projects
        }
        [IO.File]::WriteAllText($script:TestCfg.Path, ($cfg | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    }

    It 'клон на чужой ветке - error с командой switch' {
        New-EdtWtTestRepo -Root $script:R -Name 'p' -Branch 'main' -Projects @{ 'src/cf' = 'Configuration' } | Out-Null
        Set-DoctorConfig -Projects @{ p = @{ ref_branch = 'develop'; cf_project = 'src/cf'; extensions = @() } }
        $row = Test-EdtEnvironment | Where-Object { $_.Check -match 'ветка' -and $_.Status -eq 'error' }
        $row.Fix | Should -Match 'switch develop'
    }

    It 'новое расширение - warn с edt project ext' {
        New-EdtWtTestRepo -Root $script:R -Name 'p' -Branch 'main' -Projects @{ 'src/cf' = 'Configuration'; 'src/cfe_ad' = 'Extension' } | Out-Null
        Set-DoctorConfig -Projects @{ p = @{ ref_branch = 'main'; cf_project = 'src/cf'; extensions = @() } }
        $row = Test-EdtEnvironment | Where-Object Fix -Match '^edt project ext p$'
        $row.Status | Should -Be 'warn'
    }

    It 'рабочее расширение отсутствует на диске - warn с -имя' {
        New-EdtWtTestRepo -Root $script:R -Name 'p' -Branch 'main' -Projects @{ 'src/cf' = 'Configuration' } | Out-Null
        Set-DoctorConfig -Projects @{ p = @{ ref_branch = 'main'; cf_project = 'src/cf'; extensions = @('src/cfe_gone') } }
        $row = Test-EdtEnvironment | Where-Object Fix -Match '^edt project ext p -cfe_gone$'
        $row.Status | Should -Be 'warn'
    }

    It 'нет эталона - warn с edt warmup' {
        New-EdtWtTestRepo -Root $script:R -Name 'p' -Branch 'main' -Projects @{ 'src/cf' = 'Configuration' } | Out-Null
        Set-DoctorConfig -Projects @{ p = @{ ref_branch = 'main'; cf_project = 'src/cf'; extensions = @() } }
        $row = Test-EdtEnvironment | Where-Object Fix -Eq 'edt warmup p'
        $row.Status | Should -Be 'warn'
    }

    It 'нет клона - error' {
        Set-DoctorConfig -Projects @{ p = @{ ref_branch = 'main'; cf_project = 'src/cf'; extensions = @() } }
        @(Test-EdtEnvironment | Where-Object { $_.Check -match 'клон' -and $_.Status -eq 'error' }).Count | Should -BeGreaterThan 0
    }

    It 'нет проектов - warn с edt project add' {
        Set-DoctorConfig
        (Test-EdtEnvironment | Where-Object Fix -Eq 'edt project add').Status | Should -Be 'warn'
    }

    It 'несуществующий путь paths.* - error с edt setup' {
        Set-DoctorConfig
        Remove-Item -LiteralPath $script:W -Force
        $row = Test-EdtEnvironment | Where-Object { $_.Check -match 'worktrees_root' }
        $row.Status | Should -Be 'error'
        $row.Fix | Should -Be 'edt setup'
    }

    It 'EDT не найден - error' {
        Mock -ModuleName EdtWorktree Find-EdtWtCli { @() }
        Set-DoctorConfig
        (Test-EdtEnvironment | Where-Object Check -Match 'EDT$').Status | Should -Be 'error'
    }

    It 'JVM none - warn, иначе ok с причиной в Detail' {
        Set-DoctorConfig
        $ok = Test-EdtEnvironment | Where-Object Check -Match 'JVM'
        $ok.Status | Should -Be 'ok'
        $ok.Detail | Should -Match 'scan'
        $ok.Detail | Should -Match 'jvm\.dll'
        Mock -ModuleName EdtWorktree Resolve-EdtWtGuiJvm { [pscustomobject]@{ Path = $null; Reason = 'none' } }
        (Test-EdtEnvironment | Where-Object Check -Match 'JVM').Status | Should -Be 'warn'
    }

    It 'edt.vm_path без jvm.dll - warn с путём и edt config set' {
        $bad = Join-Path $script:Root 'nojdk'
        Set-DoctorConfig -Edt @{ vm_path = $bad }
        $row = Test-EdtEnvironment | Where-Object Check -Match 'vm_path'
        $row.Status | Should -Be 'warn'
        $row.Detail | Should -Match ([regex]::Escape($bad))
        $row.Fix | Should -Match 'edt config set edt\.vm_path'
    }

    It 'повреждённый конфиг - одна строка error, без исключения' {
        [IO.File]::WriteAllText($script:TestCfg.Path, '{ not json', [Text.UTF8Encoding]::new($false))
        $rows = @(Test-EdtEnvironment)
        $rows.Count | Should -Be 1
        $rows[0].Status | Should -Be 'error'
        $rows[0].Fix | Should -Match 'edt setup'
    }

    It 'всё в порядке - ни одного error, конфиг не меняется' {
        New-EdtWtTestRepo -Root $script:R -Name 'p' -Branch 'main' -Projects @{ 'src/cf' = 'Configuration'; 'src/cfe_ad' = 'Extension' } | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:S 'p\_reference') -Force | Out-Null
        Set-DoctorConfig -Projects @{ p = @{ ref_branch = 'main'; cf_project = 'src/cf'; extensions = @('src/cfe_ad') } }
        $before = Get-Content -Raw -LiteralPath $script:TestCfg.Path
        $rows = @(Test-EdtEnvironment)
        @($rows | Where-Object Status -Eq 'error').Count | Should -Be 0
        $rows[0].PSObject.Properties.Name | Should -Be @('Check', 'Status', 'Detail', 'Fix')
        Get-Content -Raw -LiteralPath $script:TestCfg.Path | Should -Be $before
    }
}
