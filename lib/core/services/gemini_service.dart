import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/core/places/google_places_gateway.dart';

import 'chatbot_models.dart';

/// A single message in the conversation history sent to Gemini.
class GeminiTurn {
  const GeminiTurn({
    required this.role,
    required this.text,
  });

  /// Either `user` or `model`.
  final String role;
  final String text;
}

/// Thrown internally when Gemini returns a 503 / high-demand response.
class _OverloadException implements Exception {
  const _OverloadException(this.message);

  final String message;
}

/// Thin wrapper around the Gemini generateContent REST API.
///
/// Features:
/// - Fetches real in-app tourist spots and packages from Supabase.
/// - Uses Google Places for municipality and named-place searches.
/// - Intent-aware structured output.
/// - Validates Gemini-returned IDs against real app records.
/// - Automatic retry with exponential back-off.
/// - One-shot fallback model.
class GeminiService {
  GeminiService._();

  static final GeminiService instance = GeminiService._();

  // ─────────────────────────────────────────────────────────────────────────
  // Model config
  // ─────────────────────────────────────────────────────────────────────────

  static const _primaryModel = 'gemini-3.8-flash';
  static const _fallbackModel = 'gemini-3.5-flash-lite';

  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// 1 initial attempt + 3 retries = 4 total primary attempts.
  static const _maxAttempts = 4;

  // ─────────────────────────────────────────────────────────────────────────
  // Caches
  // ─────────────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>>? _cachedPackages;
  DateTime? _packagesCachedAt;

  List<Map<String, dynamic>>? _cachedSpots;
  DateTime? _spotsCachedAt;

  final Map<String, List<Map<String, dynamic>>> _googleSpotsCache = {};
  final Map<String, DateTime> _googleSpotsCachedAt = {};

  final Map<String, List<Map<String, dynamic>>> _namedPlaceCache = {};
  final Map<String, DateTime> _namedPlaceCachedAt = {};

  static const _cacheTtl = Duration(minutes: 10);

  String get _apiKey {
    const key = String.fromEnvironment('GEMINI_API_KEY');

    assert(
      key.isNotEmpty,
      'GEMINI_API_KEY is missing from --dart-define.',
    );

    return key;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  bool _isOverload(
    int statusCode,
    String message,
  ) {
    if (statusCode == 503) {
      return true;
    }

    final lower = message.toLowerCase();

    return lower.contains('high demand') ||
        lower.contains('overloaded') ||
        lower.contains('try again later') ||
        lower.contains('service unavailable');
  }

  String _packageImageUrl(
    Map<String, dynamic> pkg,
  ) {
    final cover = (pkg['cover_image_url'] as String?) ?? '';

    if (cover.isNotEmpty) {
      return cover;
    }

    return (pkg['image_url'] as String?) ?? '';
  }

  String _packagePriceText(
    Map<String, dynamic> pkg,
  ) {
    final text = (pkg['price_text'] as String?) ?? '';

    if (text.isNotEmpty) {
      return text;
    }

    final budget = pkg['estimated_budget'];

    if (budget != null && budget != 0) {
      return 'PHP $budget';
    }

    return '';
  }

  String _spotImageUrl(
    Map<String, dynamic> spot,
  ) {
    final cover = (spot['cover_image_url'] as String?) ?? '';

    if (cover.isNotEmpty) {
      return cover;
    }

    return (spot['image_url'] as String?) ?? '';
  }

  /// Maps raw category text + title/description to a normalized label.
  String _normalizeCategory(
    String raw, {
    String title = '',
    String description = '',
  }) {
    final s = '$raw $title $description'.toLowerCase();

    if (s.contains('museum')) {
      return 'Museum';
    }

    if (s.contains('park') ||
        s.contains('garden') ||
        s.contains('plaza')) {
      return 'Park';
    }

    if (s.contains('resort') ||
        s.contains('pool') ||
        s.contains('beach')) {
      return 'Resort';
    }

    if (s.contains('food') ||
        s.contains('restaurant') ||
        s.contains('cafe') ||
        s.contains('kape') ||
        s.contains('eat') ||
        s.contains('dining')) {
      return 'Food';
    }

    if (s.contains('church') ||
        s.contains('cathedral') ||
        s.contains('religious') ||
        s.contains('temple') ||
        s.contains('worship')) {
      return 'Religious';
    }

    if (s.contains('histor') ||
        s.contains('heritage') ||
        s.contains('monument') ||
        s.contains('shrine')) {
      return 'Historical';
    }

    if (s.contains('nature') ||
        s.contains('mountain') ||
        s.contains('river') ||
        s.contains('falls') ||
        s.contains('lake') ||
        s.contains('forest') ||
        s.contains('eco')) {
      return 'Nature';
    }

    return 'Attraction';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Named place helpers
  // ─────────────────────────────────────────────────────────────────────────

  bool _isNamedPlaceQuery(
    String message,
  ) {
    final lower = message.toLowerCase().trim();

    const triggers = [
      'where is ',
      "where's ",
      'where can i find ',
      'how to get to ',
      'how to go to ',
      'how do i get to ',
      'how do i go to ',
      'tell me about ',
      'information about ',
      'info about ',
      'what is ',
      "what's the ",
      'describe ',
      'directions to ',
      'i want to visit ',
      "i'd like to visit ",
      'i want to go to ',
      "i'd like to go to ",
      'near ',
      'close to ',
    ];

    if (triggers.any(lower.contains)) {
      return true;
    }

    final words = lower
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    if (words.length <= 4) {
      const generalWords = {
        'suggest',
        'recommend',
        'show',
        'give',
        'list',
        'find',
        'search',
        'cafe',
        'cafes',
        'coffee',
        'restaurant',
        'restaurants',
        'food',
        'spot',
        'spots',
        'places',
        'place',
        'park',
        'parks',
        'church',
        'churches',
        'museum',
        'museums',
        'resort',
        'resorts',
        'beach',
        'historical',
        'nature',
        'religious',
        'cultural',
        'famous',
        'popular',
        'best',
        'top',
        'nearby',
        'around',
        'me',
        'the',
        'a',
        'an',
        'in',
        'at',
        'of',
        'for',
        'and',
        'or',
        'hi',
        'hello',
        'hey',
        'help',
        'what',
        'how',
        'where',
        'when',
        'who',
        'which',
        'can',
        'please',
        'some',
        'any',
        'tell',
        'about',
        'is',
        'are',
        'was',
        'were',
        'will',
        'would',
        'could',
        'should',
        'do',
        'does',
        'did',
        'visit',
        'see',
        'go',
        'get',
      };

      final meaningful = words.where(
        (word) => !generalWords.contains(word),
      );

      if (meaningful.isNotEmpty) {
        return true;
      }
    }

    return false;
  }

  String _extractCityFromAddress(
    String address,
  ) {
    if (address.isEmpty) {
      return '';
    }

    final lower = address.toLowerCase();

    final sorted = [...bulacanMunicipalities]
      ..sort(
        (a, b) => b.name.length.compareTo(a.name.length),
      );

    for (final area in sorted) {
      if (lower.contains(area.name.toLowerCase())) {
        return area.name;
      }
    }

    return '';
  }

  Future<List<Map<String, dynamic>>> _searchNamedPlace(
    String query,
  ) async {
    final cacheKey =
        CitySpotSuggestionService.normalizeText(query);

    final cachedAt = _namedPlaceCachedAt[cacheKey];

    if (_namedPlaceCache.containsKey(cacheKey) &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return _namedPlaceCache[cacheKey]!;
    }

    try {
      final searchQuery =
          '${query.trim()} Bulacan Philippines';

      final apiKey =
          CitySpotSuggestionService.resolveApiKey();

      final gateway =
          GooglePlacesGateway(apiKey: apiKey);

      final body = await gateway.request(
        'textSearch',
        {
          'query': searchQuery,
          'region': 'ph',
        },
      );

      final results =
          (body['results'] as List?) ?? const [];

      final spots = <Map<String, dynamic>>[];

      for (final raw in results.take(6)) {
        final item =
            raw as Map<String, dynamic>;

        final name =
            (item['name'] as String?)?.trim() ?? '';

        if (name.isEmpty) {
          continue;
        }

        final address =
            (item['formatted_address'] as String?)
                    ?.trim() ??
                '';

        final city =
            _extractCityFromAddress(address);

        if (city.isEmpty &&
            !address.toLowerCase().contains('bulacan')) {
          continue;
        }

        final geometry =
            item['geometry'] as Map<String, dynamic>?;

        final loc =
            geometry?['location']
                as Map<String, dynamic>?;

        final lat =
            ((loc?['lat'] as num?) ?? 0.0)
                .toDouble();

        final lng =
            ((loc?['lng'] as num?) ?? 0.0)
                .toDouble();

        final rating =
            ((item['rating'] as num?) ?? 4.5)
                .toDouble();

        final placeId =
            (item['place_id'] as String?) ?? name;

        final types =
            ((item['types'] as List?) ?? const [])
                .map((e) => e.toString())
                .toList();

        final photos =
            (item['photos'] as List?) ?? const [];

        final photoRef = photos.isEmpty
            ? ''
            : ((photos.first as Map)['photo_reference']
                    as String?) ??
                '';

        final proxyImageUrl =
            (item['_proxy_image_url'] as String?)
                    ?.trim() ??
                '';

        final proxyMapUrl =
            (item['_proxy_static_map_url'] as String?)
                    ?.trim() ??
                '';

        final imageUrl = proxyImageUrl.isNotEmpty
            ? proxyImageUrl
            : photoRef.isNotEmpty
                ? gateway.photoUrl(photoRef)
                : proxyMapUrl;

        final category = _normalizeCategory(
          types.join(' '),
          title: name,
        );

        final municipality =
            city.isNotEmpty ? city : 'Bulacan';

        spots.add({
          'id': placeId,
          'title': name,
          'municipality': municipality,
          'city': municipality,
          'latitude': lat,
          'longitude': lng,
          'rating': rating,
          'image_url': imageUrl,
          'cover_image_url': '',
          'address': address,
          'google_place_id': placeId,
          'description':
              '$category landmark in $municipality.',
          '_category': category,
          '_isNamedResult': true,
        });
      }

      _namedPlaceCache[cacheKey] = spots;
      _namedPlaceCachedAt[cacheKey] =
          DateTime.now();

      debugPrint(
        '[Gemini] Named place "$query": '
        '${spots.length} results',
      );

      return spots;
    } catch (e) {
      debugPrint(
        '[Gemini] Named place search failed: $e',
      );

      return const [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // City detection
  // ─────────────────────────────────────────────────────────────────────────

  String? _detectCity(
    String message,
  ) {
    final lower = message.toLowerCase();

    final sorted = [...bulacanMunicipalities]
      ..sort(
        (a, b) => b.name.length.compareTo(a.name.length),
      );

    for (final area in sorted) {
      if (lower.contains(area.name.toLowerCase())) {
        return area.name;
      }
    }

    if (lower.contains('baliwag') ||
        lower.contains('baliuag')) {
      return 'Baliwag';
    }

    if (lower.contains('sta. maria') ||
        lower.contains('sta maria')) {
      return 'Santa Maria';
    }

    if (lower.contains('sjdm')) {
      return 'San Jose del Monte';
    }

    if (lower.contains('drt')) {
      return 'Dona Remedios Trinidad';
    }

    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Data fetching
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>>
      _getGoogleSpotsForCity(
    String city,
  ) async {
    final now = DateTime.now();

    final cachedAt =
        _googleSpotsCachedAt[city];

    if (_googleSpotsCache.containsKey(city) &&
        cachedAt != null &&
        now.difference(cachedAt) < _cacheTtl) {
      return _googleSpotsCache[city]!;
    }

    try {
      final service =
          CitySpotSuggestionService();

      final suggestions =
          await service.fetchSuggestions(
        city: city,
        province: 'Bulacan',
        limit: 30,
      );

      final spots = suggestions
          .map(
            (s) {
              final municipality =
                  s.city.isNotEmpty
                      ? s.city
                      : city;

              return <String, dynamic>{
                'id': s.id,
                'title': s.title,
                'municipality': municipality,
                'city': municipality,
                'latitude': s.latitude,
                'longitude': s.longitude,
                'rating': s.rating,
                'image_url': s.imageUrl,
                'cover_image_url': '',
                'address': s.address,
                'google_place_id': s.id,
                'description': s.description,
                '_category':
                    _normalizeCategory(
                  s.category,
                  title: s.title,
                  description: s.description,
                ),
              };
            },
          )
          .toList(growable: false);

      _googleSpotsCache[city] = spots;
      _googleSpotsCachedAt[city] = now;

      debugPrint(
        '[Gemini] Google spots for $city: '
        '${spots.length}',
      );

      return spots;
    } catch (e) {
      debugPrint(
        '[Gemini] Google spot fetch for '
        '"$city" failed: $e',
      );

      return _googleSpotsCache[city] ??
          const [];
    }
  }

  Future<List<Map<String, dynamic>>>
      _getPackages() async {
    final now = DateTime.now();

    if (_cachedPackages != null &&
        _packagesCachedAt != null &&
        now.difference(_packagesCachedAt!) <
            _cacheTtl) {
      return _cachedPackages!;
    }

    try {
      final rows =
          await Supabase.instance.client
              .from('tour_packages')
              .select(
                'id, title, subtitle, description, city, '
                'price_text, estimated_budget, image_url, '
                'cover_image_url, status, visibility_status',
              )
              .isFilter('archived_at', null)
              .eq(
                'visibility_status',
                'visible',
              )
              .neq('status', 'draft')
              .neq('status', 'archived')
              .limit(60);

      _cachedPackages = (rows as List)
          .map(
            (row) =>
                Map<String, dynamic>.from(
              row as Map,
            ),
          )
          .toList(growable: false);

      _packagesCachedAt = now;

      debugPrint(
        '[Gemini] Loaded '
        '${_cachedPackages!.length} '
        'packages for chatbot',
      );
    } catch (e) {
      debugPrint(
        '[Gemini] Package fetch failed: $e',
      );

      _cachedPackages ??= const [];
    }

    return _cachedPackages!;
  }

  Future<List<Map<String, dynamic>>>
      _getSpots() async {
    final now = DateTime.now();

    if (_cachedSpots != null &&
        _spotsCachedAt != null &&
        now.difference(_spotsCachedAt!) <
            _cacheTtl) {
      return _cachedSpots!;
    }

    try {
      final results = await Future.wait([
        Supabase.instance.client
            .from('tourist_spots')
            .select(
              'id, title, city, municipality, '
              'latitude, longitude, rating, '
              'image_url, description, address, '
              'google_place_id, category_id',
            )
            .neq('status', 'archived')
            .limit(100),
        Supabase.instance.client
            .from('tourism_categories')
            .select('id, name')
            .limit(50),
      ]);

      final categoryNames =
          <String, String>{
        for (final row
            in (results[1] as List)
                .whereType<Map>())
          '${row['id']}':
              ((row['name'] as String?) ?? '')
                  .trim(),
      };

      _cachedSpots = (results[0] as List)
          .whereType<Map>()
          .map(
            (row) {
              final map =
                  Map<String, dynamic>.from(
                row,
              );

              final rawCat =
                  categoryNames[
                          '${map['category_id']}'] ??
                      '';

              map['_category'] =
                  _normalizeCategory(
                rawCat,
                title:
                    (map['title'] as String?) ??
                        '',
                description:
                    (map['description']
                            as String?) ??
                        '',
              );

              return map;
            },
          )
          .toList(growable: false);

      _spotsCachedAt = now;

      debugPrint(
        '[Gemini] Loaded '
        '${_cachedSpots!.length} spots '
        'for chatbot',
      );
    } catch (e) {
      debugPrint(
        '[Gemini] Spot fetch failed: $e',
      );

      _cachedSpots ??= const [];
    }

    return _cachedSpots!;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Prompt builder
  // ─────────────────────────────────────────────────────────────────────────

  String _buildEnrichedSystemPrompt(
    String basePrompt,
    List<Map<String, dynamic>> spots,
    List<Map<String, dynamic>> packages,
  ) {
    final spotCatalog = spots.map(
      (s) {
        final raw =
            (s['description'] as String?) ?? '';

        final short = raw.length > 80
            ? '${raw.substring(0, 80)}...'
            : raw;

        final municipality =
            ((s['municipality'] as String?)
                        ?.trim()
                        .isNotEmpty ??
                    false)
                ? s['municipality'] as String
                : (s['city'] as String?) ?? '';

        return {
          'id': '${s['id']}',
          'name':
              (s['title'] as String?) ?? '',
          'municipality': municipality,
          'category':
              s['_category'] as String? ??
                  'Attraction',
          'description': short,
        };
      },
    ).toList();

    final packageCatalog = packages.map(
      (pkg) {
        final raw =
            (pkg['description'] as String?) ??
                '';

        final short = raw.length > 100
            ? '${raw.substring(0, 100)}...'
            : raw;

        return {
          'id': '${pkg['id']}',
          'name': pkg['title'] ?? '',
          'municipality':
              pkg['city'] ?? '',
          'description': short,
          'price':
              _packagePriceText(pkg),
        };
      },
    ).toList();

    return '''
$basePrompt

You are the TourisTrike AI Assistant for tourism in Bulacan, Philippines.

Use the application's REAL tourism data supplied below.

Do not invent:
- tourist spots
- package IDs
- package names
- prices
- municipalities
- booking availability

RESPONSE FORMAT

Always return ONE valid JSON object.

Required structure:

{
  "reply": "Short natural response for the tourist.",
  "spots": [],
  "packages": []
}

Do not return Markdown.
Do not return ```json fences.
Do not add text before or after the JSON object.

── INTENT DETECTION ──

NAMED PLACE:
If the user asks about a specific named place:
- Find that exact place in AVAILABLE SPOTS when possible.
- Put the matching place first.
- You may add up to 4 relevant nearby/similar spots.
- Explain what the requested place is in "reply".

SPOTS:
If the user asks about:
- spots
- attractions
- landmarks
- cafes
- restaurants
- food
- historical places
- nature
- churches
- museums
- parks
- resorts

Populate "spots".
Keep "packages" empty unless packages are clearly requested.

PACKAGES:
If the user asks about:
- package
- tour package
- booking package
- available tours
- package price
- trip package

Populate "packages".
Keep "spots" empty unless spots are explicitly requested too.

GENERAL:
For general tourism recommendations:
- Prefer relevant spots.
- Packages may be added only when clearly useful.

── SPOT RULES ──

- ONLY use IDs from AVAILABLE SPOTS.
- NEVER create or guess a spot ID.
- Prefer results matching the requested municipality.
- Maximum 5 spots.

Category matching:

historical/history/heritage
→ Historical

nature/eco/mountain/river/falls/lake/forest
→ Nature

food/cafe/coffee/restaurant/dining/eat
→ Food

church/religious/cathedral/temple/shrine
→ Religious

museum
→ Museum

park/garden/plaza
→ Park

resort/beach/pool
→ Resort

If the user asks for cafes or food and none are available in that city:
- Explain that no matching food/cafe listings are currently available.
- You may recommend other valid tourism spots from the same city.

If nothing matches:
"spots": []

── PACKAGE RULES ──

- ONLY use IDs from AVAILABLE PACKAGES.
- NEVER invent a package.
- NEVER invent a package ID.
- Maximum 4 packages.

If matching packages are available:
- Put their exact IDs in "packages".

If no matching package exists:
- Return "packages": []
- Clearly tell the tourist that no matching TourisTrike package is currently available.

For package items, the ID is the most important field.
You may return:

{
  "id": "REAL_ID"
}

The application will load the official package name, image, municipality,
description and price from its database.

── AVAILABLE SPOTS ──

${jsonEncode(spotCatalog)}

── AVAILABLE PACKAGES ──

${jsonEncode(packageCatalog)}
''';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Request body
  // ─────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> _buildBody(
    String userMessage,
    List<GeminiTurn> history,
    String systemPrompt,
  ) {
    final contents =
        <Map<String, dynamic>>[
      for (final turn in history)
        {
          'role': turn.role,
          'parts': [
            {
              'text': turn.text,
            },
          ],
        },
      {
        'role': 'user',
        'parts': [
          {
            'text': userMessage,
          },
        ],
      },
    ];

    return {
      'contents': contents,
      'generationConfig': {
        'temperature': 0.4,
        'maxOutputTokens': 1024,
        'responseMimeType':
            'application/json',

        // Force Gemini toward the exact structure
        // expected by the TourisTrike client.
        'responseSchema': {
          'type': 'OBJECT',
          'properties': {
            'reply': {
              'type': 'STRING',
            },
            'spots': {
              'type': 'ARRAY',
              'items': {
                'type': 'OBJECT',
                'properties': {
                  'id': {
                    'type': 'STRING',
                  },
                  'name': {
                    'type': 'STRING',
                  },
                },
                'required': [
                  'id',
                ],
              },
            },
            'packages': {
              'type': 'ARRAY',
              'items': {
                'type': 'OBJECT',
                'properties': {
                  'id': {
                    'type': 'STRING',
                  },
                  'name': {
                    'type': 'STRING',
                  },
                  'municipality': {
                    'type': 'STRING',
                  },
                  'description': {
                    'type': 'STRING',
                  },
                  'price': {
                    'type': 'STRING',
                  },
                },
                'required': [
                  'id',
                ],
              },
            },
          },
          'required': [
            'reply',
            'spots',
            'packages',
          ],
        },
      },
      'system_instruction': {
        'parts': [
          {
            'text': systemPrompt,
          },
        ],
      },
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HTTP
  // ─────────────────────────────────────────────────────────────────────────

  Future<String> _postRequest({
    required String model,
    required Map<String, dynamic> body,
    required String key,
  }) async {
    final url = Uri.parse(
      '$_baseUrl/$model:generateContent?key=$key',
    );

    debugPrint(
      '[Gemini] POST → $model',
    );

    late http.Response res;

    try {
      res = await http
          .post(
            url,
            headers: {
              'Content-Type':
                  'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(
            const Duration(seconds: 30),
          );
    } catch (e) {
      debugPrint(
        '[Gemini] Network error: $e',
      );

      throw Exception(
        'Network error: $e',
      );
    }

    debugPrint(
      '[Gemini] Status: ${res.statusCode}',
    );

    debugPrint(
      '[Gemini] Response length: '
      '${res.body.length} chars',
    );

    if (res.statusCode != 200) {
      String msg =
          'HTTP ${res.statusCode}';

      try {
        final errJson =
            jsonDecode(res.body) as Map?;

        msg =
            errJson?['error']?['message']
                    as String? ??
                msg;
      } catch (_) {
        // Keep the HTTP fallback message.
      }

      debugPrint(
        '[Gemini] API error: $msg',
      );

      if (_isOverload(
        res.statusCode,
        msg,
      )) {
        throw _OverloadException(msg);
      }

      throw Exception(msg);
    }

    try {
      final decoded =
          jsonDecode(res.body);

      if (decoded is! Map) {
        throw const FormatException(
          'Gemini response envelope '
          'was not an object.',
        );
      }

      final json =
          Map<String, dynamic>.from(
        decoded,
      );

      final candidates =
          (json['candidates'] as List?) ??
              const [];

      if (candidates.isEmpty) {
        throw Exception(
          'No candidates in response',
        );
      }

      final firstCandidate =
          candidates.first;

      if (firstCandidate is! Map) {
        throw const FormatException(
          'Invalid candidate format.',
        );
      }

      final candidate =
          Map<String, dynamic>.from(
        firstCandidate,
      );

      final content =
          candidate['content'];

      if (content is! Map) {
        throw const FormatException(
          'Candidate content missing.',
        );
      }

      final contentMap =
          Map<String, dynamic>.from(
        content,
      );

      final parts =
          (contentMap['parts'] as List?) ??
              const [];

      if (parts.isEmpty) {
        throw Exception(
          'No parts in response',
        );
      }

      final firstPart = parts.first;

      if (firstPart is! Map) {
        throw const FormatException(
          'Invalid Gemini part.',
        );
      }

      final partMap =
          Map<String, dynamic>.from(
        firstPart,
      );

      final text =
          partMap['text']?.toString() ?? '';

      if (text.trim().isEmpty) {
        throw Exception(
          'Empty text in response',
        );
      }

      return text.trim();
    } catch (e) {
      debugPrint(
        '[Gemini] Provider response '
        'parse error: $e',
      );

      throw Exception(
        'Failed to parse Gemini response: $e',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Structured-response helpers
  // ─────────────────────────────────────────────────────────────────────────

  dynamic _decodeStructuredJson(
    String raw,
  ) {
    var text = raw.trim();

    // Remove an unexpected Markdown fence.
    final fenceMatch = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      caseSensitive: false,
    ).firstMatch(text);

    if (fenceMatch != null) {
      text =
          fenceMatch.group(1)!.trim();
    }

    dynamic decoded;

    try {
      decoded = jsonDecode(text);
    } catch (_) {
      // Some models/providers may accidentally add
      // surrounding text despite JSON mode.
      final firstBrace =
          text.indexOf('{');

      final lastBrace =
          text.lastIndexOf('}');

      if (firstBrace < 0 ||
          lastBrace <= firstBrace) {
        rethrow;
      }

      final jsonSection =
          text.substring(
        firstBrace,
        lastBrace + 1,
      );

      decoded =
          jsonDecode(jsonSection);
    }

    // Handle double-encoded JSON such as:
    //
    // "{\"reply\":\"Hello\",\"spots\":[],\"packages\":[]}"
    //
    for (var i = 0;
        i < 2 && decoded is String;
        i++) {
      final nested =
          decoded.trim();

      if (nested.isEmpty) {
        break;
      }

      decoded =
          jsonDecode(nested);
    }

    return decoded;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Response parser
  // ─────────────────────────────────────────────────────────────────────────

  GeminiChatResponse _parseResponse(
    String raw,
    Map<String, Map<String, dynamic>>
        packageById,
    Map<String, Map<String, dynamic>>
        spotById,
  ) {
    try {
      final decoded =
          _decodeStructuredJson(raw);

      if (decoded is! Map) {
        throw const FormatException(
          'Gemini response is not '
          'a JSON object.',
        );
      }

      final json =
          Map<String, dynamic>.from(
        decoded,
      );

      final reply =
          json['reply']
                  ?.toString()
                  .trim() ??
              '';

      // ─────────────────────────────────────────────────────────────────────
      // Packages
      // ─────────────────────────────────────────────────────────────────────

      final packages =
          <ChatPackageSuggestion>[];

      final packagesRaw =
          json['packages'];

      if (packagesRaw is List) {
        for (final item
            in packagesRaw) {
          if (item is! Map) {
            continue;
          }

          final returnedMap =
              Map<String, dynamic>.from(
            item,
          );

          final id =
              returnedMap['id']
                      ?.toString()
                      .trim() ??
                  '';

          if (id.isEmpty) {
            continue;
          }

          final source =
              packageById[id];

          // Reject hallucinated package IDs.
          if (source == null) {
            debugPrint(
              '[Gemini] Ignored unknown '
              'package ID: $id',
            );

            continue;
          }

          // Hydrate from REAL Supabase data.
          //
          // Gemini only chooses the package ID.
          // Official name/image/municipality/
          // description/price come from the app.
          final hydrated =
              <String, dynamic>{
            ...returnedMap,
            'id': id,
            'name':
                (source['title']
                        as String?) ??
                    returnedMap['name'] ??
                    '',
            'title':
                (source['title']
                        as String?) ??
                    returnedMap['name'] ??
                    '',
            'municipality':
                (source['city']
                        as String?) ??
                    returnedMap[
                        'municipality'] ??
                    '',
            'city':
                (source['city']
                        as String?) ??
                    returnedMap[
                        'municipality'] ??
                    '',
            'description':
                (source['description']
                        as String?) ??
                    returnedMap[
                        'description'] ??
                    '',
            'price':
                _packagePriceText(
              source,
            ),
            'price_text':
                _packagePriceText(
              source,
            ),
          };

          try {
            final suggestion =
                ChatPackageSuggestion
                    .fromJson(
              hydrated,
              imageUrlOverride:
                  _packageImageUrl(
                source,
              ),
            );

            if (suggestion
                .name.isNotEmpty) {
              packages.add(
                suggestion,
              );
            }
          } catch (e) {
            debugPrint(
              '[Gemini] Package card '
              'parse failed for $id: $e',
            );
          }
        }
      }

      // ─────────────────────────────────────────────────────────────────────
      // Spots
      // ─────────────────────────────────────────────────────────────────────

      final spots =
          <ChatSpotSuggestion>[];

      final spotsRaw =
          json['spots'];

      if (spotsRaw is List) {
        for (final item in spotsRaw) {
          if (item is! Map) {
            continue;
          }

          final returnedMap =
              Map<String, dynamic>.from(
            item,
          );

          final id =
              returnedMap['id']
                      ?.toString()
                      .trim() ??
                  '';

          if (id.isEmpty) {
            continue;
          }

          // Gemini is only allowed to return
          // real IDs that exist in our lookup.
          final cached =
              spotById[id];

          if (cached == null) {
            debugPrint(
              '[Gemini] Ignored unknown '
              'spot ID: $id',
            );

            continue;
          }

          final name =
              (cached['title']
                          as String?)
                      ?.trim() ??
                  returnedMap['name']
                      ?.toString()
                      .trim() ??
                  '';

          if (name.isEmpty) {
            continue;
          }

          final cachedMunicipality =
              (cached['municipality']
                          as String?)
                      ?.trim() ??
                  '';

          final municipality =
              cachedMunicipality.isNotEmpty
                  ? cachedMunicipality
                  : ((cached['city']
                                  as String?) ??
                              returnedMap[
                                  'municipality']
                                  ?.toString() ??
                              returnedMap[
                                  'city']
                                  ?.toString() ??
                              '')
                          .trim();

          final category =
              (cached['_category']
                      as String?) ??
                  returnedMap['category']
                      ?.toString() ??
                  'Attraction';

          final address =
              (cached['address']
                      as String?) ??
                  returnedMap['address']
                      ?.toString() ??
                  '';

          spots.add(
            ChatSpotSuggestion(
              id: id,
              name: name,
              municipality:
                  municipality,
              category: category,
              address: address,
              imageUrl:
                  _spotImageUrl(cached),
              rating:
                  (cached['rating']
                              as num?)
                          ?.toDouble() ??
                      4.5,
              latitude:
                  (cached['latitude']
                              as num?)
                          ?.toDouble() ??
                      0,
              longitude:
                  (cached['longitude']
                              as num?)
                          ?.toDouble() ??
                      0,
              googlePlaceId:
                  (cached[
                              'google_place_id']
                          as String?) ??
                      id,
            ),
          );
        }
      }

      var safeReply = reply;

      if (safeReply.isEmpty) {
        if (packages.isNotEmpty) {
          safeReply =
              'Here are some TourisTrike '
              'packages you can explore.';
        } else if (spots.isNotEmpty) {
          safeReply =
              'Here are some places '
              'you can explore.';
        } else {
          safeReply =
              'I could not find a '
              'matching result right now.';
        }
      }

      return GeminiChatResponse(
        reply: safeReply,
        spots: spots,
        packages: packages,
      );
    } catch (e) {
      debugPrint(
        '[Gemini] Structured response '
        'parse failed: $e',
      );

      // CRITICAL:
      //
      // Do NOT return `raw` here.
      //
      // Returning raw caused JSON such as
      // {"reply":"...", "spots":[]}
      // to appear directly inside the chat UI.
      return const GeminiChatResponse(
        reply:
            'I had trouble formatting that '
            'response. Please try asking again.',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  Future<GeminiChatResponse> chat({
    required String userMessage,
    List<GeminiTurn> history = const [],
    String? systemPrompt,
  }) async {
    final key = _apiKey;

    if (key.isEmpty) {
      throw Exception(
        'GEMINI_API_KEY was not provided '
        'with --dart-define.',
      );
    }

    // Do not print any part of the secret.
    debugPrint(
      '[Gemini] API key configured.',
    );

    // ───────────────────────────────────────────────────────────────────────
    // Step 1: Detect municipality and intent
    // ───────────────────────────────────────────────────────────────────────

    final detectedCity =
        _detectCity(userMessage);

    final isNamedQuery =
        _isNamedPlaceQuery(
      userMessage,
    );

    // ───────────────────────────────────────────────────────────────────────
    // Step 2: Fetch TourisTrike data
    // ───────────────────────────────────────────────────────────────────────

    final dataFutures =
        <Future<List<Map<String, dynamic>>>>[
      _getPackages(),
      _getSpots(),
      if (detectedCity != null)
        _getGoogleSpotsForCity(
          detectedCity,
        ),
      if (isNamedQuery)
        _searchNamedPlace(
          userMessage,
        ),
    ];

    final results =
        await Future.wait(
      dataFutures,
    );

    final allPackages =
        results[0];

    final supabaseSpots =
        results[1];

    // ───────────────────────────────────────────────────────────────────────
    // Step 3: Filter package catalogue by requested municipality
    // ───────────────────────────────────────────────────────────────────────

    List<Map<String, dynamic>>
        packages;

    if (detectedCity == null) {
      packages = allPackages;
    } else {
      final requestedCity =
          CitySpotSuggestionService
              .normalizeText(
        detectedCity,
      );

      packages = allPackages.where(
        (pkg) {
          final packageCity =
              CitySpotSuggestionService
                  .normalizeText(
            (pkg['city'] as String?) ??
                '',
          );

          if (packageCity.isEmpty) {
            return false;
          }

          return packageCity ==
                  requestedCity ||
              packageCity.contains(
                requestedCity,
              ) ||
              requestedCity.contains(
                packageCity,
              );
        },
      ).toList(growable: false);
    }

    debugPrint(
      '[Gemini] Packages: '
      'all=${allPackages.length} '
      'filtered=${packages.length} '
      'city=${detectedCity ?? "none"}',
    );

    // ───────────────────────────────────────────────────────────────────────
    // Step 4: Read optional Google results
    // ───────────────────────────────────────────────────────────────────────

    var resultIdx = 2;

    final googleCitySpots =
        detectedCity != null
            ? results[resultIdx++]
            : <Map<String, dynamic>>[];

    final namedSpots =
        isNamedQuery
            ? results[resultIdx]
            : <Map<String, dynamic>>[];

    // ───────────────────────────────────────────────────────────────────────
    // Step 5: Determine working municipality
    // ───────────────────────────────────────────────────────────────────────

    String? workingCity =
        detectedCity;

    if (workingCity == null &&
        namedSpots.isNotEmpty) {
      final foundCity =
          (namedSpots.first[
                      'municipality']
                  as String?)
              ?.trim() ??
          '';

      if (foundCity.isNotEmpty &&
          foundCity != 'Bulacan') {
        workingCity =
            foundCity;
      }
    }

    List<Map<String, dynamic>>
        extraCitySpots = const [];

    if (workingCity != null &&
        workingCity != detectedCity) {
      extraCitySpots =
          await _getGoogleSpotsForCity(
        workingCity,
      );
    }

    // ───────────────────────────────────────────────────────────────────────
    // Step 6: Merge spot sources without duplicates
    // ───────────────────────────────────────────────────────────────────────

    final seenTitles =
        <String>{};

    final mergedSpots =
        <Map<String, dynamic>>[];

    void addSpots(
      Iterable<Map<String, dynamic>> src,
    ) {
      for (final spot in src) {
        final title =
            CitySpotSuggestionService
                .normalizeText(
          (spot['title']
                  as String?) ??
              '',
        );

        if (title.isNotEmpty &&
            seenTitles.add(title)) {
          mergedSpots.add(
            spot,
          );
        }
      }
    }

    if (workingCity != null) {
      final cityNorm =
          CitySpotSuggestionService
              .normalizeText(
        workingCity,
      );

      final citySupabaseSpots =
          supabaseSpots.where(
        (spot) {
          final rawMunicipality =
              ((spot['municipality']
                              as String?)
                          ?.isNotEmpty ==
                      true)
                  ? spot['municipality']
                      as String
                  : (spot['city']
                          as String?) ??
                      '';

          final municipality =
              CitySpotSuggestionService
                  .normalizeText(
            rawMunicipality,
          );

          return municipality ==
                  cityNorm ||
              municipality.contains(
                cityNorm,
              ) ||
              cityNorm.contains(
                municipality,
              );
        },
      );

      // Specific named result first.
      addSpots(namedSpots);

      // Then app-managed spots.
      addSpots(
        citySupabaseSpots,
      );

      // Then Google suggestions.
      addSpots(
        googleCitySpots,
      );

      addSpots(
        extraCitySpots,
      );
    } else {
      addSpots(namedSpots);
      addSpots(
        supabaseSpots,
      );
    }

    final spots =
        mergedSpots;

    debugPrint(
      '[Gemini] Spots: '
      'named=${namedSpots.length} '
      'city=${googleCitySpots.length} '
      'extra=${extraCitySpots.length} '
      'merged=${spots.length}',
    );

    // ───────────────────────────────────────────────────────────────────────
    // Step 7: Build trusted lookup maps
    // ───────────────────────────────────────────────────────────────────────

    final packageById =
        <String, Map<String, dynamic>>{
      for (final pkg in packages)
        '${pkg['id']}': pkg,
    };

    final spotById =
        <String, Map<String, dynamic>>{
      for (final spot in spots)
        '${spot['id']}': spot,
    };

    // ───────────────────────────────────────────────────────────────────────
    // Step 8: ALWAYS build enriched system prompt
    // ───────────────────────────────────────────────────────────────────────

    // Previously, the enriched prompt was only created
    // when `systemPrompt != null`.
    //
    // That could cause Gemini to receive no catalogue,
    // package rules, spot rules or JSON instructions.
    final enrichedPrompt =
        _buildEnrichedSystemPrompt(
      systemPrompt ?? '',
      spots,
      packages,
    );

    final body =
        _buildBody(
      userMessage,
      history,
      enrichedPrompt,
    );

    // ───────────────────────────────────────────────────────────────────────
    // Step 9: Primary model + exponential backoff
    // ───────────────────────────────────────────────────────────────────────

    for (var attempt = 0;
        attempt < _maxAttempts;
        attempt++) {
      if (attempt > 0) {
        final delay =
            Duration(
          seconds:
              1 << (attempt - 1),
        );

        debugPrint(
          '[Gemini] Overloaded – '
          'retrying in '
          '${delay.inSeconds}s '
          '(attempt '
          '${attempt + 1}/'
          '$_maxAttempts)',
        );

        await Future.delayed(
          delay,
        );
      }

      try {
        final raw =
            await _postRequest(
          model: _primaryModel,
          body: body,
          key: key,
        );

        return _parseResponse(
          raw,
          packageById,
          spotById,
        );
      } on _OverloadException catch (e) {
        debugPrint(
          '[Gemini] Overload on '
          'attempt ${attempt + 1}: '
          '${e.message}',
        );
      }
    }

    // ───────────────────────────────────────────────────────────────────────
    // Step 10: One-shot fallback model
    // ───────────────────────────────────────────────────────────────────────

    debugPrint(
      '[Gemini] Primary exhausted – '
      'trying fallback: '
      '$_fallbackModel',
    );

    try {
      final raw =
          await _postRequest(
        model: _fallbackModel,
        body: body,
        key: key,
      );

      return _parseResponse(
        raw,
        packageById,
        spotById,
      );
    } catch (e) {
      debugPrint(
        '[Gemini] Fallback also '
        'failed: $e',
      );

      throw Exception(
        'AI assistant is currently busy. '
        'Please try again in a moment.',
      );
    }
  }
}