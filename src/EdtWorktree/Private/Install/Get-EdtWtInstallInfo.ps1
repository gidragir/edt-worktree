function Get-EdtWtInstallInfo {
    <#
      Раскладка установки: ссылка модуля в Documents\PowerShell\Modules (корень
      переопределяется EDT_MODULES_DIR), каталог установки (цель junction/symlink или
      сам каталог модуля, если это копия), bin и каталог конфигурации.
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

    $installDir = $null
    $viaLink = $false
    $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    if ($item) {
        $viaLink = $true
        if ($item.LinkType -and $item.Target) { $installDir = @($item.Target)[0] } else { $installDir = $link }
    } else {
        $installDir = $script:EdtWtModuleRoot
    }

    return [PSCustomObject]@{
        ModuleLink = $link
        InstallDir = $installDir
        ViaLink    = $viaLink
        BinDir     = Join-Path $installDir 'bin'
        ConfigDir  = Split-Path -Parent (Get-EdtWtUserConfigPath)
    }
}
