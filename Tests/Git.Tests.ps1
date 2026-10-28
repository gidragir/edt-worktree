BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
}

AfterAll {
    Exit-EdtWtTestConfig -State $script:TestCfg
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\EdtWorktree.psd1') -Force
}

Describe 'Invoke-EdtWtGit и кодировка вывода Git' {
    BeforeAll {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('git_test_' + [guid]::NewGuid().ToString('N') + '\Интеграция с Каспи\retail-test')
        New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
        Push-Location -LiteralPath $script:TempDir
        try {
            git init -q
            git config user.email "test@test.com"
            git config user.name "Test"
            git checkout -q -b "feature/тестовая-ветка" 2>$null
            git commit --allow-empty -m "init" -q
        } finally {
            Pop-Location
        }
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:TempDir) {
            # Удаляем корневую временную папку
            $root = Split-Path (Split-Path $script:TempDir)
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-EdtWtGit возвращает путь с кириллицей без искажения кодировки' {
        Push-Location -LiteralPath $script:TempDir
        try {
            $topLevel = & (Get-Module EdtWorktree) {
                Invoke-EdtWtGit rev-parse --show-toplevel 2>$null
            }
            $topLevel | Should -Not -BeNullOrEmpty
            # Проверяем, что в строке нет кракозябр от CP866 (байты D0 98 как ╨Ш)
            $topLevel | Should -Not -Match '╨'
            $topLevel | Should -Match 'Интеграция с Каспи'
        } finally {
            Pop-Location
        }
    }

    It 'Invoke-EdtWtGit возвращает имя ветки с кириллицей без искажения' {
        Push-Location -LiteralPath $script:TempDir
        try {
            $branch = & (Get-Module EdtWorktree) {
                Invoke-EdtWtGit rev-parse --abbrev-ref HEAD 2>$null
            }
            $branch | Should -Be 'feature/тестовая-ветка'
        } finally {
            Pop-Location
        }
    }

    It 'Invoke-EdtWtGit корректно сохраняет LASTEXITCODE при ошибке' {
        & (Get-Module EdtWorktree) {
            Invoke-EdtWtGit show-ref --verify --quiet "refs/heads/nonexistent_test_branch"
        }
        $LASTEXITCODE | Should -Be 1
    }
}
