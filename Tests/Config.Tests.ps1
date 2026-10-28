BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
    $script:Root = $script:TestCfg.Root
    $script:CfgPath = $script:TestCfg.Path
    Import-Module (Join-Path $PSScriptRoot '..\EdtWorktree.psd1') -Force -DisableNameChecking
    $script:m = Get-Module EdtWorktree
}

AfterAll {
    Exit-EdtWtTestConfig -State $script:TestCfg
}
Describe 'Конфигурация EdtWorktree v3' {
    BeforeEach {
        Remove-Item -LiteralPath $script:CfgPath, "$script:CfgPath.v2.bak" -Force -ErrorAction SilentlyContinue
    }

    Context 'Чтение' {
        It 'без файла возвращает дефолты v3 и ничего не пишет' {
            $cfg = & $m { Get-EdtWtConfig }
            $cfg.version | Should -Be 3
            $cfg.git.remote | Should -Be 'origin'
            $cfg.git.branch_prefix | Should -Be 'feature/'
            $cfg.edt.timeout_sec | Should -Be 7200
            Test-Path $script:CfgPath | Should -BeFalse
        }

        It 'Get-EdtWtUserConfigPath уважает EDT_CONFIG_PATH' {
            & $m { Get-EdtWtUserConfigPath } | Should -Be $script:CfgPath
        }

        It 'файл накладывается поверх дефолтов, неизвестные ключи сохраняются' {
            '{"version":3,"paths":{"repos_root":"X:\\repos"},"custom":{"x":1}}' | Set-Content $script:CfgPath -Encoding utf8NoBOM
            $cfg = & $m { Get-EdtWtConfig }
            $cfg.paths.repos_root | Should -Be 'X:\repos'
            $cfg.paths.worktrees_root | Should -Not -BeNullOrEmpty
            $cfg.edt.timeout_sec | Should -Be 7200
            $cfg.custom.x | Should -Be 1
        }

        It 'битый JSON: понятная ошибка, файл не перезаписан' {
            '{ broken' | Set-Content $script:CfgPath
            { & $m { Get-EdtWtConfig } } | Should -Throw '*Конфиг повреждён*'
            Get-Content $script:CfgPath -Raw | Should -Match '\{ broken'
        }

        It 'JSON с корнем не-объектом: та же ошибка' {
            foreach ($body in '[]', '"x"', '123') {
                [IO.File]::WriteAllText($script:CfgPath, $body)
                { & $m { Get-EdtWtConfig } } | Should -Throw '*Конфиг повреждён*'
            }
        }

        It 'пустой файл даёт дефолты' {
            [IO.File]::WriteAllText($script:CfgPath, "  `n")
            (& $m { Get-EdtWtConfig }).version | Should -Be 3
        }

        It 'Set-EdtConfig и Invoke-EdtSetup не перезаписывают повреждённый файл' {
            Mock -ModuleName EdtWorktree Test-EdtWtInteractive { $false }
            foreach ($body in '{ broken', '[]', '"x"') {
                [IO.File]::WriteAllText($script:CfgPath, $body)
                $before = [IO.File]::ReadAllBytes($script:CfgPath)
                { Set-EdtConfig -Key edt.max_heap -Value 8g -Confirm:$false } | Should -Throw '*Конфиг повреждён*'
                { Invoke-EdtSetup } | Should -Throw '*Конфиг повреждён*'
                { & $m { Save-EdtWtConfig -Config (Get-EdtWtConfig) } } | Should -Throw '*Конфиг повреждён*'
                [IO.File]::ReadAllBytes($script:CfgPath) | Should -Be $before
            }
        }
    }

    Context 'Сохранение' {
        It 'round-trip сохраняет проекты и неизвестные ключи' {
            '{"version":3,"custom":{"x":1},"projects":{"p":{"ref_branch":"main","cf_project":"src/cf","extensions":["src/cfe"]}}}' |
                Set-Content $script:CfgPath -Encoding utf8NoBOM
            & $m { Save-EdtWtConfig -Config (Get-EdtWtConfig) } | Out-Null
            $j = Get-Content $script:CfgPath -Raw | ConvertFrom-Json
            $j.custom.x | Should -Be 1
            $j.projects.p.extensions | Should -Be @('src/cfe')
            $j.git.remote | Should -Be 'origin'
        }

        It 'пишет UTF-8 без BOM и возвращает путь' {
            $saved = & $m { Save-EdtWtConfig -Config (New-EdtWtDefaultConfig) }
            $saved | Should -Be $script:CfgPath
            ([IO.File]::ReadAllBytes($script:CfgPath))[0] | Should -Not -Be 0xEF
        }

        It 'не оставляет временных файлов рядом с конфигом' {
            & $m { Save-EdtWtConfig -Config (New-EdtWtDefaultConfig) } | Out-Null
            @(Get-ChildItem -LiteralPath $script:Root -Filter 'config.json*').Name | Should -Be @('config.json')
        }
    }

    Context 'Проекты' {
        It 'Get-EdtWtProjectDef для незарегистрированного проекта подсказывает edt project add' {
            { & $m { Get-EdtWtProjectDef -Config (New-EdtWtDefaultConfig) -Name 'zzz' } } | Should -Throw '*edt project add zzz*'
        }

        It 'Get-EdtWtProjectDef возвращает описание зарегистрированного проекта' {
            '{"version":3,"projects":{"p":{"ref_branch":"main"}}}' | Set-Content $script:CfgPath -Encoding utf8NoBOM
            $def = & $m { Get-EdtWtProjectDef -Config (Get-EdtWtConfig) -Name 'p' }
            $def.ref_branch | Should -Be 'main'
        }
    }

    Context 'Интерактивность' {
        It 'Test-EdtWtInteractive возвращает bool' {
            (& $m { Test-EdtWtInteractive }) | Should -BeOfType [bool]
        }
    }

    Context 'Автопоиск EDT' {
        It 'Find-EdtWtCli возвращает список или пустой массив без падения' {
            { & $m { Find-EdtWtCli } } | Should -Not -Throw
        }
    }

    Context 'Безопасность Set-StrictMode и пустые коллекции' {
        It 'Get-EdtWtProperty не выбрасывает исключение для пустого объекта' {
            $empty = [PSCustomObject]@{}
            $val = & $m {
                param($o) Get-EdtWtProperty $o 'missing' 'default_val'
            } $empty
            $val | Should -Be 'default_val'
        }

        It 'Resolve-EdtWtTarget не падает при отсутствии проектов в реестре' {
            {
                & $m {
                    Resolve-EdtWtTarget -Positional @() -Command 'open'
                }
            } | Should -Not -Throw
        }
    }
}
