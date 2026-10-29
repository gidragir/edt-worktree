BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
}

AfterAll {
    Exit-EdtWtTestConfig -State $script:TestCfg
}

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

    It 'gui_max_heap в мегабайтах не превращается в гигабайты' {
        $r = & (Get-Module EdtWorktree) {
            param($c, $h) Resolve-EdtWtGuiVmArgs -Context $c -MaxHeap $h
        } $script:Ctx '12288M'

        $r.MaxHeapGb | Should -Be 12
        $r.Args | Should -Contain '-Xmx12g'
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

    It 'куча в мегабайтах переводится в гигабайты, а не читается как гигабайты' {
        $r = & (Get-Module EdtWorktree) {
            param($a, $h) Resolve-EdtWtJvmArgs -JvmArgs $a -MaxHeap $h
        } '-Xmx16g' '8192m'

        $r.MaxHeapGb | Should -Be 8
        $r.Args | Should -BeLike '*-Xmx8g*'
    }

    It 'держит -Xms не больше четверти кучи' {
        $r = & (Get-Module EdtWorktree) {
            param($a, $h) Resolve-EdtWtJvmArgs -JvmArgs $a -MaxHeap $h
        } '-Xmx16g -Xms4g' '8g'

        $r.MinHeapGb | Should -BeLessOrEqual 2
    }
}

Describe 'Resolve-EdtWtJvmArgs: авто-куча' {
    It 'без -Xmx в аргументах и без MaxHeap подставляет кучу по свободной памяти' {
        $r = & (Get-Module EdtWorktree) {
            param($a) Resolve-EdtWtJvmArgs -JvmArgs $a
        } '-Xms2g -XX:+UseG1GC'

        $r.Args | Should -Match '-Xmx\d+g'
        $r.MaxHeapGb | Should -BeGreaterOrEqual 2
        $r.Args | Should -BeLike '*-XX:+UseG1GC*'
    }
}

Describe 'JVM для GUI' {
    BeforeAll {
        function New-FakeJdk {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
            param([string]$Dir, [string]$Version = '17.0.9', [switch]$NoFx)
            New-Item -ItemType Directory -Path (Join-Path $Dir 'bin\server') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $Dir 'bin\server\jvm.dll') -Value 'stub'
            Set-Content -LiteralPath (Join-Path $Dir 'release') -Value "JAVA_VERSION=`"$Version`""
            if (-not $NoFx) {
                New-Item -ItemType Directory -Path (Join-Path $Dir 'jmods') -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $Dir 'jmods\javafx.base.jmod') -Value 'stub'
            }
            return $Dir
        }
    }

    BeforeEach {
        $script:PrevJavaHome = $env:JAVA_HOME
        $script:Root = Join-Path ([System.IO.Path]::GetTempPath()) ('edtjvm_' + [guid]::NewGuid().ToString('N'))
        $script:Edt = Join-Path $script:Root 'edt dir'
        New-Item -ItemType Directory -Path $script:Edt -Force | Out-Null
        $script:Gui = Join-Path $script:Edt '1cedt.exe'
        Set-Content -LiteralPath $script:Gui -Value 'stub'
        Set-Content -LiteralPath (Join-Path $script:Edt '1cedt.ini') -Value @('-startup', 'x.jar', '-vmargs', '-Xmx4096m')
        $script:FxRoot = Join-Path $script:Root 'jdks'
        $script:JdkFx = New-FakeJdk -Dir (Join-Path $script:FxRoot 'zulu fx 17')
        $script:JdkNoFx = New-FakeJdk -Dir (Join-Path $script:Root 'nofx') -NoFx
        $script:Jdk11Fx = New-FakeJdk -Dir (Join-Path $script:Root 'jdk11') -Version '11.0.2'
        $script:Resolve = {
            param($gui, $vm, $roots)
            & (Get-Module EdtWorktree) {
                param($g, $v, $r)
                $p = @{ EdtGuiPath = $g; SearchRoots = $r }
                if ($v) { $p.VmPath = $v }
                Resolve-EdtWtGuiJvm @p
            } $gui $vm $roots
        }
    }

    AfterEach {
        $env:JAVA_HOME = $script:PrevJavaHome
        if (Test-Path -LiteralPath $script:Root) { Remove-Item -LiteralPath $script:Root -Recurse -Force }
    }

    It '-vm в 1cedt.ini побеждает JAVA_HOME' {
        Set-Content -LiteralPath (Join-Path $script:Edt '1cedt.ini') -Value @('-vm', 'jre/bin/server/jvm.dll', '-vmargs', '-Xmx4096m')
        $env:JAVA_HOME = $script:JdkFx
        $r = & $script:Resolve $script:Gui $null @($script:FxRoot)
        $r.Reason | Should -Be 'ini'
        $r.Path | Should -BeNullOrEmpty
    }

    It 'JAVA_HOME с JavaFX используется, если в ini нет -vm' {
        $env:JAVA_HOME = $script:JdkFx
        $r = & $script:Resolve $script:Gui $null @()
        $r.Reason | Should -Be 'JAVA_HOME'
        $r.Path | Should -Be (Join-Path $script:JdkFx 'bin\server\jvm.dll')
    }

    It 'JAVA_HOME без JavaFX пропускается, берётся найденная JDK с JavaFX' {
        $env:JAVA_HOME = $script:JdkNoFx
        $r = & $script:Resolve $script:Gui $null @($script:FxRoot)
        $r.Reason | Should -Be 'scan'
        $r.Path | Should -Be (Join-Path $script:JdkFx 'bin\server\jvm.dll')
    }

    It 'из нескольких JDK выбирается самая новая по версии, а не по строке' {
        $env:JAVA_HOME = $null
        $roots = Join-Path $script:Root 'many'
        New-FakeJdk -Dir (Join-Path $roots 'zulu17.9-ca-fx') | Out-Null
        $newest = New-FakeJdk -Dir (Join-Path $roots 'zulu17.10-ca-fx')
        $r = & $script:Resolve $script:Gui $null @($roots)
        $r.Path | Should -Be (Join-Path $newest 'bin\server\jvm.dll')
    }

    It 'ничего не найдено: Reason none, Path пуст' {
        $env:JAVA_HOME = $script:JdkNoFx
        $r = & $script:Resolve $script:Gui $null @((Join-Path $script:Root 'пусто'))
        $r.Reason | Should -Be 'none'
        $r.Path | Should -BeNullOrEmpty
    }

    It 'Java 11 с JavaFX не подходит' {
        & (Get-Module EdtWorktree) { param($j) Test-EdtWtJdkHasJavaFx -JdkHome $j } $script:Jdk11Fx | Should -BeFalse
    }

    It 'JDK 17 с JavaFX подходит, без JavaFX нет' {
        & (Get-Module EdtWorktree) { param($j) Test-EdtWtJdkHasJavaFx -JdkHome $j } $script:JdkFx | Should -BeTrue
        & (Get-Module EdtWorktree) { param($j) Test-EdtWtJdkHasJavaFx -JdkHome $j } $script:JdkNoFx | Should -BeFalse
    }

    It 'edt.vm_path из конфига имеет приоритет (даже над -vm в ini)' {
        Set-Content -LiteralPath (Join-Path $script:Edt '1cedt.ini') -Value @('-vm', 'jre/bin/server/jvm.dll', '-vmargs', '-Xmx4096m')
        $env:JAVA_HOME = $script:JdkFx
        $r = & $script:Resolve $script:Gui $script:JdkFx @()
        $r.Reason | Should -Be 'config'
        $r.Path | Should -Be (Join-Path $script:JdkFx 'bin\server\jvm.dll')
    }

    Context 'Start-EdtWtGui' {
        BeforeEach {
            $script:Captured = $null
            $script:Ctx = [pscustomobject]@{
                EdtGuiPath   = $script:Gui
                WorkspaceDir = Join-Path $script:Root 'work space'
                VmPath       = $null
                GuiMaxHeap   = $null
            }
            $script:Start = { param($c) & (Get-Module EdtWorktree) { param($c) Start-EdtWtGui -Context $c } $c }
        }

        It '-vm и -data идут с кавычками, -vm раньше -data' {
            $env:JAVA_HOME = $script:JdkFx
            Mock -ModuleName EdtWorktree -CommandName Start-Process -MockWith { $script:Captured = $ArgumentList }
            & $script:Start $script:Ctx 6>$null
            Should -Invoke -ModuleName EdtWorktree -CommandName Start-Process -Times 1 -Exactly
            $vmIdx = [array]::IndexOf($script:Captured, '-vm')
            $dataIdx = [array]::IndexOf($script:Captured, '-data')
            $vmIdx | Should -BeGreaterOrEqual 0
            $dataIdx | Should -BeGreaterThan $vmIdx
            $script:Captured[$vmIdx + 1] | Should -Be ('"' + (Join-Path $script:JdkFx 'bin\server\jvm.dll') + '"')
            $script:Captured[$dataIdx + 1] | Should -Be ('"' + $script:Ctx.WorkspaceDir + '"')
        }

        It 'при -vm в ini параметр -vm не передаётся' {
            Set-Content -LiteralPath (Join-Path $script:Edt '1cedt.ini') -Value @('-vm', 'jre/bin/server/jvm.dll', '-vmargs', '-Xmx4096m')
            $env:JAVA_HOME = $script:JdkFx
            Mock -ModuleName EdtWorktree -CommandName Start-Process -MockWith { $script:Captured = $ArgumentList }
            & $script:Start $script:Ctx 6>$null
            $script:Captured | Should -Not -Contain '-vm'
            $script:Captured | Should -Contain '-data'
        }

        It 'куча из GuiMaxHeap контекста попадает в -vmargs' {
            $env:JAVA_HOME = $script:JdkFx
            $script:Ctx.GuiMaxHeap = '12g'
            Mock -ModuleName EdtWorktree -CommandName Start-Process -MockWith { $script:Captured = $ArgumentList }
            & $script:Start $script:Ctx 6>$null
            $script:Captured | Should -Contain '-Xmx12g'
        }

        It 'без подходящей JDK предупреждает и запускает без -vm' {
            Mock -ModuleName EdtWorktree -CommandName Resolve-EdtWtGuiJvm -MockWith { [pscustomobject]@{ Path = $null; Reason = 'none' } }
            Mock -ModuleName EdtWorktree -CommandName Start-Process -MockWith { $script:Captured = $ArgumentList }
            & $script:Start $script:Ctx 6>$null 3>&1 | Out-String | Should -Match 'JavaFX'
            $script:Captured | Should -Not -Contain '-vm'
        }

        It 'нет параметра -GuiMaxHeap' {
            $cmd = & (Get-Module EdtWorktree) { Get-Command Start-EdtWtGui }
            $cmd.Parameters.Keys | Should -Not -Contain 'GuiMaxHeap'
        }
    }
}

Describe 'Invoke-EdtWorktreeAdd: перезапуск IDE' {
    BeforeEach {
        $script:Ws = Join-Path ([System.IO.Path]::GetTempPath()) ('edtadd_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Ws -Force | Out-Null
    }
    AfterEach {
        if (Test-Path -LiteralPath $script:Ws) { Remove-Item -LiteralPath $script:Ws -Recurse -Force }
    }

    It 'перезапускает IDE через Start-EdtWtGui, а не Start-Process' {
        $script:AddCtx = [pscustomobject]@{ WorkspaceDir = $script:Ws; WorktreePath = $script:Ws; ProjectId = 'p'; WorktreeId = 'w'; ReferenceWsDir = $script:Ws; EdtGuiPath = 'x' }
        Mock -ModuleName EdtWorktree -CommandName Get-EdtWtContext -MockWith { $script:AddCtx }
        Mock -ModuleName EdtWorktree -CommandName Find-EdtWtEdtProjects -MockWith { @() }
        Mock -ModuleName EdtWorktree -CommandName Resolve-EdtWtExtensionRef -MockWith { 'cfe_a' }
        Mock -ModuleName EdtWorktree -CommandName Get-EdtWtImportTargets -MockWith { [pscustomobject]@{ Targets = @('C:\x\cfe_a') } }
        Mock -ModuleName EdtWorktree -CommandName Get-EdtWtWorkspaceProcesses -MockWith { @([pscustomobject]@{ ProcessId = 1 }) }
        Mock -ModuleName EdtWorktree -CommandName Stop-EdtWtProcesses -MockWith { 1 }
        Mock -ModuleName EdtWorktree -CommandName Repair-EdtWtWorkspaceLocations -MockWith { }
        Mock -ModuleName EdtWorktree -CommandName Invoke-EdtWtCli -MockWith { }
        Mock -ModuleName EdtWorktree -CommandName Start-EdtWtGui -MockWith { }
        Mock -ModuleName EdtWorktree -CommandName Start-Process -MockWith { }

        Invoke-EdtWorktreeAdd cfe_a -Force -Confirm:$false 6>$null

        Should -Invoke -ModuleName EdtWorktree -CommandName Start-EdtWtGui -Times 1 -Exactly
        Should -Invoke -ModuleName EdtWorktree -CommandName Start-Process -Times 0 -Exactly
    }
}
