function Get-EdtWtWorkspaceTitle {
    <#
      Формирует заголовок рабочей области для EDT по шаблону:
      <проект>-<тикет без указания feature>.
      Для эталона (_reference) используется <проект>-<ref_branch>.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$Context,
        [string]$WorkspaceDir
    )

    $project = [string](Get-EdtWtProperty $Context 'ProjectId' '')
    $wsDir = if ($WorkspaceDir) { $WorkspaceDir } else { [string](Get-EdtWtProperty $Context 'WorkspaceDir' '') }
    $isRef = $wsDir -and ((Split-Path -Leaf $wsDir) -in '_reference', '_reference.building')

    $raw = if ($isRef) {
        [string](Get-EdtWtProperty $Context 'RefBranch' '')
    } else {
        $b = [string](Get-EdtWtProperty $Context 'Branch' '')
        if ($b -and $b -ne 'HEAD') {
            $b
        } else {
            [string](Get-EdtWtProperty $Context 'WorktreeId' '')
        }
    }

    $ticket = $raw -replace '(?i)^feature[/\-_]?', ''
    if ($ticket.Contains('/')) {
        $ticket = $ticket -replace '/', '-'
    }
    $ticket = $ticket.Trim('-')

    if (-not $ticket) {
        return $project
    }
    if (-not $project) {
        return $ticket
    }
    return "$project-$ticket"
}
