function Test-EdtWtProcessOnWorkspace {
    <# Процесс работает на рабочей области: -data равен пути (нормализованное сравнение). #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowEmptyString()][AllowNull()][string]$CommandLine,
        [Parameter(Mandatory)][string]$WorkspaceDir
    )

    $data = Get-EdtWtDataArgument -CommandLine $CommandLine
    if (-not $data) { return $false }
    try { return (Test-EdtWtSamePath $data $WorkspaceDir) } catch { return $false }
}
