import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'chatbot_models.dart';

/// A single message in the conversation history sent to Gemini.
class GeminiTurn {
  const GeminiTurn({required this.role, required this.text});

  /// Either `'user'` or `'model'`.
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
/// - Fetches real in-app tourist spots AND packages from Supabase as context
/// - Intent-aware: returns spot cards, package cards, or both based on the query
/// - Automatic retry with exponential back-off on 503 / high-demand errors
/// - One-shot fallback to [_fallbackModel] before giving up
class GeminiService {
  GeminiService._();
  static final GeminiService instance = GeminiService._();

  // ── Model config ──────────────────────────────────────────────────────────
  static const _primaryModel = 'gemini-2.5-flash';
  static const _fallbackModel = 'gemini-1.5-flash';
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// 1 initial attempt + 3 retries = 4 total on the primary model.
  static const _maxAttempts = 4;

  // ── Caches ────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>>? _cachedPackages;
  DateTime? _packagesCachedAt;

  List<Map<String, dynamic>>? _cachedSpots;
  DateTime? _spotsCachedAt;

  // Per-city Google Maps spot cache (populated on demand).
  final Map<String, List<Map<String, dynamic>>> _googleSpotsCache = {};
  final Map<String, DateTime> _googleSpotsCachedAt = {};

  // Named-place search cache keyed by normalized query.
  final Map<String, List<Map<String, dynamic>>> _namedPlaceCache = {};
  final Map<String, DateTime> _namedPlaceCachedAt = {};

  static const _cacheTtl = Duration(minutes: 10);

  String get _apiKey {
    final key = dotenv.env['GEMINI_API_KEY'] ?? '';
    assert(key.isNotEmpty, 'GEMINI_API_KEY is missing in .env');
    return key;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _isOverload(int statusCode, String message) {
    if (statusCode == 503) return true;
    final lower = message.toLowerCase();
    return lower.contains('high demand') ||
        lower.contains('overloaded') ||
        lower.contains('try again later') ||
        lower.contains('service unavailable');
  }

  String _packageImageUrl(Map<String, dynamic> pkg) {
    final cover = (pkg['cover_image_url'] as String?) ?? '';
    return cover.isNotEmpty ? cover : ((pkg['image_url'] as String?) ?? '');
  }

  String _packagePriceText(Map<String, dynamic> pkg) {
    final text = (pkg['price_text'] as String?) ?? '';
    if (text.isNotEmpty) return text;
    final budget = pkg['estimated_budget'];
    if (budget != null && budget != 0) return 'PHP $budget';
    return '';
  }

  String _spotImageUrl(Map<String, dynamic> spot) {
    final cover = (spot['cover_image_url'] as String?) ?? '';
    return cover.isNotEmpty ? cover : ((spot['image_url'] as String?) ?? '');
  }

  /// Maps raw category text + title/description to a normalized label.
  String _normalizeCategory(
    String raw, {
    String title = '',
    String description = '',
  }) {
    final s = '$raw $title $description'.toLowerCase();
    if (s.contains('museum')) return 'Museum';
    if (s.contains('park') || s.contains('garden') || s.contains('plaza')) {
      return 'Park';
    }
    if (s.contains('resort') || s.contains('pool') || s.contains('beach')) {
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

  // ── Named place helpers ───────────────────────────────────────────────────

  /// Returns true when the message appears to be asking about a specific named
  /// place rather than a general category query.
  bool _isNamedPlaceQuery(String message) {
    final lower = message.toLowerCase().trim();

    // Explicit trigger phrases always indicate a named-place intent.
    const triggers = [
      'where is ', "where's ", 'where can i find ',
      'how to get to ', 'how to go to ',
      'how do i get to ', 'how do i go to ',
      'tell me about ', 'information about ', 'info about ',
      'what is ', "what's the ", 'describe ',
      'directions to ',
      'i want to visit ', "i'd like to visit ",
      'i want to go to ', "i'd like to go to ",
      'near ', 'close to ',
    ];
    if (triggers.any((t) => lower.contains(t))) return true;

    // Short messages (≤4 words) that contain at least one word that isn't a
    // common category / general word are likely a named-place query.
    final words =
        lower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= 4) {
      const generalWords = {
        'suggest', 'recommend', 'show', 'give', 'list', 'find', 'search',
        'cafe', 'cafes', 'coffee', 'restaurant', 'restaurants', 'food',
        'spot', 'spots', 'places', 'place', 'park', 'parks',
        'church', 'churches', 'museum', 'museums', 'resort', 'resorts',
        'beach', 'historical', 'nature', 'religious', 'cultural',
        'famous', 'popular', 'best', 'top', 'nearby', 'around',
        'me', 'the', 'a', 'an', 'in', 'at', 'of', 'for', 'and', 'or',
        'hi', 'hello', 'hey', 'help', 'what', 'how', 'where', 'when',
        'who', 'which', 'can', 'please', 'some', 'any', 'tell', 'about',
        'is', 'are', 'was', 'were', 'will', 'would', 'could', 'should',
        'do', 'does', 'did', 'visit', 'see', 'go', 'get',
      };
      final meaningful = words.where((w) => !generalWords.contains(w));
      if (meaningful.isNotEmpty) return true;
    }

    return false;
  }

  /// Extracts the Bulacan municipality name from a Google Maps address string.
  String _extractCityFromAddress(String address) {
    if (address.isEmpty) return '';
    final lower = address.toLowerCase();
    final sorted = [...bulacanMunicipalities]
      ..sort((a, b) => b.name.length.compareTo(a.name.length));
    for (final area in sorted) {
      if (lower.contains(area.name.toLowerCase())) return area.name;
    }
    return '';
  }

  /// Searches Google Maps for the specific place(s) named in [query]
  /// (e.g. "Barasoain Church", "SM Malolos"). Results are only kept when
  /// they are verifiably inside Bulacan. Cached by normalized query.
  Future<List<Map<String, dynamic>>> _searchNamedPlace(String query) async {
    final cacheKey = CitySpotSuggestionService.normalizeText(query);
    final cachedAt = _namedPlaceCachedAt[cacheKey];
    if (_namedPlaceCache.containsKey(cacheKey) &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return _namedPlaceCache[cacheKey]!;
    }

    try {
      final searchQuery = '${query.trim()} Bulacan Philippines';
      final encoded = Uri.encodeQueryComponent(searchQuery);
      final apiKey = CitySpotSuggestionService.resolveApiKey();
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/textsearch/json'
        '?query=$encoded&region=ph&key=$apiKey',
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['status'] != 'OK') return const [];

      final results = (body['results'] as List?) ?? const [];
      final spots = <Map<String, dynamic>>[];

      for (final raw in results.take(6)) {
        final item = raw as Map<String, dynamic>;
        final name = (item['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;

        final address = (item['formatted_address'] as String?)?.trim() ?? '';
        final city = _extractCityFromAddress(address);

        // Keep only results that are actually in Bulacan.
        if (city.isEmpty && !address.toLowerCase().contains('bulacan')) {
          continue;
        }

        final geometry = item['geometry'] as Map<String, dynamic>?;
        final loc = geometry?['location'] as Map<String, dynamic>?;
        final lat = ((loc?['lat'] as num?) ?? 0.0).toDouble();
        final lng = ((loc?['lng'] as num?) ?? 0.0).toDouble();
        final rating = ((item['rating'] as num?) ?? 4.5).toDouble();
        final placeId = (item['place_id'] as String?) ?? name;
        final types = ((item['types'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList();

        // Photo URL
        final photos = (item['photos'] as List?) ?? const [];
        final photoRef = photos.isEmpty
            ? ''
            : ((photos.first as Map)['photo_reference'] as String?) ?? '';
        final imageUrl = photoRef.isEmpty
            ? ''
            : 'https://maps.googleapis.com/maps/api/place/photo'
                '?maxwidth=900'
                '&photo_reference=${Uri.encodeComponent(photoRef)}'
                '&key=$apiKey';

        final category = _normalizeCategory(types.join(' '), title: name);
        final municipality = city.isNotEmpty ? city : 'Bulacan';

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
          'description': '$category landmark in $municipality.',
          '_category': category,
          '_isNamedResult': true,
        });
      }

      _namedPlaceCache[cacheKey] = spots;
      _namedPlaceCachedAt[cacheKey] = DateTime.now();
      debugPrint('[Gemini] Named place "$query": ${spots.length} results');
      return spots;
    } catch (e) {
      debugPrint('[Gemini] Named place search failed: $e');
      return const [];
    }
  }

  // ── City detection ────────────────────────────────────────────────────────

  /// Returns the canonical municipality name if one is mentioned in [message].
  String? _detectCity(String message) {
    final lower = message.toLowerCase();

    // Sort longest names first to avoid prefix false-positives.
    final sorted = [...bulacanMunicipalities]
      ..sort((a, b) => b.name.length.compareTo(a.name.length));

    for (final area in sorted) {
      if (lower.contains(area.name.toLowerCase())) return area.name;
    }

    // Common alternate spellings / abbreviations.
    if (lower.contains('baliwag') || lower.contains('baliuag')) {
      return 'Baliwag';
    }
    if (lower.contains('sta. maria') || lower.contains('sta maria')) {
      return 'Santa Maria';
    }
    if (lower.contains('sjdm')) return 'San Jose del Monte';
    if (lower.contains('drt')) return 'Dona Remedios Trinidad';

    return null;
  }

  // ── Data fetching ─────────────────────────────────────────────────────────

  /// Fetches live Google Maps spots for [city] (same source as the explore
  /// screen). Results are cached for [_cacheTtl] per city.
  Future<List<Map<String, dynamic>>> _getGoogleSpotsForCity(
      String city) async {
    final now = DateTime.now();
    final cachedAt = _googleSpotsCachedAt[city];
    if (_googleSpotsCache.containsKey(city) &&
        cachedAt != null &&
        now.difference(cachedAt) < _cacheTtl) {
      return _googleSpotsCache[city]!;
    }

    try {
      final service = CitySpotSuggestionService();
      // fetchSuggestions resolves the city center internally.
      final suggestions = await service.fetchSuggestions(
        city: city,
        province: 'Bulacan',
        limit: 30,
      );

      final spots = suggestions.map((s) {
        final municipality = s.city.isNotEmpty ? s.city : city;
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
          '_category': _normalizeCategory(
            s.category,
            title: s.title,
            description: s.description,
          ),
        };
      }).toList(growable: false);

      _googleSpotsCache[city] = spots;
      _googleSpotsCachedAt[city] = now;
      debugPrint('[Gemini] Google spots for $city: ${spots.length}');
      return spots;
    } catch (e) {
      debugPrint('[Gemini] Google spot fetch for "$city" failed: $e');
      return _googleSpotsCache[city] ?? const [];
    }
  }

  Future<List<Map<String, dynamic>>> _getPackages() async {
    final now = DateTime.now();
    if (_cachedPackages != null &&
        _packagesCachedAt != null &&
        now.difference(_packagesCachedAt!) < _cacheTtl) {
      return _cachedPackages!;
    }

    try {
      final rows = await Supabase.instance.client
          .from('tour_packages')
          .select(
            'id, title, subtitle, description, city, price_text, '
            'estimated_budget, image_url, cover_image_url, '
            'status, visibility_status',
          )
          .eq('visibility_status', 'visible')
          .neq('status', 'draft')
          .neq('status', 'archived')
          .limit(60);

      _cachedPackages = (rows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);
      _packagesCachedAt = now;
      debugPrint(
          '[Gemini] Loaded ${_cachedPackages!.length} packages for chatbot');
    } catch (e) {
      debugPrint('[Gemini] Package fetch failed: $e');
      _cachedPackages ??= const [];
    }

    return _cachedPackages!;
  }

  Future<List<Map<String, dynamic>>> _getSpots() async {
    final now = DateTime.now();
    if (_cachedSpots != null &&
        _spotsCachedAt != null &&
        now.difference(_spotsCachedAt!) < _cacheTtl) {
      return _cachedSpots!;
    }

    try {
      final results = await Future.wait([
        Supabase.instance.client
            .from('tourist_spots')
            .select(
              'id, title, city, municipality, latitude, longitude, '
              'rating, image_url, description, address, google_place_id, '
              'category_id',
            )
            .neq('status', 'archived')
            .limit(100),
        Supabase.instance.client
            .from('tourism_categories')
            .select('id, name')
            .limit(50),
      ]);

      final categoryNames = <String, String>{
        for (final row in (results[1] as List).whereType<Map>())
          '${row['id']}': ((row['name'] as String?) ?? '').trim(),
      };

      _cachedSpots = (results[0] as List)
          .whereType<Map>()
          .map((row) {
            final map = Map<String, dynamic>.from(row);
            final rawCat = categoryNames['${map['category_id']}'] ?? '';
            map['_category'] = _normalizeCategory(
              rawCat,
              title: (map['title'] as String?) ?? '',
              description: (map['description'] as String?) ?? '',
            );
            return map;
          })
          .toList(growable: false);

      _spotsCachedAt = now;
      debugPrint(
          '[Gemini] Loaded ${_cachedSpots!.length} spots for chatbot');
    } catch (e) {
      debugPrint('[Gemini] Spot fetch failed: $e');
      _cachedSpots ??= const [];
    }

    return _cachedSpots!;
  }

  // ── Prompt builder ────────────────────────────────────────────────────────

  String _buildEnrichedSystemPrompt(
    String basePrompt,
    List<Map<String, dynamic>> spots,
    List<Map<String, dynamic>> packages,
  ) {
    final spotCatalog = spots.map((s) {
      final raw = (s['description'] as String?) ?? '';
      final short = raw.length > 80 ? '${raw.substring(0, 80)}...' : raw;
      final municipality =
          ((s['municipality'] as String?)?.trim().isNotEmpty ?? false)
              ? s['municipality'] as String
              : (s['city'] as String?) ?? '';
      return {
        'id': '${s['id']}',
        'name': (s['title'] as String?) ?? '',
        'municipality': municipality,
        'category': s['_category'] as String? ?? 'Attraction',
        'description': short,
      };
    }).toList();

    final packageCatalog = packages.map((pkg) {
      final raw = (pkg['description'] as String?) ?? '';
      final short = raw.length > 100 ? '${raw.substring(0, 100)}...' : raw;
      return {
        'id': pkg['id'],
        'name': pkg['title'] ?? '',
        'municipality': pkg['city'] ?? '',
        'description': short,
        'price': _packagePriceText(pkg),
      };
    }).toList();

    return '''$basePrompt

RESPONSE FORMAT — You MUST always reply with valid JSON in this exact structure:
{"reply":"<your message>","spots":[],"packages":[]}

── INTENT DETECTION ──
Read what the user is asking and decide which arrays to populate:

• NAMED PLACE intent (user asks about a SPECIFIC named place: "where is X", "tell me about X", "Barasoain Church", "SM Malolos", "Candaba Swamp", etc.) →
  - If that exact place appears in AVAILABLE SPOTS, put it FIRST in "spots"
  - Then add up to 4 more spots of the SAME category from the same city
  - Write a "reply" that describes the named place: what it is, address, why visit
  - If the named place is NOT in AVAILABLE SPOTS, say so and still suggest similar places from AVAILABLE SPOTS
• SPOTS intent (spots/places/attractions/landmarks/cafes/food/historical/nature/religious/museum/park) → populate "spots", keep "packages":[]
• PACKAGES intent (package/tour/itinerary/booking/trip package/how much/price) → populate "packages", keep "spots":[]
• GENERAL intent ("suggest places", "what to visit", "recommend something") → populate "spots" first; optionally add "packages" if highly relevant
• NEVER say "I can only assist with..." for spot/cafe/food/restaurant/place queries — those ARE tourism topics

── SPOT RULES ──
- ONLY include spots from AVAILABLE SPOTS below
- Use the EXACT "id" string value — never fabricate ids
- Filter by municipality/city when the user mentions one
- Category filter map (match user's words to these):
    historical/history/heritage → Historical
    nature/eco/mountain/river/falls/lake/forest → Nature
    food/cafe/coffee/restaurant/dining/eat → Food
    church/religious/cathedral/temple/shrine → Religious
    museum → Museum
    park/garden/plaza → Park
    resort/beach/pool → Resort
- If the user asks for cafes/food → filter by "Food" category; if none exist in that city, reply "No food/cafe spots are currently listed in [city]. Here are other spots you can visit:" and still populate "spots" with other available spots from that city
- If no spots match at all → "spots":[] and explain in "reply"
- Limit to 5 spots maximum per response

── PACKAGE RULES ──
- ONLY include packages from AVAILABLE PACKAGES below
- Use the EXACT "id" value — never fabricate ids
- If no package matches → "packages":[] and say "No matching package is currently available in the app."
- Limit to 4 packages maximum per response

AVAILABLE SPOTS:
${jsonEncode(spotCatalog)}

AVAILABLE PACKAGES:
${jsonEncode(packageCatalog)}
''';
  }

  // ── Request body ──────────────────────────────────────────────────────────

  Map<String, dynamic> _buildBody(
    String userMessage,
    List<GeminiTurn> history,
    String? systemPrompt,
  ) {
    final contents = <Map<String, dynamic>>[
      for (final turn in history)
        {
          'role': turn.role,
          'parts': [
            {'text': turn.text}
          ],
        },
      {
        'role': 'user',
        'parts': [
          {'text': userMessage}
        ],
      },
    ];

    return {
      'contents': contents,
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 1024,
        'responseMimeType': 'application/json',
      },
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        'system_instruction': {
          'parts': [
            {'text': systemPrompt}
          ],
        },
    };
  }

  // ── HTTP ──────────────────────────────────────────────────────────────────

  Future<String> _postRequest({
    required String model,
    required Map<String, dynamic> body,
    required String key,
  }) async {
    final url = Uri.parse('$_baseUrl/$model:generateContent?key=$key');
    debugPrint('[Gemini] POST → $model');

    late http.Response res;
    try {
      res = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('[Gemini] Network error: $e');
      throw Exception('Network error: $e');
    }

    debugPrint('[Gemini] Status: ${res.statusCode}');
    debugPrint('[Gemini] Body:   ${res.body}');

    if (res.statusCode != 200) {
      String msg = 'HTTP ${res.statusCode}';
      try {
        final errJson = jsonDecode(res.body) as Map?;
        msg = errJson?['error']?['message'] as String? ?? msg;
      } catch (_) {}
      debugPrint('[Gemini] API error: $msg');
      if (_isOverload(res.statusCode, msg)) throw _OverloadException(msg);
      throw Exception(msg);
    }

    try {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final candidates = (json['candidates'] as List?) ?? [];
      if (candidates.isEmpty) throw Exception('No candidates in response');

      final content = candidates.first['content'] as Map?;
      final parts = (content?['parts'] as List?) ?? [];
      if (parts.isEmpty) throw Exception('No parts in response');

      final text = (parts.first['text'] as String?) ?? '';
      if (text.trim().isEmpty) throw Exception('Empty text in response');

      return text.trim();
    } catch (e) {
      debugPrint('[Gemini] Parse error: $e');
      throw Exception('Failed to parse Gemini response: $e');
    }
  }

  // ── Response parser ───────────────────────────────────────────────────────

  GeminiChatResponse _parseResponse(
    String raw,
    Map<String, String> packageImageById,
    Map<String, Map<String, dynamic>> spotById,
  ) {
    try {
      var text = raw;
      final fenceMatch =
          RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(text);
      if (fenceMatch != null) text = fenceMatch.group(1)!;

      final json = jsonDecode(text) as Map<String, dynamic>;
      final reply = (json['reply'] as String?) ?? text;

      // ── Parse packages ────────────────────────────────────────────────────
      final packagesRaw = json['packages'];
      List<ChatPackageSuggestion> packages = const [];
      if (packagesRaw is List && packagesRaw.isNotEmpty) {
        packages = packagesRaw
            .whereType<Map>()
            .map((item) {
              final map = Map<String, dynamic>.from(item);
              final idStr = '${map['id']}';
              return ChatPackageSuggestion.fromJson(
                map,
                imageUrlOverride: packageImageById[idStr] ?? '',
              );
            })
            .where((pkg) => pkg.name.isNotEmpty)
            .toList(growable: false);
      }

      // ── Parse spots ───────────────────────────────────────────────────────
      final spotsRaw = json['spots'];
      List<ChatSpotSuggestion> spots = const [];
      if (spotsRaw is List && spotsRaw.isNotEmpty) {
        spots = spotsRaw
            .whereType<Map>()
            .map((item) {
              final map = Map<String, dynamic>.from(item);
              final idStr = '${map['id']}';
              final cached = spotById[idStr];

              final name = (cached?['title'] as String?) ??
                  (map['name'] as String?) ??
                  '';
              if (name.isEmpty) return null;

              final municipality =
                  ((cached?['municipality'] as String?)?.trim().isNotEmpty ??
                          false)
                      ? (cached!['municipality'] as String).trim()
                      : ((cached?['city'] as String?) ??
                              (map['municipality'] as String?) ??
                              (map['city'] as String?) ??
                              '')
                          .toString()
                          .trim();

              final category = (cached?['_category'] as String?) ??
                  (map['category'] as String?) ??
                  'Attraction';

              final address = (cached?['address'] as String?) ??
                  (map['address'] as String?) ??
                  '';

              final imageUrl = cached != null
                  ? _spotImageUrl(cached)
                  : (map['imageUrl'] as String?) ??
                      (map['image_url'] as String?) ??
                      '';

              return ChatSpotSuggestion(
                id: idStr,
                name: name,
                municipality: municipality,
                category: category,
                address: address,
                imageUrl: imageUrl,
                rating: (cached?['rating'] as num?)?.toDouble() ??
                    (map['rating'] as num?)?.toDouble() ??
                    4.5,
                latitude: (cached?['latitude'] as num?)?.toDouble() ??
                    (map['latitude'] as num?)?.toDouble() ??
                    0,
                longitude: (cached?['longitude'] as num?)?.toDouble() ??
                    (map['longitude'] as num?)?.toDouble() ??
                    0,
                googlePlaceId: (cached?['google_place_id'] as String?) ??
                    (map['google_place_id'] as String?) ??
                    idStr,
              );
            })
            .whereType<ChatSpotSuggestion>()
            .where((s) => s.name.isNotEmpty)
            .toList(growable: false);
      }

      return GeminiChatResponse(
        reply: reply.trim(),
        spots: spots,
        packages: packages,
      );
    } catch (e) {
      debugPrint('[Gemini] JSON parse error: $e — falling back to plain text');
      return GeminiChatResponse(reply: raw.trim());
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Sends [userMessage] to Gemini with real tourist spots AND packages
  /// injected as context. Returns a [GeminiChatResponse] with the reply text
  /// and matched spot/package cards based on intent detection.
  Future<GeminiChatResponse> chat({
    required String userMessage,
    List<GeminiTurn> history = const [],
    String? systemPrompt,
  }) async {
    final key = _apiKey;
    debugPrint(
        '[Gemini] Key: ${key.isEmpty ? "EMPTY" : "${key.substring(0, 8)}... (${key.length} chars)"}');
    if (key.isEmpty) throw Exception('GEMINI_API_KEY not set in .env');

    // ── Step 1: Detect city and intent ───────────────────────────────────────
    final detectedCity = _detectCity(userMessage);
    final isNamedQuery = _isNamedPlaceQuery(userMessage);

    // ── Step 2: Parallel data fetching ────────────────────────────────────────
    final dataFutures = <Future<List<Map<String, dynamic>>>>[
      _getPackages(),
      _getSpots(),
      if (detectedCity != null) _getGoogleSpotsForCity(detectedCity),
      if (isNamedQuery) _searchNamedPlace(userMessage),
    ];
    final results = await Future.wait(dataFutures);

    final packages = results[0];
    final supabaseSpots = results[1];
    int resultIdx = 2;
    final googleCitySpots =
        detectedCity != null ? results[resultIdx++] : <Map<String, dynamic>>[];
    final namedSpots =
        isNamedQuery ? results[resultIdx] : <Map<String, dynamic>>[];

    // ── Step 3: Determine the working city ────────────────────────────────────
    // If no city was mentioned but the named search found a place, use its city
    // so we can also fetch similar spots from that city.
    String? workingCity = detectedCity;
    if (workingCity == null && namedSpots.isNotEmpty) {
      final foundCity =
          (namedSpots.first['municipality'] as String?)?.trim() ?? '';
      if (foundCity.isNotEmpty && foundCity != 'Bulacan') {
        workingCity = foundCity;
      }
    }

    // If named search revealed a new city we haven't fetched yet, fetch it now.
    List<Map<String, dynamic>> extraCitySpots = const [];
    if (workingCity != null && workingCity != detectedCity) {
      extraCitySpots = await _getGoogleSpotsForCity(workingCity);
    }

    // ── Step 4: Merge all spot sources ────────────────────────────────────────
    List<Map<String, dynamic>> spots;
    final seenTitles = <String>{};
    final mergedSpots = <Map<String, dynamic>>[];

    void addSpots(Iterable<Map<String, dynamic>> src) {
      for (final s in src) {
        final title = CitySpotSuggestionService.normalizeText(
          (s['title'] as String?) ?? '');
        if (title.isNotEmpty && seenTitles.add(title)) mergedSpots.add(s);
      }
    }

    if (workingCity != null) {
      // Filter Supabase spots to the working city first.
      final cityNorm = CitySpotSuggestionService.normalizeText(workingCity);
      final citySupabaseSpots = supabaseSpots.where((s) {
        final m = CitySpotSuggestionService.normalizeText(
          ((s['municipality'] as String?)?.isNotEmpty == true
              ? s['municipality'] as String
              : (s['city'] as String?) ?? ''),
        );
        return m == cityNorm || m.contains(cityNorm);
      });
      // Named results first (the specific place the user asked about).
      addSpots(namedSpots);
      addSpots(citySupabaseSpots);
      addSpots(googleCitySpots);
      addSpots(extraCitySpots);
    } else {
      // No city detected — use full Supabase catalogue + any named results.
      addSpots(namedSpots);
      addSpots(supabaseSpots);
    }

    spots = mergedSpots;
    debugPrint(
      '[Gemini] Spots: named=${namedSpots.length} city=${googleCitySpots.length} '
      'extra=${extraCitySpots.length} merged=${spots.length}',
    );

    // Build lookups used after response parsing.
    final packageImageById = {
      for (final pkg in packages) '${pkg['id']}': _packageImageUrl(pkg),
    };
    final spotById = {
      for (final spot in spots) '${spot['id']}': spot,
    };

    final enrichedPrompt = systemPrompt != null
        ? _buildEnrichedSystemPrompt(systemPrompt, spots, packages)
        : null;

    final body = _buildBody(userMessage, history, enrichedPrompt);

    // ── Primary model with exponential-backoff retries ────────────────────
    for (int attempt = 0; attempt < _maxAttempts; attempt++) {
      if (attempt > 0) {
        final delay = Duration(seconds: 1 << (attempt - 1));
        debugPrint('[Gemini] Overloaded – retrying in ${delay.inSeconds}s '
            '(attempt ${attempt + 1}/$_maxAttempts)');
        await Future.delayed(delay);
      }
      try {
        final raw =
            await _postRequest(model: _primaryModel, body: body, key: key);
        return _parseResponse(raw, packageImageById, spotById);
      } on _OverloadException catch (e) {
        debugPrint('[Gemini] Overload on attempt ${attempt + 1}: ${e.message}');
      }
    }

    // ── One-shot fallback model ───────────────────────────────────────────
    debugPrint('[Gemini] Primary exhausted – trying fallback: $_fallbackModel');
    try {
      final raw =
          await _postRequest(model: _fallbackModel, body: body, key: key);
      return _parseResponse(raw, packageImageById, spotById);
    } catch (e) {
      debugPrint('[Gemini] Fallback also failed: $e');
      throw Exception(
          'AI assistant is currently busy. Please try again in a moment.');
    }
  }
}
