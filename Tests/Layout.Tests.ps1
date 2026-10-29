BeforeDiscovery {
    $script:SrcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\EdtWorktree'
    $script:Files = foreach ($dir in 'Public', 'Private', 'Completers') {
        $d = Join-Path $script:SrcRoot $dir
        if (Test-Path -LiteralPath $d) {
            Get-ChildItem -LiteralPath $d -Recurse -File -Filter *.ps1 |
                ForEach-Object { @{ Path = $_.FullName; Name = $_.Name; BaseName = $_.BaseName } }
        }
    }
}

BeforeAll {
    $script:SrcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\EdtWorktree'
}

Describe 'Раскладка модуля: одна функция - один файл' {
    It 'в файле <Name> ровно одна функция верхнего уровня, имя = имя файла' -ForEach $script:Files -Skip:([bool]$env:EDT_TEST_MODULE) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $funcs = @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })
        $funcs.Count | Should -Be 1
        $funcs[0].Name | Should -Be $BaseName
    }

    It 'вне функции в <Name> нет кода' -ForEach $script:Files -Skip:([bool]$env:EDT_TEST_MODULE) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $other = @($ast.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] })
        $other.Count | Should -Be 0
    }

    It 'FunctionsToExport совпадает с файлами Public/' -Skip:([bool]$env:EDT_TEST_MODULE) {
        $exported = (Import-PowerShellDataFile (Join-Path $script:SrcRoot 'EdtWorktree.psd1')).FunctionsToExport | Sort-Object
        $public = (Get-ChildItem (Join-Path $script:SrcRoot 'Public') -Filter *.ps1).BaseName | Sort-Object
        $public | Should -Be $exported
    }

    It 'Set-StrictMode только в EdtWorktree.psm1' -Skip:([bool]$env:EDT_TEST_MODULE) {
        $hits = foreach ($dir in 'Public', 'Private', 'Completers') {
            Get-ChildItem (Join-Path $script:SrcRoot $dir) -Recurse -File -Filter *.ps1 |
                Select-String -Pattern 'Set-StrictMode'
        }
        @($hits).Count | Should -Be 0
    }
}

Describe 'Манифест' {
    It 'манифест готов к публикации' -Skip:([bool]$env:EDT_TEST_MODULE) {
        $psd1 = Join-Path $script:SrcRoot 'EdtWorktree.psd1'
        { Test-ModuleManifest -Path $psd1 -ErrorAction Stop | Out-Null } | Should -Not -Throw
        $m = Import-PowerShellDataFile $psd1
        $m.CompatiblePSEditions | Should -Be @('Core')
        $m.PrivateData.PSData.ProjectUri | Should -Be 'https://github.com/gidragir/edt-worktree'
        $m.PrivateData.PSData.LicenseUri | Should -Be 'https://github.com/gidragir/edt-worktree/blob/main/LICENSE'
        $m.PrivateData.PSData.ReleaseNotes | Should -Match 'CHANGELOG.md'
        $m.PrivateData.PSData.Tags | Should -Contain 'Windows'
        $m.PrivateData.PSData.Tags | Should -Contain 'PSEdition_Core'
        Test-Path -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'LICENSE') | Should -BeTrue
    }
}