import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';

/// Uses the same user-scoped queries as History and Earnings. No service role
/// client is created in the mobile app.
class PersonalReportService {
  PersonalReportService({TourisTrikeRepository? repository})
    : _repository = repository ?? TourisTrikeRepository();

  final TourisTrikeRepository _repository;
  final _client = Supabase.instance.client;
  static final _date = DateFormat('MMM d, yyyy');
  static final _time = DateFormat('MMM d, yyyy h:mm a');
  static final _money = NumberFormat('#,##0.00');

  Future<({String name, String id})> _identity(String role) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign in to export your report.');
    final profile = await _client
        .from('profiles')
        .select('role,full_name')
        .eq('id', user.id)
        .maybeSingle();
    if (profile?['role'] != role) throw StateError('Report access denied.');
    final name = (profile?['full_name'] as String?)?.trim();
    return (name: name == null || name.isEmpty ? role : name, id: user.id);
  }

  Future<void> shareTouristReport() async {
    final person = await _identity('tourist');
    final bookings = await _repository.fetchTouristPackageBookings(limit: 500);
    if (bookings.any((booking) => booking.touristId != person.id)) {
      throw StateError('Report ownership check failed.');
    }
    final payments = await _repository.fetchPaymentRecords(
      role: 'payer',
      limit: 500,
    );
    if (payments.any((payment) => payment.payerId != person.id)) {
      throw StateError('Payment ownership check failed.');
    }
    final confirmedByBooking = <String, double>{};
    for (final payment in payments.where((record) => record.isConfirmed)) {
      final id = payment.bookingId?.toString();
      if (id != null) {
        confirmedByBooking[id] = (confirmedByBooking[id] ?? 0) + payment.amount;
      }
    }
    final bytes = await _buildPdf(
      title: 'Tourist Booking Report',
      person: person.name,
      columns: const [
        'Reference',
        'Tour / Date',
        'Pickup / Drop-off',
        'Status',
        'Total / Confirmed Paid',
      ],
      rows: [
        for (final booking in bookings)
          [
            booking.row['id']?.toString() ?? '',
            '${dbString(booking.packageRow?['title'], fallback: 'Tour package')}\n'
                '${booking.scheduledStartAt == null ? _date.format(booking.travelDate ?? DateTime.now()) : _time.format(booking.scheduledStartAt!.toUtc().add(const Duration(hours: 8)))}',
            '${booking.pickupAddress}\n${booking.dropoffAddress}',
            booking.bookingStatus,
            'PHP ${_money.format(booking.totalAmount)}\n'
                'Paid: PHP ${_money.format(confirmedByBooking[booking.row['id']?.toString()] ?? 0)}',
          ],
      ],
      empty: 'No personal booking records are available.',
      note:
          'Confirmed paid amounts include only payment records authorized to this tourist. '
          'Amounts due remain subject to the booking payment record.',
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'touristrike-tourist-report.pdf',
    );
  }

  Future<void> shareDriverReport() async {
    final person = await _identity('driver');
    final activities = await _repository.fetchDriverActivities(limit: 500);
    if (activities.any((activity) => activity.driverId != person.id)) {
      throw StateError('Assignment ownership check failed.');
    }
    final allocations = await _repository
        .fetchConfirmedDriverPaymentAllocations(limit: 500);
    final direct = await _repository.fetchPaymentRecords(
      role: 'payee',
      limit: 500,
    );
    if (allocations.any((item) => item.driverId != person.id) ||
        direct.any((item) => item.payeeId != person.id)) {
      throw StateError('Earnings ownership check failed.');
    }
    final confirmedDirect = direct.where((item) => item.isConfirmed).toList();
    final bytes = await _buildPdf(
      title: 'Driver Activity & Earnings Report',
      person: person.name,
      columns: const [
        'Reference',
        'Tour / Schedule',
        'Assignment status',
        'Confirmed earnings',
      ],
      rows: [
        for (final activity in activities)
          [
            activity.bookingId,
            '${dbString(activity.bookingRow?['tour_packages']?['title'], fallback: 'Tour package')}\n'
                '${_formatBookingDate(activity.bookingRow)}',
            activity.lifecycleStatus,
            'PHP ${_money.format(allocations.where((a) => a.bookingId == activity.bookingId).fold<double>(0, (sum, a) => sum + a.driverAmount) + confirmedDirect.where((p) => p.bookingId?.toString() == activity.bookingId).fold<double>(0, (sum, p) => sum + p.amount))}',
          ],
      ],
      empty: 'No assigned or completed tour records are available.',
      note:
          'Earnings include confirmed payment allocations and confirmed direct payments '
          'visible to this driver. Pending or disputed amounts are excluded.',
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'touristrike-driver-report.pdf',
    );
  }

  String _formatBookingDate(Map<String, dynamic>? booking) {
    final value = booking?['scheduled_start_at'];
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null
        ? 'Schedule unavailable'
        : _time.format(parsed.toUtc().add(const Duration(hours: 8)));
  }

  Future<Uint8List> _buildPdf({
    required String title,
    required String person,
    required List<String> columns,
    required List<List<String>> rows,
    required String empty,
    required String note,
  }) async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'TOURISTRIKE',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue700,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              'For $person  |  Generated ${_time.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.Divider(),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (_) => [
          if (rows.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.all(24),
              child: pw.Text(empty),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: columns,
              data: rows,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                fontSize: 8,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blue700,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              cellPadding: const pw.EdgeInsets.all(6),
              oddRowDecoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
              ),
            ),
          pw.SizedBox(height: 14),
          pw.Text(
            note,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return document.save();
  }
}
