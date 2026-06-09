import 'dart:io';
import 'package:image/image.dart' as img;

class ChannelStats {
  final double maeR;
  final double maeG;
  final double maeB;
  final double blueMaeR;
  final double blueMaeG;
  final double blueMaeB;
  final int bluePixels;
  final int totalPixels;

  const ChannelStats({
    required this.maeR,
    required this.maeG,
    required this.maeB,
    required this.blueMaeR,
    required this.blueMaeG,
    required this.blueMaeB,
    required this.bluePixels,
    required this.totalPixels,
  });
}

ChannelStats measure(img.Image pred, img.Image target) {
  final p = pred.width == target.width && pred.height == target.height
      ? pred
      : img.copyResize(pred, width: target.width, height: target.height);

  double errR = 0, errG = 0, errB = 0;
  double bErrR = 0, bErrG = 0, bErrB = 0;
  int n = 0, blueN = 0;

  for (int y = 0; y < target.height; y++) {
    for (int x = 0; x < target.width; x++) {
      final t = target.getPixel(x, y);
      final r = p.getPixel(x, y);

      final tr = t.r.toDouble(), tg = t.g.toDouble(), tb = t.b.toDouble();
      final rr = r.r.toDouble(), rg = r.g.toDouble(), rb = r.b.toDouble();

      errR += (rr - tr).abs();
      errG += (rg - tg).abs();
      errB += (rb - tb).abs();
      n++;

      if (tb > tr + 15 && tb > tg + 15) {
        bErrR += (rr - tr).abs();
        bErrG += (rg - tg).abs();
        bErrB += (rb - tb).abs();
        blueN++;
      }
    }
  }

  return ChannelStats(
    maeR: errR / n,
    maeG: errG / n,
    maeB: errB / n,
    blueMaeR: blueN > 0 ? bErrR / blueN : 0.0,
    blueMaeG: blueN > 0 ? bErrG / blueN : 0.0,
    blueMaeB: blueN > 0 ? bErrB / blueN : 0.0,
    bluePixels: blueN,
    totalPixels: n,
  );
}

void printStats(String label, ChannelStats s) {
  final blueRatio = s.totalPixels > 0 ? (100.0 * s.bluePixels / s.totalPixels) : 0.0;
  print('[$label]');
  print('Global MAE: R=${s.maeR.toStringAsFixed(2)} G=${s.maeG.toStringAsFixed(2)} B=${s.maeB.toStringAsFixed(2)}');
  print('Blue pixels: ${s.bluePixels} (${blueRatio.toStringAsFixed(2)}%)');
  print('Blue MAE  : R=${s.blueMaeR.toStringAsFixed(2)} G=${s.blueMaeG.toStringAsFixed(2)} B=${s.blueMaeB.toStringAsFixed(2)}');
}

void main(List<String> args) {
  if (args.length < 3) {
    print('Usage: dart run tool/channel_compare.dart <target.jpg> <before.jpg> <after.jpg>');
    exit(1);
  }

  final target = img.decodeImage(File(args[0]).readAsBytesSync())!;
  final before = img.decodeImage(File(args[1]).readAsBytesSync())!;
  final after = img.decodeImage(File(args[2]).readAsBytesSync())!;

  final sBefore = measure(before, target);
  final sAfter = measure(after, target);

  printStats('Before', sBefore);
  print('');
  printStats('After', sAfter);
}
