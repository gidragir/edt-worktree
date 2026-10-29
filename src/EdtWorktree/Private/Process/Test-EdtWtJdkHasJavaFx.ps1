function Test-EdtWtJdkHasJavaFx {
    <#
      JDK подходит для GUI EDT: версия 17+ (по файлу release) и есть JavaFX.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$JdkHome)

    $fx = (Test-Path -LiteralPath (Join-Path $JdkHome 'jmods\javafx.base.jmod')) -or
          (Test-Path -LiteralPath (Join-Path $JdkHome 'lib\javafx-swt.jar'))
    if (-not $fx) { return $false }

    $release = Join-Path $JdkHome 'release'
    if (-not (Test-Path -LiteralPath $release)) { return $false }
    $line = Get-Content -LiteralPath $release -ErrorAction SilentlyContinue | Where-Object { $_ -match '^JAVA_VERSION=' } | Select-Object -First 1
    if ($line -notmatch 'JAVA_VERSION="?(\d+)') { return $false }
    return ([int]$Matches[1] -ge 17)
}
