# ==============================================================================
# Interaction.ps1 - Диалог с пользователем
# ==============================================================================

Set-StrictMode -Version Latest

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

function Read-EdtWtAnswer {
    <#
      Задаёт вопрос и возвращает ответ. Пустой ответ означает значение по умолчанию.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Default
    )

    $suffix = if ($Default) { " [$Default]" } else { '' }
    $answer = Read-Host "$Prompt$suffix"
    if ($null -eq $answer -or [string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim()
}
