function Get-EdtWtInstallInfo {
    <#
      Вид и раскладка установки.
        Dev     - ссылка модуля ведёт на <клон>\src\EdtWorktree (клон разработчика, есть .git).
        Legacy  - ссылка ведёт на корень клона 3.0 (в цели есть .git).
        Gallery - модуль этой версии установлен из PowerShell Gallery.
        Zip     - остальное (установщик из zip: обычный каталог в Modules).
      CloneDir задан только для Dev и Legacy. Корень Modules переопределяется
      EDT_MODULES_DIR.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $modulesDir = if ($env:EDT_MODULES_DIR) {
        $env:EDT_MODULES_DIR
    } else {
        Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules'
    }
    $link = Join-Path $modulesDir 'EdtWorktree'

    $mod = Get-Module -Name EdtWorktree | Select-Object -First 1
    $moduleBase = if ($mod) { $mod.ModuleBase } else { $script:EdtWtModuleRoot }
    $version = if ($mod) { $mod.Version.ToString() } else { $null }

    $kind = $null
    $cloneDir = $null
    $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $item.Target) {
        $target = [string]@($item.Target)[0]
        $trimmed = $target.TrimEnd('\', '/')
        $root = [IO.Path]::GetFullPath((Join-Path $trimmed '..\..'))
        if ($trimmed -like '*src\EdtWorktree' -and (Test-Path -LiteralPath (Join-Path $root '.git'))) {
            $kind = 'Dev'
            $cloneDir = $root
        } elseif (Test-Path -LiteralPath (Join-Path $trimmed '.git')) {
            $kind = 'Legacy'
            $cloneDir = $trimmed
        }
    }
    if (-not $kind) {
        $kind = if ($version -and (Get-EdtWtGalleryInstall -Version $version)) { 'Gallery' } else { 'Zip' }
    }

    return [PSCustomObject]@{
        Kind       = $kind
        ModuleBase = $moduleBase
        ModulesDir = $modulesDir
        ModuleLink = $link
        CloneDir   = $cloneDir
        ShimDir    = Get-EdtWtShimDir
        ConfigDir  = Split-Path -Parent (Get-EdtWtUserConfigPath)
    }
}