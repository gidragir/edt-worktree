BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
    $script:Root = $script:TestCfg.Root
    $script:CfgPath = $script:TestCfg.Path
    $script:LegacyPath = $env:EDT_LEGACY_CONFIG_PATH
    Import-Module (Get-EdtWtTestModulePath) -Force -DisableNameChecking
    $script:m = Get-Module EdtWorktree

    # Клон p с расширением cfe_a (cfe_gone отсутствует)
    $script:Repos = Join-Path $script:Root 'repos'
    New-Item -ItemType Directory -Path (Join-Path $script:Repos 'p\src\cfe_a') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $script:Repos 'p\src\cfe_a\.project') -Value '<x/>'
    $script:FakeCli = Join-Path $script:Root '1cedtcli.exe'
    Set-Content -LiteralPath $script:FakeCli -Value 'x'

    $script:V2Primary = ([ordered]@{
            paths    = [ordered]@{ projects_root = 'R'; worktree_root = 'W'; workspaces_root = 'S' }
            edt      = [ordered]@{ cli_path = $script:FakeCli; jvm = [ordered]@{ max_heap = '16g'; gui_max_heap = '8g' } }
            defaults = [ordered]@{ reference_branch = 'pre-prod'; edt_prefs_source = '' }
        } | ConvertTo-Json -Depth 6)
    $script:V2Legacy = '{"defaults":{"jvm":{"extra_args":"-XX:+UseG1GC"}},"worktree":{"root_dir":"X","reference_branch":"pre-prod"},"projects":{"p":{"cf_project":"src/cf","active_extensions":["cfe_a","cfe_gone"]}}}'
}

AfterAll {
    Exit-EdtWtTestConfig -State $script:TestCfg
}

Describe 'Миграция конфига 2.x -> v3' {
    BeforeEach {
        Remove-Item -LiteralPath $script:CfgPath, "$script:CfgPath.v2.bak", "$script:CfgPath.v2.bak.1", $script:LegacyPath -Force -ErrorAction SilentlyContinue
    }

    Context 'ConvertFrom-EdtWtV2Config' {
        It 'переносит пути, EDT, JVM и проекты' {
            $primary = $script:V2Primary | ConvertFrom-Json
            $legacy = $script:V2Legacy | ConvertFrom-Json
            $r = & $m { param($a, $b, $c) ConvertFrom-EdtWtV2Config -Primary $a -Legacy $b -ReposRootForCheck $c } $primary $legacy $script:Repos
            $r.Config.paths.repos_root | Should -Be 'R'
            $r.Config.paths.worktrees_root | Should -Be 'W'
            $r.Config.paths.workspaces_root | Should -Be 'S'
            $r.Config.edt.cli_path | Should -Be $script:FakeCli
            $r.Config.edt.max_heap | Should -Be '16g'
            $r.Config.edt.gui_max_heap | Should -Be '8g'
            $r.Config.edt.extra_vmargs | Should -Be '-XX:+UseG1GC'
            $r.Config.projects.p.cf_project | Should -Be 'src/cf'
            $r.Config.projects.p.extensions | Should -Be @('src/cfe_a')
            $r.Config.projects.p.ref_branch | Should -Be 'pre-prod'
            $r.Notes | Should -Not -BeNullOrEmpty
        }

        It 'несуществующий cli_path превращается в null (автопоиск)' {
            $primary = '{"edt":{"cli_path":"Z:\\nope\\1cedtcli.exe"}}' | ConvertFrom-Json
            $r = & $m { param($a, $c) ConvertFrom-EdtWtV2Config -Primary $a -Legacy $null -ReposRootForCheck $c } $primary $script:Repos
            $r.Config.edt.cli_path | Should -BeNullOrEmpty
        }

        It 'legacy заполняет недостающее; workspaces_root из worktree.root_dir' {
            $legacy = $script:V2Legacy | ConvertFrom-Json
            $r = & $m { param($b, $c) ConvertFrom-EdtWtV2Config -Primary $null -Legacy $b -ReposRootForCheck $c } $legacy $script:Repos
            $r.Config.paths.workspaces_root | Should -Be 'X'
        }

        It 'ref_branch проекта приоритетнее общего' {
            $legacy = '{"worktree":{"reference_branch":"general"},"projects":{"p":{"reference_branch":"own"},"q":{}}}' | ConvertFrom-Json
            $r = & $m { param($b, $c) ConvertFrom-EdtWtV2Config -Primary $null -Legacy $b -ReposRootForCheck $c } $legacy $script:Repos
            $r.Config.projects.p.ref_branch | Should -Be 'own'
            $r.Config.projects.q.ref_branch | Should -Be 'general'
        }

        It 'без reference_branch берёт текущую ветку клона' {
            $clone = Join-Path $script:Repos 'gitp'
            New-Item -ItemType Directory -Path $clone -Force | Out-Null
            & git -C $clone init -q -b devbranch 2>&1 | Out-Null
            & git -C $clone -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>&1 | Out-Null
            $legacy = '{"projects":{"gitp":{}}}' | ConvertFrom-Json
            $r = & $m { param($b, $c) ConvertFrom-EdtWtV2Config -Primary $null -Legacy $b -ReposRootForCheck $c } $legacy $script:Repos
            $r.Config.projects.gitp.ref_branch | Should -Be 'devbranch'
        }

        It 'ключи проекта без аналога не переносятся' {
            $legacy = '{"projects":{"p":{"min_heap":"1g","ibconnection":"x","v8version":"8.3","bases_dir":"b","ignored_patterns":["a"],"cf_project":"src/cf"}}}' | ConvertFrom-Json
            $r = & $m { param($b, $c) ConvertFrom-EdtWtV2Config -Primary $null -Legacy $b -ReposRootForCheck $c } $legacy $script:Repos
            $names = @($r.Config.projects.p.PSObject.Properties.Name)
            $names | Should -Not -Contain 'min_heap'
            $names | Should -Not -Contain 'ibconnection'
            $names | Should -Not -Contain 'ignored_patterns'
            $names | Should -Contain 'cf_project'
        }
    }

    Context 'Get-EdtWtConfig' {
        It 'мигрирует один раз, оставляет .v2.bak и не трогает legacy' {
            Set-Content -LiteralPath $script:CfgPath -Value $script:V2Primary -Encoding utf8NoBOM
            Set-Content -LiteralPath $script:LegacyPath -Value $script:V2Legacy -Encoding utf8NoBOM
            $legacyHash = (Get-FileHash -LiteralPath $script:LegacyPath).Hash
            $v2Hash = (Get-FileHash -LiteralPath $script:CfgPath).Hash

            (& $m { Get-EdtWtConfig 6>$null }).version | Should -Be 3
            Test-Path "$script:CfgPath.v2.bak" | Should -BeTrue
            (Get-FileHash -LiteralPath "$script:CfgPath.v2.bak").Hash | Should -Be $v2Hash
            $saved = Get-Content -LiteralPath $script:CfgPath -Raw | ConvertFrom-Json
            $saved.version | Should -Be 3
            $saved.paths.repos_root | Should -Be 'R'
            (Get-FileHash -LiteralPath $script:LegacyPath).Hash | Should -Be $legacyHash

            # второй вызов: уже v3, бэкап не пересоздаётся
            Remove-Item -LiteralPath "$script:CfgPath.v2.bak"
            (& $m { Get-EdtWtConfig }).paths.repos_root | Should -Be 'R'
            Test-Path "$script:CfgPath.v2.bak" | Should -BeFalse
        }

        It 'без config.json мигрирует из legacy, бэкап не нужен' {
            Set-Content -LiteralPath $script:LegacyPath -Value $script:V2Legacy -Encoding utf8NoBOM
            $legacyHash = (Get-FileHash -LiteralPath $script:LegacyPath).Hash
            $cfg = & $m { Get-EdtWtConfig 6>$null }
            $cfg.version | Should -Be 3
            $cfg.paths.workspaces_root | Should -Be 'X'
            (Get-Content -LiteralPath $script:CfgPath -Raw | ConvertFrom-Json).version | Should -Be 3
            Test-Path "$script:CfgPath.v2.bak" | Should -BeFalse
            (Get-FileHash -LiteralPath $script:LegacyPath).Hash | Should -Be $legacyHash
        }

        It 'нет ни config.json, ни legacy - дефолты, ничего не пишется' {
            (& $m { Get-EdtWtConfig }).version | Should -Be 3
            Test-Path $script:CfgPath | Should -BeFalse
        }

        It 'повреждённый JSON по-прежнему бросает ошибку и не переписывает файл' {
            Set-Content -LiteralPath $script:LegacyPath -Value $script:V2Legacy -Encoding utf8NoBOM
            Set-Content -LiteralPath $script:CfgPath -Value '{ broken' -Encoding utf8NoBOM
            $before = (Get-FileHash -LiteralPath $script:CfgPath).Hash
            { & $m { Get-EdtWtConfig } } | Should -Throw '*Конфиг повреждён*'
            (Get-FileHash -LiteralPath $script:CfgPath).Hash | Should -Be $before
            Test-Path "$script:CfgPath.v2.bak" | Should -BeFalse
        }

        It 'битый legacy-файл: ошибка, ничего не записано (ни config.json, ни .bak)' {
            Set-Content -LiteralPath $script:LegacyPath -Value '{ broken' -Encoding utf8NoBOM
            $legacyHash = (Get-FileHash -LiteralPath $script:LegacyPath).Hash
            { & $m { Get-EdtWtConfig } } | Should -Throw '*Конфиг повреждён*'
            Test-Path $script:CfgPath | Should -BeFalse
            Test-Path "$script:CfgPath.v2.bak" | Should -BeFalse
            (Get-FileHash -LiteralPath $script:LegacyPath).Hash | Should -Be $legacyHash
        }

        It 'битый legacy при существующем v2 config.json: файл не изменён, бэкапа нет' {
            Set-Content -LiteralPath $script:CfgPath -Value $script:V2Primary -Encoding utf8NoBOM
            Set-Content -LiteralPath $script:LegacyPath -Value '[1,2]' -Encoding utf8NoBOM
            $before = (Get-FileHash -LiteralPath $script:CfgPath).Hash
            { & $m { Get-EdtWtConfig } } | Should -Throw '*Конфиг повреждён*'
            (Get-FileHash -LiteralPath $script:CfgPath).Hash | Should -Be $before
            Test-Path "$script:CfgPath.v2.bak" | Should -BeFalse
        }

        It 'существующий .v2.bak не перезаписывается' {
            Set-Content -LiteralPath $script:CfgPath -Value $script:V2Primary -Encoding utf8NoBOM
            Set-Content -LiteralPath "$script:CfgPath.v2.bak" -Value 'OLD BACKUP' -Encoding utf8NoBOM
            $oldHash = (Get-FileHash -LiteralPath "$script:CfgPath.v2.bak").Hash
            $v2Hash = (Get-FileHash -LiteralPath $script:CfgPath).Hash
            (& $m { Get-EdtWtConfig 6>$null }).version | Should -Be 3
            (Get-FileHash -LiteralPath "$script:CfgPath.v2.bak").Hash | Should -Be $oldHash
            Test-Path "$script:CfgPath.v2.bak.1" | Should -BeTrue
            (Get-FileHash -LiteralPath "$script:CfgPath.v2.bak.1").Hash | Should -Be $v2Hash
        }
        It 'v3-файл не мигрируется' {
            Set-Content -LiteralPath $script:LegacyPath -Value $script:V2Legacy -Encoding utf8NoBOM
            Set-Content -LiteralPath $script:CfgPath -Value '{"version":3,"paths":{"repos_root":"Q"}}' -Encoding utf8NoBOM
            (& $m { Get-EdtWtConfig }).paths.repos_root | Should -Be 'Q'
            Test-Path "$script:CfgPath.v2.bak" | Should -BeFalse
        }
    }
}
