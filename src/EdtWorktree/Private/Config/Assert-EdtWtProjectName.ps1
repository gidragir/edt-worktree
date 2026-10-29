function Assert-EdtWtProjectName {
    <# Имя проекта - имя папки клона, не путь. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -match '[\\/:]' -or $Name -in @('.', '..')) {
        throw "Недопустимое имя проекта '$Name': это имя папки клона в repos_root, а не путь."
    }
}
