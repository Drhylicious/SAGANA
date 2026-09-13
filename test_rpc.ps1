 $url = 'https://nitqahryddbojbmprpmo.supabase.co/rest/v1/rpc/admin_reset_user_password'
 $headers = @{
   apikey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5pdHFhaHJ5ZGRib2pibXBycG1vIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0MDQ4ODMsImV4cCI6MjA5Mzk4MDg4M30.hi1-5w4v6JY4D-4_XjO4WGcrJo8EhqewkydigiQhuHM'
   Authorization = 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5pdHFhaHJ5ZGRib2pibXBycG1vIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0MDQ4ODMsImV4cCI6MjA5Mzk4MDg4M30.hi1-5w4v6JY4D-4_XjO4WGcrJo8EhqewkydigiQhuHM'
 }
 $body = '{"p_user_id":"00000000-0000-0000-0000-000000000000"}'
try {
  $response = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -Body $body -ContentType 'application/json' -UseBasicParsing
  Write-Host 'SUCCESS'
  Write-Host $response.StatusCode
  Write-Host $response.Content
} catch {
  Write-Host 'ERROR'
  if ($_.Exception.Response -ne $null) {
    $resp = $_.Exception.Response
    Write-Host $resp.StatusCode.Value__
    Write-Host $resp.StatusDescription
    try {
      $stream = $resp.GetResponseStream()
      $reader = New-Object System.IO.StreamReader($stream)
      Write-Host $reader.ReadToEnd()
    } catch {
      Write-Host 'Unable to read response body.'
    }
  } else {
    Write-Host $_.Exception.Message
  }
}
