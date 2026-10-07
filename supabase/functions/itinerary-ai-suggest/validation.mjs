export function isExactSelectedDestinationOrder(ordered, selected) {
  if (!Array.isArray(ordered) || !Array.isArray(selected) ||
      ordered.length !== selected.length ||
      selected.some((id) => typeof id !== 'string') ||
      ordered.some((id) => typeof id !== 'string')) return false;
  const selectedIds = new Set(selected);
  return selectedIds.size === selected.length &&
    new Set(ordered).size === selectedIds.size &&
    ordered.every((id) => selectedIds.has(id));
}
