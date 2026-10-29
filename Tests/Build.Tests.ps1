BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:RepoRoot = Get-EdtWtTestRepoRoot
    $script:Build = Join-Path $script:RepoRoot 'scripts\build.ps1'
    $script:Root = New-EdtWtTestRoot
    $script:Result = & $script:Build -OutputDir (Join-Path $script:Root 'out')
}

AfterAll {
    if ($script:Root -and (Test-Path -LiteralPath $script:Root)) {
        Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Сборка модуля' {
    It 'собирает модуль, zip и установщик' {
        Test-Path -LiteralPath $script:Result.ModuleDir | Should -BeTrue
        Test-Path -LiteralPath $script:Result.ZipPath | Should -BeTrue
        Test-Path -LiteralPath $script:Result.InstallerPath | Should -BeTrue
        $script:Result.ReleaseNotesPath | Should -BeNullOrEmpty
        $ps1 = @(Get-ChildItem -LiteralPath $script:Result.ModuleDir -Recurse -File |
            Where-Object { $_.Extension -eq '.ps1' } |
            ForEach-Object { $_.FullName.Substring($script:Result.ModuleDir.Length).TrimStart('\') })
        $ps1 | Should -Be @('bin\edt.ps1')
        Test-Path -LiteralPath (Join-Path $script:Result.ModuleDir 'Public') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Result.ModuleDir 'Private') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Result.ModuleDir 'EdtWorktree.format.ps1xml') | Should -BeTrue
    }

    It 'psm1 выпуска с BOM и содержит все функции src' {
        $psm1 = Join-Path $script:Result.ModuleDir 'EdtWorktree.psm1'
        $bytes = [IO.File]::ReadAllBytes($psm1)
        ($bytes[0..2] -join ',') | Should -Be '239,187,191'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($psm1, [ref]$null, [ref]$null)
        $funcs = @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })
        $srcCount = 0
        foreach ($d in 'Public', 'Private', 'Completers') {
            $srcCount += @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot "src\EdtWorktree\$d") -Recurse -File -Filter *.ps1).Count
        }
        $funcs.Count | Should -Be $srcCount
    }

    It 'файл без завершающего перевода строки не склеивается со следующим' {
        $src = Join-Path $script:Root 'srccopy'
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'src\EdtWorktree') -Destination $src -Recurse
        $victim = Get-ChildItem -LiteralPath (Join-Path $src 'Private') -Recurse -File -Filter *.ps1 | Sort-Object FullName | Select-Object -First 1
        $text = [IO.File]::ReadAllText($victim.FullName).TrimEnd("`r", "`n")
        [IO.File]::WriteAllText($victim.FullName, $text, [Text.UTF8Encoding]::new($true))
        $r = & $script:Build -OutputDir (Join-Path $script:Root 'out2') -SourceDir $src
        $names = & pwsh -NoProfile -Command "`$env:EDT_CONFIG_PATH = Join-Path ([IO.Path]::GetTempPath()) 'nocfg.json'; Import-Module '$($r.ModuleDir)\EdtWorktree.psd1' -Force; (Get-Command -Module EdtWorktree).Count"
        [int]$names | Should -BeGreaterThan 10
    }

    It 'zip распаковывается в EdtWorktree/{версия}' {
        $dest = Join-Path $script:Root 'unzip'
        Expand-Archive -LiteralPath $script:Result.ZipPath -DestinationPath $dest
        Test-Path -LiteralPath (Join-Path $dest "EdtWorktree\$($script:Result.Version)\EdtWorktree.psd1") | Should -BeTrue
    }

    It '-Release без раздела CHANGELOG падает' {
        $cl = Join-Path $script:Root 'CHANGELOG.md'
        Set-Content -LiteralPath $cl -Value "# Changelog`n`n## [Unreleased]`n"
        { & $script:Build -OutputDir (Join-Path $script:Root 'out3') -ChangelogPath $cl -Release } | Should -Throw '*нет раздела*'
    }

    It '-Release записывает тело раздела в release-notes.md' {
        $cl = Join-Path $script:Root 'CHANGELOG2.md'
        $v = $script:Result.Version
        Set-Content -LiteralPath $cl -Value "# Changelog`n`n## [Unreleased]`n`n## [$v] - 2026-01-01`n`n- первая строка`n`n## [0.0.1]`n- старое`n"
        $r = & $script:Build -OutputDir (Join-Path $script:Root 'out4') -ChangelogPath $cl -Release
        $notes = Get-Content -LiteralPath $r.ReleaseNotesPath -Raw
        $notes | Should -Match 'первая строка'
        $notes | Should -Not -Match 'старое'
    }
}
