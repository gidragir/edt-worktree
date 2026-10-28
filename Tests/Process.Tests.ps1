BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
    $script:ModulePath = Join-Path $PSScriptRoot '..\EdtWorktree.psd1'
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
}
