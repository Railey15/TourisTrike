import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const defaultBulacanCoverUrl =
    'https://mvtqhsrdgtwdeootgjci.supabase.co/storage/v1/object/public/'
    'public-assets/welcome.png';

enum MunicipalityCoverSource {
  uploaded('uploaded', 'Uploaded'),
  touristrike('touristrike', 'TourisTrike destination'),
  pexels('pexels', 'Pexels'),
  defaultCover('default', 'TourisTrike default');

  const MunicipalityCoverSource(this.databaseValue, this.label);

  final String databaseValue;
  final String label;

  static MunicipalityCoverSource fromDatabaseValue(String value) {
    return MunicipalityCoverSource.values.firstWhere(
      (source) => source.databaseValue == value.trim().toLowerCase(),
      orElse: () => MunicipalityCoverSource.defaultCover,
    );
  }
}

class MunicipalityCoverSuggestion {
  const MunicipalityCoverSuggestion({
    required this.imageUrl,
    required this.source,
    required this.title,
    this.attribution = '',
    this.sourceUrl = '',
    this.municipality = '',
    this.width = 0,
    this.height = 0,
    this.score = 0,
    this.isGenericFallback = false,
    this.isVerifiedDestination = false,
  });

  final String imageUrl;
  final MunicipalityCoverSource source;
  final String title;
  final String attribution;
  final String sourceUrl;
  final String municipality;
  final int width;
  final int height;
  final double score;
  final bool isGenericFallback;
  final bool isVerifiedDestination;

  bool get hasDimensions => width > 0 && height > 0;

  bool get isLandscape => !hasDimensions || width / height >= 1.2;

  MunicipalityCoverSuggestion withDimensions({
    required int width,
    required int height,
  }) {
    return MunicipalityCoverSuggestion(
      imageUrl: imageUrl,
      source: source,
      title: title,
      attribution: attribution,
      sourceUrl: sourceUrl,
      municipality: municipality,
      width: width,
      height: height,
      score: score,
      isGenericFallback: isGenericFallback,
      isVerifiedDestination: isVerifiedDestination,
    );
  }

  Map<String, dynamic> toRpcParameters() {
    return {
      'p_cover_image_url': imageUrl,
      'p_cover_image_source': source.databaseValue,
      'p_cover_image_attribution': attribution,
      'p_cover_image_source_url': sourceUrl,
    };
  }

  factory MunicipalityCoverSuggestion.fromExternalMap(
    Map<String, dynamic> map,
    String municipality,
  ) {
    return MunicipalityCoverSuggestion(
      imageUrl: _string(map['image_url']),
      source: MunicipalityCoverSource.pexels,
      title: _string(map['title'], fallback: 'Pexels photo'),
      attribution: _string(map['attribution']),
      sourceUrl: _string(map['source_url']),
      municipality: municipality,
      width: _integer(map['width']),
      height: _integer(map['height']),
      score: _number(map['score']),
      isGenericFallback: map['is_generic_fallback'] == true,
    );
  }
}

class MunicipalityCoverSuggestionsResult {
  const MunicipalityCoverSuggestionsResult({
    required this.suggestions,
    this.warning = '',
  });

  final List<MunicipalityCoverSuggestion> suggestions;
  final String warning;
}

class MunicipalityCoverSelection {
  const MunicipalityCoverSelection({
    required this.imageUrl,
    required this.source,
    this.attribution = '',
    this.sourceUrl = '',
    this.updatedAt,
    this.fallbackImageUrls = const [],
  });

  final String imageUrl;
  final MunicipalityCoverSource source;
  final String attribution;
  final String sourceUrl;
  final DateTime? updatedAt;
  final List<String> fallbackImageUrls;

  bool get isDefault => source == MunicipalityCoverSource.defaultCover;

  List<String> get candidateImageUrls {
    final seen = <String>{};
    return [imageUrl, ...fallbackImageUrls]
        .where(MunicipalityCoverService.isSafeImageUrl)
        .where(
          (url) => seen.add(MunicipalityCoverService.normalizedImageUrl(url)),
        )
        .toList(growable: false);
  }
}

class MunicipalityCoverService {
  MunicipalityCoverService({
    SupabaseClient? client,
    Future<MunicipalityCoverSuggestion?> Function(
      MunicipalityCoverSuggestion suggestion,
    )?
    imageValidator,
  }) : _supabase = client ?? Supabase.instance.client,
       _imageValidator = imageValidator ?? _probeImage;

  final SupabaseClient _supabase;
  final Future<MunicipalityCoverSuggestion?> Function(
    MunicipalityCoverSuggestion suggestion,
  )
  _imageValidator;

  Future<MunicipalityCoverSuggestionsResult> loadSuggestions({
    required String municipality,
    int limit = 5,
  }) async {
    var warning = '';
    List<MunicipalityCoverSuggestion> local = const [];
    try {
      local = await loadLocalSuggestions(
        municipality: municipality,
        limit: limit,
      );
    } catch (_) {
      warning = 'Local destination images are temporarily unavailable.';
    }

    final remaining = remainingSuggestionSlots(
      validLocalCount: local.length,
      limit: limit,
    );
    if (remaining == 0) {
      return MunicipalityCoverSuggestionsResult(
        suggestions: local.take(limit).toList(growable: false),
        warning: warning,
      );
    }

    List<MunicipalityCoverSuggestion> external = const [];
    try {
      final response = await _supabase.functions.invoke(
        'municipality-cover-suggestions',
        method: HttpMethod.post,
        body: {'limit': remaining},
      );
      final data = response.data;
      if (data is Map) {
        final payload = Map<String, dynamic>.from(data);
        external = parseExternalSuggestions(payload, municipality);
        final externalWarning = _string(payload['warning']);
        if (externalWarning.isNotEmpty) warning = externalWarning;
      }
    } on FunctionException catch (error) {
      warning = _functionMessage(error);
    } catch (_) {
      warning = 'External suggestions are temporarily unavailable.';
    }

    return MunicipalityCoverSuggestionsResult(
      suggestions: combineSuggestions(
        localSuggestions: local,
        externalSuggestions: external,
        municipality: municipality,
        limit: limit,
      ),
      warning: warning,
    );
  }

  Future<List<MunicipalityCoverSuggestion>> loadLocalSuggestions({
    required String municipality,
    int limit = 5,
  }) async {
    final rows = await _supabase
        .from('tourist_spots')
        .select(
          'id, title, city, municipality, rating, image_url, status, '
          'verification_status, tourist_spot_images(image_url, sort_order, is_cover)',
        )
        .eq('city', municipality)
        .eq('status', 'active')
        .inFilter('verification_status', const ['approved', 'verified'])
        .order('rating', ascending: false)
        .limit(20);

    final candidates = localSuggestionsFromRows(
      (rows as List).whereType<Map>().map(
        (row) => Map<String, dynamic>.from(row),
      ),
      municipality: municipality,
      limit: 20,
    );
    if (candidates.isEmpty) return const [];

    final probeCount = (limit * 3).clamp(10, 20);
    final checked = await Future.wait(
      candidates.take(probeCount).map(_imageValidator),
    );
    return rankSuggestions(
      checked.whereType<MunicipalityCoverSuggestion>(),
      municipality: municipality,
      limit: limit,
    );
  }

  Future<void> selectCover(MunicipalityCoverSuggestion suggestion) async {
    if (!canSelectSuggestion(suggestion)) {
      throw ArgumentError('The cover image is unavailable or unsuitable.');
    }
    await _supabase.rpc(
      'set_subtenant_municipality_cover',
      params: suggestion.toRpcParameters(),
    );
  }

  Future<void> removeCover() async {
    await _supabase.rpc(
      'set_subtenant_municipality_cover',
      params: const {
        'p_cover_image_url': null,
        'p_cover_image_source': null,
        'p_cover_image_attribution': null,
        'p_cover_image_source_url': null,
      },
    );
  }

  Future<MunicipalityCoverSelection> loadTouristHomeCover(
    String municipality,
  ) async {
    MunicipalityCoverSuggestion? selected;
    try {
      final rows = await _supabase.rpc(
        'get_municipality_cover',
        params: {'p_municipality': municipality},
      );
      if (rows is List && rows.isNotEmpty && rows.first is Map) {
        final row = Map<String, dynamic>.from(rows.first as Map);
        final url = _string(row['cover_image_url']);
        if (isSafeImageUrl(url)) {
          selected = MunicipalityCoverSuggestion(
            imageUrl: url,
            source: MunicipalityCoverSource.fromDatabaseValue(
              _string(row['cover_image_source']),
            ),
            title: '$municipality municipality cover',
            attribution: _string(row['cover_image_attribution']),
            sourceUrl: _string(row['cover_image_source_url']),
            municipality: _string(row['municipality']),
          );
        }
      }
    } catch (_) {
      // The local-image and default fallbacks keep Home usable when the
      // branding migration is not deployed or the database is offline.
    }

    List<MunicipalityCoverSuggestion> local = const [];
    try {
      local = await loadLocalSuggestions(municipality: municipality, limit: 1);
    } catch (_) {
      local = const [];
    }

    return resolveHomeCover(
      selectedMunicipality: municipality,
      selectedCover: selected,
      localSuggestions: local,
    );
  }

  static List<MunicipalityCoverSuggestion> localSuggestionsFromRows(
    Iterable<Map<String, dynamic>> rows, {
    required String municipality,
    int limit = 5,
  }) {
    final expected = normalizeMunicipality(municipality);
    final suggestions = <MunicipalityCoverSuggestion>[];
    for (final row in rows) {
      final city = _string(row['municipality'], fallback: _string(row['city']));
      final active = _string(row['status']).toLowerCase() == 'active';
      final verified = const {
        'approved',
        'verified',
      }.contains(_string(row['verification_status']).toLowerCase());
      if (normalizeMunicipality(city) != expected || !active || !verified) {
        continue;
      }

      final title = _string(row['title'], fallback: 'TourisTrike destination');
      final rating = _number(row['rating']);
      final nested = row['tourist_spot_images'];
      if (nested is List) {
        final images =
            nested
                .whereType<Map>()
                .map((image) => Map<String, dynamic>.from(image))
                .toList()
              ..sort((left, right) {
                final coverCompare = (right['is_cover'] == true ? 1 : 0)
                    .compareTo(left['is_cover'] == true ? 1 : 0);
                if (coverCompare != 0) return coverCompare;
                return _integer(
                  left['sort_order'],
                ).compareTo(_integer(right['sort_order']));
              });
        for (final image in images) {
          final url = _string(image['image_url']);
          if (!isSafeImageUrl(url)) continue;
          suggestions.add(
            MunicipalityCoverSuggestion(
              imageUrl: url,
              source: MunicipalityCoverSource.touristrike,
              title: title,
              municipality: city,
              score:
                  1000 + (rating * 10) + (image['is_cover'] == true ? 20 : 0),
              isVerifiedDestination: true,
            ),
          );
        }
      }

      final primaryUrl = _string(row['image_url']);
      if (isSafeImageUrl(primaryUrl)) {
        suggestions.add(
          MunicipalityCoverSuggestion(
            imageUrl: primaryUrl,
            source: MunicipalityCoverSource.touristrike,
            title: title,
            municipality: city,
            score: 990 + (rating * 10),
            isVerifiedDestination: true,
          ),
        );
      }
    }
    return rankSuggestions(
      suggestions,
      municipality: municipality,
      limit: limit,
    );
  }

  static List<MunicipalityCoverSuggestion> parseExternalSuggestions(
    Map<String, dynamic> response,
    String municipality,
  ) {
    final raw = response['suggestions'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => MunicipalityCoverSuggestion.fromExternalMap(
            Map<String, dynamic>.from(item),
            municipality,
          ),
        )
        .where(
          (item) =>
              isSafeImageUrl(item.imageUrl) &&
              item.sourceUrl.toLowerCase().startsWith(
                'https://www.pexels.com/',
              ),
        )
        .toList(growable: false);
  }

  static List<MunicipalityCoverSuggestion> rankSuggestions(
    Iterable<MunicipalityCoverSuggestion> suggestions, {
    required String municipality,
    int limit = 5,
  }) {
    final expected = normalizeMunicipality(municipality);
    final bestByUrl = <String, MunicipalityCoverSuggestion>{};
    for (final item in suggestions) {
      if (!isCandidateMetadataUsable(item)) continue;
      final key = normalizedImageUrl(item.imageUrl);
      final current = bestByUrl[key];
      if (current == null ||
          _coverScore(item, expected) > _coverScore(current, expected)) {
        bestByUrl[key] = item;
      }
    }
    final ranked = bestByUrl.values.toList()
      ..sort(
        (left, right) =>
            _coverScore(right, expected).compareTo(_coverScore(left, expected)),
      );
    return ranked.take(limit).toList(growable: false);
  }

  static MunicipalityCoverSelection resolveHomeCover({
    required String selectedMunicipality,
    MunicipalityCoverSuggestion? selectedCover,
    Iterable<MunicipalityCoverSuggestion> localSuggestions = const [],
  }) {
    final expected = normalizeMunicipality(selectedMunicipality);
    if (selectedCover != null &&
        normalizeMunicipality(selectedCover.municipality) == expected &&
        isSafeImageUrl(selectedCover.imageUrl)) {
      return MunicipalityCoverSelection(
        imageUrl: selectedCover.imageUrl,
        source: selectedCover.source,
        attribution: selectedCover.attribution,
        sourceUrl: selectedCover.sourceUrl,
        fallbackImageUrls: [
          ...localSuggestions.map((item) => item.imageUrl),
          defaultBulacanCoverUrl,
        ],
      );
    }
    final ranked = rankSuggestions(
      localSuggestions,
      municipality: selectedMunicipality,
      limit: 1,
    );
    if (ranked.isNotEmpty) {
      final local = ranked.first;
      return MunicipalityCoverSelection(
        imageUrl: local.imageUrl,
        source: local.source,
        attribution: local.attribution,
        sourceUrl: local.sourceUrl,
        fallbackImageUrls: const [defaultBulacanCoverUrl],
      );
    }
    return const MunicipalityCoverSelection(
      imageUrl: defaultBulacanCoverUrl,
      source: MunicipalityCoverSource.defaultCover,
    );
  }

  static String normalizeMunicipality(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\b(city|municipality|of|bulacan|province)\b'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool isSafeImageUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  static bool isCandidateMetadataUsable(
    MunicipalityCoverSuggestion suggestion,
  ) {
    if (!isSafeImageUrl(suggestion.imageUrl) ||
        _hasUnsupportedImageType(suggestion.imageUrl) ||
        _looksLikePlaceholderOrGraphic(suggestion.imageUrl)) {
      return false;
    }
    if ((suggestion.width > 0) != (suggestion.height > 0)) return false;
    if (!suggestion.hasDimensions) return true;
    return suggestion.isLandscape &&
        suggestion.width >= 900 &&
        suggestion.height >= 500;
  }

  static bool canSelectSuggestion(MunicipalityCoverSuggestion suggestion) {
    return isCandidateMetadataUsable(suggestion) && suggestion.hasDimensions;
  }

  static int remainingSuggestionSlots({
    required int validLocalCount,
    int limit = 5,
  }) {
    if (limit <= 0) return 0;
    return (limit - validLocalCount).clamp(0, limit);
  }

  static List<MunicipalityCoverSuggestion> combineSuggestions({
    required Iterable<MunicipalityCoverSuggestion> localSuggestions,
    required Iterable<MunicipalityCoverSuggestion> externalSuggestions,
    required String municipality,
    int limit = 5,
  }) {
    if (limit <= 0) return const [];
    final local = rankSuggestions(
      localSuggestions,
      municipality: municipality,
      limit: limit,
    );
    final remaining = remainingSuggestionSlots(
      validLocalCount: local.length,
      limit: limit,
    );
    if (remaining == 0) return local;

    final usedUrls = local
        .map((item) => normalizedImageUrl(item.imageUrl))
        .toSet();
    final external = rankSuggestions(
      externalSuggestions.where(
        (item) => !usedUrls.contains(normalizedImageUrl(item.imageUrl)),
      ),
      municipality: municipality,
      limit: remaining,
    );
    return [...local, ...external];
  }

  static String normalizedImageUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return value.trim().toLowerCase();
    const transformationParameters = {
      'w',
      'h',
      'width',
      'height',
      'fit',
      'quality',
      'auto',
      'cs',
      'dpr',
    };
    final keys =
        uri.queryParameters.keys
            .where(
              (key) => !transformationParameters.contains(key.toLowerCase()),
            )
            .toList()
          ..sort();
    final keptParameters = {
      for (final key in keys) key: uri.queryParameters[key]!,
    };
    final normalized = keptParameters.isEmpty
        ? uri.replace(fragment: '', query: '')
        : uri.replace(fragment: '', queryParameters: keptParameters);
    return normalized.toString().toLowerCase();
  }

  static double _coverScore(
    MunicipalityCoverSuggestion suggestion,
    String expectedMunicipality,
  ) {
    final sourceScore = switch (suggestion.source) {
      MunicipalityCoverSource.touristrike => 10000,
      MunicipalityCoverSource.uploaded => 9000,
      MunicipalityCoverSource.pexels => 1000,
      MunicipalityCoverSource.defaultCover => 0,
    };
    final exactMunicipality =
        normalizeMunicipality(suggestion.municipality) == expectedMunicipality;
    final landscapeBonus = suggestion.isLandscape ? 100 : -500;
    final sizeBonus = suggestion.width > 0 && suggestion.height > 0
        ? (suggestion.width * suggestion.height / 1000000).clamp(0, 50)
        : 0;
    return sourceScore +
        (exactMunicipality ? 500 : 0) +
        (suggestion.isVerifiedDestination ? 300 : 0) +
        landscapeBonus +
        sizeBonus +
        _titleQualityScore(suggestion.title) +
        suggestion.score -
        (suggestion.isGenericFallback ? 250 : 0);
  }

  static double _titleQualityScore(String value) {
    final title = value.toLowerCase();
    const preferred = [
      'landmark',
      'heritage',
      'historical',
      'park',
      'plaza',
      'museum',
      'church',
      'shrine',
      'nature',
      'falls',
      'garden',
      'resort',
    ];
    const deprioritized = [
      'cafe',
      'coffee',
      'restaurant',
      'menu',
      'shop',
      'store',
      'logo',
      'poster',
    ];
    var score = 0.0;
    if (preferred.any(title.contains)) score += 180;
    if (deprioritized.any(title.contains)) score -= 180;
    return score;
  }

  static bool _hasUnsupportedImageType(String value) {
    final path = Uri.tryParse(value.trim())?.path.toLowerCase() ?? '';
    return const ['.svg', '.gif', '.bmp', '.ico', '.pdf'].any(path.endsWith);
  }

  static bool _looksLikePlaceholderOrGraphic(String value) {
    if (normalizedImageUrl(value) ==
        normalizedImageUrl(defaultBulacanCoverUrl)) {
      return true;
    }
    final uri = Uri.tryParse(value.trim());
    final path = (uri?.path ?? value).toLowerCase();
    const blockedTokens = [
      'placeholder',
      'no-image',
      'no_image',
      'noimage',
      'image-not-found',
      'default-image',
      'default_image',
      'dummy-image',
      '/logo.',
      '-logo.',
      '_logo.',
      '/icon.',
      '-icon.',
      '_icon.',
      '/menu.',
      '-menu.',
      '_menu.',
      '/poster.',
      '-poster.',
      '_poster.',
    ];
    return blockedTokens.any(path.contains);
  }

  static Future<MunicipalityCoverSuggestion?> _probeImage(
    MunicipalityCoverSuggestion suggestion,
  ) async {
    if (!isCandidateMetadataUsable(suggestion)) return null;

    final provider = NetworkImage(suggestion.imageUrl);
    final stream = provider.resolve(ImageConfiguration.empty);
    final completer = Completer<ImageInfo>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info);
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
    );
    stream.addListener(listener);
    try {
      final info = await completer.future.timeout(const Duration(seconds: 6));
      final checked = suggestion.withDimensions(
        width: info.image.width,
        height: info.image.height,
      );
      return isCandidateMetadataUsable(checked) ? checked : null;
    } catch (_) {
      return null;
    } finally {
      stream.removeListener(listener);
    }
  }

  static String _functionMessage(FunctionException error) {
    final details = error.details;
    if (details is Map) {
      final message = _string(details['message']);
      if (message.isNotEmpty) return message;
    }
    return 'External suggestions are temporarily unavailable.';
  }
}

String _string(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int _integer(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
