function Resolve-EdtWtTarget {
    <#
      Определяет, над чем работать, по позиционным аргументам и текущему каталогу.
      Возвращает Path (где выполнять; $null - текущий каталог), ProjectId,
      Branch (полное имя ветки, для remove) и Extensions (для add).
      open <проект> <ветка> создаёт недостающий worktree (под -WhatIf - нет).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()][AllowEmptyCollection()][string[]]$Positional,

        [Parameter(Mandatory)][ValidateSet('open', 'warmup', 'add', 'remove')]
        [string]$Command
    )

    $items = @($Positional | Where-Object { $_ })
    $cfg = Get-EdtWtConfig
    $prefix = Get-EdtWtProperty $cfg.git 'branch_prefix' ''

    $result = [PSCustomObject]@{
        Path       = $null
        ProjectId  = $null
        Branch     = $null
        Extensions = @()
    }

    switch ($Command) {
        'warmup' {
            if ($items.Count -gt 1) {
                throw "Лишние аргументы: $(($items | Select-Object -Skip 1) -join ', '). Использование: edt warmup [проект]"
            }
            if ($items.Count -eq 1) {
                Get-EdtWtProjectDef -Config $cfg -Name $items[0] | Out-Null
                $result.ProjectId = $items[0]
                $result.Path = Join-Path $cfg.paths.repos_root $items[0]
                if (-not (Test-Path -LiteralPath $result.Path)) {
                    throw "Каталог проекта не найден: $($result.Path)"
                }
            }
        }

        'add' {
            $result.Extensions = $items
        }

        'remove' {
            if ($items.Count -gt 2) {
                throw "Лишние аргументы: $(($items | Select-Object -Skip 2) -join ', '). Использование: edt remove [проект] [ветка]"
            }
            $projectGiven = ($items.Count -gt 0 -and $null -ne $cfg.projects.PSObject.Properties[$items[0]])
            if ($projectGiven) {
                if ($items.Count -lt 2) { throw "Не указана ветка. Пример: edt remove $($items[0]) TASK-123" }
                $result.ProjectId = $items[0]
                $result.Branch = Resolve-EdtWtBranchName -Name $items[1] -Prefix $prefix
                $result.Path = Get-EdtWtWorktreeDir -Project $items[0] -Branch $result.Branch
            } elseif ($items.Count -eq 2) {
                Get-EdtWtProjectDef -Config $cfg -Name $items[0] | Out-Null
            } elseif ($items.Count -eq 1) {
                $result.Branch = Resolve-EdtWtBranchName -Name $items[0] -Prefix $prefix
            }
        }

        'open' {
            if ($items.Count -gt 2) {
                throw "Лишние аргументы: $(($items | Select-Object -Skip 2) -join ', '). Использование: edt open [проект ветка]"
            }
            if ($items.Count -gt 0) {
                Get-EdtWtProjectDef -Config $cfg -Name $items[0] | Out-Null
                if ($items.Count -lt 2) { throw "Не указана ветка. Пример: edt open $($items[0]) TASK-123" }
                $result.ProjectId = $items[0]
                $result.Branch = Resolve-EdtWtBranchName -Name $items[1] -Prefix $prefix
                $result.Path = Get-EdtWtWorktreeDir -Project $items[0] -Branch $result.Branch -CreateIfMissing
            }
        }
    }

    return $result
}
