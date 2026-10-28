# Автодополнение для команды edt.
#
# У Invoke-EdtCommand нет отдельных параметров проекта и ветки: всё приходит
# позиционно в -Arguments. Поэтому подсказки строятся по разбору командной
# строки: какая подкоманда набрана и сколько позиционных значений уже введено.
function Register-EdtWtCompleters {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    [CmdletBinding()]
    param()

    $completer = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        $cfg = Get-EdtWtConfig
        $projects = @(@($cfg.projects.PSObject.Properties).ForEach('Name'))

        # Ключи со значением: само значение позиционным не считается.
        $valueKeys = @('extensions', 'refbranch', 'cfproject', 'reposroot', 'worktreesroot', 'workspacesroot')
        $commonFlag = '^--?(what-?if|dry-?run|yes)$'

        $positional = @()
        $changes = @()
        $skipNext = $false
        $elements = @($commandAst.CommandElements | Select-Object -Skip 1)

        for ($i = 0; $i -lt $elements.Count; $i++) {
            $text = $elements[$i].Extent.Text
            # Слово, которое сейчас набирается, завершённым значением не считается.
            if ($i -eq ($elements.Count - 1) -and $wordToComplete -and $text -eq $wordToComplete) { continue }
            if ($skipNext) { $skipNext = $false; continue }

            $inExt = ($positional.Count -ge 3 -and $positional[0] -eq 'project' -and $positional[1] -eq 'ext')
            if ($inExt -and $text -match '^[+-]' -and $text -notmatch $commonFlag) {
                $changes += $text
                continue
            }
            if ($text.StartsWith('-')) {
                if ($valueKeys -contains ($text.ToLower() -replace '-', '')) { $skipNext = $true }
                continue
            }
            $positional += $text
        }
        # Ключ ждёт значение, подсказывать нечего.
        if ($skipNext) { return }

        $cloneExtensions = {
            param([string]$Project)
            if (-not $Project -or ($null -eq $cfg.projects.PSObject.Properties[$Project])) { return @() }
            $repo = Join-Path $cfg.paths.repos_root $Project
            if (-not (Test-Path -LiteralPath $repo)) { return @() }
            return @(Find-EdtWtEdtProjects -RepoPath $repo | Where-Object Kind -eq 'Extension')
        }

        $branches = {
            param([string]$Project, [bool]$IncludeAll)
            $repo = Join-Path $cfg.paths.repos_root $Project
            if (-not (Test-Path -LiteralPath $repo)) { return @() }
            $remote = Get-EdtWtProperty $cfg.git 'remote' 'origin'
            $prefix = [string](Get-EdtWtProperty $cfg.git 'branch_prefix' '')
            $refBranch = [string](Get-EdtWtProperty $cfg.projects.$Project 'ref_branch' '')
            $names = @()
            try {
                foreach ($line in @(Invoke-EdtWtGit -C $repo worktree list --porcelain 2>$null)) {
                    if ($line -match '^branch\s+refs/heads/(.+)$') { $names += $Matches[1] }
                }
                if ($IncludeAll) {
                    foreach ($ref in @(Invoke-EdtWtGit -C $repo for-each-ref '--format=%(refname)' refs/heads "refs/remotes/$remote" 2>$null)) {
                        $names += ($ref -replace "^refs/heads/", '' -replace "^refs/remotes/$([regex]::Escape($remote))/", '')
                    }
                }
            } catch { return @() }
            return @($names | Where-Object { $_ -and $_ -ne 'HEAD' -and $_ -ne $refBranch } | ForEach-Object {
                    if ($prefix -and $_.StartsWith($prefix)) { $_.Substring($prefix.Length) } else { $_ }
                } | Select-Object -Unique)
        }

        $subcommand = if ($positional.Count -gt 0) { $positional[0].ToLower() } else { '' }
        $rest = @($positional | Select-Object -Skip 1)
        $candidates = @()

        if ($positional.Count -eq 0) {
            $candidates = @('open', 'warmup', 'add', 'remove', 'status', 'update', 'vr', 'setup', 'project', 'config', 'doctor', 'self-update', 'uninstall', 'help')
        } else {
            switch ($subcommand) {
                { $_ -in @('open', 'remove') } {
                    if ($rest.Count -eq 0) { $candidates = $projects }
                    elseif ($rest.Count -eq 1 -and ($projects -contains $rest[0])) {
                        $candidates = & $branches $rest[0] ($subcommand -eq 'open')
                    }
                }
                { $_ -in @('warmup', 'status') } {
                    if ($rest.Count -eq 0) { $candidates = $projects }
                }
                'update' {
                    $candidates = @($projects | Where-Object { $rest -notcontains $_ })
                }
                'add' {
                    $resolved = Resolve-EdtWtProjectFromPath -Path (Get-Location).Path -Config $cfg
                    if ($resolved -and $resolved.Registered) {
                        $candidates = @(& $cloneExtensions $resolved.Name | ForEach-Object { Split-Path -Leaf $_.RelPath } |
                                Where-Object { $rest -notcontains $_ })
                    }
                }
                'project' {
                    if ($rest.Count -eq 0) {
                        $candidates = @('list', 'add', 'ext', 'set', 'remove')
                    } else {
                        $psub = $rest[0].ToLower()
                        $pr = @($rest | Select-Object -Skip 1)
                        switch ($psub) {
                            'add' {
                                if ($pr.Count -eq 0 -and (Test-Path -LiteralPath $cfg.paths.repos_root)) {
                                    $candidates = @(Get-ChildItem -LiteralPath $cfg.paths.repos_root -Directory -Force -ErrorAction SilentlyContinue |
                                            Where-Object { (Test-Path -LiteralPath (Join-Path $_.FullName '.git')) -and ($projects -notcontains $_.Name) } |
                                            ForEach-Object { $_.Name })
                                }
                            }
                            { $_ -in @('list', 'set', 'remove') } {
                                if ($pr.Count -eq 0) { $candidates = $projects }
                            }
                            'ext' {
                                if ($pr.Count -eq 0) {
                                    $candidates = $projects
                                } elseif ($projects -contains $pr[0]) {
                                    $found = @(& $cloneExtensions $pr[0] | ForEach-Object { Split-Path -Leaf $_.RelPath })
                                    $working = @(@(Get-EdtWtProperty $cfg.projects.($pr[0]) 'extensions' @()) | ForEach-Object { Split-Path -Leaf $_ })
                                    $added = @($found | Where-Object { $working -notcontains $_ } | ForEach-Object { "+$_" })
                                    $removed = @($working | ForEach-Object { "-$_" })
                                    $candidates = @($added + $removed | Where-Object { $changes -notcontains $_ })
                                }
                            }
                        }
                    }
                }
                'config' {
                    if ($rest.Count -eq 0) {
                        $candidates = @('show', 'path', 'set')
                    } elseif ($rest[0] -eq 'set' -and $rest.Count -eq 1) {
                        $candidates = @('paths.repos_root', 'paths.worktrees_root', 'paths.workspaces_root',
                            'edt.cli_path', 'edt.vm_path', 'edt.prefs_source', 'edt.max_heap', 'edt.gui_max_heap',
                            'edt.extra_vmargs', 'edt.timeout_sec', 'git.remote', 'git.branch_prefix')
                    }
                }
            }
        }

        $candidates |
            Where-Object { $_ -and $_.StartsWith($wordToComplete, [System.StringComparison]::OrdinalIgnoreCase) } |
            Select-Object -Unique |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
    }

    # Подкоманды подсказывает ValidateSet параметра Command; здесь - всё остальное.
    Register-ArgumentCompleter -CommandName 'Invoke-EdtCommand', 'edt' -ParameterName 'Arguments' -ScriptBlock $completer

    # Update-EdtWtReference принимает проекты явным параметром.
    Register-ArgumentCompleter -CommandName 'Update-EdtWtReference' -ParameterName 'Project' -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $cfg = Get-EdtWtConfig
        @($cfg.projects.PSObject.Properties).ForEach('Name') |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
}
