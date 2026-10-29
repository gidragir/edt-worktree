function Get-EdtWtGalleryInstall {
    <#
      Установлен ли модуль EdtWorktree этой версии из PowerShell Gallery.
      Сначала PSResourceGet (Get-InstalledPSResource), при его отсутствии - PowerShellGet
      (Get-InstalledModule). Любая ошибка даёт $false. Шов для моков в тестах.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Version)

    try {
        if (Get-Command -Name Get-InstalledPSResource -ErrorAction SilentlyContinue) {
            return [bool](Get-InstalledPSResource -Name EdtWorktree -Version $Version -ErrorAction Stop)
        }
        if (Get-Command -Name Get-InstalledModule -ErrorAction SilentlyContinue) {
            return [bool](Get-InstalledModule -Name EdtWorktree -RequiredVersion $Version -ErrorAction Stop)
        }
    } catch {
        return $false
    }
    return $false
}