function Get-EdtWtExtensionNames {
    <# Имена (папки) рабочих расширений проекта из Context.Extensions (пути относительно клона). #>
    [OutputType([string[]])]
    param([Parameter(Mandatory)]$Context)

    return [string[]]@(@($Context.Extensions) | Where-Object { $_ } | ForEach-Object { Split-Path -Leaf $_ })
}
