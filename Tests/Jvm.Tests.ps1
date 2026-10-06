BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\EdtWorktree.psd1') -Force

    # Фикстура 1cedt.ini: важна именно структура - всё после -vmargs копируется
    # в командную строку целиком, потому что аргументы CLI заменяют секцию ini.
    $script:IniLines = @(
        '-startup'
        'plugins/org.eclipse.equinox.launcher.jar'
        '-vmargs'
        '-Dosgi.requiredJavaVersion=17'
        '--add-opens=java.base/java.lang=ALL-UNNAMED'
        '-XX:+UseG1GC'
        '-Xms80m'
        '-Xmx4096m'
    )

    function New-TestGuiLayout {
        # Тестовая фикстура во временном каталоге.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
        param([string]$Root)
        New-Item -ItemType Directory -Force -Path $Root | Out-Null
        Set-Content -LiteralPath (Join-Path $Root '1cedt.ini') -Value $script:IniLines -Encoding UTF8
        $gui = Join-Path $Root '1cedt.exe'
        Set-Content -LiteralPath $gui -Value 'stub' -Encoding UTF8
        return [PSCustomObject]@{ EdtGuiPath = $gui }
    }
}

Describe 'Resolve-EdtWtGuiVmArgs' {
    BeforeEach {
        $script:Root = Join-Path ([System.IO.Path]::GetTempPath()) ("edtgui_" + [guid]::NewGuid().ToString('N'))
        $script:Ctx = New-TestGuiLayout -Root $script:Root
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:Root) { Remove-Item -LiteralPath $script:Root -Recurse -Force }
    }

    It 'заменяет -Xmx на запрошенный и сохраняет остальные аргументы' {
        $r = & (Get-Module EdtWorktree) {
            param($c, $h) Resolve-EdtWtGuiVmArgs -Context $c -MaxHeap $h
        } $script:Ctx '12g'

        $r.MaxHeapGb | Should -Be 12
        $r.Args | Should -Contain '-Xmx12g'
        $r.Args | Should -Not -Contain '-Xmx4096m'
        # --add-opens критичен: без него IDE не стартует
        $r.Args | Should -Contain '--add-opens=java.base/java.lang=ALL-UNNAMED'
        $r.Args | Should -Contain '-XX:+UseG1GC'
        $r.Args | Should -Contain '-Xms80m'
    }

    It 'не включает в vmargs строки до секции -vmargs' {
        $r = & (Get-Module EdtWorktree) {
            param($c, $h) Resolve-EdtWtGuiVmArgs -Context $c -MaxHeap $h
        } $script:Ctx '8g'

        $r.Args | Should -Not -Contain '-startup'
        $r.Args | Should -Not -Contain '-vmargs'
    }

    It 'возвращает $null, если поднимать кучу не требуется' {
        # Меньше штатных 4 ГБ подставлять бессмысленно: остаётся значение из ini.
        $r = & (Get-Module EdtWorktree) {
            param($c, $h) Resolve-EdtWtGuiVmArgs -Context $c -MaxHeap $h
        } $script:Ctx '2g'

        $r | Should -BeNullOrEmpty
    }

    It 'возвращает $null, если 1cedt.ini отсутствует' {
        Remove-Item -LiteralPath (Join-Path $script:Root '1cedt.ini') -Force
        $r = & (Get-Module EdtWorktree) {
            param($c, $h) Resolve-EdtWtGuiVmArgs -Context $c -MaxHeap $h
        } $script:Ctx '12g'

        $r | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-EdtWtJvmArgs' {
    It 'подставляет запрошенную кучу для headless-процесса' {
        $r = & (Get-Module EdtWorktree) {
            param($a, $h) Resolve-EdtWtJvmArgs -JvmArgs $a -MaxHeap $h
        } '-Xmx16g -Xms4g -XX:+UseG1GC' '8g'

        $r.MaxHeapGb | Should -Be 8
        $r.Args | Should -BeLike '*-Xmx8g*'
        $r.Args | Should -BeLike '*-XX:+UseG1GC*'
    }

    It 'держит -Xms не больше четверти кучи' {
        $r = & (Get-Module EdtWorktree) {
            param($a, $h) Resolve-EdtWtJvmArgs -JvmArgs $a -MaxHeap $h
        } '-Xmx16g -Xms4g' '8g'

        $r.MinHeapGb | Should -BeLessOrEqual 2
    }
}
