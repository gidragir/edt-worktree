# Общие помощники тестов. Подключаются точечно: . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
# Тесты не должны трогать реальный конфиг пользователя: любой тест, загружающий
# модуль, вызывает Use-EdtWtTestConfig с временным каталогом.

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
