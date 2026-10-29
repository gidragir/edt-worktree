function Get-EdtWtShimDir {
    <#
      Каталог постоянного shim: не зависит от версии модуля и каталога установки.
      EDT_SHIM_DIR переопределяет (тесты), иначе %LOCALAPPDATA%\EdtWorktree\bin.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($env:EDT_SHIM_DIR) { return $env:EDT_SHIM_DIR }
    return Join-Path $env:LOCALAPPDATA 'EdtWorktree\bin'
}
