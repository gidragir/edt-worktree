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
