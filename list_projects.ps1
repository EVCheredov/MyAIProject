$token='tstmt_Bd33an40TaQ6iBIzbkyzjzp2eEcij1K5uw1793565758'
$headers = @{'Authorization' = "Bearer $token"}
$url = "https://app.testomat.io/api/v1/projects"
try {
    $resp = Invoke-RestMethod -Method Get -Uri $url -Headers $headers -ErrorAction Stop
    Write-Host "Projects list received:"
    $resp | ConvertTo-Json -Depth 5
} catch {
    Write-Host "Error retrieving projects: $_"
}
