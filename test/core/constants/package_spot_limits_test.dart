import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/constants/package_spot_limits.dart';

void main() {
  test('only package spot counts three through six are valid', () {
    expect(isValidPackageSpotCount(2), isFalse);
    expect(isValidPackageSpotCount(3), isTrue);
    expect(isValidPackageSpotCount(4), isTrue);
    expect(isValidPackageSpotCount(5), isTrue);
    expect(isValidPackageSpotCount(6), isTrue);
    expect(isValidPackageSpotCount(7), isFalse);
  });

  test('returns the required UI messages at both bounds', () {
    expect(
      packageSpotCountValidationMessage(2),
      'Add at least 3 spots to continue.',
    );
    expect(
      packageSpotCountValidationMessage(7),
      'Packages can contain a maximum of 6 spots.',
    );
  });
}
