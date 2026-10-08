# Prepare a local, isolated Supabase workdir from the linked migration history.
# Two tracked SQL files have version IDs already used by different remote
# migrations. Keep those files untouched; exclude them only from this copy.
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$source = Join-Path $repo 'supabase'
$release = Join-Path $repo ('build/deployment-validation-' +
  (Get-Date -Format 'yyyyMMdd-HHmmss'))
$migrations = Join-Path $release 'supabase/migrations'
$temporary = Join-Path $release 'supabase/.temp'

foreach ($required in @(
  'migrations/20260930020000_repair_system_maintenance.sql',
  'migrations/20261008005000_payment_email_verification.sql',
  'migrations/20261008010000_booking_tour_developer_overrides.sql',
  'migrations/20261008015000_waiting_charge_integrity.sql',
  'migrations/20261008020000_additional_tricycle_review.sql',
  'migrations/20261008030000_tourist_late_cancellation_protection.sql',
  'migrations/20261008040000_transactional_email_outbox.sql',
  '.temp/project-ref', '.temp/pooler-url'
)) {
  if (-not (Test-Path -LiteralPath (Join-Path $source $required))) {
    throw "Missing required local migration or project link: $required"
  }
}

New-Item -ItemType Directory -Path $migrations -Force | Out-Null
New-Item -ItemType Directory -Path $temporary -Force | Out-Null
$excluded = @(
  '20260930020000_booking_notices_cancellation_policy.sql',
  '20261008000000_payment_email_verification.sql'
)
Get-ChildItem -LiteralPath (Join-Path $source 'migrations') -Filter '*.sql' -File |
  Where-Object { $_.Name -notin $excluded } |
  ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $migrations }
Copy-Item -LiteralPath (Join-Path $source 'config.toml') -Destination (
  Join-Path $release 'supabase/config.toml')
Get-ChildItem -LiteralPath (Join-Path $source '.temp') -File |
  ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $temporary }

Write-Output $release
