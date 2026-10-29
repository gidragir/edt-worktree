function Get-EdtWtProjectDef {
    <#
      Описание зарегистрированного проекта из конфига.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][string]$Name
    )

    $projects = Get-EdtWtProperty $Config 'projects'
    if ($null -eq $projects -or $null -eq $projects.PSObject.Properties[$Name]) {
        throw "Проект '$Name' не зарегистрирован. Зарегистрируйте: edt project add $Name"
    }
    return $projects.$Name
}
