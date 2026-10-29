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

    It 'README содержит команду установки' {
        $script:Readme | Should -Match ([regex]::Escape('irm https://raw.githubusercontent.com/gidragir/edt-worktree/main/scripts/install.ps1 | iex'))
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

    It 'CI прогоняет проверки и установщик' {
        $wf = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/checks.yml') -Raw
        $wf | Should -Match 'windows-latest'
        $wf | Should -Match 'scripts/Invoke-EdtWtChecks\.ps1'
        $wf | Should -Match 'scripts/install\.ps1'
    }
}
