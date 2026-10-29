function Merge-EdtWtConfigObject {
    <#
      Глубокое слияние: значения Override ложатся поверх Base, неизвестные ключи
      сохраняются. Явный null в Override не затирает непустое значение Base.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Base,
        [PSCustomObject]$Override
    )

    if ($null -eq $Override) { return $Base }

    foreach ($prop in $Override.PSObject.Properties) {
        $existing = $Base.PSObject.Properties[$prop.Name]
        if ($null -eq $existing) {
            Add-Member -InputObject $Base -MemberType NoteProperty -Name $prop.Name -Value $prop.Value
            continue
        }
        # "x" -is [PSCustomObject] истинно для строки, обёрнутой в PSObject (например, результат
        # Join-Path), и тогда слияние лезет в её свойство Length: смотрим на базовый объект.
        if ($null -ne $prop.Value -and $null -ne $existing.Value -and
            $prop.Value.PSObject.BaseObject -is [System.Management.Automation.PSCustomObject] -and
            $existing.Value.PSObject.BaseObject -is [System.Management.Automation.PSCustomObject]) {
            $existing.Value = Merge-EdtWtConfigObject -Base $existing.Value -Override $prop.Value
            continue
        }
        if ($null -eq $prop.Value -and $null -ne $existing.Value) { continue }
        $existing.Value = $prop.Value
    }
    return $Base
}
