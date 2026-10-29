function Invoke-EdtWtVrunner {
    <#
      Запускает vrunner в текущем worktree с рабочей областью EDT этого worktree.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][string[]]$Arguments = @()
    )

    $context = Get-EdtWtContext
    $preset = @(Get-ChildItem Env: | Where-Object { $_.Name -like 'VRUNNER_EDT_*' } | Select-Object -ExpandProperty Name)
    $plan = Resolve-EdtWtVrunnerPlan -Context $context -Arguments $Arguments -PresetEnv $preset

    foreach ($note in $plan.Notes) { Write-Host "    -> $note" -ForegroundColor Gray }

    Push-Location -LiteralPath $plan.WorkingDirectory
    try {
        foreach ($name in $plan.Env.Keys) { Set-Item -Path "Env:$name" -Value $plan.Env[$name] }
        & vrunner @($plan.Arguments) | Out-Host
    } finally {
        foreach ($name in $plan.Env.Keys) { Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue }
        Pop-Location
    }
}
