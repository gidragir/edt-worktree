BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\EdtWorktree.psd1') -Force

    $script:NewBatch = { & (Get-Module EdtWorktree) { New-EdtWtBatch } }
}

Describe 'New-EdtWtBatch' {
    It 'новый батч пуст' {
        $b = & $script:NewBatch
        $b.IsEmpty() | Should -BeTrue
        @($b.ToArray()).Count | Should -Be 0
    }

    It 'формирует команду import с прямыми слэшами' {
        # 1cedtcli не принимает обратные слэши в путях.
        $b = & $script:NewBatch
        $b.AddImport('D:\projects\worktree\proj\feature-X\src\cf') | Out-Null

        $b.ToArray()[0] | Should -Be 'import --project "D:/projects/worktree/proj/feature-X/src/cf"'
        $b.IsEmpty() | Should -BeFalse
    }

    It 'формирует команду export с двумя путями' {
        $b = & $script:NewBatch
        $b.AddExport('D:\src\cf', 'D:\temp\xml_cf') | Out-Null

        $b.ToArray()[0] | Should -Be 'export --project "D:/src/cf" --configuration-files "D:/temp/xml_cf"'
    }

    It 'формирует команду validate со списком проектов' {
        $b = & $script:NewBatch
        $b.AddValidate(@('cf', 'cfe', 'cfe_mp'), 'D:\ws\result.tsv') | Out-Null

        $b.ToArray()[0] | Should -Be 'validate --project-name-list cf,cfe,cfe_mp --file "D:/ws/result.tsv"'
    }

    It 'сохраняет порядок команд' {
        # Импорт конфигурации обязан идти первым: расширения ссылаются на неё.
        $b = & $script:NewBatch
        $b.AddImport('D:\src\cf') | Out-Null
        $b.AddImport('D:\src\cfe') | Out-Null
        $b.AddValidate(@('cf'), 'D:\r.tsv') | Out-Null

        $cmds = $b.ToArray()
        $cmds.Count | Should -Be 3
        $cmds[0] | Should -BeLike '*src/cf"*'
        $cmds[1] | Should -BeLike '*src/cfe"*'
        $cmds[2] | Should -BeLike 'validate*'
    }

    It 'позволяет цепочку вызовов' {
        $b = & $script:NewBatch
        $b.AddImport('D:\a').AddImport('D:\b') | Out-Null
        @($b.ToArray()).Count | Should -Be 2
    }
}

Describe 'Get-EdtWtImportTargets' {
    BeforeAll {
        # Каталоги-заглушки: .project делает каталог EDT-проектом.
        $script:Wt = Join-Path ([System.IO.Path]::GetTempPath()) ("wt_" + [guid]::NewGuid().ToString('N'))
        foreach ($rel in 'src\cf', 'src\cfe', 'src\cfe_mp') {
            $dir = Join-Path $script:Wt $rel
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            Set-Content -LiteralPath (Join-Path $dir '.project') -Value @"
<projectDescription><name>$(Split-Path -Leaf $rel)</name></projectDescription>
"@ -Encoding UTF8
        }
        # Каталог без .project - не EDT-проект.
        New-Item -ItemType Directory -Force -Path (Join-Path $script:Wt 'src\cfe_broken') | Out-Null

        # Рабочая область, в которой уже есть проект cfe.
        $script:Ws = Join-Path ([System.IO.Path]::GetTempPath()) ("ws_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $script:Ws '.metadata\.plugins\org.eclipse.core.resources\.projects\cfe') | Out-Null

        $script:Ctx = [PSCustomObject]@{
            ProjectId        = 'test-proj'
            WorktreePath     = $script:Wt
            WorkspaceDir     = $script:Ws
            CfProject        = 'src\cf'
            ActiveExtensions = @('cfe', 'cfe_mp')
        }

        $script:Plan = {
            param($Extensions, [switch]$IncludeConfiguration)
            & (Get-Module EdtWorktree) {
                param($c, $e, $i)
                Get-EdtWtImportTargets -Context $c -Extensions $e -IncludeConfiguration:$i
            } $script:Ctx $Extensions $IncludeConfiguration
        }
    }

    AfterAll {
        foreach ($d in $script:Wt, $script:Ws) {
            if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
        }
    }

    It 'пропускает проект, уже присутствующий в рабочей области' {
        # Повторный import того же имени завершается ошибкой 204.
        $plan = & $script:Plan @('cfe', 'cfe_mp')
        ($plan.Targets | Split-Path -Leaf) | Should -Be @('cfe_mp')
    }

    It 'пропускает каталог без .project' {
        $plan = & $script:Plan @('cfe_broken')
        @($plan.Targets).Count | Should -Be 0
        @($plan.Skipped).Count | Should -Be 1
    }

    It 'пропускает отсутствующий каталог' {
        $plan = & $script:Plan @('cfe_nonexistent')
        @($plan.Targets).Count | Should -Be 0
    }

    It 'включает конфигурацию только по запросу' {
        $withCf = & $script:Plan @() -IncludeConfiguration
        ($withCf.Targets | Split-Path -Leaf) | Should -Be @('cf')

        $withoutCf = & $script:Plan @()
        @($withoutCf.Targets).Count | Should -Be 0
    }
}
