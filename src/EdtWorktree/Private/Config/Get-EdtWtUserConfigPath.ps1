function Get-EdtWtUserConfigPath {
    <#
      Путь к config.json: EDT_CONFIG_PATH, иначе %APPDATA%\EdtWorktree\config.json.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($env:EDT_CONFIG_PATH) { return $env:EDT_CONFIG_PATH }
    return (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'EdtWorktree\config.json')
}
