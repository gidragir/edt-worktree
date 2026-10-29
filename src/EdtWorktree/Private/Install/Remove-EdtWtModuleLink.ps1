function Remove-EdtWtModuleLink {
    <#
      Удаляет ссылку модуля. Для junction/symlink удаляется только сама ссылка
      (нерекурсивное Directory.Delete), цель не затрагивается. Remove-Item -Recurse
      по ссылке не используется: в части версий PowerShell он заходит в цель.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return }
    $isLink = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    if ($isLink) {
        [System.IO.Directory]::Delete($Path)
    } else {
        # Копия модуля: обычный каталог.
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}
