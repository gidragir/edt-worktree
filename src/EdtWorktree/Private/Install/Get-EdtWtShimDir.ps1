function Get-EdtWtShimDir {
    <#
      Каталог постоянного shim: не зависит от версии модуля и каталога установки.
      EDT_SHIM_DIR переопределяет (тесты), иначе %LOCALAPPDATA%\Programs\EdtWorktree\bin.
      Не %LOCALAPPDATA%\EdtWorktree\bin: там клон установки 3.0 с отслеживаемыми bin\edt.*.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($env:EDT_SHIM_DIR) { return $env:EDT_SHIM_DIR }
    return Join-Path $env:LOCALAPPDATA 'Programs\EdtWorktree\bin'
}
