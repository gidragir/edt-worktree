function Get-EdtWtWorkspaceProcesses {
    <#
      Процессы, занимающие рабочую область: EDT держит .metadata/.lock, поэтому
      headless-импорт при запущенной IDE невозможен. Совпадение - по значению -data
      (равенство нормализованных путей), а не по подстроке.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$WorkspaceDir,
        [switch]$IncludeHeadless
    )

    $names = @('1cedt.exe', '1cedtc.exe', 'javaw.exe', 'java.exe')
    if ($IncludeHeadless) { $names += '1cedtcli.exe' }

    $filter = ($names | ForEach-Object { "Name = '$_'" }) -join ' OR '

    return @(Get-CimInstance -ClassName Win32_Process -Filter $filter -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and (Test-EdtWtProcessOnWorkspace -CommandLine $_.CommandLine -WorkspaceDir $WorkspaceDir) })
}
