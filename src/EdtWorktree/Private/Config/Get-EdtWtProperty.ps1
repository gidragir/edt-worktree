# Безопасное чтение необязательного свойства из разобранного JSON.
# ConvertFrom-Json отдаёт PSCustomObject без отсутствующих ключей, поэтому в
# строгом режиме прямое обращение к ним - ошибка, а не $null. Все необязательные
# ключи projects.json читаются только через эту функцию.
function Get-EdtWtProperty {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        $InputObject,

        [Parameter(Position = 1, Mandatory)]
        [string]$Name,

        [Parameter(Position = 2)]
        $Default = $null
    )

    if ($null -eq $InputObject) { return $Default }
    if ($null -eq $InputObject.PSObject.Properties[$Name]) { return $Default }

    $value = $InputObject.$Name
    if ($null -eq $value) { return $Default }
    if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}
