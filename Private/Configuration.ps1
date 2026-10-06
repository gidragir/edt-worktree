# ==============================================================================
# Configuration.ps1 - Конфигурация, переменные путей и реестр проектов
# ==============================================================================

Set-StrictMode -Version Latest

# ------------------------------------------------------------------------------
# 1. Значения по умолчанию и переменные окружения
# ------------------------------------------------------------------------------

# Значения по умолчанию, если в config.json / projects.json нет секции paths/worktree.
$script:EdtWtDefaultRoot = if (Test-Path "D:\workspaces\worktree") { "D:\workspaces\worktree" } else { Join-Path $env:USERPROFILE "edt-workspaces" }
$script:EdtWtDefaultRefBranch = "pre-prod"

# Корень исходных репозиториев проектов.
$script:EdtWtProjectsRoot = if ($env:PROJECTS_ROOT) {
    $env:PROJECTS_ROOT
} elseif (Test-Path "D:\projects\default") {
    "D:\projects\default"
} else {
    Join-Path $env:USERPROFILE "projects\default"
}

# Корень git-worktree проектов.
$script:EdtWtWorktreeRoot = if ($env:PROJECTS_WORKTREE_ROOT) {
    $env:PROJECTS_WORKTREE_ROOT
} elseif (Test-Path "D:\projects\worktree") {
    "D:\projects\worktree"
} else {
    Join-Path $env:USERPROFILE "projects\worktree"
}

# Пользовательские настройки IDE: тема, шрифты, цвета, раскладка горячих клавиш,
# настройки редактора BSL. Всё это Eclipse хранит per-workspace в .prefs-файлах,
# поэтому каждая новая рабочая область стартует с настройками по умолчанию.
# Файлы, привязанные к конкретному проекту (инфобазы, публикации, серверы,
# порты MCP), сюда намеренно не входят.
$script:EdtWtPortablePrefs = @(
    'org.eclipse.ui.workbench.prefs'              # шрифты, цвета, горячие клавиши, декораторы
    'org.eclipse.ui.prefs'
    'org.eclipse.ui.ide.prefs'
    'org.eclipse.ui.editors.prefs'
    'org.eclipse.ui.navigator.prefs'
    'org.eclipse.ui.genericeditor.prefs'
    'org.eclipse.e4.ui.css.swt.theme.prefs'       # тема оформления
    'org.eclipse.e4.ui.workbench.renderers.swt.prefs'
    'org.eclipse.egit.ui.prefs'
    'com._1c.g5.v8.dt.theming.ui.prefs'
    'com._1c.g5.v8.dt.bsl.ui.prefs'               # редактор встроенного языка
    'com._1c.g5.v8.dt.compare.ui.prefs'
    'com._1c.g5.v8.dt.navigator.ui.navigator.prefs'
    'com._1c.g5.v8.dt.right.ql.ui.prefs'
    'com._1c.g5.v8.dt.ui.language.prefs'
    'com._1c.g5.v8.dt.ui.validation.prefs'
    'com.e1c.edt.ai.ui.prefs'
)

# Старые имена команд, о которых уже предупредили в этой сессии.
$script:EdtWtLegacyWarned = [System.Collections.Generic.HashSet[string]]::new()

# ------------------------------------------------------------------------------
# 2. Вспомогательные функции чтения свойств и идентификаторов
# ------------------------------------------------------------------------------

# Безопасное чтение необязательного свойства из разобранного JSON.
# ConvertFrom-Json отдаёт PSCustomObject без отсутствующих ключей, поэтому под
# Set-StrictMode прямое обращение к ним - ошибка, а не $null. Все необязательные
# ключи projects.json читаются только через эту функцию.
function Get-EdtWtProperty {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        $InputObject,

        [Parameter(Position = 1, Mandatory)]
        [string]$Name,

        [Parameter(Position = 2)]
        $Default = $null
    )

    if ($null -eq $InputObject) { return $Default }
    if ($null -eq $InputObject.PSObject.Properties[$Name]) { return $Default }

    $value = $InputObject.$Name
    if ($null -eq $value) { return $Default }
    if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

function Get-EdtWtProjectIdFromRepo {
    param([Parameter(Mandatory)][string]$GitCommonDir, [Parameter(Mandatory)]$Projects)

    $candidates = @()

    $originUrl = (git config --get remote.origin.url 2>$null)
    if ($originUrl) {
        $leaf = ($originUrl -replace '\\', '/').TrimEnd('/').Split('/')[-1]
        $candidates += ($leaf -replace '\.git$', '')
    }

    # .git общей папки: <repo>/.git или <repo>/.git/worktrees/<id>
    $common = (Resolve-Path -LiteralPath $GitCommonDir -ErrorAction SilentlyContinue)
    if ($common) {
        $commonPath = $common.Path.TrimEnd('\')
        if ((Split-Path -Leaf $commonPath) -eq '.git') {
            $candidates += (Split-Path -Leaf (Split-Path -Parent $commonPath))
        } else {
            $candidates += (Split-Path -Leaf $commonPath)
        }
    }

    foreach ($c in $candidates) {
        if ($c -and ($null -ne $Projects.PSObject.Properties[$c])) { return $c }
    }
    return $null
}

# ------------------------------------------------------------------------------
# 3. Пути конфигурационных файлов и чтение/слияние настроек
# ------------------------------------------------------------------------------

function Get-EdtWtUserConfigPath {
    <#
    .SYNOPSIS
        Возвращает путь к пользовательскому конфигурационному файлу.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($env:EDT_CONFIG_PATH) {
        return $env:EDT_CONFIG_PATH
    }

    $appData = [Environment]::GetFolderPath('ApplicationData')
    $primary = Join-Path $appData "EdtWorktree\config.json"
    if (Test-Path -LiteralPath $primary) { return $primary }

    $legacy = Join-Path $env:USERPROFILE ".config\1c\projects.json"
    if (Test-Path -LiteralPath $legacy) { return $legacy }

    return $primary
}

function Get-EdtWtProjectConfigFile {
    <#
    .SYNOPSIS
        Ищет .edt-worktree.json в текущем git-репозитории.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Path)

    $startPath = if ($Path) { $Path } else { (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $startPath)) { return $null }

    # 1. Быстрая проверка прямо в каталоге
    $direct = Join-Path $startPath ".edt-worktree.json"
    if (Test-Path -LiteralPath $direct) { return $direct }

    # 2. Если доступен git, проверяем корень репозитория
    $gitCmd = Get-Command "git" -ErrorAction SilentlyContinue
    if (-not $gitCmd) { return $null }

    Push-Location -LiteralPath $startPath
    try {
        $topLevel = (& $gitCmd.Source rev-parse --show-toplevel 2>$null)
        if ($topLevel) {
            $topLevel = ($topLevel -replace '/', '\')
            $projFile = Join-Path $topLevel ".edt-worktree.json"
            if (Test-Path -LiteralPath $projFile) { return $projFile }

            # Проверка git-common-dir для worktree
            $gitCommonDir = (& $gitCmd.Source rev-parse --git-common-dir 2>$null)
            if ($gitCommonDir) {
                if (-not [System.IO.Path]::IsPathRooted($gitCommonDir)) {
                    $gitCommonDir = Join-Path $topLevel $gitCommonDir
                }
                $parentRepo = Split-Path -Parent ($gitCommonDir -replace '/', '\')
                $projFile2 = Join-Path $parentRepo ".edt-worktree.json"
                if (Test-Path -LiteralPath $projFile2) { return $projFile2 }
            }
        }
    } finally {
        Pop-Location
    }

    return $null
}

function Get-EdtWtConfig {
    <#
    .SYNOPSIS
        Возвращает объединенную конфигурацию модуля EdtWorktree.
    .DESCRIPTION
        Сливает:
        1. Встроенные дефолты модуля
        2. Пользовательский конфиг (%APPDATA%\EdtWorktree\config.json или ~/.config/1c/projects.json)
        3. Конфиг проекта (.edt-worktree.json в корне git)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([string]$Path)

    # 1. Базовые дефолты
    $workspacesRoot = if ($script:EdtWtDefaultRoot) { $script:EdtWtDefaultRoot } else { Join-Path $env:USERPROFILE "edt-workspaces" }
    $projectsRoot = if ($script:EdtWtProjectsRoot) { $script:EdtWtProjectsRoot } else { Join-Path $env:USERPROFILE "projects\default" }
    $worktreeRoot = if ($script:EdtWtWorktreeRoot) { $script:EdtWtWorktreeRoot } else { Join-Path $env:USERPROFILE "projects\worktree" }

    $config = [PSCustomObject]@{
        paths      = [PSCustomObject]@{
            projects_root   = $projectsRoot
            worktree_root   = $worktreeRoot
            workspaces_root = $workspacesRoot
        }
        defaults   = [PSCustomObject]@{
            reference_branch = 'pre-prod'
            '1cedtcli'       = $null
            edt_prefs_source = ''
            jvm              = [PSCustomObject]@{
                max_heap   = '12g'
                min_heap   = '2g'
                extra_args = ''
            }
            timeouts         = [PSCustomObject]@{
                export_batch_sec = 7200
            }
        }
        projects   = [PSCustomObject]@{}
        worktree   = [PSCustomObject]@{
            root_dir         = $workspacesRoot
            reference_branch = 'pre-prod'
        }
    }

    # 2. Пользовательский конфиг (с поддержкой fallback на ~/.config/1c/projects.json)
    $explicitCfgPath = $env:EDT_CONFIG_PATH
    $primaryCfgPath = Join-Path ([Environment]::GetFolderPath('ApplicationData')) "EdtWorktree\config.json"
    $legacyCfgPath = Join-Path $env:USERPROFILE ".config\1c\projects.json"

    $configsToLoad = @()
    if ($explicitCfgPath) {
        if (Test-Path -LiteralPath $explicitCfgPath) {
            $configsToLoad += $explicitCfgPath
        }
    } else {
        # Сначала подгружаем legacy projects.json как fallback
        if (Test-Path -LiteralPath $legacyCfgPath) {
            $configsToLoad += $legacyCfgPath
        }
        # Затем основной конфиг пользователя (перекрывает пути, jvm и т.д.)
        if (Test-Path -LiteralPath $primaryCfgPath) {
            $configsToLoad += $primaryCfgPath
        }
    }

    foreach ($cfgPath in $configsToLoad) {
        try {
            $userJson = Get-Content -Raw -LiteralPath $cfgPath -Encoding UTF8 | ConvertFrom-Json
            if ($userJson) {
                if ($null -ne $userJson.PSObject.Properties['defaults'] -and $userJson.defaults) {
                    foreach ($prop in $userJson.defaults.PSObject.Properties) {
                        Add-Member -InputObject $config.defaults -MemberType NoteProperty -Name $prop.Name -Value $prop.Value -Force
                    }
                }
                if ($null -ne $userJson.PSObject.Properties['worktree'] -and $userJson.worktree) {
                    $config.worktree = $userJson.worktree
                    if ($null -ne $userJson.worktree.PSObject.Properties['root_dir']) {
                        $config.paths.workspaces_root = $userJson.worktree.root_dir
                    }
                    if ($null -ne $userJson.worktree.PSObject.Properties['reference_branch']) {
                        Add-Member -InputObject $config.defaults -MemberType NoteProperty -Name 'reference_branch' -Value $userJson.worktree.reference_branch -Force
                    }
                }
                if ($null -ne $userJson.PSObject.Properties['paths'] -and $userJson.paths) {
                    if ($null -ne $userJson.paths.PSObject.Properties['projects_root']) {
                        $config.paths.projects_root = $userJson.paths.projects_root
                    }
                    if ($null -ne $userJson.paths.PSObject.Properties['worktree_root']) {
                        $config.paths.worktree_root = $userJson.paths.worktree_root
                    }
                    if ($null -ne $userJson.paths.PSObject.Properties['workspaces_root']) {
                        $config.paths.workspaces_root = $userJson.paths.workspaces_root
                        $config.worktree.root_dir = $userJson.paths.workspaces_root
                    }
                }
                if ($null -ne $userJson.PSObject.Properties['edt'] -and $userJson.edt) {
                    if ($null -ne $userJson.edt.PSObject.Properties['cli_path']) {
                        Add-Member -InputObject $config.defaults -MemberType NoteProperty -Name '1cedtcli' -Value $userJson.edt.cli_path -Force
                    }
                    if ($null -ne $userJson.edt.PSObject.Properties['jvm']) {
                        Add-Member -InputObject $config.defaults -MemberType NoteProperty -Name 'jvm' -Value $userJson.edt.jvm -Force
                    }
                }
                if ($null -ne $userJson.PSObject.Properties['projects'] -and $userJson.projects) {
                    foreach ($pProp in $userJson.projects.PSObject.Properties) {
                        Add-Member -InputObject $config.projects -MemberType NoteProperty -Name $pProp.Name -Value $pProp.Value -Force
                    }
                }
            }
        } catch {
            Write-Warning "Ошибка чтения пользовательского конфига ($cfgPath): $($_.Exception.Message)"
        }
    }

    # Автопоиск EDT, если путь не задан
    if (-not $config.defaults.'1cedtcli') {
        $found = Find-EdtWtCli
        if ($found -and $found.Count -gt 0) {
            $config.defaults.'1cedtcli' = $found[0].Path
        }
    }

    # Синхронизация script-переменных
    $script:EdtWtProjectsRoot = $config.paths.projects_root
    $script:EdtWtWorktreeRoot = $config.paths.worktree_root
    $script:EdtWtDefaultRoot = $config.paths.workspaces_root
    $script:EdtWtDefaultRefBranch = $config.defaults.reference_branch

    # 3. Конфиг проекта (.edt-worktree.json)
    $projectCfgFile = Get-EdtWtProjectConfigFile -Path $Path
    if ($projectCfgFile) {
        try {
            $projJson = Get-Content -Raw -LiteralPath $projectCfgFile -Encoding UTF8 | ConvertFrom-Json
            if ($projJson) {
                $projId = if ($null -ne $projJson.PSObject.Properties['project_id'] -and $projJson.project_id) {
                    $projJson.project_id
                } elseif ($null -ne $projJson.PSObject.Properties['project_name'] -and $projJson.project_name) {
                    $projJson.project_name
                } elseif ($null -ne $projJson.PSObject.Properties['name'] -and $projJson.name) {
                    $projJson.name
                } elseif ($null -ne $projJson.PSObject.Properties['cf_project'] -and $projJson.cf_project -and ($projJson.cf_project -notmatch '[\\/]')) {
                    $projJson.cf_project
                } else {
                    Split-Path -Leaf (Split-Path -Parent $projectCfgFile)
                }

                # Добавляем или обновляем проект в реестре
                $projProps = @{}
                foreach ($prop in $projJson.PSObject.Properties) {
                    $projProps[$prop.Name] = $prop.Value
                }
                if (-not $projProps.ContainsKey('1cedtcli') -or -not $projProps['1cedtcli']) {
                    $projProps['1cedtcli'] = $config.defaults.'1cedtcli'
                }

                # Регистрируем в объекте projects
                Add-Member -InputObject $config.projects -MemberType NoteProperty -Name $projId -Value ([PSCustomObject]$projProps) -Force
                Add-Member -InputObject $config -MemberType NoteProperty -Name 'ActiveProjectConfigFile' -Value $projectCfgFile -Force
                Add-Member -InputObject $config -MemberType NoteProperty -Name 'ActiveProjectId' -Value $projId -Force
            }
        } catch {
            Write-Warning "Ошибка чтения .edt-worktree.json ($projectCfgFile): $($_.Exception.Message)"
        }
    }

    return $config
}

# Реестр проектов (Repository): единственное место чтения projects.json.
function Get-EdtWtProjectsConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$Path
    )

    if ($Path) {
        if (-not (Test-Path -LiteralPath $Path)) {
            throw "Конфигурационный файл не найден: $Path"
        }
        return (Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json)
    }

    return (Get-EdtWtConfig)
}

function Get-EdtWtSettings {
    $cfg = Get-EdtWtProjectsConfig
    $root = $script:EdtWtDefaultRoot
    $refBranch = $script:EdtWtDefaultRefBranch
    $worktree = Get-EdtWtProperty $cfg 'worktree'
    $root = Get-EdtWtProperty $worktree 'root_dir' $root
    $refBranch = Get-EdtWtProperty $worktree 'reference_branch' $refBranch
    return [PSCustomObject]@{
        Config          = $cfg
        RootDir         = ($root -replace '/', '\')
        ReferenceBranch = $refBranch
    }
}

function Save-EdtWtConfig {
    <#
    .SYNOPSIS
        Сохраняет конфигурацию пользователя в файл.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [string]$Path
    )

    $savePath = if ($Path) { $Path } else { Get-EdtWtUserConfigPath }

    $parentDir = Split-Path -Parent $savePath
    if (-not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    # Формируем структуру для сохранения
    $data = [ordered]@{
        paths    = [ordered]@{
            projects_root   = $Config.paths.projects_root
            worktree_root   = $Config.paths.worktree_root
            workspaces_root = $Config.paths.workspaces_root
        }
        edt      = [ordered]@{
            cli_path = $Config.defaults.'1cedtcli'
            jvm      = [ordered]@{
                max_heap     = (Get-EdtWtProperty (Get-EdtWtProperty $Config.defaults 'jvm') 'max_heap' '12g')
                gui_max_heap = (Get-EdtWtProperty (Get-EdtWtProperty $Config.defaults 'jvm') 'gui_max_heap' '8g')
                min_heap     = (Get-EdtWtProperty (Get-EdtWtProperty $Config.defaults 'jvm') 'min_heap' '2g')
            }
        }
        defaults = [ordered]@{
            reference_branch = (Get-EdtWtProperty $Config.defaults 'reference_branch' 'pre-prod')
            edt_prefs_source = (Get-EdtWtProperty $Config.defaults 'edt_prefs_source' '')
        }
    }

    $json = ConvertTo-Json -InputObject $data -Depth 5
    Set-Content -LiteralPath $savePath -Value $json -Encoding UTF8
    return $savePath
}
