BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
}

AfterAll {
    Exit-EdtWtTestConfig -State $script:TestCfg
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\EdtWorktree.psd1') -Force

    # Файл .location Eclipse: 16 байт заголовка, writeUTF (2 байта длины + UTF-8),
    # затем неизменяемый хвост. Хвост в тестах проверяется побайтово: именно его
    # повреждение делает рабочую область нечитаемой для IDE.
    function New-TestLocationFile {
        # Тестовая фикстура во временном каталоге.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
        param([string]$Path, [string]$Uri)

        $head = [byte[]](1..16)
        $tail = [byte[]](40, 41, 42, 43)
        $body = [System.Text.Encoding]::UTF8.GetBytes($Uri)
        $hi = [byte](($body.Length -shr 8) -band 0xFF)
        $lo = [byte]($body.Length -band 0xFF)
        $len = [byte[]]@($hi, $lo)

        $bytes = [byte[]]($head + $len + $body + $tail)
        [System.IO.File]::WriteAllBytes($Path, $bytes)
        return $tail
    }

    $script:InModule = {
        param($ScriptBlock, $Arguments)
        & (Get-Module EdtWorktree) $ScriptBlock @Arguments
    }
}

Describe 'Чтение и перезапись .location' {
    BeforeEach {
        $script:File = Join-Path ([System.IO.Path]::GetTempPath()) ("loc_" + [guid]::NewGuid().ToString('N') + ".bin")
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:File) { Remove-Item -LiteralPath $script:File -Force }
    }

    It 'читает записанный URI' {
        $uri = 'URI//file:/D:/projects/worktree/proj/feature-X/src/cf'
        New-TestLocationFile -Path $script:File -Uri $uri | Out-Null

        $parsed = & (Get-Module EdtWorktree) { param($f) Get-EdtWtLocationUri -LocationFile $f } $script:File
        $parsed.Value | Should -Be $uri
        $parsed.Offset | Should -Be 18
    }

    It 'сохраняет заголовок и хвост при замене пути' {
        $old = 'URI//file:/D:/projects/worktree/proj/pre-prod/src/cf'
        $new = 'URI//file:/D:/projects/worktree/proj/feature-TASK-123/src/cf'
        $tail = New-TestLocationFile -Path $script:File -Uri $old

        $parsed = & (Get-Module EdtWorktree) { param($f) Get-EdtWtLocationUri -LocationFile $f } $script:File
        & (Get-Module EdtWorktree) { param($f, $p, $v) Set-EdtWtLocationUri -LocationFile $f -Parsed $p -NewValue $v } $script:File $parsed $new

        $bytes = [System.IO.File]::ReadAllBytes($script:File)
        $bytes[0..15] | Should -Be @(1..16)
        $bytes[($bytes.Length - 4)..($bytes.Length - 1)] | Should -Be $tail

        $again = & (Get-Module EdtWorktree) { param($f) Get-EdtWtLocationUri -LocationFile $f } $script:File
        $again.Value | Should -Be $new
    }

    It 'корректно пишет длину при удлинении пути' {
        # Длина хранится двумя байтами: ошибка старшего байта проявляется только
        # на путях длиннее 255 символов.
        $old = 'URI//file:/D:/x'
        $new = 'URI//file:/D:/' + ('a' * 300)
        New-TestLocationFile -Path $script:File -Uri $old | Out-Null

        $parsed = & (Get-Module EdtWorktree) { param($f) Get-EdtWtLocationUri -LocationFile $f } $script:File
        & (Get-Module EdtWorktree) { param($f, $p, $v) Set-EdtWtLocationUri -LocationFile $f -Parsed $p -NewValue $v } $script:File $parsed $new

        $again = & (Get-Module EdtWorktree) { param($f) Get-EdtWtLocationUri -LocationFile $f } $script:File
        $again.Value | Should -Be $new
        $again.Length | Should -Be $new.Length
    }

    It 'возвращает $null на слишком коротком файле' {
        [System.IO.File]::WriteAllBytes($script:File, [byte[]](1, 2, 3))
        $parsed = & (Get-Module EdtWorktree) { param($f) Get-EdtWtLocationUri -LocationFile $f } $script:File
        $parsed | Should -BeNullOrEmpty
    }

    It 'экранирует пробелы и сохраняет кириллицу в ConvertTo-EdtWtEclipseLocationUri' {
        $path = 'D:\projects\worktree\Интеграция с Каспи\ka-intertop-4edt-INITKZ-2126\src\cf'
        $expected = 'URI//file:/D:/projects/worktree/Интеграция%20с%20Каспи/ka-intertop-4edt-INITKZ-2126/src/cf'
        $actual = & (Get-Module EdtWorktree) { param($p) ConvertTo-EdtWtEclipseLocationUri -Path $p } $path
        $actual | Should -Be $expected
    }

    It 'декодирует URI с экранированными пробелами и кириллицей в ConvertFrom-EdtWtEclipseLocationUri' {
        $uri = 'URI//file:/D:/projects/worktree/Интеграция%20с%20Каспи/ka-intertop-4edt-INITKZ-2126/src/cf'
        $expected = 'D:\projects\worktree\Интеграция с Каспи\ka-intertop-4edt-INITKZ-2126\src\cf'
        $actual = & (Get-Module EdtWorktree) { param($u) ConvertFrom-EdtWtEclipseLocationUri -UriValue $u } $uri
        $actual | Should -Be $expected
    }

    It 'декодирует URI с percent-encoded кириллицей в ConvertFrom-EdtWtEclipseLocationUri' {
        $uri = 'URI//file:/D:/projects/worktree/%D0%98%D0%BD%D1%82%D0%B5%D0%B3%D1%80%D0%B0%D1%86%D0%B8%D1%8F%20%D1%81%20%D0%9A%D0%B0%D1%81%D0%BF%D0%B8/src/cf'
        $expected = 'D:\projects\worktree\Интеграция с Каспи\src\cf'
        $actual = & (Get-Module EdtWorktree) { param($u) ConvertFrom-EdtWtEclipseLocationUri -UriValue $u } $uri
        $actual | Should -Be $expected
    }

    It 'исправляет неэкранированные пробелы в .location через Repair-EdtWtWorkspaceLocations' {
        $tempWs = Join-Path ([System.IO.Path]::GetTempPath()) ('ws_' + [guid]::NewGuid().ToString('N'))
        $tempWt = Join-Path ([System.IO.Path]::GetTempPath()) ('wt_' + [guid]::NewGuid().ToString('N') + '\Интеграция с Каспи\ka-intertop')
        $refWs = Join-Path ([System.IO.Path]::GetTempPath()) ('ref_' + [guid]::NewGuid().ToString('N'))

        $projDir = Join-Path $tempWs '.metadata\.plugins\org.eclipse.core.resources\.projects\cf'
        $wtCfDir = Join-Path $tempWt 'src\cf'
        New-Item -ItemType Directory -Path $projDir -Force | Out-Null
        New-Item -ItemType Directory -Path $wtCfDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $wtCfDir '.project') -Force | Out-Null

        $locFile = Join-Path $projDir '.location'
        # Записываем старый сломанный URI с сырыми пробелами
        $brokenUri = "URI//file:/$($wtCfDir -replace '\\', '/')"
        New-TestLocationFile -Path $locFile -Uri $brokenUri | Out-Null

        try {
            $repaired = & (Get-Module EdtWorktree) {
                param($ws, $wt, $ref)
                Repair-EdtWtWorkspaceLocations -WorkspaceDir $ws -WorktreePath $wt -ReferenceWsDir $ref
            } $tempWs $tempWt $refWs

            $repaired | Should -Contain 'cf'

            $parsed = & (Get-Module EdtWorktree) { param($f) Get-EdtWtLocationUri -LocationFile $f } $locFile
            $parsed.Value | Should -Not -Match ' '
            $parsed.Value | Should -Match '%20'
        } finally {
            Remove-Item -LiteralPath $tempWs -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Split-Path (Split-Path $tempWt)) -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
