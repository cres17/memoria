import 'dart:isolate';

void main() async {
  final uri = Uri.parse('package:image/image.dart');
  final resolved = await Isolate.resolvePackageUri(uri);
  print('Resolved package path: $resolved');
}
