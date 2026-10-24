import 'dart:typed_data';

/// 테스트용 최소 DNG(무압축 16bit RGGB Bayer)를 만든다.
///
/// 위쪽 [skyRatio] 비율은 푸른 하늘, 아래는 초록 땅이다. 카메라 색 공간은
/// 선형 sRGB와 같다고 두고 ColorMatrix1에 XYZ(D65)→선형 sRGB 행렬을 넣는다.
/// 내장 미리보기 JPEG는 넣지 않는다(플랫폼 RAW 현상만으로 열려야 한다).
Uint8List buildBayerDng({
  required int width,
  required int height,
  double skyRatio = 0.45,
}) {
  assert(width.isEven && height.isEven);
  const sky = [0.16, 0.34, 0.80];
  const ground = [0.08, 0.20, 0.05];

  final pixels = ByteData(width * height * 2);
  for (var y = 0; y < height; y++) {
    final color = y < height * skyRatio ? sky : ground;
    for (var x = 0; x < width; x++) {
      final channel = (y.isEven ? 0 : 1) + (x.isEven ? 0 : 1); // R,G / G,B
      final v = (color[channel] * 60000).round();
      pixels.setUint16((y * width + x) * 2, v, Endian.little);
    }
  }

  final entries = <_Entry>[
    _Entry.long(254, [0]),
    _Entry.long(256, [width]),
    _Entry.long(257, [height]),
    _Entry.short(258, [16]),
    _Entry.short(259, [1]),
    _Entry.short(262, [32803]),
    _Entry.ascii(271, 'Memoria'),
    _Entry.ascii(272, 'Synthetic Bayer'),
    _Entry.long(273, [0]), // StripOffsets: 아래에서 채운다
    _Entry.short(274, [1]),
    _Entry.short(277, [1]),
    _Entry.long(278, [height]),
    _Entry.long(279, [width * height * 2]),
    _Entry.short(284, [1]),
    _Entry.short(33421, [2, 2]),
    _Entry.bytes(33422, [0, 1, 1, 2]),
    _Entry.bytes(50706, [1, 4, 0, 0]),
    _Entry.bytes(50707, [1, 1, 0, 0]),
    _Entry.ascii(50708, 'Memoria Synthetic Bayer'),
    _Entry.long(50714, [0]),
    _Entry.long(50717, [65535]),
    _Entry.srational(50721, const [
      [32406, 10000], [-15372, 10000], [-4986, 10000],
      [-9689, 10000], [18758, 10000], [415, 10000],
      [557, 10000], [-2040, 10000], [10570, 10000],
    ]),
    _Entry.rational(50728, const [
      [1, 1], [1, 1], [1, 1],
    ]),
    _Entry.short(50778, [21]),
  ];

  const ifdOffset = 8;
  final ifdSize = 2 + entries.length * 12 + 4;
  var extraOffset = ifdOffset + ifdSize;
  final extraOffsets = <int>[];
  for (final e in entries) {
    if (e.data.length > 4) {
      extraOffsets.add(extraOffset);
      extraOffset += e.data.length + (e.data.length.isOdd ? 1 : 0);
    } else {
      extraOffsets.add(-1);
    }
  }
  final stripOffset = extraOffset;
  entries[8] = _Entry.long(273, [stripOffset]);

  final out = ByteData(stripOffset + pixels.lengthInBytes);
  out.setUint8(0, 0x49);
  out.setUint8(1, 0x49);
  out.setUint16(2, 42, Endian.little);
  out.setUint32(4, ifdOffset, Endian.little);
  out.setUint16(ifdOffset, entries.length, Endian.little);
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final at = ifdOffset + 2 + i * 12;
    out.setUint16(at, e.tag, Endian.little);
    out.setUint16(at + 2, e.type, Endian.little);
    out.setUint32(at + 4, e.count, Endian.little);
    if (e.data.length <= 4) {
      for (var b = 0; b < e.data.length; b++) {
        out.setUint8(at + 8 + b, e.data[b]);
      }
    } else {
      out.setUint32(at + 8, extraOffsets[i], Endian.little);
      for (var b = 0; b < e.data.length; b++) {
        out.setUint8(extraOffsets[i] + b, e.data[b]);
      }
    }
  }
  out.setUint32(ifdOffset + 2 + entries.length * 12, 0, Endian.little);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(stripOffset, bytes.length, pixels.buffer.asUint8List());
  return bytes;
}

class _Entry {
  final int tag;
  final int type;
  final int count;
  final List<int> data;

  _Entry(this.tag, this.type, this.count, this.data);

  factory _Entry.short(int tag, List<int> values) {
    final d = ByteData(values.length * 2);
    for (var i = 0; i < values.length; i++) {
      d.setUint16(i * 2, values[i], Endian.little);
    }
    return _Entry(tag, 3, values.length, d.buffer.asUint8List());
  }

  factory _Entry.long(int tag, List<int> values) {
    final d = ByteData(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      d.setUint32(i * 4, values[i], Endian.little);
    }
    return _Entry(tag, 4, values.length, d.buffer.asUint8List());
  }

  factory _Entry.bytes(int tag, List<int> values) =>
      _Entry(tag, 1, values.length, values);

  factory _Entry.ascii(int tag, String value) {
    final data = [...value.codeUnits, 0];
    return _Entry(tag, 2, data.length, data);
  }

  factory _Entry.rational(int tag, List<List<int>> values) {
    final d = ByteData(values.length * 8);
    for (var i = 0; i < values.length; i++) {
      d.setUint32(i * 8, values[i][0], Endian.little);
      d.setUint32(i * 8 + 4, values[i][1], Endian.little);
    }
    return _Entry(tag, 5, values.length, d.buffer.asUint8List());
  }

  factory _Entry.srational(int tag, List<List<int>> values) {
    final d = ByteData(values.length * 8);
    for (var i = 0; i < values.length; i++) {
      d.setInt32(i * 8, values[i][0], Endian.little);
      d.setInt32(i * 8 + 4, values[i][1], Endian.little);
    }
    return _Entry(tag, 10, values.length, d.buffer.asUint8List());
  }
}
