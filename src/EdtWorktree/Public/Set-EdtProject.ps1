function Set-EdtProject {
    <#
    .SYNOPSIS
        Меняет эталонную ветку или конфигурацию проекта.
    .PARAMETER Name
        Имя зарегистрированного проекта.
    .PARAMETER RefBranch
        Новая эталонная ветка.
    .PARAMETER CfProject
        Конфигурация (папка или относительный путь), найденная в клоне.
    .EXAMPLE
        Set-EdtProject ka -RefBranch pre-prod
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [string]$RefBranch,
        [string]$CfProject
    )

    if (-not $RefBranch -and -not $CfProject) { throw 'Укажите -RefBranch <ветка> и/или -CfProject <путь>.' }

    $cfg = Get-EdtWtConfig
    $def = Get-EdtWtProjectDef -Config $cfg -Name $Name

    $cf = $null
    if ($CfProject) {
        $repo = Join-Path $cfg.paths.repos_root $Name
        if (-not (Test-Path -LiteralPath $repo)) { throw "Клон проекта '$Name' не найден: $repo." }
        $configs = @(Find-EdtWtEdtProjects -RepoPath $repo | Where-Object Kind -eq 'Configuration')
        $cf = Resolve-EdtWtExtensionRef -Found $configs -Ref $CfProject
    }

    $what = @()
    if ($RefBranch) { $what += "ветка $RefBranch" }
    if ($cf) { $what += "конфигурация $cf" }
    if ($PSCmdlet.ShouldProcess($Name, "Изменить: $($what -join ', ')")) {
        if ($RefBranch) { Set-EdtWtProjectProperty -Def $def -Name 'ref_branch' -Value $RefBranch }
        if ($cf) { Set-EdtWtProjectProperty -Def $def -Name 'cf_project' -Value $cf }
        Save-EdtWtConfig -Config $cfg | Out-Null
        Write-Host "✓ Проект '$Name' обновлён." -ForegroundColor Green
    }
}
