# Runs against the linked project. Creates no booking; removes its test Tourist.
$ErrorActionPreference = 'Stop'
$projectRef = 'mvtqhsrdgtwdeootgjci'
$baseUrl = "https://$projectRef.supabase.co"
$userId = $null
$cleanupFailed = $false

function Status-Code($errorRecord) {
  if ($errorRecord.Exception.Response) {
    return [int]$errorRecord.Exception.Response.StatusCode
  }
  return 0
}

function Assert-Booking-Rpc-Rejection($count, $reason, $expectedMessage) {
  $booking = @{ additional_tricycle_count = $count }
  if ($reason) { $booking.additional_tricycle_reason = $reason }
  $requestBody = @{ p_booking = $booking; p_customized_spots = @();
    p_itinerary_items = @() } | ConvertTo-Json -Depth 6
  try {
    Invoke-RestMethod -Method Post -Uri "$baseUrl/rest/v1/rpc/create_package_booking" `
      -Headers $touristHeaders -ContentType 'application/json' -Body $requestBody | Out-Null
    throw 'An incomplete booking was unexpectedly created.'
  } catch {
    if (!(Status-Code $_)) { throw 'Booking RPC was not reachable.' }
    $rawError = $_.ErrorDetails.Message
    if (!$rawError) {
      $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      $rawError = $reader.ReadToEnd()
    }
    $errorBody = $rawError | ConvertFrom-Json
    if ($errorBody.message -ne $expectedMessage) {
      throw "Booking RPC returned status $(Status-Code $_), '$($errorBody.message)' for count $count."
    }
  }
}

try {
  $ErrorActionPreference = 'Continue'
  $rawKeys = & npx supabase projects api-keys --project-ref $projectRef --reveal --output json 2>$null
  $ErrorActionPreference = 'Stop'
  if ($LASTEXITCODE -ne 0) { throw 'Project API keys are unavailable.' }
  $keys = $rawKeys | ConvertFrom-Json
  $serviceKey = ($keys | Where-Object { $_.name -eq 'service_role' }).api_key
  $anonKey = ($keys | Where-Object { $_.name -eq 'anon' }).api_key
  if (!$serviceKey -or !$anonKey) { throw 'Required project API keys are unavailable.' }

  $adminHeaders = @{ apikey = $serviceKey; Authorization = "Bearer $serviceKey" }
  $email = 'touristrike-live-verify+' + [guid]::NewGuid().ToString('N') + '@example.com'
  $password = [guid]::NewGuid().ToString('N') + '!Az9'
  $created = Invoke-RestMethod -Method Post -Uri "$baseUrl/auth/v1/admin/users" `
    -Headers $adminHeaders -ContentType 'application/json' `
    -Body (@{ email = $email; password = $password; email_confirm = $true } | ConvertTo-Json)
  $userId = if ($created.id) { $created.id } else { $created.user.id }
  if (!$userId) { throw 'Temporary Tourist could not be created.' }

  $profile = Invoke-RestMethod -Method Get `
    -Uri "$baseUrl/rest/v1/profiles?select=role&id=eq.$userId" -Headers $adminHeaders
  if (!$profile -or $profile.Count -eq 0) {
    Invoke-RestMethod -Method Post -Uri "$baseUrl/rest/v1/profiles" `
      -Headers $adminHeaders -ContentType 'application/json' `
      -Body (@{ id = $userId; role = 'tourist' } | ConvertTo-Json) | Out-Null
  } elseif ($profile[0].role -ne 'tourist') {
    throw 'Temporary account did not receive the Tourist role.'
  }

  $login = Invoke-RestMethod -Method Post `
    -Uri "$baseUrl/auth/v1/token?grant_type=password" `
    -Headers @{ apikey = $anonKey } -ContentType 'application/json' `
    -Body (@{ email = $email; password = $password } | ConvertTo-Json)
  if (!$login.access_token) { throw 'Temporary Tourist sign-in failed.' }
  $touristHeaders = @{ apikey = $anonKey; Authorization = "Bearer $($login.access_token)" }
  Write-Output 'Temporary Tourist authenticated: yes'

  foreach ($count in 0..3) {
    $reason = if ($count -eq 0) { $null } else { 'extra_luggage' }
    Assert-Booking-Rpc-Rejection $count $reason 'BOOKING_TERMS_REQUIRED'
  }
  Write-Output 'Booking RPC accepts optional count validation for 0, 1, 2, 3: yes'
  Assert-Booking-Rpc-Rejection 4 'extra_luggage' 'INVALID_ADDITIONAL_TRICYCLE_COUNT'
  Assert-Booking-Rpc-Rejection -1 'extra_luggage' 'INVALID_ADDITIONAL_TRICYCLE_COUNT'
  Assert-Booking-Rpc-Rejection 2 $null 'INVALID_ADDITIONAL_TRICYCLE_REASON'
  Write-Output 'Booking RPC rejects +4, negative, and missing reason: yes'

  $envLine = Get-Content '.env' | Where-Object { $_ -match '^GOOGLE_MAPS_API_KEY=' } | Select-Object -First 1
  $mapsKey = if ($envLine) { ($envLine -split '=', 2)[1].Trim().Trim('"', "'") } else { '' }
  if (!$mapsKey) { throw 'Google Maps test key is unavailable.' }
  $points = @('14.949,120.912', '14.9497,120.9126', '14.9677,120.9266',
    '14.9717,120.9176', '14.949,120.912')
  $legs = @()
  for ($i = 0; $i -lt $points.Count - 1; $i++) {
    $origin = $points[$i].Split(',')
    $destination = $points[$i + 1].Split(',')
    $routeBody = @{
      origin = @{ location = @{ latLng = @{
        latitude = [double]$origin[0]; longitude = [double]$origin[1]
      } } }
      destination = @{ location = @{ latLng = @{
        latitude = [double]$destination[0]; longitude = [double]$destination[1]
      } } }
      travelMode = 'DRIVE'
      routingPreference = 'TRAFFIC_UNAWARE'
      regionCode = 'PH'
      units = 'METRIC'
    } | ConvertTo-Json -Depth 8
    $routeHeaders = @{
      'X-Goog-Api-Key' = $mapsKey
      'X-Goog-FieldMask' = 'routes.duration,routes.distanceMeters'
    }
    try {
      $directions = Invoke-RestMethod -Method Post `
        -Uri 'https://routes.googleapis.com/directions/v2:computeRoutes' `
        -Headers $routeHeaders -ContentType 'application/json' `
        -Body $routeBody -TimeoutSec 20
    } catch {
      throw 'Google Maps test route is unavailable.'
    }
    if (!$directions.routes[0]) {
      throw 'Google Maps test route is unavailable.'
    }
    $route = $directions.routes[0]
    $durationSeconds = [double]($route.duration.TrimEnd('s'))
    $legs += @{ duration_minutes = [int][math]::Ceiling($durationSeconds / 60);
      distance_meters = [int]$route.distanceMeters }
  }
  Write-Output 'Google Maps route legs obtained: 4'

  $destinations = @(
    @{ id = 'spot:18'; name = 'Bustos Heritage Walk'; coordinates = @(14.9497, 120.9126);
      stay_minutes = 60; recommended_stay_minutes = 60 },
    @{ id = 'spot:19'; name = 'Bustos Resort and Leisure Area'; coordinates = @(14.9677, 120.9266);
      stay_minutes = 60; recommended_stay_minutes = 60 },
    @{ id = 'spot:20'; name = 'Bustos Faith and Cultural Site'; coordinates = @(14.9717, 120.9176);
      stay_minutes = 60; recommended_stay_minutes = 60 }
  )
  $payload = @{ package_id = 12; pickup = @(14.949, 120.912);
    dropoff = @(14.949, 120.912); pickup_minutes = 540;
    destinations = $destinations; current_route_legs = $legs }
  $functionUrl = "$baseUrl/functions/v1/itinerary-ai-suggest"
  $duplicate = $payload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
  $duplicate.destinations[1].id = $duplicate.destinations[0].id
  try {
    Invoke-RestMethod -Method Post -Uri $functionUrl -Headers $touristHeaders `
      -ContentType 'application/json' -Body ($duplicate | ConvertTo-Json -Depth 10) | Out-Null
    throw 'Duplicate destination IDs were accepted.'
  } catch {
    if ((Status-Code $_) -ne 400) { throw 'Duplicate destination ID check failed.' }
  }
  Write-Output 'Duplicate destination IDs rejected: HTTP 400'

  $missing = $payload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
  $missing.destinations = @($missing.destinations | Select-Object -First 2)
  $missing.current_route_legs = @($missing.current_route_legs | Select-Object -First 3)
  try {
    Invoke-RestMethod -Method Post -Uri $functionUrl -Headers $touristHeaders `
      -ContentType 'application/json' -Body ($missing | ConvertTo-Json -Depth 10) | Out-Null
    throw 'A destination was silently removed.'
  } catch {
    if ((Status-Code $_) -ne 400) { throw 'Missing destination check failed.' }
  }
  Write-Output 'Fewer than three selected destinations rejected: HTTP 400'

  try {
    $result = Invoke-RestMethod -Method Post -Uri $functionUrl -Headers $touristHeaders `
      -ContentType 'application/json' -Body ($payload | ConvertTo-Json -Depth 10) -TimeoutSec 40
  } catch {
    $requestError = $_
    $failureCode = 'unknown'
    if ($requestError.Exception.Response) {
      try {
        $rawFailure = $requestError.ErrorDetails.Message
        if (!$rawFailure) {
          $reader = New-Object System.IO.StreamReader($requestError.Exception.Response.GetResponseStream())
          $rawFailure = $reader.ReadToEnd()
        }
        $failure = $rawFailure | ConvertFrom-Json
        $failureCode = $failure.code
        if ($failureCode -eq 'AI_UNAVAILABLE' -and !$failure.error -and !$failure.diagnostic) {
          Write-Output 'AI failure response exposes only a generic code: yes'
        }
      } catch { $failureCode = 'unreadable' }
    }
    throw "Valid Tourist AI request returned HTTP $(Status-Code $requestError), code $failureCode."
  }
  $expected = @('spot:18', 'spot:19', 'spot:20')
  $actual = @($result.ordered_destination_ids)
  if ($result.code -ne 'OK' -or $actual.Count -ne 3 -or
      (@($actual | Select-Object -Unique).Count -ne 3) -or
      (@($actual | Where-Object { $_ -notin $expected }).Count -ne 0) -or
      !$result.explanation) { throw 'AI returned an invalid structured response.' }
  Write-Output 'Authenticated Tourist function invocation: HTTP 200'
  Write-Output 'Structured response contains exactly the selected IDs: yes'
  Write-Output 'Response has an explanation: yes'
  Write-Output 'Function response has authoritative travel legs: no'
} catch {
  Write-Output ('Live Tourist check failed: ' + $_.Exception.Message)
  exit 1
} finally {
  if ($userId -and $adminHeaders) {
    try {
      Invoke-RestMethod -Method Delete -Uri "$baseUrl/auth/v1/admin/users/$userId" `
        -Headers $adminHeaders | Out-Null
      Write-Output 'Temporary Tourist removed: yes'
    } catch {
      $cleanupFailed = $true
      Write-Output 'Temporary Tourist removal failed'
    }
  }
  if ($cleanupFailed) { exit 1 }
}
