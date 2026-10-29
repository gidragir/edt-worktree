BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:RepoRoot = Get-EdtWtTestRepoRoot
    $script:Readme = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Raw
    $script:Commands = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'docs\COMMANDS.md') -Raw
}

Describe 'Документация' {
    It 'README не ссылается на dotfiles автора' {
        $script:Readme | Should -Not -Match '~/.config/bin|_Variables\.ps1|conf\.d|nushell/custom'
    }

    It 'COMMANDS.md не ссылается на dotfiles автора' {
        $script:Commands | Should -Not -Match '\.config\\bin|\.config/bin|conf\.d'
    }

    It 'README содержит команды установки и раздел обновления с 3.0' {
        $script:Readme | Should -Match ([regex]::Escape('Install-PSResource EdtWorktree'))
        $script:Readme | Should -Match ([regex]::Escape('irm https://github.com/gidragir/edt-worktree/releases/latest/download/install.ps1 | iex'))
        $script:Readme | Should -Match ([regex]::Escape('edt setup'))
        $script:Readme | Should -Match 'Обновление с 3\.0'
        $script:Readme | Should -Not -Match ([regex]::Escape('raw.githubusercontent.com/gidragir/edt-worktree/main/install.ps1'))
        $script:Readme | Should -Not -Match ([regex]::Escape('raw.githubusercontent.com/gidragir/edt-worktree/main/scripts/install.ps1'))
    }

    It 'документы не описывают установку клоном 3.0' {
        $script:Readme | Should -Not -Match 'InstallDir|EDT_INSTALL_DIR'
        $script:Commands | Should -Not -Match 'InstallDir|EDT_INSTALL_DIR|LOCALAPPDATA\\EdtWorktree\\src'
    }

    It 'release.yml публикует в Gallery и создаёт Release' {
        $wf = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/release.yml') -Raw
        $wf | Should -Match 'Publish-PSResource'
        $wf | Should -Match 'secrets\.PSGALLERY_API_KEY'
        $wf | Should -Match 'build\.ps1 -Release'
        $wf | Should -Match 'GITHUB_REF_NAME'
        $wf | Should -Match 'ModuleVersion'
        $wf.LastIndexOf('Publish-PSResource') | Should -BeLessThan $wf.IndexOf('gh release create')
    }

    It 'release.yml публикует из каталога EdtWorktree после Test-ModuleManifest, ключ через env' {
        $wf = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/release.yml') -Raw
        $wf | Should -Match 'Join-Path \$env:RUNNER_TEMP ''EdtWorktree'''
        $wf | Should -Match 'Test-ModuleManifest'
        $wf.IndexOf('Test-ModuleManifest') | Should -BeLessThan $wf.LastIndexOf('Publish-PSResource -Path $stage')
        $wf | Should -Match 'PSGALLERY_API_KEY: \$\{\{ secrets\.PSGALLERY_API_KEY \}\}'
        $wf | Should -Match '-ApiKey \$env:PSGALLERY_API_KEY'
        $wf | Should -Match "EDT_INSTALL_NOSETUP = '1'"
    }

    It 'CHANGELOG содержит раздел 4.0.0' {
        Get-Content -LiteralPath (Join-Path $script:RepoRoot 'CHANGELOG.md') -Raw | Should -Match '## \[4\.0\.0\]'
    }

    It 'README описывает ручную установку из ZIP с Unblock-File' {
        $script:Readme | Should -Match 'Unblock-File'
    }

    It 'все подкоманды описаны в README и COMMANDS.md' -ForEach @(
        'setup', 'project', 'config', 'doctor', 'warmup', 'open', 'add', 'remove', 'status', 'update', 'vr', 'self-update', 'uninstall'
    ) {
        $script:Readme | Should -Match "edt $_"
        $script:Commands | Should -Match "edt $_"
    }

    It 'документы не упоминают удалённые ключи и команды 2.x' -ForEach @(
        '-GuiMaxHeap', '-MaxHeap', '-Validate', 'edt init', 'edt config init', 'wt-open', 'Initialize-EdtConfig', 'New-EdtProjectConfig', '.edt-worktree.json'
    ) {
        $script:Readme | Should -Not -Match ([regex]::Escape($_))
        $script:Commands | Should -Not -Match ([regex]::Escape($_))
    }

    It '.gitattributes фиксирует CRLF для .cmd' {
        Get-Content -LiteralPath (Join-Path $script:RepoRoot '.gitattributes') -Raw | Should -Match '\*\.cmd\s+text\s+eol=crlf'
    }

    It 'CI прогоняет проверки над src и out, сборку и установку из zip' {
        $wf = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/checks.yml') -Raw
        $wf | Should -Match 'windows-latest'
        $wf | Should -Match 'scripts/Invoke-EdtWtChecks\.ps1'
        $wf | Should -Match 'scripts/build\.ps1'
        $wf | Should -Match '-ModulePath\s+"?out/EdtWorktree/'
        $wf | Should -Match 'scripts/install\.ps1 -ZipPath out/EdtWorktree\.zip'
    }
}
