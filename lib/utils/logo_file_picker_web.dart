// Web implementation of the logo file picker. Uses a hidden `<input
// type="file">` for browse (so SVG files are allowed, unlike ImagePicker) and
// document-level drag & drop listeners for the drop zone. When the page is
// rendered by an HTML engine this implementation is exported by
// `logo_file_picker.dart`; the stub is used everywhere else.
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

import 'logo_picked.dart';

Future<PickedLogoFile?> pickLogoFile() async {
  final completer = Completer<PickedLogoFile?>();

  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/png,image/jpeg,image/svg+xml,.png,.jpg,.jpeg,.svg'
    ..style.display = 'none';
  web.document.body?.appendChild(input);

  input.onChange.first.then((_) {
    final files = input.files;
    final file = (files == null || files.length == 0) ? null : files.item(0);
    if (file == null) {
      completer.complete(null);
      return;
    }
    final reader = web.FileReader();
    reader.addEventListener(
        'load',
        ((web.Event _) {
          final result = reader.result;
          if (result != null) {
            final bytes = (result as JSArrayBuffer).toDart.asUint8List();
            completer.complete(PickedLogoFile(
              bytes: bytes,
              name: file.name,
              mimeType: file.type,
            ));
          } else {
            completer.complete(null);
          }
        }).toJS);
    reader.addEventListener(
        'error', ((web.Event _) => completer.complete(null)).toJS);
    reader.readAsArrayBuffer(file);
  });

  input.click();

  final result = await completer.future;
  input.remove();
  return result;
}

/// Listens for logo files dragged anywhere over the page. Returns a callback
/// that removes the listeners (call it in `dispose`).
void Function() listenForLogoDragDrop({
  required void Function(PickedLogoFile file) onFile,
  required void Function(bool active) onHover,
}) {
  bool hasDraggedFiles(web.Event event) {
    final dragEvent = event as web.DragEvent;
    final files = dragEvent.dataTransfer?.files;
    return files != null && files.length > 0 && _isAllowedFile(files.item(0)!);
  }

  void onDragOver(web.Event event) {
    if (!hasDraggedFiles(event)) return;
    event.preventDefault();
    final dragEvent = event as web.DragEvent;
    if (dragEvent.dataTransfer != null) {
      dragEvent.dataTransfer!.dropEffect = 'copy';
    }
    onHover(true);
  }

  void onDragLeave(web.Event event) {
    onHover(false);
  }

  void onDrop(web.Event event) {
    onHover(false);
    if (!hasDraggedFiles(event)) return;
    event.preventDefault();
    final dragEvent = event as web.DragEvent;
    final file = dragEvent.dataTransfer?.files.item(0);
    if (file == null) return;
    final reader = web.FileReader();
    reader.addEventListener(
        'load',
        ((web.Event _) {
          final result = reader.result;
          if (result != null) {
            final bytes = (result as JSArrayBuffer).toDart.asUint8List();
            onFile(PickedLogoFile(
              bytes: bytes,
              name: file.name,
              mimeType: file.type,
            ));
          }
        }).toJS);
    reader.readAsArrayBuffer(file);
  }

  final onDragOverJS = onDragOver.toJS;
  final onDragLeaveJS = onDragLeave.toJS;
  final onDropJS = onDrop.toJS;

  web.document
    ..addEventListener('dragover', onDragOverJS)
    ..addEventListener('dragleave', onDragLeaveJS)
    ..addEventListener('drop', onDropJS);

  return () {
    web.document
      ..removeEventListener('dragover', onDragOverJS)
      ..removeEventListener('dragleave', onDragLeaveJS)
      ..removeEventListener('drop', onDropJS);
  };
}

bool _isAllowedFile(web.File file) {
  final ext = _extensionOf(file.name);
  return PickedLogoFile.allowedExtensions.contains(ext);
}

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}
