# Общие помощники тестов. Подключаются точечно: . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
# Тесты не должны трогать реальный конфиг пользователя: любой тест, загружающий
# модуль, вызывает Use-EdtWtTestConfig с временным каталогом.

function Get-EdtWtTestRepoRoot {
    <# Корень репозитория (родитель каталога Tests). #>
    [OutputType([string])]
    param()

    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-EdtWtTestModulePath {
    <# Манифест тестируемого модуля: $env:EDT_TEST_MODULE, иначе src\EdtWorktree\EdtWorktree.psd1. #>
    [OutputType([string])]
    param()

    if ($env:EDT_TEST_MODULE) { return $env:EDT_TEST_MODULE }
    return Join-Path (Get-EdtWtTestRepoRoot) 'src\EdtWorktree\EdtWorktree.psd1'
}

function Get-EdtWtTestModuleRoot {
    <# Каталог тестируемого модуля (там лежат bin\ и манифест). #>
    [OutputType([string])]
    param()

    return Split-Path -Parent (Get-EdtWtTestModulePath)
}
function New-EdtWtTestRoot {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [OutputType([string])]
    param()

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('edtwt_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    return $root
}

function Use-EdtWtTestConfig {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Root)

    $path = Join-Path $Root 'config.json'
    $env:EDT_CONFIG_PATH = $path
    # Старый конфиг (Task 2) тоже уводим во временный каталог.
    $env:EDT_LEGACY_CONFIG_PATH = Join-Path $Root 'legacy-projects.json'
    return $path
}

function Enter-EdtWtTestConfig {
    <# Создаёт временный корень, уводит в него конфиг; возвращает состояние для Exit-EdtWtTestConfig. #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [OutputType([PSCustomObject])]
    param()

    $state = [PSCustomObject]@{
        Root       = New-EdtWtTestRoot
        Path       = $null
        PrevConfig = $env:EDT_CONFIG_PATH
        PrevLegacy = $env:EDT_LEGACY_CONFIG_PATH
    }
    $state.Path = Use-EdtWtTestConfig -Root $state.Root
    return $state
}

function Exit-EdtWtTestConfig {
    <# Восстанавливает прежние EDT_CONFIG_PATH / EDT_LEGACY_CONFIG_PATH и удаляет временный корень. #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param([Parameter(Mandatory)][PSCustomObject]$State)

    $env:EDT_CONFIG_PATH = $State.PrevConfig
    $env:EDT_LEGACY_CONFIG_PATH = $State.PrevLegacy
    if (Test-Path -LiteralPath $State.Root) {
        Remove-Item -LiteralPath $State.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-EdtWtTestRepo {
    <# Тестовый git-репозиторий с EDT-проектами во временном корне (git вызывается напрямую - только тестовый помощник). #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Name,
        [string]$Branch = 'main',
        [hashtable]$Projects = @{},
        [switch]$WithRemote
    )

    $natures = @{
        Configuration = 'com._1c.g5.v8.dt.core.V8ConfigurationNature'
        Extension     = 'com._1c.g5.v8.dt.core.V8ExtensionNature'
    }
    $repo = Join-Path $Root $Name
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    # Подписи и хуки пользователя не должны влиять на фикстуру; ошибка git - ошибка теста.
    $noHooks = Join-Path $Root '.no-hooks'
    $git = {
        $out = & git -c user.name=test -c user.email=test@example.com -c core.autocrlf=false -c commit.gpgsign=false -c "core.hooksPath=$noHooks" -C $repo @args 2>&1
        if ($LASTEXITCODE -ne 0) { throw "git $args завершился с кодом ${LASTEXITCODE}: $out" }
    }

    & $git init -q -b $Branch
    foreach ($rel in $Projects.Keys) {
        $dir = Join-Path $repo $rel
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $projName = Split-Path $rel -Leaf
        $xml = "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n<projectDescription>`n`t<name>$projName</name>`n`t<natures>`n`t`t<nature>$($natures[$Projects[$rel]])</nature>`n`t</natures>`n</projectDescription>`n"
        [System.IO.File]::WriteAllText((Join-Path $dir '.project'), $xml, [System.Text.UTF8Encoding]::new($false))
    }
    [System.IO.File]::WriteAllText((Join-Path $repo 'README.md'), "test`n", [System.Text.UTF8Encoding]::new($false))
    & $git add -A
    & $git commit -q -m 'init'

    $remote = $null
    if ($WithRemote) {
        $remote = Join-Path $Root "$Name.git"
        $out = & git init -q --bare -b $Branch $remote 2>&1
        if ($LASTEXITCODE -ne 0) { throw "git init --bare завершился с кодом ${LASTEXITCODE}: $out" }
        & $git remote add origin $remote
        & $git push -q -u origin $Branch
    }
    return [pscustomobject]@{ RepoPath = $repo; RemotePath = $remote }
}
