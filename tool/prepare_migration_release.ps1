# Prepare a local, isolated Supabase workdir from the linked migration history.
# Historical SQL with a reused version lives in supabase/migration_hold, so
# every file in supabase/migrations must have a unique deployable version.
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
  'migrations/20261009000000_paymongo_test_pending_payout_lifecycle.sql',
  'migrations/20261009010000_payment_history_same_day_driver_cleanup.sql',
  'migrations/20261009020000_waiting_charge_integrity.sql',
  'migrations/20261009030000_additional_tricycle_review.sql',
  'migrations/20261009040000_tourist_late_cancellation_protection.sql',
  'migrations/20261009050000_transactional_email_outbox.sql',
  'migrations/20261009060000_administrator_tour_testing_progression.sql',
  '.temp/project-ref', '.temp/pooler-url'
)) {
  if (-not (Test-Path -LiteralPath (Join-Path $source $required))) {
    throw "Missing required local migration or project link: $required"
  }
}

New-Item -ItemType Directory -Path $migrations -Force | Out-Null
New-Item -ItemType Directory -Path $temporary -Force | Out-Null
$migrationFiles = @(Get-ChildItem -LiteralPath (Join-Path $source 'migrations') -Filter '*.sql' -File)
$duplicates = @($migrationFiles | Group-Object { $_.Name.Substring(0, 14) } | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) {
  throw "Duplicate migration versions: $($duplicates.Name -join ', ')"
}
$migrationFiles | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination $migrations
}
Copy-Item -LiteralPath (Join-Path $source 'config.toml') -Destination (
  Join-Path $release 'supabase/config.toml')
Get-ChildItem -LiteralPath (Join-Path $source '.temp') -File |
  ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $temporary }

Write-Output $release
