export type CoverSuggestion = {
  image_url: string;
  source: "pexels";
  title: string;
  attribution: string;
  source_url: string;
  width: number;
  height: number;
  score: number;
  is_generic_fallback: boolean;
};

type PexelsPhoto = {
  id?: unknown;
  width?: unknown;
  height?: unknown;
  url?: unknown;
  photographer?: unknown;
  alt?: unknown;
  location?: unknown;
  src?: unknown;
};

const KNOWN_PHILIPPINE_LOCATIONS = [
  "angat",
  "balagtas",
  "baliwag",
  "baliuag",
  "bocaue",
  "bulakan",
  "bustos",
  "calumpit",
  "dona remedios trinidad",
  "guiguinto",
  "hagonoy",
  "malolos",
  "marilao",
  "meycauayan",
  "norzagaray",
  "obando",
  "pandi",
  "paombong",
  "plaridel",
  "pulilan",
  "san ildefonso",
  "san jose del monte",
  "san miguel",
  "san rafael",
  "santa maria",
  "manila",
  "metro manila",
  "quezon city",
  "makati",
  "pasig",
  "taguig",
  "baguio",
  "cebu",
  "cebu city",
  "davao",
  "davao city",
  "vigan",
  "laoag",
  "ilocos",
  "ilocos region",
  "abra",
  "agusan del norte",
  "agusan del sur",
  "aklan",
  "albay",
  "antique",
  "apayao",
  "aurora",
  "basilan",
  "batanes",
  "benguet",
  "biliran",
  "bukidnon",
  "cagayan",
  "camarines norte",
  "camarines sur",
  "camiguin",
  "capiz",
  "catanduanes",
  "cotabato",
  "davao de oro",
  "davao del norte",
  "davao del sur",
  "davao occidental",
  "davao oriental",
  "dinagat islands",
  "eastern samar",
  "guimaras",
  "ifugao",
  "ilocos norte",
  "ilocos sur",
  "isabela",
  "kalinga",
  "la union",
  "lanao del norte",
  "lanao del sur",
  "leyte",
  "maguindanao del norte",
  "maguindanao del sur",
  "marinduque",
  "masbate",
  "misamis occidental",
  "misamis oriental",
  "mountain province",
  "negros occidental",
  "negros oriental",
  "northern samar",
  "nueva vizcaya",
  "occidental mindoro",
  "oriental mindoro",
  "pangasinan",
  "quezon",
  "quirino",
  "romblon",
  "samar",
  "sarangani",
  "siquijor",
  "sorsogon",
  "south cotabato",
  "southern leyte",
  "sultan kudarat",
  "sulu",
  "surigao del norte",
  "surigao del sur",
  "tawi tawi",
  "zamboanga del norte",
  "zamboanga del sur",
  "zamboanga sibugay",
  "pampanga",
  "tarlac",
  "nueva ecija",
  "bataan",
  "zambales",
  "cavite",
  "laguna",
  "batangas",
  "rizal",
  "tagaytay",
  "palawan",
  "boracay",
  "bohol",
  "iloilo",
  "bacolod",
  "cagayan de oro",
  "zamboanga",
  "bicol region",
  "western visayas",
  "central visayas",
  "eastern visayas",
  "northern mindanao",
  "davao region",
  "soccsksargen",
  "caraga",
  "bangsamoro",
  "cordillera",
] as const;

const MUNICIPALITY_ALIASES: Record<string, string[]> = {
  baliwag: ["baliwag", "baliuag"],
  baliuag: ["baliwag", "baliuag"],
};

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function integer(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : 0;
}

function safeHttpsUrl(value: unknown): string {
  const raw = text(value);
  try {
    const url = new URL(raw);
    return url.protocol === "https:" && !url.username && !url.password
      ? url.toString()
      : "";
  } catch {
    return "";
  }
}

function normalizeGeographicText(value: unknown): string {
  return text(value)
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function normalizeMunicipalityName(value: string): string {
  return normalizeGeographicText(value)
    .replace(/\b(city|municipality)\s+of\b/g, " ")
    .replace(/\b(city|municipality)\b/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function containsPlace(textValue: string, place: string): boolean {
  return (` ${textValue} `).includes(` ${place} `);
}

export function hasDefensibleMunicipalityRelevance(
  metadata: {
    alt?: unknown;
    sourceUrl?: unknown;
    location?: unknown;
  },
  municipality: string,
): boolean {
  const target = normalizeMunicipalityName(municipality);
  if (!target) return false;

  const targetAliases = new Set(MUNICIPALITY_ALIASES[target] ?? [target]);
  targetAliases.add(target);
  const metadataText = normalizeGeographicText([
    text(metadata.alt),
    text(metadata.sourceUrl),
    text(metadata.location),
  ].join(" "));
  if (!metadataText) return false;

  const targetPresent = [...targetAliases].some((alias) =>
    containsPlace(metadataText, alias)
  );
  if (!targetPresent) return false;

  for (const location of KNOWN_PHILIPPINE_LOCATIONS) {
    const normalizedLocation = normalizeMunicipalityName(location);
    if (targetAliases.has(normalizedLocation)) continue;
    if (containsPlace(metadataText, normalizedLocation)) return false;
  }
  return true;
}

export function municipalityQueries(
  municipality: string,
  province = "Bulacan",
  localGovernmentType = "",
): string[] {
  const city = municipality.trim();
  const area = province.trim() || "Bulacan";
  const queries = [
    `${city} ${area} Philippines`,
    localGovernmentType.trim().toLowerCase() === "city"
      ? `${city} City ${area} Philippines`
      : "",
    `${city} ${area} landmark`,
    `${city} ${area} tourism`,
  ];
  return [...new Set(queries.filter(Boolean))];
}

export function suggestionLimitFromPayload(payload: unknown): number {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return 5;
  }
  const requested = integer((payload as Record<string, unknown>).limit);
  return Math.min(5, Math.max(1, requested || 5));
}

export function parsePexelsResponse(
  payload: unknown,
  queryIndex: number,
  municipality: string,
): CoverSuggestion[] {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return [];
  }
  const photos = (payload as Record<string, unknown>).photos;
  if (!Array.isArray(photos)) return [];

  const suggestions: CoverSuggestion[] = [];
  for (const value of photos) {
    if (!value || typeof value !== "object" || Array.isArray(value)) continue;
    const photo = value as PexelsPhoto;
    const src = photo.src && typeof photo.src === "object" &&
        !Array.isArray(photo.src)
      ? photo.src as Record<string, unknown>
      : {};
    const imageUrl = safeHttpsUrl(
      src.landscape ?? src.large2x ?? src.large ?? src.original,
    );
    const sourceUrl = safeHttpsUrl(photo.url);
    const width = integer(photo.width);
    const height = integer(photo.height);
    const photographer = text(photo.photographer);
    const alt = text(photo.alt);
    const unsuitableAlt = /\b(logo|menu|poster|flyer|icon|advertisement)\b/i
      .test(alt);
    if (
      !imageUrl || !sourceUrl ||
      new URL(imageUrl).hostname !== "images.pexels.com" ||
      !["pexels.com", "www.pexels.com"].includes(new URL(sourceUrl).hostname) ||
      width / height < 1.2 || width < 1200 || height < 600 || !photographer ||
      unsuitableAlt ||
      !hasDefensibleMunicipalityRelevance({
        alt,
        sourceUrl,
        location: photo.location,
      }, municipality)
    ) continue;

    const megapixels = (width * height) / 1_000_000;
    suggestions.push({
      image_url: imageUrl,
      source: "pexels",
      title: alt || "Municipality tourism photo",
      attribution: `Photo by ${photographer} on Pexels`,
      source_url: sourceUrl,
      width,
      height,
      score: (4 - queryIndex) * 100 + Math.min(megapixels, 50),
      is_generic_fallback: false,
    });
  }
  return suggestions;
}

export function mergePexelsSuggestions(
  groups: CoverSuggestion[][],
  limit = 8,
): CoverSuggestion[] {
  const byUrl = new Map<string, CoverSuggestion>();
  for (const item of groups.flat()) {
    const url = new URL(item.image_url);
    for (const parameter of ["w", "h", "width", "height", "fit", "quality"]) {
      url.searchParams.delete(parameter);
    }
    url.hash = "";
    const key = url.toString().toLowerCase();
    const existing = byUrl.get(key);
    if (!existing || item.score > existing.score) byUrl.set(key, item);
  }
  return [...byUrl.values()]
    .sort((left, right) => right.score - left.score)
    .slice(0, limit);
}

export function pexelsConfigurationWarning(apiKey: string): string {
  return apiKey.trim()
    ? ""
    : "Pexels suggestions are not configured. Local images remain available.";
}
