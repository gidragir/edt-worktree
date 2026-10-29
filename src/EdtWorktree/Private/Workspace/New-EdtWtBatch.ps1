function New-EdtWtBatch {
    <#
      Builder батча для 1cedtcli. Команды собираются как значение, поэтому их
      можно напечатать под -WhatIf и сравнить в тесте, не запуская EDT.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $batch = [PSCustomObject]@{
        Commands = [System.Collections.Generic.List[string]]::new()
    }

    $batch | Add-Member -MemberType ScriptMethod -Name AddImport -Value {
        param([Parameter(Mandatory)][string]$ProjectDir)
        $this.Commands.Add("import --project `"$($ProjectDir.Replace('\', '/'))`"")
        return $this
    }

    $batch | Add-Member -MemberType ScriptMethod -Name AddExport -Value {
        param(
            [Parameter(Mandatory)][string]$ProjectDir,
            [Parameter(Mandatory)][string]$ConfigurationFiles
        )
        $this.Commands.Add("export --project `"$($ProjectDir.Replace('\', '/'))`" --configuration-files `"$($ConfigurationFiles.Replace('\', '/'))`"")
        return $this
    }

    $batch | Add-Member -MemberType ScriptMethod -Name AddBuild -Value {
        # Без имён 1cedtcli собирает все проекты рабочей области (help build).
        $this.Commands.Add('build --yes true')
        return $this
    }

    $batch | Add-Member -MemberType ScriptMethod -Name AddValidate -Value {
        param(
            [Parameter(Mandatory)][string[]]$ProjectNames,
            [Parameter(Mandatory)][string]$ResultFile
        )
        # Список - в [] через пробел (1cedtcli -command help validate); через запятую
        # 1cedtcli ищет один проект с именем "cf,cfe" и падает.
        $names = ($ProjectNames | ForEach-Object { "`"$_`"" }) -join ' '
        $this.Commands.Add("validate --file `"$($ResultFile.Replace('\', '/'))`" --project-name-list [$names]")
        return $this
    }

    $batch | Add-Member -MemberType ScriptMethod -Name IsEmpty -Value {
        return $this.Commands.Count -eq 0
    }

    $batch | Add-Member -MemberType ScriptMethod -Name ToArray -Value {
        return , $this.Commands.ToArray()
    }

    $batch | Add-Member -MemberType ScriptMethod -Name Print -Value {
        foreach ($c in $this.Commands) {
            Write-Host "       $c" -ForegroundColor DarkGray
        }
    }

    return $batch
}
