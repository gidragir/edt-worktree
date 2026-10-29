function Test-EdtWtDirtyWorkTree {
    <#
      Состояние рабочего дерева git (только чтение): 'clean' (или это не git-каталог),
      'dirty' (есть незафиксированные изменения) или 'unverified' (.git есть, но git
      недоступен или status завершился ошибкой). Проверка закрывается в сторону отказа:
      при неопределённости каталог считается занятым.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath (Join-Path $Path '.git'))) { return 'clean' }
    if (-not (Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue)) { return 'unverified' }
    try {
        $global:LASTEXITCODE = 0
        $out = Invoke-EdtWtGit -C $Path status --porcelain 2>$null
        if ($LASTEXITCODE -ne 0) { return 'unverified' }
    } catch {
        return 'unverified'
    }
    if ($out) { return 'dirty' }
    return 'clean'
}
