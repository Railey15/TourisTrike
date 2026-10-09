import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MunicipalRestrictionNotice extends StatefulWidget {
  const MunicipalRestrictionNotice({super.key});
  @override
  State<MunicipalRestrictionNotice> createState() =>
      _MunicipalRestrictionNoticeState();
}

class _MunicipalRestrictionNoticeState
    extends State<MunicipalRestrictionNotice> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() => setState(() => _future = _load());
  Future<List<Map<String, dynamic>>> _load() async {
    final value = await Supabase.instance.client.rpc(
      'get_my_municipal_restrictions',
    );
    return value is List
        ? value
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : const [];
  }

  Future<void> _appeal(Map<String, dynamic> row) async {
    final reason = TextEditingController();
    try {
      final response = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Appeal municipal restriction'),
          content: TextField(
            controller: reason,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Reason for review',
              hintText: 'Explain why this restriction should be reviewed.',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (reason.text.trim().length < 20) return;
                Navigator.pop(context, reason.text.trim());
              },
              child: const Text('Submit appeal'),
            ),
          ],
        ),
      );
      if (response == null) return;
      await Supabase.instance.client.rpc(
        'appeal_municipal_restriction',
        params: {'p_restriction_id': row['id'], 'p_reason': response},
      );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Appeal submitted to the municipal tourism office.'),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to submit appeal: $error')),
        );
      }
    } finally {
      reason.dispose();
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Card(
          color: const Color(0xFFFFFBEB),
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Restriction status unavailable'),
            subtitle: const Text(
              'Booking and job eligibility will still be checked by the server.',
            ),
            trailing: IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
        );
      }
      final active =
          snapshot.data?.where((row) => row['active'] == true).toList() ??
          const <Map<String, dynamic>>[];
      if (active.isEmpty) return const SizedBox.shrink();
      return Column(
        children: active
            .map(
              (row) => Card(
                color: const Color(0xFFFFFBEB),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Municipal booking restriction',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text('${row['municipality']}: ${row['reason']}'),
                      Text(
                        'Until ${DateFormat.yMMMd().add_jm().format(DateTime.parse(row['ends_at'].toString()).toLocal())}',
                      ),
                      const Text(
                        'Existing bookings, payments, refunds, and support remain available.',
                      ),
                      if (row['appeal_status'] == 'pending')
                        const Text('Appeal under review')
                      else
                        TextButton(
                          onPressed: () => _appeal(row),
                          child: const Text('Request review / appeal'),
                        ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      );
    },
  );
}
