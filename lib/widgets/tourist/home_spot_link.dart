import 'package:flutter/material.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/core/recommendations/tourist_ai_recommendation_service.dart';
import 'package:touristrike/screens/tourist/spot_details_screen.dart';

class HomeSpotLink extends StatelessWidget {
  const HomeSpotLink({super.key, required this.spot, required this.child});
  final TouristAiRecommendationSpot spot;
  final Widget child;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TouristSpotDetailsScreen(
          spot: TouristSpotDetailsData(
            id: spot.id,
            title: spot.title,
            address: spot.address,
            distance: spot.distanceText,
            distanceKm: spot.distanceKm,
            tag: spot.category,
            rating: spot.rating,
            userRatingsTotal: spot.userRatingsTotal,
            imageUrl: spot.imageUrl,
            latitude: spot.latitude,
            longitude: spot.longitude,
            openNow: spot.openNow,
            municipality: spot.municipality,
            description: spot.description,
            googlePlaceId: spot.googlePlaceId,
          ),
          googleMapsApiKey: CitySpotSuggestionService.resolveApiKey(),
        ),
      ),
    ),
    child: child,
  );
}
