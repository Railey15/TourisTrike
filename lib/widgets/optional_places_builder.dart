import 'package:flutter/material.dart';

/// Loads optional Places content without replacing the core Home screen.
class OptionalPlacesBuilder<T> extends StatefulWidget {
  const OptionalPlacesBuilder({
    super.key,
    required this.load,
    required this.builder,
  });

  final Future<T> Function() load;
  final Widget Function(
    BuildContext context,
    T? data,
    bool loading,
    bool unavailable,
    VoidCallback retry,
  )
  builder;

  @override
  State<OptionalPlacesBuilder<T>> createState() =>
      _OptionalPlacesBuilderState<T>();
}

class _OptionalPlacesBuilderState<T> extends State<OptionalPlacesBuilder<T>> {
  T? _data;
  bool _loading = false;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _unavailable = false;
    });
    try {
      final data = await widget.load();
      if (!mounted) return;
      setState(() => _data = data);
    } catch (_) {
      if (!mounted) return;
      setState(() => _unavailable = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _data, _loading, _unavailable, _load);
}

class OptionalPlacesNotice extends StatelessWidget {
  const OptionalPlacesNotice({
    super.key,
    required this.loading,
    required this.onRetry,
  });

  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loading
                ? 'Loading nearby suggestions…'
                : 'Nearby suggestions unavailable',
          ),
          const SizedBox(height: 6),
          const Text(
            'Saved destinations and tour packages are still available.',
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            )
          else
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
        ],
      ),
    ),
  );
}
