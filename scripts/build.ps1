#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Собирает выпуск модуля EdtWorktree: однофайловый psm1, zip и установщик.

.DESCRIPTION
    Из src\EdtWorktree\ (по файлу на функцию) делает out\EdtWorktree\<версия>\ с одним
    EdtWorktree.psm1, затем упаковывает его в out\EdtWorktree.zip и кладёт рядом install.ps1.

        pwsh -NoProfile -File scripts/build.ps1

.PARAMETER OutputDir
    Каталог сборки, по умолчанию <репозиторий>\out. Перед сборкой очищается.

.PARAMETER SourceDir
    Каталог исходников модуля (нужен тестам), по умолчанию <репозиторий>\src\EdtWorktree.

.PARAMETER ChangelogPath
    Путь к CHANGELOG.md (нужен тестам), по умолчанию <репозиторий>\CHANGELOG.md.

.PARAMETER Release
    Требует в CHANGELOG.md раздел [<версия>] и пишет его тело в release-notes.md.

.OUTPUTS
    PSCustomObject: Version, ModuleDir, ZipPath, InstallerPath, ReleaseNotesPath.
#>
[CmdletBinding()]
param(
    [string]$OutputDir,
    [string]$SourceDir,
    [string]$ChangelogPath,
    [switch]$Release
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDir) { $OutputDir = Join-Path $repoRoot 'out' }
if (-not $SourceDir) { $SourceDir = Join-Path $repoRoot 'src\EdtWorktree' }
if (-not $ChangelogPath) { $ChangelogPath = Join-Path $repoRoot 'CHANGELOG.md' }
$OutputDir = [IO.Path]::GetFullPath($OutputDir)
$SourceDir = [IO.Path]::GetFullPath($SourceDir)

$srcManifest = Join-Path $SourceDir 'EdtWorktree.psd1'
$version = [string](Import-PowerShellDataFile -LiteralPath $srcManifest).ModuleVersion
$utf8Bom = [Text.UTF8Encoding]::new($true)

# Заметки выпуска проверяем до сборки: без раздела в CHANGELOG выпуск не нужен.
$notes = $null
if ($Release) {
    $changelog = if (Test-Path -LiteralPath $ChangelogPath) { [IO.File]::ReadAllText($ChangelogPath) } else { '' }
    $pattern = '(?ms)^## \[' + [regex]::Escape($version) + '\][^\r\n]*\r?\n(?<body>.*?)(?=^## \[|\z)'
    $m = [regex]::Match($changelog, $pattern)
    if (-not $m.Success) { throw "В CHANGELOG.md нет раздела [$version]" }
    $notes = $m.Groups['body'].Value.Trim() + "`n"
}

Write-Host "==> Сборка EdtWorktree $version" -ForegroundColor Cyan
if (Test-Path -LiteralPath $OutputDir) { Remove-Item -LiteralPath $OutputDir -Recurse -Force }
$moduleDir = Join-Path $OutputDir "EdtWorktree\$version"
New-Item -ItemType Directory -Path $moduleDir -Force | Out-Null

# Склейка: блок между маркерами заменяется содержимым файлов функций.
$psm1Text = [IO.File]::ReadAllText((Join-Path $SourceDir 'EdtWorktree.psm1'))
$markerPattern = '(?s)(?<open>^[ \t]*# <build:files>[^\r\n]*\r?\n).*?(?<close>^[ \t]*# </build:files>)'
$marker = [regex]::Match($psm1Text, $markerPattern, 'Multiline')
if (-not $marker.Success) { throw 'В EdtWorktree.psm1 нет маркеров # <build:files> ... # </build:files>' }

$parts = foreach ($dir in 'Private', 'Public', 'Completers') {
    $dirPath = Join-Path $SourceDir $dir
    if (-not (Test-Path -LiteralPath $dirPath)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $dirPath -Recurse -File -Filter *.ps1 | Sort-Object FullName) {
        if ($file.Extension -ne '.ps1') { continue }
        $relative = $file.FullName.Substring($SourceDir.Length).TrimStart('\', '/')
        # ReadAllText снимает BOM; конец файла приводим к одному переводу строки,
        # чтобы файл без завершающего \n не склеился со строкой '# endregion'.
        $body = [IO.File]::ReadAllText($file.FullName).TrimEnd("`r", "`n")
        "# region $relative`n$body`n# endregion`n"
    }
}
$combined = $parts -join "`n"
$built = $psm1Text.Substring(0, $marker.Index) +
    $marker.Groups['open'].Value + $combined + "`n" +
    $marker.Groups['close'].Value +
    $psm1Text.Substring($marker.Index + $marker.Length)
$builtPsm1 = Join-Path $moduleDir 'EdtWorktree.psm1'
[IO.File]::WriteAllText($builtPsm1, $built, $utf8Bom)

# Остальное содержимое модуля копируется как есть.
Copy-Item -LiteralPath $srcManifest -Destination $moduleDir
$format = Join-Path $SourceDir 'EdtWorktree.format.ps1xml'
if (Test-Path -LiteralPath $format) { Copy-Item -LiteralPath $format -Destination $moduleDir }
$binDir = Join-Path $SourceDir 'bin'
if (Test-Path -LiteralPath $binDir) { Copy-Item -LiteralPath $binDir -Destination $moduleDir -Recurse }

# Проверки сборки.
foreach ($f in Get-ChildItem -LiteralPath $moduleDir -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.psm1' }) {
    $head = [byte[]]::new(3)
    $stream = [IO.File]::OpenRead($f.FullName)
    try { $null = $stream.Read($head, 0, 3) } finally { $stream.Dispose() }
    if (($head -join ',') -ne '239,187,191') {
        throw "Файл выпуска без BOM: $($f.FullName.Substring($moduleDir.Length).TrimStart('\'))"
    }
}

$builtManifest = Join-Path $moduleDir 'EdtWorktree.psd1'
try {
    Test-ModuleManifest -Path $builtManifest -ErrorAction Stop | Out-Null
} catch {
    throw "Манифест выпуска не проходит Test-ModuleManifest: $($_.Exception.Message)"
}

$probe = {
    param($Manifest)
    $ErrorActionPreference = 'Stop'
    $env:EDT_CONFIG_PATH = Join-Path ([IO.Path]::GetTempPath()) 'edtwt-build-probe\config.json'
    $m = Import-Module $Manifest -Force -PassThru
    ConvertTo-Json -Compress -InputObject @{
        Functions = @($m.ExportedFunctions.Keys | Sort-Object)
        Aliases   = @($m.ExportedAliases.Keys | Sort-Object)
    }
}
$pwsh = (Get-Process -Id $PID).Path
function Get-ModuleExportSet([string]$Manifest) {
    $json = & $pwsh -NoProfile -Command $probe -args $Manifest
    if ($LASTEXITCODE -ne 0) { throw "Не удалось импортировать $Manifest в дочернем pwsh: $json" }
    return ($json | Select-Object -Last 1 | ConvertFrom-Json)
}
$srcSet = Get-ModuleExportSet $srcManifest
$outSet = Get-ModuleExportSet $builtManifest
foreach ($kind in 'Functions', 'Aliases') {
    $diff = Compare-Object @($srcSet.$kind) @($outSet.$kind)
    if ($diff) {
        throw "Экспорт ($kind) собранного модуля отличается от src: $(($diff | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join ', ')"
    }
}

# Активы выпуска: постоянные имена, чтобы работал адрес latest/download/<имя>.
$zipPath = Join-Path $OutputDir 'EdtWorktree.zip'
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $OutputDir 'EdtWorktree'), $zipPath,
    [IO.Compression.CompressionLevel]::Optimal, $true)

$installerPath = Join-Path $OutputDir 'install.ps1'
Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\install.ps1') -Destination $installerPath

$notesPath = $null
if ($Release) {
    $notesPath = Join-Path $OutputDir 'release-notes.md'
    [IO.File]::WriteAllText($notesPath, $notes, [Text.UTF8Encoding]::new($false))
}

Write-Host "    $moduleDir" -ForegroundColor Green
[PSCustomObject]@{
    Version          = $version
    ModuleDir        = $moduleDir
    ZipPath          = $zipPath
    InstallerPath    = $installerPath
    ReleaseNotesPath = $notesPath
}
