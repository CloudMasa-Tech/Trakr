import 'package:file_picker/file_picker.dart';

import 'logo_picked.dart';

Future<PickedLogoFile?> pickLogoFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['png', 'jpg', 'jpeg', 'svg'],
    withData: true,
  );
  final file = result?.files.firstOrNull;
  if (file == null) return null;

  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) return null;

  return PickedLogoFile(
    bytes: bytes,
    name: file.name,
    mimeType: _mimeFromName(file.name),
  );
}

void Function() listenForLogoDragDrop({
  required void Function(PickedLogoFile file) onFile,
  required void Function(bool active) onHover,
}) {
  return () {};
}

String _mimeFromName(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'svg':
      return 'image/svg+xml';
    default:
      return 'application/octet-stream';
  }
}
