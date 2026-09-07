export const maxPhotoBytes = 4 * 1024 * 1024;

export function parsePhoto(
  value: unknown,
): { filename: string; content: string } | undefined {
  if (value == null) return undefined;
  const content = (value as { content?: unknown }).content;
  if (
    typeof content !== "string" ||
    content.length > 4 * Math.ceil(maxPhotoBytes / 3) ||
    !/^[A-Za-z0-9+/]+={0,2}$/.test(content)
  ) throw new Error("INVALID_PHOTO");
  let raw: string;
  try {
    raw = atob(content);
  } catch {
    throw new Error("INVALID_PHOTO");
  }
  if (!raw.length || raw.length > maxPhotoBytes) {
    throw new Error("INVALID_PHOTO");
  }
  const bytes = Uint8Array.from(raw, (c) => c.charCodeAt(0));
  const extension = bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 &&
      bytes[2] === 255
    ? "jpg"
    : raw.startsWith("\x89PNG\r\n\x1a\n")
    ? "png"
    : raw.startsWith("RIFF") && raw.slice(8, 12) === "WEBP"
    ? "webp"
    : null;
  if (!extension) throw new Error("INVALID_PHOTO");
  // Ignore user-controlled filenames and MIME headers.
  return { filename: `emergency-photo.${extension}`, content };
}

export function recipientsFor(...lists: string[][]): string[] {
  return [
    ...new Set(
      lists.flat().map((s) => s.trim().toLowerCase()).filter(
        (s) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s),
      ),
    ),
  ];
}

export function escapeHtml(value: unknown): string {
  return String(value ?? "Not available").replace(
    /[&<>"']/g,
    (c) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    }[c]!),
  );
}

export function buildEmailHtml(fields: Record<string, unknown>): string {
  const rows = Object.entries(fields).map(([label, value]) =>
    `<tr><th style="text-align:left;padding:8px;vertical-align:top">${
      escapeHtml(label)
    }</th><td style="padding:8px;white-space:pre-wrap">${
      escapeHtml(value)
    }</td></tr>`
  ).join("");
  return `<!doctype html><html><body style="font-family:Arial,sans-serif;color:#0f172a">
    <h1 style="color:#dc2626">TourisTrike Emergency Alert</h1>
    <p>A tourist has requested emergency assistance.</p>
    <table>${rows}</table>
    <p>Please contact the tourist and tourism office to assist.</p>
    </body></html>`;
}

export function allEmailsSent(sent: number, total: number): boolean {
  return total > 0 && sent === total;
}
