function ConvertTo-EdtWtSafeName {
    param([Parameter(Mandatory)][string]$Name)
    $sanitized = $Name
    foreach ($ch in @('/', '\', ':', '*', '?', '"', '<', '>', '|')) {
        $sanitized = $sanitized.Replace($ch, '-')
    }
    return $sanitized.Trim('-')
}
