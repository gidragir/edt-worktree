function Remove-EdtWtShim {
    <#
      Удаляет файлы shim и каталог (если он пуст), убирает каталог из PATH
      (пользователя - если не EDT_PATH_SCOPE=Process - и процесса).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $dir = Get-EdtWtShimDir
    foreach ($name in 'edt.cmd', 'edt.ps1') {
        Remove-Item -LiteralPath (Join-Path $dir $name) -Force -ErrorAction SilentlyContinue
    }
    if ((Test-Path -LiteralPath $dir -PathType Container) -and -not (Get-ChildItem -LiteralPath $dir -Force)) {
        Remove-Item -LiteralPath $dir -Force
    }
    if ($env:EDT_PATH_SCOPE -ne 'Process') {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($userPath) {
            $newUser = Remove-EdtWtPathEntry -PathValue $userPath -Entry $dir
            if ($newUser -ne $userPath) { [Environment]::SetEnvironmentVariable('Path', $newUser, 'User') }
        }
    }
    $env:Path = Remove-EdtWtPathEntry -PathValue $env:Path -Entry $dir
}
