BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
    $script:ModulePath = Get-EdtWtTestModulePath
    Import-Module $script:ModulePath -Force
    $script:m = Get-Module EdtWorktree
}

AfterAll {
    Exit-EdtWtTestConfig -State $script:TestCfg
}

Describe 'Get-EdtWtDataArgument' {
    It 'разбирает -data в кавычках и без' -ForEach @(
        @{ C = '"C:\EDT\1cedt.exe" -data "D:\ws\p\feature-T-1" -vmargs -Xmx8g'; E = 'D:\ws\p\feature-T-1' },
        @{ C = '1cedtcli.exe -data D:\ws\p\x -timeout 7200'; E = 'D:\ws\p\x' },
        @{ C = '"C:\Program Files\EDT\1cedt.exe" -data "D:\ws\с пробелом\x"'; E = 'D:\ws\с пробелом\x' }
    ) {
        & $m { param($c) Get-EdtWtDataArgument -CommandLine $c } $C | Should -Be $E
    }

    It 'возвращает $null, если -data нет' {
        & $m { Get-EdtWtDataArgument -CommandLine 'java.exe -jar x.jar' } | Should -BeNullOrEmpty
    }
}

Describe 'Get-EdtWtWorkspaceProcesses' {
    It 'feature-T-1 не захватывает процесс feature-T-10' {
        Mock -ModuleName EdtWorktree Get-CimInstance {
            [pscustomobject]@{ Name = '1cedt.exe'; ProcessId = 1; CommandLine = '1cedt.exe -data "D:\ws\p\feature-T-10"' }
        }
        @(& $m { Get-EdtWtWorkspaceProcesses -WorkspaceDir 'D:\ws\p\feature-T-1' }).Count | Should -Be 0
        @(& $m { Get-EdtWtWorkspaceProcesses -WorkspaceDir 'd:\WS\p\feature-T-10\' }).Count | Should -Be 1
    }
}

Describe 'Invoke-EdtWtCli' {
    It 'большой stderr не вешает Invoke-EdtWtCli' {
        $root = New-EdtWtTestRoot
        try {
            $cli = Join-Path $root 'fakecli.cmd'
            $body = @(
                '@echo off'
                'for /L %%i in (1,1,5000) do echo error line %%i xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx 1>&2'
                'for /L %%i in (1,1,10) do echo out line %%i'
                'exit /b 0'
            )
            Set-Content -LiteralPath $cli -Value $body -Encoding ASCII
            $ws = Join-Path $root 'ws'

            $mod = $script:ModulePath
            $cfgRoot = $script:TestCfg.Root
            $job = Start-ThreadJob -ScriptBlock {
                $env:EDT_CONFIG_PATH = Join-Path $using:cfgRoot 'config.json'
                $env:EDT_LEGACY_CONFIG_PATH = Join-Path $using:cfgRoot 'legacy-projects.json'
                Import-Module $using:mod -Force
                $ctx = [pscustomobject]@{ EdtCliPath = $using:cli; JvmArgs = '-Xmx2g'; TimeoutSec = 60 }
                & (Get-Module EdtWorktree) {
                    param($c, $w) Invoke-EdtWtCli -Context $c -WorkspaceDir $w -Commands @('version') -MaxHeap '2g'
                } $ctx $using:ws
                'finished'
            }
            try {
                $done = $job | Wait-Job -Timeout 60
                $done | Should -Not -BeNullOrEmpty
                ($job | Receive-Job) | Should -Contain 'finished'
            } finally {
                # Зависший поток не останавливаем (Stop-Job блокируется на нативном чтении).
                if ($job.State -eq 'Completed') { $job | Remove-Job -Force -ErrorAction SilentlyContinue }
            }
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'сбой без вывода: в ошибке код, время работы и пометка о пустом выводе' {
        $root = New-EdtWtTestRoot
        try {
            $cli = Join-Path $root 'fakecli.cmd'
            Set-Content -LiteralPath $cli -Value @('@echo off', 'exit /b 14') -Encoding ASCII
            $ctx = [pscustomobject]@{ EdtCliPath = $cli; JvmArgs = '-Xmx2g'; TimeoutSec = 60 }
            $out = & {
                try {
                    & (Get-Module EdtWorktree) {
                        param($c, $w) Invoke-EdtWtCli -Context $c -WorkspaceDir $w -Commands @('version') -MaxHeap '2g'
                    } $ctx (Join-Path $root 'ws') 6>&1
                } catch { $_.Exception.Message }
            } | Out-String
            $out | Should -Match 'ExitCode 14'
            $out | Should -Match 'через \d+ с'
            $out | Should -Match 'вывод пуст'
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'JDK из Resolve-EdtWtGuiJvm первая в PATH и в JAVA_HOME процесса 1cedtcli' {
        # 1cedtcli не принимает -vm, а лончер без него берёт первый javaw из PATH
        # (шим mise, Oracle java8path) или Java 8 из реестра.
        $root = New-EdtWtTestRoot
        try {
            $cli = Join-Path $root 'fakecli.cmd'
            Set-Content -LiteralPath $cli -Value @('@echo off', 'echo PATH=%PATH%', 'echo JH=%JAVA_HOME%') -Encoding ASCII
            $jdk = Join-Path $root 'jdk 17'
            Mock -ModuleName EdtWorktree Resolve-EdtWtGuiJvm { [pscustomobject]@{ Path = "$jdk\bin\server\jvm.dll"; Reason = 'scan' } }.GetNewClosure()
            $ctx = [pscustomobject]@{ EdtCliPath = $cli; JvmArgs = '-Xmx2g'; TimeoutSec = 60 }
            $out = & (Get-Module EdtWorktree) {
                param($c, $w) Invoke-EdtWtCli -Context $c -WorkspaceDir $w -Commands @('version') -MaxHeap '2g'
            } $ctx (Join-Path $root 'ws') 6>&1 | Out-String
            $out | Should -Match ([regex]::Escape("PATH=$jdk\bin;"))
            $out | Should -Match ([regex]::Escape("JH=$jdk"))
            $env:PATH | Should -Not -Match ([regex]::Escape("$jdk\bin"))
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
