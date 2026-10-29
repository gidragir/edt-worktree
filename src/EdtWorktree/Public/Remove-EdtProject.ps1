function Remove-EdtProject {
    <#
    .SYNOPSIS
        Убирает проект из конфига.
    .DESCRIPTION
        Клон, рабочие области и эталон на диске не затрагиваются.
    .PARAMETER Name
        Имя зарегистрированного проекта.
    .EXAMPLE
        Remove-EdtProject ka
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name
    )

    $cfg = Get-EdtWtConfig
    Get-EdtWtProjectDef -Config $cfg -Name $Name | Out-Null

    if ($PSCmdlet.ShouldProcess($Name, 'Убрать проект из конфига (файлы не удаляются)')) {
        $cfg.projects.PSObject.Properties.Remove($Name)
        Save-EdtWtConfig -Config $cfg | Out-Null
        Write-Host "✓ Проект '$Name' убран из конфига; файлы не тронуты." -ForegroundColor Green
    }
}
