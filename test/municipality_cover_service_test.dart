import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/branding/municipality_cover_service.dart';

void main() {
  const bustosLocal = MunicipalityCoverSuggestion(
    imageUrl: 'https://touristrike.example/bustos.jpg',
    source: MunicipalityCoverSource.touristrike,
    title: 'Bustos Heritage Park',
    municipality: 'Bustos',
    width: 1600,
    height: 900,
    score: 100,
  );
  const pexels = MunicipalityCoverSuggestion(
    imageUrl: 'https://images.pexels.com/photos/42/cover.jpeg',
    source: MunicipalityCoverSource.pexels,
    title: 'Landscape',
    attribution: 'Photo by Ana on Pexels',
    sourceUrl: 'https://www.pexels.com/photo/42/',
    municipality: 'Bustos',
    width: 2400,
    height: 1350,
    score: 500,
  );

  test('local suggestions are municipality-scoped and approved/active', () {
    final suggestions = MunicipalityCoverService.localSuggestionsFromRows([
      {
        'title': 'Bustos Heritage Park',
        'city': 'Bustos',
        'status': 'active',
        'verification_status': 'verified',
        'rating': 4.8,
        'image_url': 'https://touristrike.example/bustos.jpg',
        'tourist_spot_images': const [],
      },
      {
        'title': 'Other municipality',
        'city': 'Baliwag',
        'status': 'active',
        'verification_status': 'verified',
        'image_url': 'https://touristrike.example/baliwag.jpg',
        'tourist_spot_images': const [],
      },
      {
        'title': 'Pending place',
        'city': 'Bustos',
        'status': 'active',
        'verification_status': 'pending',
        'image_url': 'https://touristrike.example/pending.jpg',
        'tourist_spot_images': const [],
      },
      {
        'title': 'Archived place',
        'city': 'Bustos',
        'status': 'archived',
        'verification_status': 'verified',
        'image_url': 'https://touristrike.example/archived.jpg',
        'tourist_spot_images': const [],
      },
    ], municipality: 'Municipality of Bustos');

    expect(suggestions, hasLength(1));
    expect(suggestions.single.title, 'Bustos Heritage Park');
  });

  test('ranking keeps TourisTrike local images ahead of Pexels', () {
    final ranked = MunicipalityCoverService.rankSuggestions([
      pexels,
      bustosLocal,
    ], municipality: 'Bustos');
    expect(ranked.first.source, MunicipalityCoverSource.touristrike);
  });

  test('destination and landmark labels rank above commercial labels', () {
    final ranked = MunicipalityCoverService.rankSuggestions(const [
      MunicipalityCoverSuggestion(
        imageUrl: 'https://touristrike.example/cafe.jpg',
        source: MunicipalityCoverSource.touristrike,
        title: 'Downtown Cafe',
        municipality: 'Bustos',
        width: 1600,
        height: 900,
        isVerifiedDestination: true,
      ),
      MunicipalityCoverSuggestion(
        imageUrl: 'https://touristrike.example/heritage-park.jpg',
        source: MunicipalityCoverSource.touristrike,
        title: 'Bustos Heritage Park',
        municipality: 'Bustos',
        width: 1600,
        height: 900,
        isVerifiedDestination: true,
      ),
    ], municipality: 'Bustos');

    expect(ranked.first.title, 'Bustos Heritage Park');
  });

  test('duplicate image URLs are removed using the highest-ranked item', () {
    final ranked = MunicipalityCoverService.rankSuggestions([
      bustosLocal,
      const MunicipalityCoverSuggestion(
        imageUrl: 'https://touristrike.example/bustos.jpg#duplicate',
        source: MunicipalityCoverSource.touristrike,
        title: 'Duplicate',
        municipality: 'Bustos',
        width: 1600,
        height: 900,
        score: 1,
      ),
    ], municipality: 'Bustos');
    expect(ranked, hasLength(1));
    expect(ranked.single.title, 'Bustos Heritage Park');
  });

  test(
    'empty, malformed, unsupported, and placeholder images are excluded',
    () {
      final suggestions = MunicipalityCoverService.localSuggestionsFromRows([
        {
          'title': 'Empty image',
          'city': 'Bustos',
          'status': 'active',
          'verification_status': 'verified',
          'image_url': '',
          'tourist_spot_images': const [],
        },
        {
          'title': 'Malformed image',
          'city': 'Bustos',
          'status': 'active',
          'verification_status': 'verified',
          'image_url': 'not-a-url',
          'tourist_spot_images': const [],
        },
        {
          'title': 'Placeholder image',
          'city': 'Bustos',
          'status': 'active',
          'verification_status': 'verified',
          'image_url': 'https://touristrike.example/no-image.png',
          'tourist_spot_images': const [],
        },
        {
          'title': 'Unsupported image',
          'city': 'Bustos',
          'status': 'active',
          'verification_status': 'verified',
          'image_url': 'https://touristrike.example/cover.svg',
          'tourist_spot_images': const [],
        },
      ], municipality: 'Bustos');

      expect(suggestions, isEmpty);
    },
  );

  test('unvalidated or failed image cannot be selected as a cover', () {
    const unknownDimensions = MunicipalityCoverSuggestion(
      imageUrl: 'https://touristrike.example/unvalidated.jpg',
      source: MunicipalityCoverSource.touristrike,
      title: 'Unvalidated image',
      municipality: 'Bustos',
    );
    const portrait = MunicipalityCoverSuggestion(
      imageUrl: 'https://touristrike.example/portrait.jpg',
      source: MunicipalityCoverSource.touristrike,
      title: 'Portrait image',
      municipality: 'Bustos',
      width: 800,
      height: 1200,
    );

    expect(
      MunicipalityCoverService.canSelectSuggestion(unknownDimensions),
      isFalse,
    );
    expect(MunicipalityCoverService.canSelectSuggestion(portrait), isFalse);
    expect(MunicipalityCoverService.canSelectSuggestion(bustosLocal), isTrue);
  });

  test('fewer than five valid locals requests only the remaining slots', () {
    expect(
      MunicipalityCoverService.remainingSuggestionSlots(validLocalCount: 2),
      3,
    );
    expect(
      MunicipalityCoverService.remainingSuggestionSlots(validLocalCount: 5),
      0,
    );
  });

  test('Pexels fills only remaining slots after valid local images', () {
    final external = List.generate(
      5,
      (index) => MunicipalityCoverSuggestion(
        imageUrl: 'https://images.pexels.com/photos/$index/cover.jpeg',
        source: MunicipalityCoverSource.pexels,
        title: 'Landscape $index',
        attribution: 'Photo by Author $index on Pexels',
        sourceUrl: 'https://www.pexels.com/photo/$index/',
        municipality: 'Bustos',
        width: 2400,
        height: 1350,
        score: 500 - index.toDouble(),
      ),
    );
    final combined = MunicipalityCoverService.combineSuggestions(
      localSuggestions: const [bustosLocal],
      externalSuggestions: external,
      municipality: 'Bustos',
    );

    expect(combined, hasLength(5));
    expect(combined.first, same(bustosLocal));
    expect(
      combined.where((item) => item.source == MunicipalityCoverSource.pexels),
      hasLength(4),
    );
  });

  test('five valid local candidates need no Pexels backfill', () {
    final local = List.generate(
      5,
      (index) => MunicipalityCoverSuggestion(
        imageUrl: 'https://touristrike.example/local-$index.jpg',
        source: MunicipalityCoverSource.touristrike,
        title: 'Local landmark $index',
        municipality: 'Bustos',
        width: 1600,
        height: 900,
      ),
    );
    final combined = MunicipalityCoverService.combineSuggestions(
      localSuggestions: local,
      externalSuggestions: const [pexels],
      municipality: 'Bustos',
    );

    expect(combined, hasLength(5));
    expect(
      combined.every(
        (item) => item.source == MunicipalityCoverSource.touristrike,
      ),
      isTrue,
    );
  });

  test('duplicate Pexels candidates consume one backfill slot', () {
    final combined = MunicipalityCoverService.combineSuggestions(
      localSuggestions: const [bustosLocal],
      externalSuggestions: const [
        pexels,
        MunicipalityCoverSuggestion(
          imageUrl: 'https://images.pexels.com/photos/42/cover.jpeg#duplicate',
          source: MunicipalityCoverSource.pexels,
          title: 'Duplicate landscape',
          attribution: 'Photo by Ana on Pexels',
          sourceUrl: 'https://www.pexels.com/photo/42/',
          municipality: 'Bustos',
          width: 2400,
          height: 1350,
        ),
      ],
      municipality: 'Bustos',
    );

    expect(combined, hasLength(2));
  });

  test('Pexels response metadata is parsed and unsafe rows are rejected', () {
    final parsed = MunicipalityCoverService.parseExternalSuggestions({
      'suggestions': [
        {
          'image_url': 'https://images.pexels.com/photos/42/cover.jpeg',
          'source_url': 'https://www.pexels.com/photo/42/',
          'attribution': 'Photo by Ana on Pexels',
          'title': 'Bulacan landscape',
          'width': 2400,
          'height': 1350,
          'score': 420,
        },
        {
          'image_url': 'http://insecure.example/image.jpg',
          'source_url': 'https://www.pexels.com/photo/43/',
        },
      ],
    }, 'Bustos');

    expect(parsed, hasLength(1));
    expect(parsed.single.attribution, 'Photo by Ana on Pexels');
    expect(parsed.single.source, MunicipalityCoverSource.pexels);
  });

  test('Pexels failure fallback keeps the local TourisTrike suggestion', () {
    final external = MunicipalityCoverService.parseExternalSuggestions(const {
      'error': 'RATE_LIMITED',
    }, 'Bustos');
    final resolved = MunicipalityCoverService.resolveHomeCover(
      selectedMunicipality: 'Bustos',
      localSuggestions: [bustosLocal, ...external],
    );
    expect(resolved.imageUrl, bustosLocal.imageUrl);
    expect(resolved.source, MunicipalityCoverSource.touristrike);
  });

  test('selected and uploaded covers preserve RPC persistence metadata', () {
    expect(pexels.toRpcParameters(), {
      'p_cover_image_url': pexels.imageUrl,
      'p_cover_image_source': 'pexels',
      'p_cover_image_attribution': 'Photo by Ana on Pexels',
      'p_cover_image_source_url': 'https://www.pexels.com/photo/42/',
    });

    const uploaded = MunicipalityCoverSuggestion(
      imageUrl:
          'https://project.supabase.co/storage/v1/object/public/public-assets/'
          'municipality-covers/user-id/bustos/cover.jpg',
      source: MunicipalityCoverSource.uploaded,
      title: 'Uploaded cover',
      municipality: 'Bustos',
    );
    expect(uploaded.toRpcParameters()['p_cover_image_source'], 'uploaded');
    expect(uploaded.toRpcParameters()['p_cover_image_url'], uploaded.imageUrl);
  });

  test('home cover cannot cross municipality boundaries', () {
    const baliwagCover = MunicipalityCoverSuggestion(
      imageUrl: 'https://touristrike.example/baliwag.jpg',
      source: MunicipalityCoverSource.touristrike,
      title: 'Baliwag cover',
      municipality: 'Baliwag',
    );
    final resolved = MunicipalityCoverService.resolveHomeCover(
      selectedMunicipality: 'Bustos',
      selectedCover: baliwagCover,
      localSuggestions: const [bustosLocal],
    );
    expect(resolved.imageUrl, bustosLocal.imageUrl);
  });

  test('changing selected municipality changes the chosen cover', () {
    const baliwag = MunicipalityCoverSuggestion(
      imageUrl: 'https://touristrike.example/baliwag.jpg',
      source: MunicipalityCoverSource.touristrike,
      title: 'Baliwag cover',
      municipality: 'Baliwag',
    );
    final bustos = MunicipalityCoverService.resolveHomeCover(
      selectedMunicipality: 'Bustos',
      selectedCover: bustosLocal,
    );
    final changed = MunicipalityCoverService.resolveHomeCover(
      selectedMunicipality: 'Baliwag City',
      selectedCover: baliwag,
    );
    expect(bustos.imageUrl, isNot(changed.imageUrl));
    expect(changed.imageUrl, baliwag.imageUrl);
    expect(changed.fallbackImageUrls, contains(defaultBulacanCoverUrl));
  });

  test('invalid selected cover falls back to a safe local image', () {
    const invalid = MunicipalityCoverSuggestion(
      imageUrl: 'javascript:alert(1)',
      source: MunicipalityCoverSource.uploaded,
      title: 'Invalid',
      municipality: 'Bustos',
    );
    final resolved = MunicipalityCoverService.resolveHomeCover(
      selectedMunicipality: 'Bustos',
      selectedCover: invalid,
      localSuggestions: const [bustosLocal],
    );
    expect(resolved.imageUrl, bustosLocal.imageUrl);
  });

  test('no selected or local cover uses the default Bulacan cover', () {
    final resolved = MunicipalityCoverService.resolveHomeCover(
      selectedMunicipality: 'Bustos',
    );
    expect(resolved.imageUrl, defaultBulacanCoverUrl);
    expect(resolved.isDefault, isTrue);
  });
}
