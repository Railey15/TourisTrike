export function calculateRouteFareAdjustment(
  baseFare: number,
  farePerKm: number,
  minimumFare: number,
  originalMeters: number,
  customMeters: number,
  packagePrice: number,
) {
  const money = (value: number) => Math.round((value + Number.EPSILON) * 100) / 100;
  const fareFor = (meters: number) =>
    Math.max(minimumFare, baseFare + farePerKm * meters / 1000);
  const surcharge = money(Math.max(0, fareFor(customMeters) - fareFor(originalMeters)));
  return { surcharge, unitPrice: money(packagePrice + surcharge) };
}
