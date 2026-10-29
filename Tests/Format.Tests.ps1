BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:TestCfg = Enter-EdtWtTestConfig
    Import-Module (Get-EdtWtTestModulePath) -Force
    $script:Views = [ordered]@{
        'EdtWorktree.Worktree'        = @('Project', 'Worktree', 'CodePath', 'Workspace', 'Locked', 'Processes')
        'EdtWorktree.DoctorCheck'     = @('Check', 'Status', 'Detail', 'Fix')
        'EdtWorktree.Project'         = @('Name', 'RefBranch', 'CloneBranch', 'Extensions', 'Reference', 'RepoPath')
        'EdtWorktree.ConfigSummary'   = @('ConfigFile', 'ReposRoot', 'WorktreesRoot', 'WorkspacesRoot', 'EdtCli', 'Projects')
        'EdtWorktree.ReferenceUpdate' = @('Project', 'Status', 'Detail', 'Seconds')
    }
}

AfterAll {
    Exit-EdtWtTestConfig -State $script:TestCfg
}

Describe 'Табличные виды EdtWorktree.format.ps1xml' {
    It 'у каждого типа есть табличный вид с колонками в порядке свойств' {
        foreach ($name in $script:Views.Keys) {
            $data = Get-FormatData -TypeName $name
            $data | Should -Not -BeNullOrEmpty -Because $name
            $cols = @($data.FormatViewDefinition[0].Control.Headers.Label)
            $cols | Should -Be $script:Views[$name] -Because $name
        }
    }

    It 'Test-EdtEnvironment отдаёт EdtWorktree.DoctorCheck' {
        Mock -ModuleName EdtWorktree Find-EdtWtCli { @([pscustomobject]@{ Version = '2024.2'; Path = 'C:\fake\1cedtcli.exe'; Folder = 'C:\fake' }) }
        Mock -ModuleName EdtWorktree Resolve-EdtWtGuiJvm { [pscustomobject]@{ Path = 'C:\jdk\bin\server\jvm.dll'; Reason = 'scan' } }
        $rows = @(Test-EdtEnvironment)
        $rows.Count | Should -BeGreaterThan 0
        $rows[0].PSObject.TypeNames[0] | Should -Be 'EdtWorktree.DoctorCheck'
        $rows[0].PSObject.Properties.Name | Should -Be $script:Views['EdtWorktree.DoctorCheck']
    }

    It 'Get-EdtWorktreeList отдаёт EdtWorktree.Worktree' {
        $root = Join-Path $script:TestCfg.Root 'fmt-ws'
        New-Item -ItemType Directory -Path (Join-Path $root 'p\feature-x') -Force | Out-Null
        $cfg = & (Get-Module EdtWorktree) { Get-EdtWtConfig }
        $cfg.paths.workspaces_root = $root
        & (Get-Module EdtWorktree) { param($c) Save-EdtWtConfig -Config $c | Out-Null } $cfg
        Mock -ModuleName EdtWorktree Get-CimInstance { @() }
        $rows = @(Get-EdtWorktreeList)
        $rows.Count | Should -Be 1
        $rows[0].PSObject.TypeNames[0] | Should -Be 'EdtWorktree.Worktree'
        $rows[0].PSObject.Properties.Name | Should -Be $script:Views['EdtWorktree.Worktree']
    }

    It 'Get-EdtConfig отдаёт EdtWorktree.ConfigSummary' {
        $row = Get-EdtConfig
        $row.PSObject.TypeNames[0] | Should -Be 'EdtWorktree.ConfigSummary'
        $row.PSObject.Properties.Name | Should -Be $script:Views['EdtWorktree.ConfigSummary']
    }

    It 'Get-EdtProject отдаёт EdtWorktree.Project' {
        $cfg = & (Get-Module EdtWorktree) { Get-EdtWtConfig }
        $def = [PSCustomObject]@{ ref_branch = 'develop'; cf_project = 'src/cf'; extensions = [string[]]@() }
        Add-Member -InputObject $cfg.projects -MemberType NoteProperty -Name 'fmtp' -Value $def -Force
        & (Get-Module EdtWorktree) { param($c) Save-EdtWtConfig -Config $c | Out-Null } $cfg
        $row = @(Get-EdtProject -Name 'fmtp')[0]
        $row.PSObject.TypeNames[0] | Should -Be 'EdtWorktree.Project'
        $row.PSObject.Properties.Name | Should -Be $script:Views['EdtWorktree.Project']
    }

    It 'Update-EdtWtReference отдаёт EdtWorktree.ReferenceUpdate' {
        $rows = @(Update-EdtWtReference -Project 'нет-такого' -Confirm:$false 6>&1 | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] })
        $rows.Count | Should -Be 1
        $rows[0].PSObject.TypeNames[0] | Should -Be 'EdtWorktree.ReferenceUpdate'
        $rows[0].PSObject.Properties.Name | Should -Be $script:Views['EdtWorktree.ReferenceUpdate']
    }
}