# ==============================================================================
# ConfigMigration.ps1 - Миграция пользовательского конфига 2.x -> v3 (spec 5.2)
# ==============================================================================

Set-StrictMode -Version Latest

function Read-EdtWtJsonObject {
    <#
      Читает JSON-файл с объектом в корне. Нет файла - $null. Битый JSON или
      не-объект - исключение с путём файла.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }

    $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

    $problem = $null
    $obj = $null
    try {
        $obj = $raw | ConvertFrom-Json -NoEnumerate -ErrorAction Stop
        if ($null -eq $obj -or $obj.GetType().FullName -ne 'System.Management.Automation.PSCustomObject') {
            $problem = 'корнем должен быть JSON-объект'
        }
    } catch {
        $problem = $_.Exception.Message
    }
    if ($problem) { throw "Конфиг повреждён: ${Path}: $problem." }
    return $obj
}

function ConvertFrom-EdtWtV2Config {
    <#
      Чистое преобразование двух источников 2.x в конфиг v3 по таблице spec 5.2.
      Primary (config.json из %APPDATA%) побеждает Legacy (~/.config/1c/projects.json).
      Единственное обращение к диску - проверки существования и чтение текущей
      ветки клона.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [PSCustomObject]$Primary,
        [PSCustomObject]$Legacy,
        [Parameter(Mandatory)][string]$ReposRootForCheck
    )

    $notes = [System.Collections.Generic.List[string]]::new()
    $config = New-EdtWtDefaultConfig

    # Первое непустое значение из списка "источник, путь из ключей".
    $pick = {
        param([object[]]$Candidates)
        foreach ($c in $Candidates) {
            $node = $c[0]
            foreach ($key in $c[1..($c.Count - 1)]) {
                $node = Get-EdtWtProperty $node $key
                if ($null -eq $node) { break }
            }
            # "x" -is [PSCustomObject] истинно в PowerShell, поэтому сравниваем имя типа.
            if ($null -ne $node -and $node.GetType().FullName -ne 'System.Management.Automation.PSCustomObject') { return $node }
        }
        return $null
    }

    # --- paths ---
    $v = & $pick @(, @($Primary, 'paths', 'repos_root'))
    if ($null -eq $v) { $v = & $pick @(, @($Primary, 'paths', 'projects_root')) }
    if ($null -ne $v) { $config.paths.repos_root = [string]$v; $notes.Add("paths.repos_root = $v") }

    $v = & $pick @(, @($Primary, 'paths', 'worktree_root'))
    if ($null -ne $v) { $config.paths.worktrees_root = [string]$v; $notes.Add("paths.worktrees_root = $v") }

    $v = & $pick @(@($Primary, 'paths', 'workspaces_root'), @($Legacy, 'worktree', 'root_dir'))
    if ($null -ne $v) { $config.paths.workspaces_root = [string]$v; $notes.Add("paths.workspaces_root = $v") }

    # --- edt ---
    $cliCandidates = @(
        (& $pick @(, @($Primary, 'edt', 'cli_path')))
        (& $pick @(, @($Primary, 'defaults', '1cedtcli')))
        (& $pick @(, @($Legacy, 'defaults', '1cedtcli')))
    ) | Where-Object { $_ }
    $cli = $cliCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ($cli) {
        $config.edt.cli_path = [string]$cli
        $notes.Add("edt.cli_path = $cli")
    } elseif ($cliCandidates) {
        $notes.Add("edt.cli_path: путь '$($cliCandidates | Select-Object -First 1)' не найден, будет автопоиск")
    }

    $v = & $pick @(
        @($Primary, 'edt', 'prefs_source'), @($Primary, 'defaults', 'edt_prefs_source'),
        @($Legacy, 'defaults', 'edt_prefs_source'))
    if ($null -ne $v) { $config.edt.prefs_source = [string]$v; $notes.Add("edt.prefs_source = $v") }

    $v = & $pick @(
        @($Primary, 'edt', 'jvm', 'max_heap'), @($Primary, 'defaults', 'jvm', 'max_heap'),
        @($Legacy, 'defaults', 'jvm', 'max_heap'))
    if ($null -ne $v) { $config.edt.max_heap = [string]$v; $notes.Add("edt.max_heap = $v") }

    $v = & $pick @(
        @($Primary, 'edt', 'jvm', 'gui_max_heap'), @($Primary, 'defaults', 'jvm', 'gui_max_heap'),
        @($Legacy, 'defaults', 'jvm', 'gui_max_heap'))
    if ($null -ne $v) { $config.edt.gui_max_heap = [string]$v; $notes.Add("edt.gui_max_heap = $v") }

    $v = & $pick @(
        @($Primary, 'edt', 'jvm', 'extra_args'), @($Primary, 'defaults', 'jvm', 'extra_args'),
        @($Legacy, 'defaults', 'jvm', 'extra_args'))
    if ($null -ne $v) { $config.edt.extra_vmargs = [string]$v; $notes.Add("edt.extra_vmargs = $v") }

    # --- projects ---
    $generalRef = & $pick @(
        @($Primary, 'defaults', 'reference_branch'), @($Primary, 'worktree', 'reference_branch'),
        @($Legacy, 'worktree', 'reference_branch'), @($Legacy, 'defaults', 'reference_branch'))

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($src in @($Primary, $Legacy)) {
        $projects = Get-EdtWtProperty $src 'projects'
        if ($null -eq $projects) { continue }
        foreach ($n in $projects.PSObject.Properties.Name) {
            if (-not $names.Contains($n)) { $names.Add($n) }
        }
    }

    foreach ($name in $names) {
        $pPrimary = Get-EdtWtProperty (Get-EdtWtProperty $Primary 'projects') $name
        $pLegacy = Get-EdtWtProperty (Get-EdtWtProperty $Legacy 'projects') $name
        $clone = Join-Path $ReposRootForCheck $name

        $proj = [ordered]@{}

        $ref = & $pick @(@($pPrimary, 'reference_branch'), @($pLegacy, 'reference_branch'))
        if ($null -eq $ref) { $ref = $generalRef }
        if ($null -eq $ref -and (Test-Path -LiteralPath $clone -PathType Container)) {
            $head = Invoke-EdtWtGit -C $clone rev-parse --abbrev-ref HEAD 2>$null
            if ($LASTEXITCODE -eq 0 -and $head -and $head -ne 'HEAD') { $ref = ([string]($head | Select-Object -First 1)).Trim() }
        }
        if ($null -ne $ref) { $proj['ref_branch'] = [string]$ref }

        $cf = & $pick @(@($pPrimary, 'cf_project'), @($pLegacy, 'cf_project'))
        if ($null -ne $cf) { $proj['cf_project'] = [string]$cf }

        $exts = [System.Collections.Generic.List[string]]::new()
        $declared = & $pick @(@($pPrimary, 'active_extensions'), @($pLegacy, 'active_extensions'))
        foreach ($ext in @($declared)) {
            if (-not $ext) { continue }
            $rel = "src/$ext"
            if (Test-Path -LiteralPath (Join-Path $clone ($rel + '/.project'))) { $exts.Add($rel) }
            else { $notes.Add("projects.${name}: расширение '$ext' не найдено на диске, пропущено") }
        }
        $proj['extensions'] = [string[]]$exts.ToArray()

        Add-Member -InputObject $config.projects -MemberType NoteProperty -Name $name -Value ([PSCustomObject]$proj)
        $notes.Add("projects.$name перенесён")
    }

    if ($names.Count -gt 0) {
        $notes.Add('Не переносятся (в 3.0 не используются): min_heap, ignored_patterns, ibconnection, v8version, bases_dir, 1cedtcli проекта.')
    }

    return [PSCustomObject]@{ Config = $config; Notes = [string[]]$notes.ToArray() }
}

function Invoke-EdtWtConfigMigration {
    <#
      Ищет конфиг 2.x (config.json без version >= 3 по пути Get-EdtWtUserConfigPath
      и legacy projects.json). Нечего переносить - $null. Иначе: копия config.json в
      config.json.v2.bak, запись v3, печать итога одним блоком, возврат конфига.
      Legacy-файл не изменяется.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $cfgPath = Get-EdtWtUserConfigPath
    $legacyPath = if ($env:EDT_LEGACY_CONFIG_PATH) { $env:EDT_LEGACY_CONFIG_PATH }
    else { Join-Path $HOME '.config\1c\projects.json' }

    $primary = Read-EdtWtJsonObject -Path $cfgPath
    $legacy = $null
    $legacyProblem = $null
    try { $legacy = Read-EdtWtJsonObject -Path $legacyPath } catch { $legacyProblem = $_.Exception.Message }

    if ($null -eq $primary -and $null -eq $legacy -and -not $legacyProblem) { return $null }
    if ($null -eq $primary -and $null -eq $legacy) {
        Write-Host "Миграция: $legacyProblem Файл пропущен." -ForegroundColor Yellow
        return $null
    }

    $reposRoot = Get-EdtWtProperty (Get-EdtWtProperty $primary 'paths') 'projects_root'
    if (-not $reposRoot) { $reposRoot = (New-EdtWtDefaultConfig).paths.repos_root }

    $result = ConvertFrom-EdtWtV2Config -Primary $primary -Legacy $legacy -ReposRootForCheck $reposRoot

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('Миграция конфига 2.x -> 3.0')
    if (Test-Path -LiteralPath $cfgPath -PathType Leaf) {
        Copy-Item -LiteralPath $cfgPath -Destination "$cfgPath.v2.bak" -Force
        $lines.Add("  Копия прежнего config.json: $cfgPath.v2.bak")
    }
    if ($legacyProblem) { $lines.Add("  $legacyProblem Legacy-файл пропущен.") }
    foreach ($n in $result.Notes) { $lines.Add("  $n") }

    $saved = Save-EdtWtConfig -Config $result.Config
    $lines.Add("  Сохранено: $saved")
    $lines.Add('  Legacy-файл ~/.config/1c/projects.json не изменён и больше не читается.')
    Write-Host ($lines -join [Environment]::NewLine) -ForegroundColor DarkGray

    return $result.Config
}
