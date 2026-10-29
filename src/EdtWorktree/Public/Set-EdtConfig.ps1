function Set-EdtConfig {
    <#
    .SYNOPSIS
        Меняет один параметр конфигурации по ключу.
    .DESCRIPTION
        Допустимые ключи: paths.repos_root, paths.worktrees_root, paths.workspaces_root,
        edt.cli_path, edt.vm_path, edt.prefs_source, edt.max_heap, edt.gui_max_heap,
        edt.extra_vmargs, edt.timeout_sec, git.remote, git.branch_prefix.
        Значение 'null' или пустое сбрасывает параметр (авто или значение по умолчанию).
    .PARAMETER Key
        Ключ вида раздел.имя.
    .PARAMETER Value
        Новое значение.
    .EXAMPLE
        Set-EdtConfig -Key edt.max_heap -Value 16g
    .EXAMPLE
        Set-EdtConfig -Key edt.cli_path -Value null
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Key,
        [Parameter(Mandatory, Position = 1)][AllowNull()][AllowEmptyString()][string]$Value
    )

    $kinds = [ordered]@{
        'paths.repos_root'      = 'string'
        'paths.worktrees_root'  = 'string'
        'paths.workspaces_root' = 'string'
        'edt.cli_path'          = 'path'
        'edt.vm_path'           = 'path'
        'edt.prefs_source'      = 'path'
        'edt.max_heap'          = 'heap'
        'edt.gui_max_heap'      = 'heap'
        'edt.extra_vmargs'      = 'string'
        'edt.timeout_sec'       = 'positiveInt'
        'git.remote'            = 'string'
        'git.branch_prefix'     = 'string'
    }
    if (-not $kinds.Contains($Key)) {
        throw "Неизвестный ключ '$Key'. Допустимые ключи: $($kinds.Keys -join ', ')."
    }

    $newValue = $null
    if (-not [string]::IsNullOrWhiteSpace($Value) -and $Value.Trim() -ne 'null') {
        $newValue = $Value
        switch ($kinds[$Key]) {
            'heap' {
                if ($Value -notmatch '^\d+[gGmM]$') {
                    throw "Недопустимое значение '$Value' для $Key. Ожидается число с суффиксом g или m, например 16g."
                }
            }
            'positiveInt' {
                [int]$n = 0
                if ($Value -notmatch '^\d+$' -or -not [int]::TryParse($Value, [ref]$n) -or $n -le 0) {
                    throw "Недопустимое значение '$Value' для $Key. Ожидается целое число больше нуля."
                }
                $newValue = $n
            }
            'path' {
                if (-not (Test-Path -LiteralPath $Value)) {
                    Write-Warning "Путь для $Key не существует: $Value"
                }
            }
        }
    }

    $cfg = Get-EdtWtConfig
    $section, $name = $Key -split '\.', 2
    $cfg.$section.$name = $newValue

    if ($PSCmdlet.ShouldProcess((Get-EdtWtUserConfigPath), "Установить $Key")) {
        Save-EdtWtConfig -Config $cfg | Out-Null
        $shown = if ($null -eq $newValue) { 'null (по умолчанию)' } else { $newValue }
        Write-Host "✓ $Key = $shown" -ForegroundColor Green
    }
}
