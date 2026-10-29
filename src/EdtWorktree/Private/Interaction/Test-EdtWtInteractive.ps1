function Test-EdtWtInteractive {
    <#
      Истина, когда есть живой пользователь: консольный хост, ввод не перенаправлен.
      Скрипты, CI и вызовы из тестов получают ложь и обходятся без вопросов.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    return ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and $Host.Name -eq 'ConsoleHost')
}
