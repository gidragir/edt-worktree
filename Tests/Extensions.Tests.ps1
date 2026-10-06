BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\EdtWorktree.psd1') -Force

    $script:Ctx = [PSCustomObject]@{
        ProjectId        = 'test-proj'
        WorktreePath     = 'D:\projects\worktree\test-proj\feature-X'
        ReferenceBranch  = 'pre-prod'
        ActiveExtensions = @('cfe', 'cfe_mp', 'cfe_pos')
    }

    $script:Resolve = {
        param($Extensions)
        & (Get-Module EdtWorktree) {
            param($c, $e) Resolve-EdtWtExtensionList -Context $c -Extensions $e
        } $script:Ctx $Extensions
    }
}

Describe 'Resolve-EdtWtExtensionList' {
    It 'без аргумента возвращает все активные расширения' {
        # Регрессия: раньше по умолчанию работал режим changed и в IDE
        # открывалась одна конфигурация без единого расширения.
        (& $script:Resolve $null) | Should -Be @('cfe', 'cfe_mp', 'cfe_pos')
    }

    It "'all' возвращает все активные расширения" {
        (& $script:Resolve @('all')) | Should -Be @('cfe', 'cfe_mp', 'cfe_pos')
    }

    It "'none' возвращает пустой список" {
        # @() обязателен: под Set-StrictMode обращение к .Count пустого
        # результата - ошибка, а не 0.
        @(& $script:Resolve @('none')).Count | Should -Be 0
    }

    It 'режим нечувствителен к регистру' {
        (& $script:Resolve @('ALL')) | Should -Be @('cfe', 'cfe_mp', 'cfe_pos')
    }

    It 'явный список возвращается как есть' {
        (& $script:Resolve @('cfe', 'cfe_pos')) | Should -Be @('cfe', 'cfe_pos')
    }

    It 'предупреждает об имени, которого нет в active_extensions' {
        $warnings = @(& $script:Resolve @('chagned') 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $warnings.Count | Should -BeGreaterThan 0
    }
}

Describe 'Get-EdtWtChangedExtensions' {
    BeforeAll {
        # Функция выполняет Push-Location в каталог worktree, поэтому нужен
        # существующий путь; сам git подменяется моком.
        $script:TempWt = Join-Path ([System.IO.Path]::GetTempPath()) ("wt_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:TempWt | Out-Null
        $script:GitCtx = [PSCustomObject]@{
            ProjectId        = 'test-proj'
            WorktreePath     = $script:TempWt
            ReferenceBranch  = 'pre-prod'
            ActiveExtensions = @('cfe', 'cfe_mp', 'cfe_pos')
        }
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:TempWt) { Remove-Item -LiteralPath $script:TempWt -Recurse -Force }
    }

    It 'отбирает из изменённых файлов только активные расширения' {
        # git подменяется: проверяется отбор, а не работа git.
        Mock -ModuleName EdtWorktree -CommandName git -MockWith {
            if ($args -contains 'status') {
                return @(' M src/cfe_mp/src/Configuration.mdo', ' M src/cfe_legacy/src/x.bsl')
            }
            return @('src/cfe/src/y.bsl', 'src/cf/src/z.bsl')
        }

        $r = & (Get-Module EdtWorktree) {
            param($c) Get-EdtWtChangedExtensions -Context $c
        } $script:GitCtx

        $r | Should -Contain 'cfe_mp'
        $r | Should -Contain 'cfe'
        $r | Should -Not -Contain 'cfe_legacy'   # нет в active_extensions
        $r | Should -Not -Contain 'cf'           # конфигурация, не расширение
    }
}
