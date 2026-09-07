Emergency Alert attachment, final confirmation and email — 7 September 2026

The Tourist Tour Tracking emergency form now keeps its optional note and photo open behind a separate final confirmation. Opening the confirmation performs no alert insert, location request, upload, notification, or email. Only the red **Yes, Send Alert** button calls the submission callback. Neutral **Cancel** returns to the unchanged form.

The final action disables itself and dismissal while processing and displays **Sending...**. The form has a stable UUID for that submission; retries reuse the existing emergency-alert primary key rather than creating another alert. Notifications run only on a newly inserted row. Successful completion closes both dialogs and shows **Emergency alert sent successfully.** If the alert is saved but email fails, both dialogs close, the existing cooldown starts, and the UI reports **Emergency alert was sent, but email delivery failed.** A database failure keeps the form available for retry.

Files and responsibilities:

1. `lib/screens/tourist/tourist_activity_tracking_screen.dart`: only the emergency-panel entry point, existing result/cooldown handling, and passing its currently known tourist position were changed. The previous private note dialog was replaced with the dedicated emergency form widget.
2. `lib/widgets/emergency_alert_form.dart`: the photo button sits immediately below the optional note; gallery selection, thumbnail, Replace Photo and Remove are local form state. Contains the separate final confirmation and submission guards.
3. `lib/core/models/emergency_photo.dart`: validates file size (maximum 4 MB), JPEG/PNG/WebP signatures and actual image decoding. Cancelled selection retains the previous photo; invalid/oversized files and permission errors are shown without blocking a photo-free alert. Uses the existing `image_picker` package. Camera capture was not added.
4. `ios/Runner/Info.plist`: adds only the photo-library usage description needed by gallery attachment. No map, camera or GPS configuration changes.
5. `lib/core/services/emergency_service.dart`: retains the existing emergency-alert row and driver/admin notifications, captures GPS after final confirmation, and uses the current known tracking position as fallback. If neither exists, coordinates remain null. Reuses one alert ID on retry and checks the function's explicit `email_sent` result instead of treating every HTTP 200 as success.
6. `supabase/functions/send-emergency-email/index.ts`: reuses the existing server-side Resend delivery. Validates the tourist's JWT and ownership of the alert before reading/emailing its details; reads credentials from server secrets. Email includes the tourist, booking, package, status, coordinates/location link, current destination, driver, note and persisted alert timestamp. No address is invented when unavailable.
7. `supabase/functions/send-emergency-email/email.ts`: image validation for the email request, safe attachment filenames, HTML escaping, recipient deduplication and all-recipients success handling.
8. `supabase/functions/send-emergency-email/config.ts`: the single server-side location for hardcoded `emergencyEmails`. **Actual recipient addresses were not supplied, so this list is currently empty.** Existing tourist emergency-contact and active tourism-office email recipients are retained. No invented/example addresses are used.

Photo storage and email delivery:

- The selected photo remains in local memory until final confirmation. After the alert row is saved, its base64 content is sent to the authenticated Edge Function and included as an email attachment. No public image URL, Storage bucket, database photo column or new SQL migration is needed.
- Uses Resend's existing email API, which can deliver to Gmail addresses; Gmail SMTP/app passwords are not needed. No email credential or service-role key was added to Flutter.
- Provider requests use an idempotency key per alert/recipient. Resend retains these keys for 24 hours; the existing `email_sent` flag also suppresses completed deliveries. A provider success means the email request was accepted, not a separately verified inbox delivery. [Resend attachment API](https://resend.com/docs/api-reference/emails/send-email), [idempotency documentation](https://resend.com/docs/dashboard/emails/idempotency-keys).
- If email fails, the database alert remains. The photo is not independently retained in Storage for a later background retry.

Required configuration and deployment:

1. Add the approved recipient addresses to `supabase/functions/send-emergency-email/config.ts`. This is the remaining user-supplied information.
2. Configure `RESEND_API_KEY` and `FROM_EMAIL` in Supabase Edge Function secrets. `FROM_EMAIL` must use the verified sender/domain configured with the existing Resend account. Supabase supplies `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` to the function; keep them server-side.
3. For the existing linked Supabase project, run:

   ```powershell
   npx supabase secrets set --env-file "$env:USERPROFILE\.touristrike-emergency.env"
   npx supabase functions deploy send-emergency-email
   ```

   The private file outside the repository should contain the two actual server-side values:

   ```dotenv
   RESEND_API_KEY=your_server_side_resend_key
   FROM_EMAIL=TourisTrike Alerts <alerts@your_verified_domain>
   ```

   Deploy the function before releasing the updated client because the client now checks its explicit `email_sent` response. Rebuild/install the Flutter client normally. Do not use `--no-verify-jwt`; the function also authenticates the user itself.

Verification completed:

- Eight Flutter tests passed across `test/emergency_alert_form_test.dart` and `test/emergency_service_test.dart`. They cover no submission before confirmation, cancelled-confirmation preservation, sending the retained photo, double taps, processing state, dialog closure, stable retry IDs, image validation, photo-permission denial, database retention and accurate email outcomes.
- Three Node tests passed in `test/emergency_email_test.mjs` for attachment validation, escaped HTML, recipient normalization and partial/zero delivery.
- Targeted Dart analysis and Deno Edge Function type-check passed. Tests use mocks; no real emergency alert, email or production deployment was performed.

Reproduce checks:

```powershell
flutter test --no-pub test/emergency_alert_form_test.dart test/emergency_service_test.dart
node --test test/emergency_email_test.mjs
npx --yes deno check --no-lock supabase/functions/send-emergency-email/index.ts
```

Manual checks after configuring test recipients in a non-production environment:

1. Open Tourist Tour Tracking → Emergency Assistance → Emergency Alert. Enter a note and select a small photo. Verify the thumbnail, Replace Photo and Remove controls.
2. Tap Send Alert. Verify the exact final confirmation text. Before confirming, verify no emergency row, notification or email has been created.
3. Tap Cancel in the confirmation. Verify the note and selected image remain and no alert was sent. Also cancel/deny the gallery picker and confirm the form remains usable.
4. Confirm Yes, Send Alert twice quickly. Verify only one alert row, the processing state, and one provider submission per recipient. Verify the configured inbox receives the note, trip information, coordinates and photo attachment.
5. Verify both dialogs close with the success message. Repeat without note/photo.
6. With the provider mocked to fail, verify the database alert remains and the partial-failure message appears. With a database failure, verify retry preserves the note/photo and uses the same alert ID.

Scope: this change is confined to the emergency flow and its photo permission, email function/configuration and tests. Booking, payment, GPS arrival, driver navigation, convoy progression, maps, chat, ratings and Testing Mode logic were not changed in this task. Earlier map-related workspace changes remain separate.
