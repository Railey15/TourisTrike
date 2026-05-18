import 'package:flutter/material.dart';
import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';

class DriverDocumentsScreen extends StatelessWidget {
  const DriverDocumentsScreen({
    super.key,
    required this.documents,
  });

  final DriverDocuments documents;

  @override
  Widget build(BuildContext context) {
    final items = [
      _DocItem('Selfie', documents.selfieUrl),
      _DocItem('License Front', documents.licenseFrontUrl),
      _DocItem('License Back', documents.licenseBackUrl),
      _DocItem('Police Clearance', documents.policeClearanceUrl),
      _DocItem('MTOP', documents.mtopUrl),
      _DocItem('Vehicle Front', documents.vehicleFrontUrl),
      _DocItem('Vehicle Back', documents.vehicleBackUrl),
      _DocItem('Vehicle Left', documents.vehicleLeftUrl),
      _DocItem('Vehicle Right', documents.vehicleRightUrl),
      _DocItem('OR', documents.orUrl),
      _DocItem('CR', documents.crUrl),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Driver Documents'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(
                '${documents.uploadedCount} uploaded of ${documents.totalCount}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
            );
          }

          final item = items[index - 1];
          final uploaded = item.url.trim().isNotEmpty;

          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(21),
                  ),
                  child: Icon(
                    uploaded
                        ? Icons.check_circle_outline
                        : Icons.folder_open_outlined,
                    color: uploaded
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF2F6FFF),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF172033),
                    ),
                  ),
                ),
                Text(
                  uploaded ? 'Uploaded' : 'Missing',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: uploaded
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DocItem {
  final String label;
  final String url;

  _DocItem(this.label, this.url);
}