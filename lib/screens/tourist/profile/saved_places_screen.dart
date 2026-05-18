import 'package:flutter/material.dart';

import 'package:touristrike/screens/tourist/tourist_saved_places_state.dart';

/// Saved Places Screen
/// - Home / Work pinned at top
/// - Other saved places list
/// - Search + filter chips
/// - Saved spots are added from the spot details screen.
///
/// Navigate:
/// Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedPlacesScreen()));
class SavedPlacesScreen extends StatefulWidget {
  const SavedPlacesScreen({super.key});

  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  final _searchCtrl = TextEditingController();

  List<SavedPlace> _places = [];

  SavedPlacesFilter _filter = SavedPlacesFilter.all;

  @override
  void initState() {
    super.initState();
    _syncPlacesFromStore();
    touristSavedPlacesStore.addListener(_onSavedPlacesChanged);
  }

  @override
  void dispose() {
    touristSavedPlacesStore.removeListener(_onSavedPlacesChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSavedPlacesChanged() {
    if (!mounted) return;
    setState(_syncPlacesFromStore);
  }

  void _syncPlacesFromStore() {
    _places = touristSavedPlacesStore.value.map(_fromSharedPlace).toList();
  }

  SavedPlace _fromSharedPlace(TouristSavedPlace place) {
    return SavedPlace(
      id: place.id,
      label: place.label,
      address: place.address,
      icon: _iconForTag(place.tag),
      kind: place.id == 'home' || place.id == 'work'
          ? SavedPlaceKind.pinned
          : SavedPlaceKind.normal,
      tag: place.tag,
    );
  }

  TouristSavedPlace _toSharedPlace(SavedPlace place) {
    return TouristSavedPlace(
      id: place.id,
      label: place.label,
      address: place.address,
      tag: place.tag ?? 'Spot',
    );
  }

  IconData _iconForTag(String tag) {
    switch (tag.toLowerCase()) {
      case 'tour':
        return Icons.tour_rounded;
      case 'pickup':
        return Icons.my_location_rounded;
      case 'church':
        return Icons.church_rounded;
      case 'historical':
        return Icons.account_balance_rounded;
      case 'museum':
        return Icons.museum_rounded;
      case 'nature':
        return Icons.park_rounded;
      case 'sports':
        return Icons.sports_basketball_rounded;
      case 'restaurant':
      case 'food':
        return Icons.restaurant_rounded;
      case 'cafe':
        return Icons.local_cafe_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  List<SavedPlace> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();

    bool matchesSearch(SavedPlace p) {
      if (q.isEmpty) return true;
      return p.label.toLowerCase().contains(q) ||
          p.address.toLowerCase().contains(q);
    }

    bool matchesFilter(SavedPlace p) {
      return switch (_filter) {
        SavedPlacesFilter.all => true,
        SavedPlacesFilter.pinned => p.kind == SavedPlaceKind.pinned,
        SavedPlacesFilter.tour => (p.tag ?? '').toLowerCase() == 'tour',
        SavedPlacesFilter.spot =>
          p.kind == SavedPlaceKind.normal &&
              (p.tag ?? '').toLowerCase() != 'tour' &&
              (p.tag ?? '').toLowerCase() != 'pickup',
      };
    }

    final items = _places
        .where((p) => matchesSearch(p) && matchesFilter(p))
        .toList();

    // Keep pinned at top
    items.sort((a, b) {
      final ap = a.kind == SavedPlaceKind.pinned ? 0 : 1;
      final bp = b.kind == SavedPlaceKind.pinned ? 0 : 1;
      if (ap != bp) return ap.compareTo(bp);
      return a.label.compareTo(b.label);
    });

    return items;
  }

  SavedPlace? get _home => _places.where((p) => p.id == 'home').isNotEmpty
      ? _places.firstWhere((p) => p.id == 'home')
      : null;
  SavedPlace? get _work => _places.where((p) => p.id == 'work').isNotEmpty
      ? _places.firstWhere((p) => p.id == 'work')
      : null;

  Future<void> _editPlace(SavedPlace place) async {
    final updated = await showModalBottomSheet<SavedPlace>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlaceEditorSheet(existing: place),
    );

    if (updated != null) {
      touristSavedPlacesStore.addOrUpdate(_toSharedPlace(updated));
    }
  }

  void _removePlace(SavedPlace place) {
    touristSavedPlacesStore.remove(place.id);
  }

  void _selectPlace(SavedPlace place) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Selected: ${place.label}')));
  }

  void _showActions(SavedPlace place) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ActionSheet(
        title: place.label,
        subtitle: place.address,
        actions: [
          _SheetAction(
            icon: Icons.edit_rounded,
            label: 'Edit',
            onTap: () {
              Navigator.pop(context);
              _editPlace(place);
            },
          ),
          _SheetAction(
            icon: Icons.delete_outline_rounded,
            label: 'Remove',
            isDanger: true,
            onTap: () {
              Navigator.pop(context);
              _removePlace(place);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const textLight = Color(0xFF94A3B8);
    const line = Color(0xFFE7EEF7);

    final items = _filtered;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // ============================================================
            // TOP BAR
            // ============================================================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  _TopCircleButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Saved Places',
                      style: TextStyle(
                        fontSize: 20.5,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      showModalBottomSheet<void>(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const _InfoSheet(
                          title: 'Tips',
                          bullets: [
                            'Save places you visit often (home, work, spots).',
                            'Use these as quick pick-up or destination shortcuts.',
                            'You can edit or remove places anytime.',
                          ],
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        color: textMid,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                children: [
                  // ============================================================
                  // SEARCH
                  // ============================================================
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: line),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 18,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, color: textLight),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              hintText: 'Search saved places...',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: textDark,
                            ),
                          ),
                        ),
                        if (_searchCtrl.text.isNotEmpty)
                          InkWell(
                            onTap: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                            borderRadius: BorderRadius.circular(999),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.close_rounded, color: textMid),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // ============================================================
                  // FILTER CHIPS
                  // ============================================================
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'All',
                          selected: _filter == SavedPlacesFilter.all,
                          onTap: () =>
                              setState(() => _filter = SavedPlacesFilter.all),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Pinned',
                          selected: _filter == SavedPlacesFilter.pinned,
                          onTap: () => setState(
                            () => _filter = SavedPlacesFilter.pinned,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Tour',
                          selected: _filter == SavedPlacesFilter.tour,
                          onTap: () =>
                              setState(() => _filter = SavedPlacesFilter.tour),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Spot',
                          selected: _filter == SavedPlacesFilter.spot,
                          onTap: () =>
                              setState(() => _filter = SavedPlacesFilter.spot),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ============================================================
                  // PINNED (HOME/WORK) QUICK ROW
                  // ============================================================
                  if (_home != null || _work != null) ...[
                    const _SectionHeader(title: 'Pinned'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (_home != null)
                          Expanded(
                            child: _PinnedTile(
                              icon: Icons.home_rounded,
                              title: 'Home',
                              subtitle: _home!.address,
                              onTap: () => _selectPlace(_home!),
                              onMore: () => _showActions(_home!),
                            ),
                          ),
                        if (_home != null && _work != null)
                          const SizedBox(width: 10),
                        if (_work != null)
                          Expanded(
                            child: _PinnedTile(
                              icon: Icons.work_rounded,
                              title: 'Work',
                              subtitle: _work!.address,
                              onTap: () => _selectPlace(_work!),
                              onMore: () => _showActions(_work!),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ============================================================
                  // LIST
                  // ============================================================
                  _SectionHeader(
                    title: 'Saved',
                    trailing: Text(
                      '${items.length}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textMid,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (items.isEmpty)
                    const _EmptyState()
                  else
                    ...items.map((p) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _Card(
                          child: _PlaceRow(
                            place: p,
                            onTap: () => _selectPlace(p),
                            onMore: () => _showActions(p),
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// MODELS
// ============================================================

enum SavedPlaceKind { pinned, normal }

enum SavedPlacesFilter { all, pinned, tour, spot }

class SavedPlace {
  SavedPlace({
    required this.id,
    required this.label,
    required this.address,
    required this.icon,
    required this.kind,
    this.tag,
  });

  final String id;
  final String label;
  final String address;
  final IconData icon;
  final SavedPlaceKind kind;
  final String? tag;
}

// ============================================================
// UI COMPONENTS
// ============================================================

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE7EEF7);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _TopCircleButton extends StatelessWidget {
  const _TopCircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF0F172A)),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    const textDark = Color(0xFF0F172A);

    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w900,
            color: textDark,
            letterSpacing: -0.2,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFFBBD7FF) : const Color(0xFFE7EEF7),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: selected ? blue : textDark,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

class _PinnedTile extends StatelessWidget {
  const _PinnedTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onMore,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE7EEF7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: textDark,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: textMid,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: onMore,
              borderRadius: BorderRadius.circular(999),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.more_horiz_rounded, color: textMid),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.place,
    required this.onTap,
    required this.onMore,
  });

  final SavedPlace place;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(place.icon, color: blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        place.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: textDark,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (place.tag != null) ...[
                      const SizedBox(width: 8),
                      _TagChip(text: place.tag!),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  place.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textMid,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: onMore,
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.more_horiz_rounded, color: textMid),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: blue,
          fontSize: 12,
          letterSpacing: 0.35,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    const textMid = Color(0xFF64748B);
    const line = Color(0xFFE7EEF7);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: line),
      ),
      child: const Text(
        'No saved places yet.\nTap the heart on a spot details page to save it here.',
        style: TextStyle(fontWeight: FontWeight.w900, color: textMid),
      ),
    );
  }
}

// ============================================================
// BOTTOM SHEETS
// ============================================================

class _ActionSheet extends StatelessWidget {
  const _ActionSheet({
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final List<_SheetAction> actions;

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE7EEF7);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textDark,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: textMid,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: line),
          const SizedBox(height: 10),
          ...actions,
        ],
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE7EEF7);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const red = Color(0xFFDC2626);

    final fg = isDanger ? red : textDark;
    final iconColor = isDanger ? red : textMid;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: line),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w900, color: fg),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: textMid),
          ],
        ),
      ),
    );
  }
}

class _PlaceEditorSheet extends StatefulWidget {
  const _PlaceEditorSheet({this.existing});
  final SavedPlace? existing;

  @override
  State<_PlaceEditorSheet> createState() => _PlaceEditorSheetState();
}

class _PlaceEditorSheetState extends State<_PlaceEditorSheet> {
  final _labelCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  String _tag = 'Spot';
  IconData _icon = Icons.place_rounded;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      _labelCtrl.text = ex.label;
      _addrCtrl.text = ex.address;
      _tag = ex.tag ?? 'Spot';
      _icon = ex.icon;
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _labelCtrl.text.trim().isNotEmpty && _addrCtrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const line = Color(0xFFE7EEF7);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.existing == null ? 'Add Place' : 'Edit Place',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: textDark,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Icon picker (simple row)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(_icon, color: blue),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Icon',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textDark,
                      ),
                    ),
                  ),
                  DropdownButton<IconData>(
                    value: _icon,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                        value: Icons.place_rounded,
                        child: Text('Place'),
                      ),
                      DropdownMenuItem(
                        value: Icons.park_rounded,
                        child: Text('Park'),
                      ),
                      DropdownMenuItem(
                        value: Icons.restaurant_rounded,
                        child: Text('Restaurant'),
                      ),
                      DropdownMenuItem(
                        value: Icons.shopping_bag_rounded,
                        child: Text('Shop'),
                      ),
                      DropdownMenuItem(
                        value: Icons.tour_rounded,
                        child: Text('Tour'),
                      ),
                      DropdownMenuItem(
                        value: Icons.home_rounded,
                        child: Text('Home'),
                      ),
                      DropdownMenuItem(
                        value: Icons.work_rounded,
                        child: Text('Work'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _icon = v);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            _TextField(
              label: 'Label',
              controller: _labelCtrl,
              hint: 'e.g. Heritage Park',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            _TextField(
              label: 'Address',
              controller: _addrCtrl,
              hint: 'e.g. Bustos, Bulacan',
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 10),

            // Tag picker
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: line),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tag',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textDark,
                      ),
                    ),
                  ),
                  DropdownButton<String>(
                    value: _tag,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'Spot', child: Text('Spot')),
                      DropdownMenuItem(value: 'Tour', child: Text('Tour')),
                      DropdownMenuItem(value: 'Pickup', child: Text('Pickup')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _tag = v);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            SizedBox(
              height: 52,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSave
                    ? () {
                        final id =
                            widget.existing?.id ??
                            DateTime.now().millisecondsSinceEpoch.toString();

                        final kind = (id == 'home' || id == 'work')
                            ? SavedPlaceKind.pinned
                            : SavedPlaceKind.normal;

                        Navigator.pop(
                          context,
                          SavedPlace(
                            id: id,
                            label: _labelCtrl.text.trim(),
                            address: _addrCtrl.text.trim(),
                            icon: _icon,
                            kind: kind,
                            tag: _tag,
                          ),
                        );
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: blue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFBBD7FF),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 0,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                child: Text(widget.existing == null ? 'Add' : 'Save'),
              ),
            ),

            const SizedBox(height: 8),
            const Text(
              'Use saved places as quick destinations.',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: textMid,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.label,
    required this.controller,
    required this.hint,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE7EEF7);
    const textDark = Color(0xFF0F172A);
    const textLight = Color(0xFF94A3B8);
    const textMid = Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: textMid,
              fontSize: 12,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            onChanged: onChanged,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: textDark,
              fontSize: 16,
              letterSpacing: -0.2,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                color: textLight,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSheet extends StatelessWidget {
  const _InfoSheet({required this.title, required this.bullets});

  final String title;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const line = Color(0xFFE7EEF7);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textDark,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: line),
          const SizedBox(height: 10),

          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'â€¢ ',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: textMid,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      b,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: textMid,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
