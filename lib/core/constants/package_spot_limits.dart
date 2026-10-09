const int minPackageSpots = 3;
const int maxPackageSpots = 6;

String? packageSpotCountValidationMessage(int count) {
  if (count < minPackageSpots) {
    return 'Add at least 3 spots to continue.';
  }
  if (count > maxPackageSpots) {
    return 'Packages can contain a maximum of 6 spots.';
  }
  return null;
}

bool isValidPackageSpotCount(int count) =>
    packageSpotCountValidationMessage(count) == null;
