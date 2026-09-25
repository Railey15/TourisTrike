# Global foreground banner UX

This change improves the existing in-app notification presentation only. **No migration, Supabase deployment, new table, or new event producer is required.** Existing uncommitted backend changes from earlier work were preserved.

## Existing architecture and presentation gap

`NotificationService` already subscribes once to recipient-filtered Supabase Realtime and foreground FCM, resolving both to the persistent notification ID. `MaterialApp.builder` already installs one `NotificationHost` above the root Navigator. The earlier missing-Overlay rendering bug was fixed in the previous investigation; the starting implementation could show a basic global banner. This task replaces its plain presentation and immediate replacement behavior with a styled card and queue. It does not claim that the earlier backend stopped generating events.

## Result

- One shared card across authenticated routes: rounded surface, subtle category accent/elevation, existing theme typography, Flutter category icons, one-line title, up to two body lines, and “Just now”/relative time.
- Entry: 240ms slide/fade down. Visible: 4.5 seconds after entry. Exit: 180ms slide/fade up. Reduced-motion settings disable entry/exit animation.
- Swipe up or the accessible close control dismisses the card. Arrival never navigates or marks history read. Timeout/dismissal leaves the persistent Notification Center untouched.
- Root `Overlay.wrap` supplies the tooltip overlay ancestor. The banner occupies a safe strip above the Navigator, below the status-bar/cutout inset, with 16px horizontal margins. Reserving that space keeps AppBars, map actions and confirmation controls uncovered. It does not take text-field focus or close dialogs.
- One active card, at most three waiting events. FIFO among retained events; overflow drops the oldest waiting card, retaining newer information. Waiting cards expire after 20 seconds. The current card is never replaced by another event.
- Account changes clear the queue and presentation IDs; inactive/background states clear active/waiting cards. Suppressed background events are remembered, so the second transport cannot replay them on resume. History reload/reconnect is not a banner source.
- A root RouteObserver tracks the Notification Center's visibility. While it is the visible route, history continues using the existing Realtime refresh but redundant banners are suppressed. Covering it with another route resumes normal presentation.
- Existing backend `in_app_enabled`/read eligibility is retained, with a presentation-only filter for diagnostic/test and technical noise events. GPS, ETA, map, reconnect, typing and debug events do not enter the queue.

## Deduplication and taps

The existing service guard deduplicates Realtime and FCM by notification ID. The host also remembers up to 300 IDs, including suppressed or overflowed events, so route rebuilds and repeated stream deliveries cannot duplicate a queued/displayed card. Account changes reset that presentation scope. Neither layer creates database rows.

Only a tap opens a destination. It passes the existing notification ID to the existing `notification_destination` RPC, verifies that the authenticated user has not changed, and uses the existing tourist tracking, driver tracking or driver jobs routes. Payment/completion controls remain in their existing tracking flows. Unknown or unavailable destinations fall back to the Notification Center. Existing read-on-tap behavior is retained; merely displaying a banner never marks it read.

## Files changed in this UX task

- `lib/widgets/notification_host.dart`: queue, animations, lifecycle, tap handling and global safe layout.
- `lib/widgets/notification_foreground_banner.dart` (new): reusable styled card and swipe/close interaction.
- `lib/core/notifications/notification_visibility.dart` (new): root route observer and center visibility.
- `lib/core/notifications/notification_presentation_guard.dart`: remember suppressed background receipts across transports.
- `lib/core/notifications/tour_notification.dart`: presentation-only event eligibility/noise filter.
- `lib/screens/shared/notification_center_screen.dart`: route visibility reporting.
- `lib/main.dart`: attach the shared route observer to the existing authenticated app roots.
- `test/notification_queue_test.dart` (new): queue, lifecycle, route, interaction, accessibility and modal regression tests.
- `docs/NOTIFICATION_PRESENTATION.md` (this report).

## Validation

23 targeted Flutter tests pass, including the existing presentation/model/loading tests and 12 new tests for route changes, bounded FIFO/deduplication, timeout, swipe, persistent/read state, background/resume, transport duplicates, center suppression, tap-only routing, dialog/keyboard safety, noise filtering, safe area and large text at 320/430/768px widths. Targeted static analysis passes; the Android debug APK builds successfully.

```powershell
flutter test test/notification_queue_test.dart test/notification_presentation_test.dart test/notification_model_test.dart test/widget_test.dart
flutter analyze --no-pub lib/widgets/notification_host.dart lib/widgets/notification_foreground_banner.dart lib/core/notifications lib/screens/shared/notification_center_screen.dart lib/main.dart test/notification_queue_test.dart
flutter build apk --debug --no-pub
```

The navigation tests use a real root Navigator with lightweight Home/Tracking/Dashboard/Profile/Chat/Booking route fixtures; they do not simulate GPS or payment transactions. Tap tests validate ID routing through the injected handler; remote authorization continues to use the existing RPC and was not changed or redeployed. A rendered visual fixture was inspected at `build/notification-preview/banner.png` using a local fallback font; it is a component preview, not a new live-tour/device acceptance claim. No remote notification rows or other production data were changed during this UX work. Actual FCM configuration status remains as documented in the earlier investigation.
