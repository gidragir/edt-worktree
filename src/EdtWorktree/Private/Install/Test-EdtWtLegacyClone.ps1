function Test-EdtWtLegacyClone {
    <#
      Корень клона EdtWorktree (установка 3.0 или клон разработчика): .git и манифест
      в корне либо (после git pull) в src\EdtWorktree. Посторонние репозитории
      (например, dotfiles в профиле) сюда не попадают.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath (Join-Path $Path '.git'))) { return $false }
    return (Test-Path -LiteralPath (Join-Path $Path 'EdtWorktree.psd1')) -or
        (Test-Path -LiteralPath (Join-Path $Path 'src\EdtWorktree\EdtWorktree.psd1'))
}