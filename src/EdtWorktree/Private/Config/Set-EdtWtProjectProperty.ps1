function Set-EdtWtProjectProperty {
    <# Записывает ключ в определение проекта, даже если его там не было (StrictMode); остальные ключи не трогает. #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Def,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Value
    )

    Add-Member -InputObject $Def -MemberType NoteProperty -Name $Name -Value $Value -Force
}
