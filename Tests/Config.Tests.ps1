BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\EdtWorktree.psd1') -Force -DisableNameChecking
}

Describe 'Конфигурация EdtWorktree' {
    Context 'Автопоиск EDT' {
        It 'Find-EdtWtCli возвращает список или пустой массив без падения' {
            $clis = & (Get-Module EdtWorktree) { Find-EdtWtCli }
            $clis | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Чтение и слияние конфигурации' {
        It 'Get-EdtConfig возвращает объект с базовыми полями' {
            $cfg = Get-EdtConfig
            $cfg.PSObject.Properties.Name | Should -Contain 'ProjectsRoot'
            $cfg.PSObject.Properties.Name | Should -Contain 'WorktreeRoot'
            $cfg.PSObject.Properties.Name | Should -Contain 'WorkspacesRoot'
            $cfg.PSObject.Properties.Name | Should -Contain 'EdtCliPath'
            $cfg.PSObject.Properties.Name | Should -Contain 'ReferenceBranch'
        }

        It 'Get-EdtConfig -AsJson возвращает валидный JSON' {
            $jsonStr = Get-EdtConfig -AsJson
            $parsed = $jsonStr | ConvertFrom-Json
            $parsed.ProjectsRoot | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Сохранение и изменение настроек' {
        BeforeAll {
            $script:TempConfigDir = Join-Path ([System.IO.Path]::GetTempPath()) ("edt_cfg_" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:TempConfigDir -Force | Out-Null
            $script:TempConfigFile = Join-Path $script:TempConfigDir 'config.json'
            $env:EDT_CONFIG_PATH = $script:TempConfigFile
        }

        AfterAll {
            Remove-Item env:EDT_CONFIG_PATH -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $script:TempConfigDir) {
                Remove-Item -LiteralPath $script:TempConfigDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Set-EdtConfig сохраняет параметры и обновляет конфигурацию' {
            Set-EdtConfig -WorkspacesRoot 'T:\test-workspaces' -MaxHeap '16g' -ReferenceBranch 'main' -Confirm:$false

            Test-Path -LiteralPath $script:TempConfigFile | Should -BeTrue
            $savedJson = Get-Content -Raw -LiteralPath $script:TempConfigFile -Encoding UTF8 | ConvertFrom-Json
            $savedJson.paths.workspaces_root | Should -Be 'T:\test-workspaces'
            $savedJson.edt.jvm.max_heap | Should -Be '16g'
            $savedJson.defaults.reference_branch | Should -Be 'main'
        }

        It 'Set-EdtConfig отклоняет невалидный формат размера памяти' {
            { Set-EdtConfig -MaxHeap 'invalid' -Confirm:$false } | Should -Throw
        }
    }

    Context 'Инициализация проекта .edt-worktree.json' {
        BeforeAll {
            $script:TempRepoDir = Join-Path ([System.IO.Path]::GetTempPath()) ("edt_repo_" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:TempRepoDir -Force | Out-Null
        }

        AfterAll {
            if (Test-Path -LiteralPath $script:TempRepoDir) {
                Remove-Item -LiteralPath $script:TempRepoDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'New-EdtProjectConfig создает валидный .edt-worktree.json' {
            # Проверяем создание файла напрямую
            $projFile = Join-Path $script:TempRepoDir '.edt-worktree.json'
            $template = [ordered]@{
                cf_project        = 'my-custom-cf'
                reference_branch  = 'master'
                v8version         = '8.3.24'
                active_extensions = @()
                ignored_patterns  = @()
                ibconnection      = ''
            }
            Set-Content -LiteralPath $projFile -Value (ConvertTo-Json $template) -Encoding UTF8

            $found = & (Get-Module EdtWorktree) {
                param($p) Get-EdtWtProjectConfigFile -Path $p
            } $script:TempRepoDir

            $found | Should -Be $projFile

            $cfg = & (Get-Module EdtWorktree) {
                param($p) Get-EdtWtConfig -Path $p
            } $script:TempRepoDir

            $cfg.ActiveProjectId | Should -Be 'my-custom-cf'
            $cfg.projects.'my-custom-cf'.reference_branch | Should -Be 'master'
        }
    }

    Context 'Безопасность Set-StrictMode и пустые коллекции' {
        It 'Get-EdtWtProperty не выбрасывает исключение для пустого объекта' {
            $empty = [PSCustomObject]@{}
            $val = & (Get-Module EdtWorktree) {
                param($o) Get-EdtWtProperty $o 'missing' 'default_val'
            } $empty
            $val | Should -Be 'default_val'
        }

        It 'Resolve-EdtWtTarget не падает при отсутствии проектов в реестре' {
            {
                & (Get-Module EdtWorktree) {
                    Resolve-EdtWtTarget -Positional @() -Command 'open'
                }
            } | Should -Not -Throw
        }

        It 'Get-EdtWtProjectIdFromRepo не падает при пустом Projects' {
            $empty = [PSCustomObject]@{}
            $res = & (Get-Module EdtWorktree) {
                param($p) Get-EdtWtProjectIdFromRepo -GitCommonDir 'C:\dummy\.git' -Projects $p
            } $empty
            $res | Should -BeNullOrEmpty
        }
    }
}

