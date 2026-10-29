function Test-EdtWtReferenceFreshness {
    <#
      Сравнивает коммит, с которого собран эталон, с последним известным клону
      состоянием эталонной ветки на remote (без fetch). Отставший эталон или
      эталон без отметки сборки - предупреждение: ветке при первом открытии
      придётся досчитывать разницу. Возвращает число коммитов отставания
      (0 - актуален) или $null, если сравнить не с чем.
    #>
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]$Context,
        [switch]$Quiet
    )

    $stamp = Get-EdtWtReferenceStamp -WorkspaceDir $Context.ReferenceWsDir
    if (-not $stamp -or -not $stamp.commit) {
        if (-not $Quiet) {
            Write-Host "    [warn] У эталона нет отметки сборки (собран прежней версией): пересоберите его, edt warmup $($Context.ProjectId)" -ForegroundColor Yellow
        }
        return $null
    }

    $remote = Get-EdtWtProperty (Get-EdtWtConfig).git 'remote' 'origin'
    $behind = Invoke-EdtWtGit -C $Context.RepoPath rev-list --count "$($stamp.commit)..refs/remotes/$remote/$($Context.RefBranch)" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $behind) { return $null }

    $n = [int]$behind
    if ($n -gt 0 -and -not $Quiet) {
        $built = try { ([datetime]$stamp.built_at).ToString('dd.MM.yyyy HH:mm') } catch { $stamp.built_at }
        Write-Host "    [warn] Эталон собран $built и отстал от $remote/$($Context.RefBranch) на $n коммит(ов): обновите его, edt warmup $($Context.ProjectId)" -ForegroundColor Yellow
    }
    return $n
}
