/// A single in-app package suggestion returned by the chatbot.
class ChatPackageSuggestion {
  const ChatPackageSuggestion({
    required this.id,
    required this.name,
    required this.municipality,
    required this.description,
    required this.price,
    required this.imageUrl,
  });

  final dynamic id;
  final String name;
  final String municipality;
  final String description;
  final String price;
  final String imageUrl;

  factory ChatPackageSuggestion.fromJson(
    Map<String, dynamic> json, {
    String imageUrlOverride = '',
  }) {
    return ChatPackageSuggestion(
      id: json['id'],
      name: json['name'] as String? ?? '',
      municipality: json['municipality'] as String? ?? '',
      description: json['description'] as String? ?? '',
      price: json['price'] as String? ?? '',
      imageUrl: imageUrlOverride.isNotEmpty
          ? imageUrlOverride
          : (json['imageUrl'] as String? ?? ''),
    );
  }
}

/// A single in-app tourist spot suggestion returned by the chatbot.
class ChatSpotSuggestion {
  const ChatSpotSuggestion({
    required this.id,
    required this.name,
    required this.municipality,
    required this.category,
    required this.address,
    required this.imageUrl,
    required this.rating,
    required this.latitude,
    required this.longitude,
    required this.googlePlaceId,
  });

  final String id;
  final String name;
  final String municipality;
  final String category;
  final String address;
  final String imageUrl;
  final double rating;
  final double latitude;
  final double longitude;
  final String googlePlaceId;
}

/// Structured response from the Gemini chatbot containing a reply and optional
/// spot and/or package suggestions.
class GeminiChatResponse {
  const GeminiChatResponse({
    required this.reply,
    this.spots = const [],
    this.packages = const [],
  });

  final String reply;
  final List<ChatSpotSuggestion> spots;
  final List<ChatPackageSuggestion> packages;
}
