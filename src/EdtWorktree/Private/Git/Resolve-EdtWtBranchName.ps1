function Resolve-EdtWtBranchName {
    <#
      Полное имя ветки: имя со слешем (feature/TASK-1, bugfix/x) остаётся как
      есть, короткое (TASK-1) дополняется префиксом git.branch_prefix.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prefix
    )

    if ($Name.Contains('/')) { return $Name }
    return $Prefix + $Name
}
