BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
    $script:Root = $script:TestCfg.Root
    $script:CfgPath = $script:TestCfg.Path
    Import-Module (Get-EdtWtTestModulePath) -Force -DisableNameChecking
}

AfterAll {
    Exit-EdtWtTestConfig -State $script:TestCfg
}

Describe 'edt setup' {
    BeforeEach {
        Remove-Item -LiteralPath $script:CfgPath -Force -ErrorAction SilentlyContinue
        $script:R = Join-Path $script:Root 'r'
        $script:W = Join-Path $script:Root 'w'
        $script:S = Join-Path $script:Root 's'
        Remove-Item -LiteralPath $script:R, $script:W, $script:S -Recurse -Force -ErrorAction SilentlyContinue
        Mock -ModuleName EdtWorktree Find-EdtWtCli { @() }
        Mock -ModuleName EdtWorktree Add-EdtProject { }
    }

    Context 'Без диалога' {
        BeforeEach {
            Mock -ModuleName EdtWorktree Test-EdtWtInteractive { $false }
            Mock -ModuleName EdtWorktree Read-EdtWtAnswer { throw 'не должен спрашивать' }
        }

        It 'пишет пути, создаёт каталоги и не задаёт вопросов' {
            Invoke-EdtSetup -ReposRoot $script:R -WorktreesRoot $script:W -WorkspacesRoot $script:S
            $j = Get-Content $script:CfgPath -Raw | ConvertFrom-Json
            $j.paths.repos_root | Should -Be $script:R
            $j.paths.worktrees_root | Should -Be $script:W
            $j.paths.workspaces_root | Should -Be $script:S
            Test-Path $script:S | Should -BeTrue
            Test-Path $script:R | Should -BeTrue
            Should -Invoke -ModuleName EdtWorktree Read-EdtWtAnswer -Times 0 -Exactly
            Should -Invoke -ModuleName EdtWorktree Add-EdtProject -Times 0 -Exactly
        }

        It 'без параметров оставляет текущие значения' {
            '{"version":3,"paths":{"repos_root":"' + ($script:R -replace '\\', '\\') + '"}}' | Set-Content $script:CfgPath -Encoding utf8NoBOM
            Invoke-EdtSetup -WorktreesRoot $script:W -WorkspacesRoot $script:S
            (Get-Content $script:CfgPath -Raw | ConvertFrom-Json).paths.repos_root | Should -Be $script:R
        }

        It 'повторный setup сохраняет проекты и неизвестные ключи' {
            '{"version":3,"custom":{"x":1},"projects":{"p":{"ref_branch":"main","cf_project":"src/cf","extensions":["src/cfe"]}}}' |
                Set-Content $script:CfgPath -Encoding utf8NoBOM
            Invoke-EdtSetup -ReposRoot $script:R -WorktreesRoot $script:W -WorkspacesRoot $script:S
            Invoke-EdtSetup -ReposRoot $script:R -WorktreesRoot $script:W -WorkspacesRoot $script:S
            $j = Get-Content $script:CfgPath -Raw | ConvertFrom-Json
            $j.projects.p | Should -Not -BeNullOrEmpty
            $j.projects.p.extensions | Should -Be @('src/cfe')
            $j.custom.x | Should -Be 1
        }

        It '-WhatIf ничего не пишет: ни конфига, ни каталогов' {
            Invoke-EdtSetup -ReposRoot $script:R -WorktreesRoot $script:W -WorkspacesRoot $script:S -WhatIf
            Test-Path $script:CfgPath | Should -BeFalse
            Test-Path $script:R | Should -BeFalse
            Test-Path $script:W | Should -BeFalse
            Test-Path $script:S | Should -BeFalse
        }

        It 'печатает подсказку, если EDT не найден' {
            $out = Invoke-EdtSetup -ReposRoot $script:R -WorktreesRoot $script:W -WorkspacesRoot $script:S 6>&1 | Out-String
            $out | Should -BeLike '*edt config set edt.cli_path*'
        }

        It 'печатает найденный EDT' {
            Mock -ModuleName EdtWorktree Find-EdtWtCli { [PSCustomObject]@{ Version = '2025.1.0'; Path = 'C:\x\1cedtcli.exe'; Folder = 'C:\x' } }
            $out = Invoke-EdtSetup -ReposRoot $script:R -WorktreesRoot $script:W -WorkspacesRoot $script:S 6>&1 | Out-String
            $out | Should -BeLike '*2025.1.0*'
        }

        It 'под установщиком с -NoPath (EDT_INSTALL_NOPATH=1) ставит shim без записи в PATH' {
            Mock -ModuleName EdtWorktree Install-EdtWtShim { 'shim-dir' }
            $prev = $env:EDT_INSTALL_NOPATH
            $env:EDT_INSTALL_NOPATH = '1'
            try {
                Invoke-EdtSetup -ReposRoot $script:R -WorktreesRoot $script:W -WorkspacesRoot $script:S 6>$null | Out-Null
            } finally { $env:EDT_INSTALL_NOPATH = $prev }
            Should -Invoke -ModuleName EdtWorktree Install-EdtWtShim -Times 1 -Exactly -ParameterFilter { $NoPath.IsPresent }
        }

        It 'без EDT_INSTALL_NOPATH ставит shim с записью в PATH' {
            Mock -ModuleName EdtWorktree Install-EdtWtShim { 'shim-dir' }
            $prev = $env:EDT_INSTALL_NOPATH
            $env:EDT_INSTALL_NOPATH = $null
            try {
                Invoke-EdtSetup -ReposRoot $script:R -WorktreesRoot $script:W -WorkspacesRoot $script:S 6>$null | Out-Null
            } finally { $env:EDT_INSTALL_NOPATH = $prev }
            Should -Invoke -ModuleName EdtWorktree Install-EdtWtShim -Times 1 -Exactly -ParameterFilter { -not $NoPath.IsPresent }
        }

        It 'повреждённый конфиг: ошибка до создания каталогов' {
            '{ broken' | Set-Content $script:CfgPath
            { Invoke-EdtSetup -ReposRoot $script:R -WorktreesRoot $script:W -WorkspacesRoot $script:S } | Should -Throw '*Конфиг повреждён*'
            Test-Path $script:R | Should -BeFalse
        }
    }

    Context 'С диалогом' {
        BeforeEach {
            Mock -ModuleName EdtWorktree Test-EdtWtInteractive { $true }
            Mock -ModuleName EdtWorktree Read-EdtWtAnswer { $Default }
        }

        It 'спрашивает три пути с текущим значением по умолчанию, создаёт каталоги, предлагает проекты' {
            Invoke-EdtSetup
            Should -Invoke -ModuleName EdtWorktree Read-EdtWtAnswer -Times 3 -Exactly -ParameterFilter { $Prompt -notlike '*Создать*' }
            Should -Invoke -ModuleName EdtWorktree Add-EdtProject -Times 1 -Exactly
            Test-Path $script:CfgPath | Should -BeTrue
        }

        It 'не спрашивает пути, переданные параметрами' {
            Invoke-EdtSetup -ReposRoot $script:R -WorktreesRoot $script:W -WorkspacesRoot $script:S
            Should -Invoke -ModuleName EdtWorktree Read-EdtWtAnswer -Times 3 -Exactly -ParameterFilter { $Prompt -like '*Создать*' }
            Test-Path $script:S | Should -BeTrue
        }

        It 'отказ создать каталог не создаёт его' {
            Mock -ModuleName EdtWorktree Read-EdtWtAnswer { if ($Prompt -like '*Создать*') { 'n' } else { $Default } }
            Invoke-EdtSetup -ReposRoot $script:R -WorktreesRoot $script:W -WorkspacesRoot $script:S
            Test-Path $script:S | Should -BeFalse
            (Get-Content $script:CfgPath -Raw | ConvertFrom-Json).paths.workspaces_root | Should -Be $script:S
        }

        It '-NoProjects не регистрирует проекты' {
            Invoke-EdtSetup -ReposRoot $script:R -WorktreesRoot $script:W -WorkspacesRoot $script:S -NoProjects
            Should -Invoke -ModuleName EdtWorktree Add-EdtProject -Times 0 -Exactly
        }

        It '-WhatIf ничего не пишет и не регистрирует проекты' {
            Invoke-EdtSetup -ReposRoot $script:R -WorktreesRoot $script:W -WorkspacesRoot $script:S -WhatIf
            Test-Path $script:CfgPath | Should -BeFalse
            Test-Path $script:R | Should -BeFalse
            Should -Invoke -ModuleName EdtWorktree Add-EdtProject -Times 0 -Exactly
        }
    }
}

Describe 'edt config' {
    BeforeEach {
        Remove-Item -LiteralPath $script:CfgPath -Force -ErrorAction SilentlyContinue
        Mock -ModuleName EdtWorktree Find-EdtWtCli { @() }
    }

    Context 'Set-EdtConfig' {
        It 'валидирует ключ и формат' {
            Set-EdtConfig -Key 'edt.max_heap' -Value '16g'
            (Get-Content $script:CfgPath -Raw | ConvertFrom-Json).edt.max_heap | Should -Be '16g'
            { Set-EdtConfig -Key 'edt.max_heap' -Value 'много' } | Should -Throw
            { Set-EdtConfig -Key 'nope' -Value 1 } | Should -Throw '*paths.repos_root*'
            Set-EdtConfig -Key 'edt.cli_path' -Value 'null'
            (Get-Content $script:CfgPath -Raw | ConvertFrom-Json).edt.cli_path | Should -BeNullOrEmpty
        }

        It 'gui_max_heap принимает только число с g/m' {
            Set-EdtConfig -Key 'edt.gui_max_heap' -Value '512M'
            (Get-Content $script:CfgPath -Raw | ConvertFrom-Json).edt.gui_max_heap | Should -Be '512M'
            { Set-EdtConfig -Key 'edt.gui_max_heap' -Value '8' } | Should -Throw
        }

        It 'timeout_sec - целое больше нуля, хранится числом' {
            Set-EdtConfig -Key 'edt.timeout_sec' -Value '600'
            (Get-Content $script:CfgPath -Raw | ConvertFrom-Json).edt.timeout_sec | Should -BeOfType [long]
            (Get-Content $script:CfgPath -Raw | ConvertFrom-Json).edt.timeout_sec | Should -Be 600
            foreach ($bad in '0', '-5', 'abc', '1.5') {
                { Set-EdtConfig -Key 'edt.timeout_sec' -Value $bad } | Should -Throw
            }
        }

        It 'пути и git-ключи принимают строку' {
            Set-EdtConfig -Key 'paths.repos_root' -Value 'X:\repos'
            Set-EdtConfig -Key 'git.remote' -Value 'upstream'
            Set-EdtConfig -Key 'git.branch_prefix' -Value 'task/'
            Set-EdtConfig -Key 'edt.extra_vmargs' -Value '-Dfoo=bar'
            $j = Get-Content $script:CfgPath -Raw | ConvertFrom-Json
            $j.paths.repos_root | Should -Be 'X:\repos'
            $j.git.remote | Should -Be 'upstream'
            $j.git.branch_prefix | Should -Be 'task/'
            $j.edt.extra_vmargs | Should -Be '-Dfoo=bar'
        }

        It 'пустое значение сбрасывает в null' {
            Set-EdtConfig -Key 'edt.vm_path' -Value 'C:\jdk\bin\server\jvm.dll' 3>$null
            Set-EdtConfig -Key 'edt.vm_path' -Value ''
            (Get-Content $script:CfgPath -Raw | ConvertFrom-Json).edt.vm_path | Should -BeNullOrEmpty
        }

        It 'предупреждает о несуществующем пути, но сохраняет' {
            $missing = Join-Path $script:Root 'нет\1cedtcli.exe'
            $warn = Set-EdtConfig -Key 'edt.cli_path' -Value $missing 3>&1 | Out-String
            $warn | Should -BeLike '*не существует*'
            (Get-Content $script:CfgPath -Raw | ConvertFrom-Json).edt.cli_path | Should -Be $missing
        }

        It 'сохраняет проекты и неизвестные ключи' {
            '{"version":3,"custom":{"x":1},"projects":{"p":{"ref_branch":"main"}}}' | Set-Content $script:CfgPath -Encoding utf8NoBOM
            Set-EdtConfig -Key 'git.remote' -Value 'o2'
            $j = Get-Content $script:CfgPath -Raw | ConvertFrom-Json
            $j.projects.p.ref_branch | Should -Be 'main'
            $j.custom.x | Should -Be 1
        }

        It '-WhatIf ничего не пишет' {
            Set-EdtConfig -Key 'git.remote' -Value 'o2' -WhatIf
            Test-Path $script:CfgPath | Should -BeFalse
        }

        It 'не перезаписывает повреждённый файл' {
            foreach ($body in '{ broken', '[]', '"x"') {
                [IO.File]::WriteAllText($script:CfgPath, $body)
                $before = [IO.File]::ReadAllBytes($script:CfgPath)
                { Set-EdtConfig -Key 'git.remote' -Value 'o2' } | Should -Throw '*Конфиг повреждён*'
                [IO.File]::ReadAllBytes($script:CfgPath) | Should -Be $before
            }
        }
    }

    Context 'Get-EdtConfig' {
        It 'сводка содержит ключевые поля' {
            '{"version":3,"projects":{"p":{"ref_branch":"main"}}}' | Set-Content $script:CfgPath -Encoding utf8NoBOM
            $s = Get-EdtConfig
            $s.ConfigFile | Should -Be $script:CfgPath
            $s.ReposRoot | Should -Not -BeNullOrEmpty
            $s.WorktreesRoot | Should -Not -BeNullOrEmpty
            $s.WorkspacesRoot | Should -Not -BeNullOrEmpty
            @($s.Projects) | Should -Be @('p')
            $s.EdtCli | Should -BeLike 'авто:*'
        }

        It 'EdtCli показывает найденный EDT, если cli_path не задан' {
            Mock -ModuleName EdtWorktree Find-EdtWtCli { [PSCustomObject]@{ Version = '2025.1.0'; Path = 'C:\x\1cedtcli.exe'; Folder = 'C:\x' } }
            (Get-EdtConfig).EdtCli | Should -Be 'авто: C:\x\1cedtcli.exe'
        }

        It 'EdtCli показывает заданный cli_path' {
            Set-EdtConfig -Key 'edt.cli_path' -Value 'C:\y\1cedtcli.exe' 3>$null
            (Get-EdtConfig).EdtCli | Should -Be 'C:\y\1cedtcli.exe'
        }

        It '-Path возвращает только путь к файлу' {
            Get-EdtConfig -Path | Should -Be $script:CfgPath
        }

        It '-AsJson возвращает разбираемый JSON' {
            ((Get-EdtConfig -AsJson) | ConvertFrom-Json).ConfigFile | Should -Be $script:CfgPath
        }
    }
}
