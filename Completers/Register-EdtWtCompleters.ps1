# Автодополнение для команды edt.
#
# У Invoke-EdtCommand нет отдельных параметров -Project и -Task: всё приходит
# позиционно в -Arguments. Поэтому подсказки строятся по разбору командной
# строки: какая подкоманда набрана и сколько позиционных значений уже введено.
function Register-EdtWtCompleters {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    [CmdletBinding()]
    param()

    $completer = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        function Get-EdtCompletionProjects {
            $cfg = Get-EdtWtConfig
            return @($cfg.projects.PSObject.Properties.Name)
        }

        function Get-EdtCompletionExtensions {
            param([string]$Project)
            $cfg = Get-EdtWtConfig
            if (-not $Project -or -not ($cfg.projects.PSObject.Properties.Name -contains $Project)) { return @() }
            $def = $cfg.projects.$Project
            if (-not ($def.PSObject.Properties.Name -contains 'active_extensions')) { return @() }
            return @($def.active_extensions)
        }

        # Ключи и их значения в подсчёте позиционных не участвуют.
        $valueKeys = @('-guimaxheap', '-maxheap', '-extensions')
        $positional = @()
        $skipNext = $false
        $elements = @($commandAst.CommandElements | Select-Object -Skip 1)

        foreach ($e in $elements) {
            $text = $e.Extent.Text
            if ($skipNext) { $skipNext = $false; continue }
            if ($text.StartsWith('-')) {
                if ($valueKeys -contains $text.ToLower()) { $skipNext = $true }
                continue
            }
            $positional += $text
        }

        # Слово, которое сейчас набирается, уже попало в список: оно не считается
        # завершённым значением.
        if ($wordToComplete -and $positional.Count -gt 0 -and $positional[-1] -eq $wordToComplete) {
            $positional = @($positional | Select-Object -SkipLast 1)
        }

        $subcommand = if ($positional.Count -gt 0) { $positional[0].ToLower() } else { '' }
        $args_ = @($positional | Select-Object -Skip 1)
        $projects = Get-EdtCompletionProjects

        $candidates = @()

        if ($positional.Count -eq 0) {
            $candidates = @('open', 'warmup', 'add', 'remove', 'status', 'update', 'self-update', 'vr', 'init', 'config', 'help')
        } elseif ($args_.Count -eq 0) {
            # Первый аргумент подкоманды: проект, а для open/add ещё и режим.
            $candidates = $projects
            if ($subcommand -in @('open', 'add')) { $candidates += @('all', 'none', 'changed') }
            if ($subcommand -eq 'config') { $candidates = @('get', 'set', 'init') }
        } elseif ($args_.Count -eq 1 -and ($projects -contains $args_[0])) {
            # Проект назван - дальше задача либо расширения.
            if ($subcommand -in @('open', 'add', 'remove')) {
                $cfg = Get-EdtWtConfig
                $wtRoot = Join-Path $cfg.paths.worktree_root $args_[0]
                if (Test-Path -LiteralPath $wtRoot) {
                    $candidates = @(Get-ChildItem -LiteralPath $wtRoot -Directory -ErrorAction SilentlyContinue |
                        ForEach-Object { $_.Name -replace '^feature-', '' })
                }
            } elseif ($subcommand -eq 'warmup') {
                $candidates = @('all', 'none') + (Get-EdtCompletionExtensions -Project $args_[0])
            }
        } elseif ($args_.Count -ge 2 -and ($projects -contains $args_[0])) {
            if ($subcommand -in @('open', 'add')) {
                $candidates = @('all', 'none', 'changed') + (Get-EdtCompletionExtensions -Project $args_[0])
            }
        }

        $candidates |
            Where-Object { $_ -and $_ -like "$wordToComplete*" } |
            Select-Object -Unique |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
    }

    Register-ArgumentCompleter -CommandName 'Invoke-EdtCommand', 'edt' -ParameterName 'Arguments' -ScriptBlock $completer
    Register-ArgumentCompleter -CommandName 'Invoke-EdtCommand', 'edt' -ParameterName 'Command' -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        @('open', 'warmup', 'add', 'remove', 'status', 'update', 'self-update', 'vr', 'init', 'config', 'help') |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }

    # Update-EdtWtReference принимает проекты явным параметром.
    Register-ArgumentCompleter -CommandName 'Update-EdtWtReference' -ParameterName 'Project' -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $cfg = Get-EdtWtConfig
        $cfg.projects.PSObject.Properties.Name |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
}
