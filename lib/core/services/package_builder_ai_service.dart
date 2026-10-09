import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/constants/package_spot_limits.dart';

typedef PackageBuilderFunctionInvoker =
    Future<Map<String, dynamic>> Function({
      required String functionName,
      required Map<String, dynamic> body,
    });

class PackageBuilderAiException implements Exception {
  const PackageBuilderAiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PackageBuilderCandidate {
  const PackageBuilderCandidate({
    required this.key,
    required this.title,
    required this.category,
    required this.address,
    required this.rating,
  });

  final String key;
  final String title;
  final String category;
  final String address;
  final double rating;

  Map<String, dynamic> toRequestJson() => {
    'id': key,
    'name': title,
    'category': category,
    'address': address,
    'rating': rating,
  };
}

class PackageBuilderAiPlan {
  const PackageBuilderAiPlan({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.category,
    required this.orderedCandidateKeys,
    required this.suggestedStayMinutes,
    required this.recommendation,
  });

  final String title;
  final String subtitle;
  final String description;
  final String category;
  final List<String> orderedCandidateKeys;
  final Map<String, int> suggestedStayMinutes;
  final String recommendation;
}

/// Turns a natural-language request into an allow-listed package draft.
class PackageBuilderAiService {
  PackageBuilderAiService({
    SupabaseClient? client,
    PackageBuilderFunctionInvoker? invokeFunction,
  }) : _invokeFunction =
           invokeFunction ??
           _supabaseInvoker(client ?? Supabase.instance.client);

  static const edgeFunctionName = 'generate-tour-package';

  final PackageBuilderFunctionInvoker _invokeFunction;

  static PackageBuilderFunctionInvoker _supabaseInvoker(SupabaseClient client) {
    return ({required functionName, required body}) async {
      try {
        final response = await client.functions.invoke(
          functionName,
          method: HttpMethod.post,
          body: body,
        );
        final data = response.data;
        if (data is! Map) {
          throw const PackageBuilderAiException(
            'AI package generation returned an invalid response.',
          );
        }
        return Map<String, dynamic>.from(data);
      } on FunctionException catch (error) {
        final details = error.details;
        final message = details is Map
            ? _cleanErrorMessage(details['error'] ?? details['message'])
            : '';
        throw PackageBuilderAiException(
          message.isEmpty
              ? 'AI package generation is temporarily unavailable.'
              : message,
        );
      }
    };
  }

  static String _cleanErrorMessage(dynamic value) =>
      value?.toString().trim() ?? '';

  Future<PackageBuilderAiPlan> generate({
    required String request,
    required String municipality,
    required int spotCount,
    required String preferences,
    required List<PackageBuilderCandidate> candidates,
  }) async {
    if (request.trim().isEmpty) {
      throw ArgumentError('Describe the package you want to create.');
    }
    if (candidates.isEmpty) {
      throw StateError('No active spots are available in $municipality.');
    }
    if (!isValidPackageSpotCount(spotCount)) {
      throw ArgumentError(
        'Number of spots must be between $minPackageSpots and '
        '$maxPackageSpots.',
      );
    }

    final eligibleCandidates = _eligibleCandidates(candidates, request);
    if (eligibleCandidates.length < minPackageSpots) {
      throw PackageBuilderAiException(
        'At least $minPackageSpots usable spots are required to generate '
        'a package. Try another request or add spots manually.',
      );
    }

    final requestedCount = spotCount;
    final payload = await _invokeFunction(
      functionName: edgeFunctionName,
      body: {
        'request': request.trim(),
        'spotCount': requestedCount,
        'municipality': municipality.trim(),
        'preferences': preferences.trim(),
        'candidates': candidates
            .map((item) => item.toRequestJson())
            .toList(growable: false),
      },
    );
    final edgeError = _cleanErrorMessage(payload['error']);
    if (edgeError.isNotEmpty) throw PackageBuilderAiException(edgeError);
    final rawPackage = payload['package'];
    if (rawPackage is! Map) {
      throw const PackageBuilderAiException(
        'AI package generation returned an invalid response.',
      );
    }
    final response = Map<String, dynamic>.from(rawPackage);

    final candidateByKey = {
      for (final item in eligibleCandidates) item.key: item,
    };
    final returnedOrder = <String>[
      ..._stringList(response['orderedSpotIds']),
      ..._stringList(response['selectedSpotIds']),
    ];
    final validOrder = <String>[];
    for (final key in returnedOrder) {
      if (candidateByKey.containsKey(key) && !validOrder.contains(key)) {
        validOrder.add(key);
      }
      if (validOrder.length == requestedCount) break;
    }

    if (validOrder.length < minPackageSpots) {
      throw const PackageBuilderAiException(
        'AI returned fewer than 3 usable spots. Please retry or build the '
        'package manually.',
      );
    }

    final stayValues = <String, int>{};
    final rawStay = response['suggestedStayMinutes'];
    if (rawStay is Map) {
      for (final entry in rawStay.entries) {
        final key = entry.key.toString();
        if (!validOrder.contains(key)) continue;
        final parsed = entry.value is num
            ? (entry.value as num).round()
            : int.tryParse(entry.value.toString());
        stayValues[key] = (parsed ?? 60).clamp(15, 240);
      }
    }
    for (final key in validOrder) {
      stayValues.putIfAbsent(key, () => 60);
    }

    final intent = request.trim();
    return PackageBuilderAiPlan(
      title: _cleanTitle(
        _cleanText(
          response['title'],
          fallback: '$municipality Tour Experience',
        ),
      ),
      subtitle: _cleanText(
        response['subtitle'],
        fallback: 'A curated day tour in $municipality',
      ),
      description: _cleanText(
        response['description'],
        fallback: 'Explore $municipality through a curated $intent itinerary.',
      ),
      category: _cleanText(response['category']),
      orderedCandidateKeys: validOrder,
      suggestedStayMinutes: stayValues,
      recommendation: _cleanText(response['recommendation']),
    );
  }

  List<PackageBuilderCandidate> _eligibleCandidates(
    List<PackageBuilderCandidate> candidates,
    String request,
  ) {
    final query = request.toLowerCase();
    const intentTerms = <String, List<String>>{
      'cafe': ['cafe', 'coffee', 'kape', 'bakery'],
      'food': ['food', 'restaurant', 'cafe', 'coffee', 'bakery', 'eatery'],
      'nature': ['nature', 'park', 'garden', 'mountain', 'river', 'farm'],
      'heritage': ['heritage', 'history', 'historic', 'museum', 'church'],
      'church': ['church', 'chapel', 'cathedral', 'religious'],
      'museum': ['museum', 'gallery', 'heritage', 'history'],
      'sports': ['sport', 'stadium', 'court', 'arena'],
      'resort': ['resort', 'pool', 'swimming', 'waterpark'],
    };

    List<String>? requiredTerms;
    for (final entry in intentTerms.entries) {
      if (query.contains(entry.key)) {
        requiredTerms = entry.value;
        break;
      }
    }
    if (requiredTerms == null) return candidates;

    return candidates
        .where((item) {
          final value = '${item.title} ${item.category} ${item.address}'
              .toLowerCase();
          return requiredTerms!.any(value.contains);
        })
        .toList(growable: false);
  }

  List<String> _stringList(dynamic value) => value is List
      ? value
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList()
      : const [];

  String _cleanText(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _cleanTitle(String value) {
    final cleaned = value
        .replaceAll(RegExp(r"[^A-Za-zÀ-ÖØ-öø-ÿÑñ' -]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'Curated Tour Experience' : cleaned;
  }
}
