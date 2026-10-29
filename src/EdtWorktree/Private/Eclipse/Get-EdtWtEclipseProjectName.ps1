function Get-EdtWtEclipseProjectName {
    param([Parameter(Mandatory)][string]$ProjectDir)

    $dotProject = Join-Path $ProjectDir ".project"
    if (Test-Path -LiteralPath $dotProject) {
        try {
            [xml]$x = Get-Content -Raw -LiteralPath $dotProject -Encoding UTF8
            $name = $x.projectDescription.name
            if ($name) { return $name.Trim() }
        } catch {
            Write-Verbose "Не удалось прочитать $dotProject, имя берётся по каталогу: $($_.Exception.Message)"
        }
    }
    return (Split-Path -Leaf $ProjectDir)
}
