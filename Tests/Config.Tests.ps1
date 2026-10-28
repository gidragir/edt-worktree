BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Root = New-EdtWtTestRoot
    $script:CfgPath = Use-EdtWtTestConfig -Root $script:Root
    Import-Module (Join-Path $PSScriptRoot '..\EdtWorktree.psd1') -Force -DisableNameChecking
    $script:m = Get-Module EdtWorktree
}

AfterAll {
    Remove-Item env:EDT_CONFIG_PATH -ErrorAction SilentlyContinue
    Remove-Item env:EDT_LEGACY_CONFIG_PATH -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $script:Root) {
        Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Конфигурация EdtWorktree v3' {
    BeforeEach {
        Remove-Item -LiteralPath $script:CfgPath -Force -ErrorAction SilentlyContinue
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
            '{"paths":{"repos_root":"X:\\repos"},"custom":{"x":1}}' | Set-Content $script:CfgPath -Encoding utf8NoBOM
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
            '{"projects":{"p":{"ref_branch":"main"}}}' | Set-Content $script:CfgPath -Encoding utf8NoBOM
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

        It 'Get-EdtWtProjectIdFromRepo не падает при пустом Projects' {
            $empty = [PSCustomObject]@{}
            $res = & $m {
                param($p) Get-EdtWtProjectIdFromRepo -GitCommonDir 'C:\dummy\.git' -Projects $p
            } $empty
            $res | Should -BeNullOrEmpty
        }
    }
}
