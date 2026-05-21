import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

// ── CRC32 ──────────────────────────────────────────────────────
final _crcTable = _buildCrcTable();
List<int> _buildCrcTable() {
  final t = List<int>.filled(256, 0);
  for (int i = 0; i < 256; i++) {
    int c = i;
    for (int j = 0; j < 8; j++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    t[i] = c;
  }
  return t;
}

int _crc32(List<int> data) {
  int crc = 0xFFFFFFFF;
  for (final b in data) {
    crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

List<int> _u32be(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

List<int> _pngChunk(String type, List<int> data) {
  final tb = type.codeUnits;
  final inner = [...tb, ...data];
  return [..._u32be(data.length), ...inner, ..._u32be(_crc32(inner))];
}

void writePng(String path, int w, int h, List<List<List<int>>> pixels) {
  // Filter byte (0 = None) + RGBA per row
  final raw = <int>[];
  for (final row in pixels) {
    raw.add(0);
    for (final p in row) raw.addAll(p);
  }
  final compressed = ZLibCodec(level: 9).encode(raw);

  final bytes = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,   // PNG signature
    ..._pngChunk('IHDR', [
      ..._u32be(w), ..._u32be(h),
      8, 6, 0, 0, 0, // bit depth, RGBA, compression, filter, interlace
    ]),
    ..._pngChunk('IDAT', compressed),
    ..._pngChunk('IEND', []),
  ];

  File(path).writeAsBytesSync(Uint8List.fromList(bytes));
  print('  written: $path');
}

// ── Pixel helpers ──────────────────────────────────────────────
typedef Px = List<List<List<int>>>;

Px canvas(int w, int h) =>
    List.generate(h, (_) => List.generate(w, (_) => [0, 0, 0, 0]));

List<int> over(List<int> bg, List<int> fg, double a) {
  if (a <= 0) return bg;
  a = a.clamp(0.0, 1.0);
  return [
    (bg[0] + (fg[0] - bg[0]) * a).round().clamp(0, 255),
    (bg[1] + (fg[1] - bg[1]) * a).round().clamp(0, 255),
    (bg[2] + (fg[2] - bg[2]) * a).round().clamp(0, 255),
    (bg[3] + (255 - bg[3]) * a).round().clamp(0, 255),
  ];
}

void disk(Px px, double cx, double cy, double r, List<int> color) {
  final h = px.length, w = px[0].length;
  final ca = color[3] / 255.0;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final d = math.sqrt(
          (x + .5 - cx) * (x + .5 - cx) + (y + .5 - cy) * (y + .5 - cy));
      final a = (r - d + .5).clamp(0.0, 1.0) * ca;
      if (a > 0) px[y][x] = over(px[y][x], color, a);
    }
  }
}

void ring(Px px, double cx, double cy, double r, double w, List<int> color) {
  final h = px.length, W = px[0].length;
  final ca = color[3] / 255.0;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < W; x++) {
      final d = math.sqrt(
          (x + .5 - cx) * (x + .5 - cx) + (y + .5 - cy) * (y + .5 - cy));
      final a = (w / 2 + .5 - (d - r).abs()).clamp(0.0, 1.0) * ca;
      if (a > 0) px[y][x] = over(px[y][x], color, a);
    }
  }
}

void fillPoly(Px px, List<List<double>> pts, List<int> color) {
  final h = px.length, w = px[0].length, n = pts.length;
  final minY = pts.map((p) => p[1]).reduce(math.min).toInt().clamp(0, h - 1);
  final maxY = pts.map((p) => p[1]).reduce(math.max).toInt().clamp(0, h - 1);
  for (int y = minY; y <= maxY; y++) {
    final xs = <double>[];
    for (int i = 0; i < n; i++) {
      final x1 = pts[i][0], y1 = pts[i][1];
      final x2 = pts[(i + 1) % n][0], y2 = pts[(i + 1) % n][1];
      if (y1 == y2) continue;
      if (math.min(y1, y2) <= y + .5 && y + .5 <= math.max(y1, y2)) {
        xs.add(x1 + (y + .5 - y1) * (x2 - x1) / (y2 - y1));
      }
    }
    xs.sort();
    for (int k = 0; k < xs.length - 1; k += 2) {
      for (int x = math.max(0, xs[k].toInt());
          x <= math.min(w - 1, xs[k + 1].toInt());
          x++) {
        px[y][x] = over(px[y][x], color, 1.0);
      }
    }
  }
}

void fillRect(Px px, double x0, double y0, double x1, double y1, List<int> c) {
  final h = px.length, w = px[0].length;
  for (int y = math.max(0, y0.toInt()); y < math.min(h, y1.toInt()); y++) {
    for (int x = math.max(0, x0.toInt()); x < math.min(w, x1.toInt()); x++) {
      px[y][x] = over(px[y][x], c, 1.0);
    }
  }
}

// ── Main ───────────────────────────────────────────────────────
void main() {
  const S = 96;
  final cx = S / 2.0, cy = S / 2.0, R = S / 2.0 - 5;
  const white  = [255, 255, 255, 255];
  const shadow = [0, 0, 0, 80];
  const blue   = [42, 134, 255, 255];
  const orange = [245, 158, 11, 255];

  Directory('assets/icons').createSync(recursive: true);

  // ── TRICYCLE (blue, chevron arrow) ─────────────────────────
  print('Generating tricycle_marker.png ...');
  var px = canvas(S, S);
  disk(px, cx, cy + 3, R, shadow);
  disk(px, cx, cy, R, blue);
  ring(px, cx, cy, R - 1, 3.5, white);

  final aw = R * 0.54, ah = R * 0.70;
  // Chevron head (notched arrow pointing up)
  fillPoly(px, [
    [cx,        cy - ah * 0.46],   // tip
    [cx + aw/2, cy + ah * 0.26],   // bottom-right
    [cx,        cy + ah * 0.04],   // notch
    [cx - aw/2, cy + ah * 0.26],   // bottom-left
  ], white);
  // Stem below notch
  fillRect(px, cx - aw * 0.20, cy + ah * 0.04, cx + aw * 0.20, cy + ah * 0.44, white);

  writePng('assets/icons/tricycle_marker.png', S, S, px);

  // ── PASSENGER (orange, person silhouette) ──────────────────
  print('Generating passenger_marker.png ...');
  px = canvas(S, S);
  disk(px, cx, cy + 3, R, shadow);
  disk(px, cx, cy, R, orange);
  ring(px, cx, cy, R - 1, 3.5, white);

  final hr  = R * 0.22;
  final hcy = cy - R * 0.18;
  disk(px, cx, hcy, hr, white);   // head

  final bt = hcy + hr + 1.5;
  final bh = R * 0.41;
  final st = R * 0.34, sb = R * 0.46;
  fillPoly(px, [           // shoulders / body trapezoid
    [cx - st/2, bt],
    [cx + st/2, bt],
    [cx + sb/2, bt + bh],
    [cx - sb/2, bt + bh],
  ], white);

  writePng('assets/icons/passenger_marker.png', S, S, px);

  print('Done!');
}
