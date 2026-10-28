# ==============================================================================
# Configuration.ps1 - Конфигурация v3: дефолты, чтение, сохранение, реестр проектов
# ==============================================================================

Set-StrictMode -Version Latest

# ------------------------------------------------------------------------------
# 1. Константы модуля
# ------------------------------------------------------------------------------
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

    $originUrl = (Invoke-EdtWtGit config --get remote.origin.url 2>$null)
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
# 2. Конфиг v3: путь, дефолты, чтение и сохранение
# ------------------------------------------------------------------------------

function Get-EdtWtUserConfigPath {
    <#
      Путь к config.json: EDT_CONFIG_PATH, иначе %APPDATA%\EdtWorktree\config.json.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($env:EDT_CONFIG_PATH) { return $env:EDT_CONFIG_PATH }
    return (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'EdtWorktree\config.json')
}

function New-EdtWtDefaultConfig {
    <#
      Схема конфига v3 (spec 5.1) со значениями по умолчанию. null означает
      «определять автоматически при каждом запуске».
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $profileDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    $pick = {
        param($Preferred, $Fallback)
        if (Test-Path -LiteralPath $Preferred) { $Preferred } else { $Fallback }
    }

    return [PSCustomObject]@{
        version  = 3
        paths    = [PSCustomObject]@{
            repos_root      = & $pick 'D:\projects\default' (Join-Path $profileDir 'projects')
            worktrees_root  = & $pick 'D:\projects\worktree' (Join-Path $profileDir 'projects\worktree')
            workspaces_root = & $pick 'D:\workspaces\worktree' (Join-Path $profileDir 'edt-workspaces')
        }
        edt      = [PSCustomObject]@{
            cli_path     = $null
            vm_path      = $null
            prefs_source = $null
            max_heap     = $null
            gui_max_heap = $null
            extra_vmargs = ''
            timeout_sec  = 7200
        }
        git      = [PSCustomObject]@{
            remote        = 'origin'
            branch_prefix = 'feature/'
        }
        projects = [PSCustomObject]@{}
    }
}

function Merge-EdtWtConfigObject {
    <#
      Глубокое слияние: значения Override ложатся поверх Base, неизвестные ключи
      сохраняются. Явный null в Override не затирает непустое значение Base.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Base,
        [PSCustomObject]$Override
    )

    if ($null -eq $Override) { return $Base }

    foreach ($prop in $Override.PSObject.Properties) {
        $existing = $Base.PSObject.Properties[$prop.Name]
        if ($null -eq $existing) {
            Add-Member -InputObject $Base -MemberType NoteProperty -Name $prop.Name -Value $prop.Value
            continue
        }
        if ($prop.Value -is [PSCustomObject] -and $existing.Value -is [PSCustomObject]) {
            $existing.Value = Merge-EdtWtConfigObject -Base $existing.Value -Override $prop.Value
            continue
        }
        if ($null -eq $prop.Value -and $null -ne $existing.Value) { continue }
        $existing.Value = $prop.Value
    }
    return $Base
}

function Invoke-EdtWtConfigMigration {
    <#
      Заглушка до Task 2: миграции с 2.x пока нет, конфиг не найден.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    return $null
}

function Get-EdtWtConfig {
    <#
      Конфиг v3. Файл есть - его JSON поверх дефолтов. Файла нет - миграция с 2.x
      (если нашлось что переносить), иначе дефолты без записи на диск.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $path = Get-EdtWtUserConfigPath
    $config = New-EdtWtDefaultConfig

    if (-not (Test-Path -LiteralPath $path)) {
        $migrated = Invoke-EdtWtConfigMigration
        if ($null -eq $migrated) { return $config }
        return (Merge-EdtWtConfigObject -Base $config -Override $migrated)
    }

    $userJson = $null
    $problem = $null
    try {
        $raw = Get-Content -Raw -LiteralPath $path -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $userJson = $raw | ConvertFrom-Json -NoEnumerate -ErrorAction Stop
            if ($null -eq $userJson -or $userJson.GetType().FullName -ne 'System.Management.Automation.PSCustomObject') { $problem = 'корнем конфига должен быть JSON-объект' }
        }
    } catch {
        $problem = $_.Exception.Message
    }
    if ($problem) {
        throw "Конфиг повреждён: ${path}: $problem. Исправьте файл или удалите его и выполните edt setup."
    }

    if ($null -eq $userJson) { return $config }
    return (Merge-EdtWtConfigObject -Base $config -Override $userJson)
}

function Save-EdtWtConfig {
    <#
      Пишет схему целиком (дефолты + переданный объект), UTF-8 без BOM:
      сначала во временный файл, затем подмена исходного.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config
    )

    $path = Get-EdtWtUserConfigPath
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $full = Merge-EdtWtConfigObject -Base (New-EdtWtDefaultConfig) -Override $Config
    $json = ConvertTo-Json -InputObject $full -Depth 10

    $tmp = "$path.tmp"
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $path -Force
    return $path
}

function Get-EdtWtProjectDef {
    <#
      Описание зарегистрированного проекта из конфига.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][string]$Name
    )

    $projects = Get-EdtWtProperty $Config 'projects'
    if ($null -eq $projects -or $null -eq $projects.PSObject.Properties[$Name]) {
        throw "Проект '$Name' не зарегистрирован. Зарегистрируйте: edt project add $Name"
    }
    return $projects.$Name
}
