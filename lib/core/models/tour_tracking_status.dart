/// Server-owned evidence state. No client-side lifecycle decisions are made.
class TourTrackingStatus {
  const TourTrackingStatus(this.data);
  final Map<String, dynamic> data;
  bool get changed => data['changed'] == true;
  bool get interrupted => data['interrupted_at'] != null;
  String get phase => data['phase'] as String? ?? 'navigating';
  String get label => interrupted
      ? 'Tour interrupted — resume GPS to verify your current stop'
      : switch (phase) {
          'detecting_arrival' => 'Detecting Arrival — remain safely stopped',
          'arrived' => 'Arrived — stop in progress',
          'stop_in_progress' => 'Stop in Progress — departure is automatic',
          'detecting_departure' => 'Detecting Departure',
          'departure_detected' => 'Departure Detected',
          'next_stop' => 'Next Stop — navigation updated',
          'waiting_for_convoy_or_payment' =>
            'Departure detected — waiting for convoy or payment',
          'completed' => 'Completed — final destination verified',
          'completion_pending' =>
            'Final destination verified — payment review required',
          'gps_interrupted' => 'GPS interrupted — waiting for an accurate fix',
          _ => 'Navigating — arrival is automatic',
        };
}
